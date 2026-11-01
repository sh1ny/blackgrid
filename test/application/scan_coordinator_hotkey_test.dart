import 'dart:async';
import 'dart:typed_data';

import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/capture/input_trigger_source.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_image.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/catalog_store.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_scan_ports.dart';
import 'support/gated_database.dart';

class _NoCatalogStore implements CatalogStore {
  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async => null;

  @override
  Future<void> commitCatalog(CatalogSnapshot snapshot) async {}
}

final _marker = VisionTemplate(
  'inspectionMarker',
  VisionImage(Uint8List(1), width: 1, height: 1, stride: 1, channels: 1),
);

/// A coordinator over real settings, a gated database and fake services.
class _Rig {
  _Rig._(this.db, this.settings, this.catalog);

  static Future<_Rig> create({ScanHotkey? saved}) async {
    final db = GatedDatabase(NativeDatabase.memory());
    if (saved != null) {
      await db.saveSettings(AppSettings(scanHotkey: saved));
    }
    final settings = SettingsController(db);
    await settings.load();
    final catalog = CatalogController(
      store: _NoCatalogStore(),
      client: CatalogClient(
        client: MockClient((_) async => http.Response('', 500)),
      ),
    );
    return _Rig._(db, settings, catalog);
  }

  final GatedDatabase db;
  final SettingsController settings;
  final CatalogController catalog;

  final ScanEventLog events = [];
  final List<FakeScanVision> visions = [];
  final List<FakeScanCapture> captures = [];
  FakeScanPlatform? platform;
  int platformOpens = 0;

  /// Configures each vision service as it is created.
  void Function(FakeScanVision vision)? configureVision;

  /// Configures the trigger when the platform opens.
  void Function(FakeScanTrigger trigger)? configureTrigger;

  late final ScanCoordinator coordinator = ScanCoordinator(
    settings: settings,
    catalog: catalog,
    appendLogLine: (_) {},
    runtimeDirectory: r'C:\fake\bundle',
    closeTimeout: const Duration(seconds: 5),
    waiter: immediateScanWaiter,
    markerLoader: (_) async => MarkerTemplateLoaded(_marker),
    captureFactory: () {
      final capture = FakeScanCapture(events);
      captures.add(capture);
      return capture;
    },
    visionFactory: (marker, directory) {
      final vision = FakeScanVision(events);
      visions.add(vision);
      configureVision?.call(vision);
      return vision;
    },
    platformFactory: () {
      platformOpens++;
      final opened = FakeScanPlatform(events);
      configureTrigger?.call(opened.trigger);
      return platform = opened;
    },
  );

  FakeScanTrigger get trigger => platform!.trigger;

  Future<void> switchOn() async {
    await coordinator.setLiveScan(true);
    await coordinator.settled;
  }

  /// Completes when the coordinator reports [state].
  Future<void> whenState(LiveScanState state) {
    if (coordinator.status.state == state) return Future.value();
    final done = Completer<void>();
    void listener() {
      if (coordinator.status.state == state && !done.isCompleted) {
        done.complete();
      }
    }

    coordinator.addListener(listener);
    return done.future.whenComplete(() => coordinator.removeListener(listener));
  }

  /// Emits a mouse release at [qpc] over the fake trigger.
  void click(int qpc) => trigger.emit(
    ScanTrigger(
      TriggerEvent(
        x: 10,
        y: 20,
        hwnd: 1,
        pid: 2,
        tid: 3,
        qpc: qpc,
        source: TriggerSource.mouse,
      ),
      0,
    ),
  );

  Future<ScanHotkey> savedHotkey() async =>
      (await db.readSettings()).settings.scanHotkey;

  /// Makes the next preference saves fail, as a database error would.
  Future<void> failSaves() => db.customStatement(
    'CREATE TRIGGER preference_failure BEFORE INSERT ON preferences '
    "BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
  );

  Future<void> dispose() async {
    await coordinator.dispose();
    settings.dispose();
    catalog.dispose();
    await db.close();
  }
}

