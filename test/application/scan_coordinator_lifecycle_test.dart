import 'dart:async';
import 'dart:typed_data';

import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_failure.dart';
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

class _NoCatalogStore implements CatalogStore {
  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async => null;

  @override
  Future<void> commitCatalog(CatalogSnapshot snapshot) async {}
}

final _marker = VisionTemplate(
  'inspectionMarker',
  VisionImage(
    // Contents are never read: the services are fakes.
    Uint8List(1),
    width: 1,
    height: 1,
    stride: 1,
    channels: 1,
  ),
);

/// Everything one lifecycle test needs, over real settings and a fake set of
/// services.
class _Rig {
  _Rig._(this.db, this.settings, this.catalog);

  static Future<_Rig> create({bool liveScanSaved = false}) async {
    final db = _GatedDatabase(NativeDatabase.memory());
    if (liveScanSaved) {
      await db.saveSettings(AppSettings(liveScan: true));
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

  final _GatedDatabase db;
  final SettingsController settings;
  final CatalogController catalog;

  final ScanEventLog events = [];
  final List<FakeScanVision> visions = [];
  final List<FakeScanCapture> captures = [];
  final List<bool> templateSawSavedSetting = [];
  final List<LiveScanState> states = [];
  final Map<int, Completer<FakeScanVision>> _created = {};
  FakeScanPlatform? platform;
  int platformOpens = 0;
  Object? platformError;

  /// What the marker loader answers next; loaded by default.
  late MarkerTemplateResult markerResult = MarkerTemplateLoaded(_marker);

  /// Configures each vision service as it is created.
  void Function(FakeScanVision vision)? configureVision;

  /// Configures the platform's trigger when the platform opens.
  void Function(FakeScanTrigger trigger)? configureTrigger;

  Duration closeTimeout = const Duration(seconds: 5);

  late final ScanCoordinator coordinator = ScanCoordinator(
    settings: settings,
    catalog: catalog,
    appendLogLine: (_) {},
    runtimeDirectory: r'C:\fake\bundle',
    closeTimeout: closeTimeout,
    markerLoader: (directory) async {
      events.add('template');
      templateSawSavedSetting.add(settings.settings.liveScan);
      return markerResult;
    },
    captureFactory: () {
      events.add('capture.create');
      final capture = FakeScanCapture(events);
      captures.add(capture);
      return capture;
    },
    visionFactory: (marker, directory) {
      events.add('vision.create');
      final vision = FakeScanVision(events);
      visions.add(vision);
      configureVision?.call(vision);
      (_created[visions.length - 1] ??= Completer<FakeScanVision>()).complete(
        vision,
      );
      return vision;
    },
    platformFactory: () {
      platformOpens++;
      events.add('platform.open');
      final error = platformError;
      if (error != null) throw error;
      final opened = FakeScanPlatform(events);
      configureTrigger?.call(opened.trigger);
      return platform = opened;
    },
  );

  /// Completes with the [index]th vision service once it is created.
  Future<FakeScanVision> visionCreated(int index) =>
      (_created[index] ??= Completer<FakeScanVision>()).future;

  FakeScanTrigger get trigger => platform!.trigger;

  /// Records every distinct state the coordinator notifies.
  void recordStates() {
    states.add(coordinator.status.state);
    coordinator.addListener(() {
      final state = coordinator.status.state;
      if (states.last != state) states.add(state);
    });
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

  Future<void> switchOn() async {
    await coordinator.setLiveScan(true);
    await coordinator.settled;
  }

  /// Makes the next preference saves fail, as a database error would.
  Future<void> failSaves() => db.customStatement(
    "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences "
    "BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
  );

  Future<void> restoreSaves() =>
      db.customStatement('DROP TRIGGER preference_failure');

  Future<void> dispose() async {
    await coordinator.dispose();
    settings.dispose();
    catalog.dispose();
    await db.close();
  }
}

void main() {
  late _Rig rig;

  Future<_Rig> ready() async {
    rig = await _Rig.create();
    rig.recordStates();
    await rig.switchOn();
    expect(rig.coordinator.status.state, LiveScanState.ready);
    return rig;
  }

  tearDown(() => rig.dispose());

  test('switch-on saves, then template, vision ready, then hook', () async {
    rig = await _Rig.create();
    rig.recordStates();
    final gate = Completer<ScanFailure?>();
    rig.configureVision = (v) => v.startGate = gate;

    await rig.coordinator.setLiveScan(true);
    expect((await rig.db.readSettings()).liveScan, isTrue);

    // Hold the vision start: the hook must wait for it.
    await (await rig.visionCreated(0)).startEntered.future;
    expect(rig.events, [
      'template',
      'capture.create',
      'vision.create',
      'vision.start',
    ]);
    expect(rig.templateSawSavedSetting, [true]);
    expect(rig.coordinator.status.state, LiveScanState.starting);
    expect(rig.platformOpens, 0, reason: 'the hook platform opens last');

    gate.complete(null);
    await rig.coordinator.settled;

    expect(rig.events, [
      'template',
      'capture.create',
      'vision.create',
      'vision.start',
      'platform.open',
      'hook.start',
    ]);
    expect(rig.states, [
      LiveScanState.off,
      LiveScanState.starting,
      LiveScanState.ready,
    ]);
    expect(rig.coordinator.switchOn, isTrue);
    expect(rig.coordinator.error, isNull);
  });

  test('vision start failure is unavailable without a hook', () async {
    rig = await _Rig.create();
    rig.configureVision = (v) => v.startResult = const ScanFailure(
      ScanFailureCode.visionRuntimeUnavailable,
      'Vision runtime file is missing: tesseract.dll',
    );

    await rig.switchOn();

    final status = rig.coordinator.status;
    expect(status.state, LiveScanState.unavailable);
    expect(status.reasonCode, ScanFailureCode.visionRuntimeUnavailable);
    expect(status.reason, contains('tesseract.dll'));
    expect(rig.platformOpens, 0);
    expect(rig.events, isNot(contains('hook.start')));
    expect(rig.visions.single.closeCalls, 1);
    expect(
      (await rig.db.readSettings()).liveScan,
      isTrue,
      reason: 'the setting stays on',
    );
    expect(rig.coordinator.switchOn, isTrue);
  });

  test('invalid marker template is unavailable before any worker', () async {
    rig = await _Rig.create();
    rig.markerResult = const MarkerTemplateInvalid('marker.gray', 'bad hash');

    await rig.switchOn();

    expect(rig.coordinator.status.state, LiveScanState.unavailable);
    expect(
      rig.coordinator.status.reasonCode,
      ScanFailureCode.markerTemplateInvalid,
    );
    expect(rig.coordinator.status.reason, contains('marker.gray'));
    expect(rig.visions, isEmpty);
    expect(rig.captures, isEmpty);
    expect(rig.platformOpens, 0);
  });

  test('missing marker template names the file', () async {
    rig = await _Rig.create();
    rig.markerResult = const MarkerTemplateUnavailable(
      VisionMissingFile(r'C:\bundle\data\vision\marker\inspection_marker.gray'),
    );

    await rig.switchOn();

    expect(rig.coordinator.status.state, LiveScanState.unavailable);
    expect(
      rig.coordinator.status.reasonCode,
      ScanFailureCode.markerTemplateUnavailable,
    );
    expect(rig.coordinator.status.reason, contains('inspection_marker.gray'));
    expect(rig.visions, isEmpty);
  });

  test('refused hook is unavailable with OS code and closes vision', () async {
    rig = await _Rig.create();
    rig.configureTrigger = (t) => t.startResult = const TriggerUnavailable(5);

    await rig.switchOn();

    final status = rig.coordinator.status;
    expect(status.state, LiveScanState.unavailable);
    expect(status.reasonCode, ScanFailureCode.triggerUnavailable);
    expect(status.reason, contains('5'));
    expect(rig.visions.single.closeCalls, 1);
    expect(rig.captures.single.closeCalls, 1);
    expect(rig.trigger.hasListener, isFalse);
  });

  test(
    'an unopenable capture platform is unavailable with its reason',
    () async {
      rig = await _Rig.create();
      rig.platformError = StateError('capture dll missing');

      await rig.switchOn();

      final status = rig.coordinator.status;
      expect(status.state, LiveScanState.unavailable);
      expect(status.reasonCode, ScanFailureCode.captureUnavailable);
      expect(status.reason, contains('capture dll missing'));
      expect(rig.visions.single.closeCalls, 1);
    },
  );

  test('switch-off removes hook and closes both workers', () async {
    await ready();

    await rig.coordinator.setLiveScan(false);
    await rig.coordinator.settled;

    expect(rig.coordinator.status.state, LiveScanState.off);
    expect(rig.coordinator.status.stopWarning, isNull);
    expect(rig.coordinator.switchOn, isFalse);
    expect(rig.trigger.stopCalls, 1);
    expect(rig.trigger.installed, isFalse);
    expect(rig.trigger.hasListener, isFalse);
    expect(rig.visions.single.closeCalls, 1);
    expect(rig.captures.single.closeCalls, 1);
    expect(
      (await rig.db.readSettings()).liveScan,
      isFalse,
      reason: 'the setting is saved off',
    );
    expect(rig.states.last, LiveScanState.off);
    expect(
      rig.states,
      isNot(contains(LiveScanState.unavailable)),
      reason: 'the coordinator\'s own close is not a worker loss',
    );
  });

  group('failed switch-off save', () {
    test('failed switch-off save still stops the pipeline', () async {
      await ready();
      await rig.failSaves();

      await rig.coordinator.setLiveScan(false);
      await rig.coordinator.settled;

      expect(rig.coordinator.status.state, LiveScanState.off);
      expect(rig.coordinator.switchOn, isFalse);
      expect(rig.coordinator.error, contains('not saved'));
      expect(rig.trigger.stopCalls, 1);
      expect(rig.visions.single.closeCalls, 1);
      expect(rig.captures.single.closeCalls, 1);
      expect(rig.settings.settings.liveScan, isTrue);
      await rig.restoreSaves();
    });

    test('a save refused as busy shows the same error and stops', () async {
      await ready();
      rig.settings.busy = true;

      await rig.coordinator.setLiveScan(false);
      await rig.coordinator.settled;
      rig.settings.busy = false;

      expect(rig.coordinator.status.state, LiveScanState.off);
      expect(rig.coordinator.error, contains('not saved'));
      expect(rig.trigger.stopCalls, 1);
      expect(rig.visions.single.closeCalls, 1);
    });
  });

  test('unrelated save after failed switch-off keeps live scan off', () async {
    await ready();
    await rig.failSaves();
    await rig.coordinator.setLiveScan(false);
    await rig.coordinator.settled;
    await rig.restoreSaves();
    final eventsBefore = List.of(rig.events);
    expect(rig.settings.settings.liveScan, isTrue);

    // A later save carries liveScan: true, as the stale copy still says.
    expect(await rig.settings.setMap('woods'), isTrue);
    await rig.coordinator.settled;

    expect(rig.settings.settings.liveScan, isTrue);
    expect(rig.coordinator.status.state, LiveScanState.off);
    expect(rig.coordinator.switchOn, isFalse);
    expect(rig.events, eventsBefore, reason: 'nothing started or installed');
    expect(rig.visions, hasLength(1));
    expect(rig.trigger.startCalls, 1);
  });

  group('failed switch-on save', () {
    test('failed switch-on save reverts and starts nothing', () async {
      rig = await _Rig.create();
      await rig.failSaves();

      await rig.coordinator.setLiveScan(true);
      await rig.coordinator.settled;

      expect(rig.coordinator.switchOn, isFalse);
      expect(rig.coordinator.status.state, LiveScanState.off);
      expect(rig.coordinator.error, contains('not saved'));
      expect(rig.events, isEmpty);
      expect(rig.platformOpens, 0);
      await rig.restoreSaves();
    });

    test('a switch-on refused as busy shows the same error', () async {
      rig = await _Rig.create();
      rig.settings.busy = true;

      await rig.coordinator.setLiveScan(true);
      rig.settings.busy = false;

      expect(rig.coordinator.switchOn, isFalse);
      expect(rig.coordinator.error, contains('not saved'));
      expect(rig.events, isEmpty);
    });
  });

  group('switch flipped during a switch-on save', () {
    test(
      'switch-off during the save persists off and starts nothing',
      () async {
        rig = await _Rig.create();

        final on = rig.coordinator.setLiveScan(true);
        final off = rig.coordinator.setLiveScan(false);
        await Future.wait([on, off]);
        await rig.coordinator.settled;

        expect((await rig.db.readSettings()).liveScan, isFalse);
        expect(rig.settings.settings.liveScan, isFalse);
        expect(rig.coordinator.switchOn, isFalse);
        expect(rig.coordinator.status.state, LiveScanState.off);
        expect(rig.coordinator.error, isNull);
        expect(rig.platformOpens, 0);
        expect(rig.visions, isEmpty);
      },
    );

    test('a second switch-on during the save starts once', () async {
      rig = await _Rig.create();

      final first = rig.coordinator.setLiveScan(true);
      final second = rig.coordinator.setLiveScan(true);
      await Future.wait([first, second]);
      await rig.coordinator.settled;

      expect(rig.coordinator.switchOn, isTrue);
      expect(rig.coordinator.status.state, LiveScanState.ready);
      expect(rig.coordinator.error, isNull);
      expect(rig.visions, hasLength(1));
    });

    test('on, off, on during the save ends on and saved on', () async {
      rig = await _Rig.create();

      final first = rig.coordinator.setLiveScan(true);
      final off = rig.coordinator.setLiveScan(false);
      final last = rig.coordinator.setLiveScan(true);
      await Future.wait([first, off, last]);
      await rig.coordinator.settled;

      expect(rig.coordinator.switchOn, isTrue);
      expect(rig.coordinator.status.state, LiveScanState.ready);
      expect(rig.coordinator.error, isNull);
      expect((await rig.db.readSettings()).liveScan, isTrue);
      expect(rig.settings.settings.liveScan, isTrue);
      expect(rig.visions, hasLength(1));
    });

    test('off, on, off during the save ends off and saved off', () async {
      rig = await _Rig.create();
      await rig.switchOn();

      final first = rig.coordinator.setLiveScan(false);
      final on = rig.coordinator.setLiveScan(true);
      final last = rig.coordinator.setLiveScan(false);
      await Future.wait([first, on, last]);
      await rig.coordinator.settled;

      expect(rig.coordinator.switchOn, isFalse);
      expect(rig.coordinator.status.state, LiveScanState.off);
      expect(rig.coordinator.error, isNull);
      expect((await rig.db.readSettings()).liveScan, isFalse);
      expect(rig.settings.settings.liveScan, isFalse);
      expect(
        rig.visions,
        hasLength(1),
        reason: 'the middle tap started nothing',
      );
    });
  });

  group('switch-off then dispose', () {
    test('a switch-off right before dispose still saves off', () async {
      rig = await _Rig.create();
      await rig.switchOn();
      expect((await rig.db.readSettings()).liveScan, isTrue);

      final off = rig.coordinator.setLiveScan(false);
      final disposed = rig.coordinator.dispose();
      await Future.wait([off, disposed]);

      expect((await rig.db.readSettings()).liveScan, isFalse);
      expect(rig.settings.settings.liveScan, isFalse);
    });

    test('dispose waits for a switch-on save in flight', () async {
      rig = await _Rig.create();
      final gate = rig.db.saveGate = Completer<void>();
      final on = rig.coordinator.setLiveScan(true);
      await rig.db.saveEntered.future;

      var disposeDone = false;
      final disposed = rig.coordinator.dispose().then(
        (_) => disposeDone = true,
      );
      // Drain everything dispose could do without the save landing.
      await pumpEventQueue();
      expect(disposeDone, isFalse, reason: 'dispose waits for the save');

      gate.complete();
      await Future.wait([on, disposed]);
      expect((await rig.db.readSettings()).liveScan, isTrue);
      expect(rig.settings.settings.liveScan, isTrue);
    });
  });

  group('switch-off during a hung start', () {
    test(
      'switch-off during a hung start is bounded by the close drain',
      () async {
        rig = await _Rig.create();
        rig.closeTimeout = const Duration(milliseconds: 20);
        final held = Completer<ScanFailure?>();
        final heldClose = Completer<ScanFailure?>();
        // A start that never completes by itself, and a service whose close
        // is a hung native call that only the drain bound gives up on.
        rig.configureVision = (v) {
          v.startGate = held;
          v.closeGate = heldClose;
        };
        await rig.coordinator.setLiveScan(true);
        await (await rig.visionCreated(0)).startEntered.future;
        expect(rig.coordinator.status.state, LiveScanState.starting);

        final off = rig.coordinator.setLiveScan(false);
        expect(
          rig.visions.single.closeCalls,
          1,
          reason: 'close is called at once, not after the start',
        );
        await off;
        await rig.coordinator.settled;

        expect(rig.coordinator.status.state, LiveScanState.off);
        expect(rig.events, isNot(contains('hook.start')));
        expect(rig.platformOpens, 0);
        expect(
          rig.coordinator.status.stopWarning,
          isNotNull,
          reason: 'a close that outlasts its bound is reported',
        );
        heldClose.complete(null);
      },
    );

    test('a held start released by close ends off with no warning', () async {
      rig = await _Rig.create();
      rig.configureVision = (v) => v.startGate = Completer<ScanFailure?>();
      await rig.coordinator.setLiveScan(true);
      await (await rig.visionCreated(0)).startEntered.future;

      await rig.coordinator.setLiveScan(false);
      await rig.coordinator.settled;

      expect(rig.coordinator.status.state, LiveScanState.off);
      expect(rig.coordinator.status.stopWarning, isNull);
      expect(rig.events, isNot(contains('hook.start')));
      expect(rig.captures.single.closeCalls, 1);
    });

    test('switch-off during the template load starts no worker', () async {
      rig = await _Rig.create();
      final loading = Completer<void>();
      final entered = Completer<void>();
      final coordinator = ScanCoordinator(
        settings: rig.settings,
        catalog: rig.catalog,
        appendLogLine: (_) {},
        runtimeDirectory: r'C:\fake',
        markerLoader: (_) async {
          entered.complete();
          await loading.future;
          return MarkerTemplateLoaded(_marker);
        },
        captureFactory: () => throw StateError('no worker expected'),
        visionFactory: (_, _) => throw StateError('no worker expected'),
        platformFactory: () => throw StateError('no hook expected'),
      );
      await coordinator.setLiveScan(true);
      await entered.future;

      await coordinator.setLiveScan(false);
      loading.complete();
      await coordinator.settled;

      expect(coordinator.status.state, LiveScanState.off);
      await coordinator.dispose();
    });
  });

  group('stuck hook', () {
    test(
      'stopTimedOut is a visible warning and the next start retries stop',
      () async {
        await ready();
        rig.trigger.stopResults.add(const StopTimedOut());

        await rig.coordinator.setLiveScan(false);
        await rig.coordinator.settled;

        expect(rig.coordinator.status.state, LiveScanState.off);
        expect(rig.coordinator.status.stopWarning, contains('did not stop'));
        rig.events.clear();

        // The retry happens before the template or the vision runtime.
        await rig.switchOn();

        expect(rig.events.take(2), ['hook.stop', 'template']);
        expect(rig.coordinator.status.state, LiveScanState.ready);
        expect(rig.coordinator.status.stopWarning, isNull);
        expect(rig.visions, hasLength(2));
      },
    );

    test(
      'a stuck hook keeps live scan unavailable without opening vision',
      () async {
        await ready();
        rig.trigger.stopResults.addAll(const [StopTimedOut(), StopTimedOut()]);
        await rig.coordinator.setLiveScan(false);
        await rig.coordinator.settled;
        rig.events.clear();

        await rig.switchOn();

        final status = rig.coordinator.status;
        expect(status.state, LiveScanState.unavailable);
        expect(status.reasonCode, ScanFailureCode.alreadyStarted);
        expect(status.stopWarning, contains('did not stop'));
        expect(rig.events, ['hook.stop']);
        expect(rig.visions, hasLength(1));
        expect(rig.trigger.startCalls, 1);
      },
    );
  });

  test('vision worker exit removes hook and is unavailable', () async {
    await ready();
    final vision = rig.visions.single;
    expect(rig.trigger.hasListener, isTrue);

    final unavailable = rig.whenState(LiveScanState.unavailable);
    vision.crash(
      const ScanFailure(ScanFailureCode.visionUnavailable, 'worker died'),
    );
    await unavailable;
    await rig.coordinator.settled;

    final status = rig.coordinator.status;
    expect(status.reasonCode, ScanFailureCode.visionUnavailable);
    expect(status.reason, 'worker died');
    expect(rig.trigger.stopCalls, 1);
    expect(rig.trigger.installed, isFalse);
    expect(
      rig.trigger.hasListener,
      isFalse,
      reason: 'later triggers go nowhere',
    );
    expect(
      rig.captures.single.closeCalls,
      1,
      reason: 'the other service closes',
    );
    expect(rig.visions, hasLength(1), reason: 'no respawn');
  });

  test('capture worker exit removes hook and is unavailable', () async {
    await ready();

    final unavailable = rig.whenState(LiveScanState.unavailable);
    rig.captures.single.crash(
      const ScanFailure(ScanFailureCode.captureUnavailable, 'capture died'),
    );
    await unavailable;
    await rig.coordinator.settled;

    expect(
      rig.coordinator.status.reasonCode,
      ScanFailureCode.captureUnavailable,
    );
    expect(rig.trigger.installed, isFalse);
    expect(rig.visions.single.closeCalls, 1);
    expect(rig.captures, hasLength(1));
  });

  test('a close warning after a loss notifies listeners', () async {
    await ready();
    final heldClose = Completer<ScanFailure?>();
    rig.visions.single.closeGate = heldClose;
    final warnings = <String?>[];
    rig.coordinator.addListener(
      () => warnings.add(rig.coordinator.status.stopWarning),
    );

    final unavailable = rig.whenState(LiveScanState.unavailable);
    rig.captures.single.crash(
      const ScanFailure(ScanFailureCode.captureUnavailable, 'capture died'),
    );
    await unavailable;
    expect(rig.coordinator.status.stopWarning, isNull);

    heldClose.complete(
      const ScanFailure(
        ScanFailureCode.shutdownIncomplete,
        'The vision worker did not stop within its drain.',
      ),
    );
    await rig.visions.single.workerExit;
    await pumpEventQueue();

    expect(rig.coordinator.status.state, LiveScanState.unavailable);
    expect(rig.coordinator.status.stopWarning, contains('did not stop'));
    expect(
      warnings.last,
      contains('did not stop'),
      reason: 'listeners hear about the warning',
    );
  });

  test('off then on after loss creates fresh services', () async {
    await ready();
    final lost = rig.whenState(LiveScanState.unavailable);
    rig.visions.single.crash(
      const ScanFailure(ScanFailureCode.visionUnavailable, 'worker died'),
    );
    await lost;
    await rig.coordinator.settled;

    await rig.coordinator.setLiveScan(false);
    await rig.coordinator.settled;
    expect(rig.coordinator.status.state, LiveScanState.off);
    await rig.switchOn();

    expect(rig.coordinator.status.state, LiveScanState.ready);
    expect(rig.visions, hasLength(2));
    expect(rig.captures, hasLength(2));
    expect(rig.visions.last, isNot(same(rig.visions.first)));
    expect(rig.platformOpens, 1, reason: 'the hook platform opens once');
    expect(rig.trigger.startCalls, 2);
    expect(rig.trigger.hasListener, isTrue);
  });

  group('launch and dispose', () {
    test('startFromSettings reads the saved setting once', () async {
      rig = await _Rig.create(liveScanSaved: true);

      rig.coordinator.startFromSettings();
      await rig.coordinator.settled;
      expect(rig.coordinator.status.state, LiveScanState.ready);
      expect(rig.coordinator.switchOn, isTrue);

      // Later calls and later settings changes start nothing more.
      rig.coordinator.startFromSettings();
      await rig.settings.setMap('woods');
      await rig.coordinator.settled;
      expect(rig.visions, hasLength(1));
      expect(rig.trigger.startCalls, 1);
    });

    test('startFromSettings with the setting off starts nothing', () async {
      rig = await _Rig.create();

      rig.coordinator.startFromSettings();
      await rig.coordinator.settled;

      expect(rig.coordinator.status.state, LiveScanState.off);
      expect(rig.coordinator.switchOn, isFalse);
      expect(rig.events, isEmpty);
      expect(rig.platformOpens, 0);
    });

    test(
      'dispose during ready closes everything and then notifies nobody',
      () async {
        await ready();
        var notified = 0;
        rig.coordinator.addListener(() => notified++);

        await rig.coordinator.dispose();

        expect(notified, 0);
        expect(rig.trigger.stopCalls, 1);
        expect(rig.trigger.disposeCalls, 1);
        expect(rig.visions.single.closeCalls, 1);
        expect(rig.captures.single.closeCalls, 1);
        // A late call changes nothing and notifies nobody.
        await rig.coordinator.setLiveScan(true);
        expect(rig.visions, hasLength(1));
        expect(notified, 0);
      },
    );

    test('dispose during a hung start is bounded', () async {
      rig = await _Rig.create();
      rig.closeTimeout = const Duration(milliseconds: 20);
      final heldClose = Completer<ScanFailure?>();
      rig.configureVision = (v) {
        v.startGate = Completer<ScanFailure?>();
        v.closeGate = heldClose;
      };
      await rig.coordinator.setLiveScan(true);
      await (await rig.visionCreated(0)).startEntered.future;

      await rig.coordinator.dispose();

      expect(rig.visions.single.closeCalls, 1);
      expect(rig.events, isNot(contains('hook.start')));
      heldClose.complete(null);
    });
  });
}

/// A database whose settings writes can be held at [saveGate].
class _GatedDatabase extends BlackgridDatabase {
  _GatedDatabase(super.executor);

  /// When set, settings writes wait for it before writing.
  Completer<void>? saveGate;

  /// Completes when a held settings write starts waiting.
  final Completer<void> saveEntered = Completer<void>();

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final gate = saveGate;
    if (gate != null) {
      if (!saveEntered.isCompleted) saveEntered.complete();
      await gate.future;
    }
    await super.saveSettings(settings);
  }
}