void main() {
  late _Rig rig;

  Future<void> ready({ScanHotkey? saved}) async {
    rig = await _Rig.create(saved: saved);
    await rig.switchOn();
    expect(rig.coordinator.status.state, LiveScanState.ready);
  }

  tearDown(() => rig.dispose());

  group('hotkey state', () {
    test('state: ready with a free key', () async {
      await ready();

      expect(
        rig.coordinator.hotkeyState,
        const ScanHotkeyRegistered(ScanHotkey.f9),
      );
      expect(rig.trigger.registered, ScanHotkey.f9);
      expect(rig.events, containsAllInOrder(['hook.start', 'hotkey.f9']));
      expect(rig.trigger.hotkeyCalls.items, [ScanHotkey.f9]);
    });

    test('state: binding off', () async {
      await ready(saved: ScanHotkey.off);

      expect(rig.coordinator.hotkeyState, const ScanHotkeyDisabled());
      expect(rig.trigger.hotkeyCalls.length, 0);
      expect(rig.trigger.registered, isNull);
    });

    test('state: live scan off', () async {
      rig = await _Rig.create();
      expect(rig.coordinator.hotkeyState, const ScanHotkeyInactive());

      // Starting: the vision start is held, so no hook exists yet.
      final gate = Completer<ScanFailure?>();
      final created = Completer<FakeScanVision>();
      rig.configureVision = (v) {
        v.startGate = gate;
        created.complete(v);
      };
      await rig.coordinator.setLiveScan(true);
      await (await created.future).startEntered.future;
      expect(rig.coordinator.status.state, LiveScanState.starting);
      expect(rig.coordinator.hotkeyState, const ScanHotkeyInactive());
      expect(rig.platformOpens, 0);

      // Unavailable: the held start fails.
      gate.complete(
        const ScanFailure(ScanFailureCode.visionStartFailed, 'no vision'),
      );
      await rig.coordinator.settled;
      expect(rig.coordinator.status.state, LiveScanState.unavailable);
      expect(rig.coordinator.hotkeyState, const ScanHotkeyInactive());
      expect(rig.platformOpens, 0, reason: 'no hook, so no hotkey call');
    });

    test('state: worker loss', () async {
      await ready();
      expect(rig.trigger.registered, ScanHotkey.f9);

      final lost = rig.whenState(LiveScanState.unavailable);
      rig.visions.single.crash(
        const ScanFailure(ScanFailureCode.visionUnavailable, 'worker died'),
      );
      await lost;
      await rig.coordinator.settled;

      expect(rig.trigger.registered, isNull);
      expect(rig.coordinator.hotkeyState, const ScanHotkeyInactive());
    });

    test('state: registration does not answer at activation', () async {
      rig = await _Rig.create();
      rig.configureTrigger = (t) => t.hotkeyResults.add(const HotkeyTimedOut());
      await rig.switchOn();

      expect(rig.coordinator.status.state, LiveScanState.ready);
      expect(
        rig.coordinator.hotkeyState,
        isA<ScanHotkeyUnavailable>()
            .having((s) => s.key, 'key', ScanHotkey.f9)
            .having((s) => s.reason, 'reason', contains('timed out')),
      );
    });
  });

  group('activation', () {
    test('activation: hotkey held by another application', () async {
      rig = await _Rig.create();
      rig.configureTrigger = (t) => t.heldKeys.add(ScanHotkey.f9);
      await rig.switchOn();

      expect(rig.coordinator.status.state, LiveScanState.ready);
      expect(
        rig.coordinator.hotkeyState,
        isA<ScanHotkeyUnavailable>()
            .having((s) => s.key, 'key', ScanHotkey.f9)
            .having((s) => s.reason, 'reason', contains('1409')),
      );
      expect(rig.trigger.registered, isNull);

      // Mouse releases over the target still start scans.
      rig.click(0);
      final call = await rig.captures.single.calls.at(0);
      expect(call.trigger.source, TriggerSource.mouse);
      expect(call.mode, CaptureMode.targeted);
    });
  });

  group('rebind', () {
    test('rebind: rebind while ready', () async {
      await ready();

      final result = await rig.coordinator.setHotkey(ScanHotkey.f10);

      expect(result, ScanRebindResult.saved);
      expect(rig.trigger.registered, ScanHotkey.f10);
      expect(rig.trigger.hotkeyCalls.items, [ScanHotkey.f9, ScanHotkey.f10]);
      expect(await rig.savedHotkey(), ScanHotkey.f10);
      expect(rig.settings.settings.scanHotkey, ScanHotkey.f10);
      expect(
        rig.coordinator.hotkeyState,
        const ScanHotkeyRegistered(ScanHotkey.f10),
      );
      expect(rig.coordinator.hotkeyError, isNull);
      expect(rig.coordinator.hotkeyRebinding, isFalse);
    });

    test('rebind: rebind to a held key', () async {
      await ready();
      rig.trigger.heldKeys.add(ScanHotkey.f10);

      final result = await rig.coordinator.setHotkey(ScanHotkey.f10);

      expect(result, ScanRebindResult.refused);
      expect(rig.trigger.registered, ScanHotkey.f9);
      expect(await rig.savedHotkey(), ScanHotkey.f9);
      expect(
        rig.coordinator.hotkeyState,
        const ScanHotkeyRegistered(ScanHotkey.f9),
      );
      expect(
        rig.coordinator.hotkeyError,
        allOf(contains('F10'), contains('1409')),
      );
      expect(rig.coordinator.hotkeyRebinding, isFalse);
    });

    test('rebind: save fails after registration', () async {
      await ready();
      await rig.failSaves();

      final result = await rig.coordinator.setHotkey(ScanHotkey.f10);

      expect(result, ScanRebindResult.notSaved);
      expect(rig.trigger.registered, ScanHotkey.f9);
      expect(rig.trigger.hotkeyCalls.items, [
        ScanHotkey.f9,
        ScanHotkey.f10,
        ScanHotkey.f9,
      ]);
      expect(
        rig.coordinator.hotkeyState,
        const ScanHotkeyRegistered(ScanHotkey.f9),
      );
      expect(rig.coordinator.hotkeyError, contains('not saved'));
    });

    test('rebind: save fails after leaving an unavailable key', () async {
      rig = await _Rig.create();
      rig.configureTrigger = (t) => t.heldKeys.add(ScanHotkey.f9);
      await rig.switchOn();
      final before = rig.coordinator.hotkeyState;
      expect(before, isA<ScanHotkeyUnavailable>());
      await rig.failSaves();

      final result = await rig.coordinator.setHotkey(ScanHotkey.f10);

      expect(result, ScanRebindResult.notSaved);
      expect(rig.trigger.registered, isNull);
      expect(rig.trigger.hotkeyCalls.items, [
        ScanHotkey.f9,
        ScanHotkey.f10,
        ScanHotkey.off,
      ]);
      expect(rig.coordinator.hotkeyState, before);
      expect(rig.coordinator.hotkeyError, contains('not saved'));
    });

    test('rebind: old key taken during a failed save', () async {
      await ready();
      final gate = rig.db.saveGate = Completer<void>();

      final rebind = rig.coordinator.setHotkey(ScanHotkey.f10);
      await rig.db.saveEntered.future;
      expect(rig.trigger.registered, ScanHotkey.f10);
      rig.trigger.heldKeys.add(ScanHotkey.f9);
      await rig.failSaves();
      gate.complete();

      expect(await rebind, ScanRebindResult.notSaved);
      expect(rig.trigger.registered, isNull);
      expect(rig.trigger.hotkeyCalls.items, [
        ScanHotkey.f9,
        ScanHotkey.f10,
        ScanHotkey.f9,
        ScanHotkey.off,
      ]);
      expect(
        rig.coordinator.hotkeyState,
        isA<ScanHotkeyUnavailable>()
            .having((s) => s.key, 'key', ScanHotkey.f9)
            .having((s) => s.reason, 'reason', contains('1409')),
      );
      expect(rig.coordinator.hotkeyError, contains('not saved'));
    });

    test('rebind: live scan switched off while a rebind saves', () async {
      await ready();
      final gate = rig.db.saveGate = Completer<void>();

      final rebind = rig.coordinator.setHotkey(ScanHotkey.f10);
      await rig.db.saveEntered.future;
      final off = rig.coordinator.setLiveScan(false);
      // Everything the switch-off can do before the rebind save lands.
      await pumpEventQueue();
      gate.complete();
      await Future.wait([rebind, off]);
      await rig.coordinator.settled;

      final saved = (await rig.db.readSettings()).settings;
      expect(saved.liveScan, isFalse, reason: 'the switch-off save waited');
      expect(saved.scanHotkey, ScanHotkey.f10);
      expect(rig.coordinator.error, isNull);
      expect(rig.coordinator.hotkeyError, isNull);
      expect(rig.trigger.registered, isNull);
      expect(rig.coordinator.hotkeyState, const ScanHotkeyInactive());
      expect(rig.coordinator.status.state, LiveScanState.off);
    });

    test('rebind: rebind and switch-on both waiting on one save', () async {
      await ready();
      final gate = rig.db.saveGate = Completer<void>();

      final off = rig.coordinator.setLiveScan(false);
      await rig.db.saveEntered.future;
      final rebind = rig.coordinator.setHotkey(ScanHotkey.f10);
      final on = rig.coordinator.setLiveScan(true);
      // Both now wait on the held switch-off save.
      await pumpEventQueue();
      gate.complete();
      await Future.wait([off, rebind, on]);
      await rig.coordinator.settled;

      expect(await rebind, ScanRebindResult.saved);
      final saved = (await rig.db.readSettings()).settings;
      expect(saved.scanHotkey, ScanHotkey.f10);
      expect(saved.liveScan, isTrue);
      expect(rig.coordinator.error, isNull);
      expect(rig.coordinator.hotkeyError, isNull);
      expect(rig.coordinator.status.state, LiveScanState.ready);
    });

    test('rebind: rebind while off', () async {
      rig = await _Rig.create();

      final result = await rig.coordinator.setHotkey(ScanHotkey.f10);

      expect(result, ScanRebindResult.saved);
      expect(await rig.savedHotkey(), ScanHotkey.f10);
      expect(rig.platformOpens, 0, reason: 'no hook, so no native call');
      expect(rig.coordinator.hotkeyState, const ScanHotkeyInactive());
      expect(rig.coordinator.hotkeyError, isNull);
    });

    test('rebind: rebind during another rebind', () async {
      await ready();
      final hold = rig.trigger.hotkeyHold = Completer<void>();

      final first = rig.coordinator.setHotkey(ScanHotkey.f10);
      await rig.trigger.hotkeyCalls.at(1);
      expect(rig.coordinator.hotkeyRebinding, isTrue);

      expect(
        await rig.coordinator.setHotkey(ScanHotkey.f11),
        ScanRebindResult.busy,
      );
      expect(rig.trigger.hotkeyCalls.length, 2, reason: 'no second request');

      hold.complete();
      expect(await first, ScanRebindResult.saved);
      expect(await rig.savedHotkey(), ScanHotkey.f10);
      expect(
        rig.coordinator.hotkeyState,
        const ScanHotkeyRegistered(ScanHotkey.f10),
      );
      expect(rig.coordinator.hotkeyError, isNull);
      expect(rig.coordinator.hotkeyRebinding, isFalse);
    });

    test('rebind: rebind out of an unavailable state', () async {
      rig = await _Rig.create();
      rig.configureTrigger = (t) => t.heldKeys.add(ScanHotkey.f9);
      await rig.switchOn();
      expect(rig.coordinator.hotkeyState, isA<ScanHotkeyUnavailable>());

      final result = await rig.coordinator.setHotkey(ScanHotkey.f10);

      expect(result, ScanRebindResult.saved);
      expect(rig.trigger.registered, ScanHotkey.f10);
      expect(await rig.savedHotkey(), ScanHotkey.f10);
      expect(
        rig.coordinator.hotkeyState,
        const ScanHotkeyRegistered(ScanHotkey.f10),
      );
    });
  });

  group('stop', () {
    test('stop: switching off during a rebind', () async {
      await ready();
      final hold = rig.trigger.hotkeyHold = Completer<void>();

      final rebind = rig.coordinator.setHotkey(ScanHotkey.f10);
      await rig.trigger.hotkeyCalls.at(1);

      await rig.coordinator.setLiveScan(false);
      await rig.coordinator.settled;
      expect(rig.trigger.registered, isNull);
      expect(rig.coordinator.hotkeyState, const ScanHotkeyInactive());

      // The input thread answers after the stop.
      hold.complete();
      expect(await rebind, ScanRebindResult.stopped);

      expect(rig.trigger.hotkeyCalls.length, 2, reason: 'no restore call');
      expect(rig.trigger.registered, isNull);
      expect(rig.coordinator.hotkeyState, const ScanHotkeyInactive());
      expect(
        await rig.savedHotkey(),
        ScanHotkey.f9,
        reason: 'the binding in force before the rebind stays saved',
      );
      expect(rig.coordinator.hotkeyError, isNull);
      expect(rig.coordinator.hotkeyRebinding, isFalse);
    });
  });
}
