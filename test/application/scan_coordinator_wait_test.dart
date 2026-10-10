@Timeout(Duration(seconds: 5))
library;

import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/catalog_store.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../ui/support/scan_ui_support.dart';
import 'support/fake_scan_ports.dart';

class _Store implements CatalogStore {
  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async =>
      mode == GameMode.pvp ? scanSnapshot() : null;

  @override
  Future<void> commitCatalog(CatalogSnapshot snapshot) async {}
}

/// Ticks per millisecond of the fake QPC clock (10 MHz).
const _ms = 10000;

/// The trigger stamp every test starts from.
const _t1 = 1000000;

OutcomeRejected<InspectionEvidence> _noMarker() =>
    const OutcomeRejected<InspectionEvidence>(
      OutcomeRejectReason.noMarker,
      targetedBestMarkerScore: 0.1,
    );

/// A coordinator over hand-written ports and a waiter the test releases.
final class _Rig {
  _Rig._(this.db, this.settings, this.catalog) {
    coordinator = ScanCoordinator(
      settings: settings,
      catalog: catalog,
      appendLogLine: logs.add,
      runtimeDirectory: r'C:\fake\bundle',
      closeTimeout: const Duration(milliseconds: 500),
      indexBuilder: builder.call,
      matcher: matcher.call,
      markerLoader: ports.loader,
      captureFactory: ports.captureFactory,
      visionFactory: ports.visionFactory,
      platformFactory: ports.platformFactory,
      waiter: waiter.call,
    );
  }

  static Future<_Rig> create() async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    final settings = SettingsController(db);
    await settings.load();
    final catalog = CatalogController(
      store: _Store(),
      client: CatalogClient(
        client: MockClient((_) async => http.Response('', 500)),
      ),
    );
    await catalog.setMode(GameMode.pvp);
    final rig = _Rig._(db, settings, catalog);
    await rig.coordinator.setLiveScan(true);
    await rig.coordinator.settled;
    expect(rig.coordinator.status.state, LiveScanState.ready);
    return rig;
  }

  final BlackgridDatabase db;
  final SettingsController settings;
  final CatalogController catalog;
  final ScanFakePorts ports = ScanFakePorts();
  final FakeScanWaiter waiter = FakeScanWaiter(hold: true);
  final FakeScanMatcher matcher = FakeScanMatcher();
  final FakeIndexBuilder builder = FakeIndexBuilder();
  final List<Map<String, Object?>> logs = [];
  late final ScanCoordinator coordinator;

  FakeScanCapture get capture => ports.capture;
  FakeScanClock get clock => ports.clock;

  /// Sets the fake QPC clock.
  void now(int qpc) => clock.now = qpc;

  /// Drives the targeted pass of the scan to a `noMarker` rejection, with the
  /// clock at [rejectedAt] when the match completes.
  Future<void> rejectTargeted({required int rejectedAt}) async {
    await waiter.requests.at(0);
    waiter.release(0);
    (await capture.calls.at(0)).succeed(ports.frames.frame());
    final evidence = scanEvidence();
    (await ports.vision.calls.at(0))
        .deliver(scanRecognised(InspectionFrameKind.targeted, [evidence]));
    final match = await matcher.calls.at(0);
    now(rejectedAt);
    match.complete(_noMarker());
  }

  Future<void> dispose() async {
    await coordinator.dispose();
    settings.dispose();
    catalog.dispose();
    await db.close();
  }
}

const _ms49 = Duration(milliseconds: 49);

void main() {
  late _Rig rig;

  setUp(() async => rig = await _Rig.create());
  tearDown(() => rig.dispose());

  group('settle wait before the targeted capture', () {
    test(
      'fresh trigger waits the remaining 49 ms before the targeted capture',
      () async {
        rig.now(_t1 + _ms);
        rig.ports.fire(_t1);

        expect(rig.waiter.requests.length, 1);
        expect(rig.waiter.requests[0], _ms49);
        expect(
          rig.capture.calls.length,
          0,
          reason: 'no capture before the wait',
        );
        expect(rig.coordinator.phase, ScanPhase.targeted);

        rig.waiter.release(0);
        final call = await rig.capture.calls.at(0);
        expect(call.mode, CaptureMode.targeted);
        expect(call.trigger.qpc, _t1);
      },
    );

    test('a trigger already 120 ms old captures without waiting', () async {
      rig.now(_t1 + 60 * _ms);
      rig.ports.fire(_t1);
      final first = await rig.capture.calls.at(0);
      expect(rig.waiter.requests.length, 0, reason: 'already past 50 ms');

      // The pending trigger starts its scan 120 ms after its own timestamp.
      const t2 = _t1 + 10 * _ms;
      rig.ports.fire(t2);
      rig.now(t2 + 120 * _ms);
      first.fail(const TargetNotForeground());

      final second = await rig.capture.calls.at(1);
      expect(second.trigger.qpc, t2);
      expect(rig.waiter.requests.length, 0);
    });

    test('switch-off during the settle wait requests no capture and publishes '
        'nothing', () async {
      rig.now(_t1 + _ms);
      rig.ports.fire(_t1);
      expect(rig.waiter.requests.length, 1);

      await rig.coordinator.setLiveScan(false);
      rig.waiter.release(0);
      await rig.coordinator.settled;

      expect(rig.capture.calls.length, 0);
      expect(rig.ports.events, isNot(contains('capture.targeted')));
      expect(rig.coordinator.latest, isNull);
      expect(rig.coordinator.phase, ScanPhase.idle);
    });
  });

  group('fallback wait', () {
    test(
      'quick noMarker publishes fallback phase, then waits to trigger + 200 ms',
      () async {
        rig.now(_t1 + _ms);
        rig.ports.fire(_t1);
        await rig.rejectTargeted(rejectedAt: _t1 + 80 * _ms);

        await rig.waiter.requests.at(1);
        expect(rig.coordinator.phase, ScanPhase.fallback);
        expect(rig.waiter.requests[1], const Duration(milliseconds: 120));
        expect(rig.capture.calls.length, 1, reason: 'no fallback capture yet');

        rig.waiter.release(1);
        final fallback = await rig.capture.calls.at(1);
        expect(fallback.mode, CaptureMode.fallback);
      },
    );

    test(
      'targeted rejection after 260 ms falls back without waiting',
      () async {
        rig.now(_t1 + _ms);
        rig.ports.fire(_t1);
        await rig.rejectTargeted(rejectedAt: _t1 + 260 * _ms);

        final fallback = await rig.capture.calls.at(1);
        expect(fallback.mode, CaptureMode.fallback);
        expect(rig.waiter.requests.length, 1, reason: 'only the settle wait');
        expect(rig.coordinator.phase, ScanPhase.fallback);
      },
    );
  });

  group('supersession during a wait', () {
    test('second click during the settle wait supersedes at once', () async {
      rig.now(_t1 + _ms);
      rig.ports.fire(_t1);
      const t2 = _t1 + 20 * _ms;
      rig.now(t2);
      rig.ports.fire(t2);

      expect(
        rig.waiter.requests.length,
        2,
        reason: 'scan 2 starts at once, no pending slot',
      );
      expect(rig.waiter.requests[1], const Duration(milliseconds: 50));

      rig.waiter.release(0);
      await rig.coordinator.settled;
      expect(rig.capture.calls.length, 0, reason: 'scan 1 requests nothing');

      rig.waiter.release(1);
      final call = await rig.capture.calls.at(0);
      expect(call.trigger.qpc, t2);
      expect(call.mode, CaptureMode.targeted);
      expect(rig.capture.calls.length, 1);
      expect(rig.coordinator.latest, isNull);
      expect(rig.logs.length, 1);
      expect(rig.logs[0]['end'], 'superseded');
    });

    test('click during the fallback wait supersedes at once', () async {
      rig.now(_t1 + _ms);
      rig.ports.fire(_t1);
      await rig.rejectTargeted(rejectedAt: _t1 + 80 * _ms);
      await rig.waiter.requests.at(1);
      expect(rig.coordinator.phase, ScanPhase.fallback);

      const t2 = _t1 + 100 * _ms;
      rig.now(t2);
      rig.ports.fire(t2);

      expect(rig.waiter.requests.length, 3, reason: 'scan 2 settle wait');
      expect(rig.coordinator.phase, ScanPhase.targeted);

      rig.waiter.release(1);
      rig.waiter.release(2);
      final call = await rig.capture.calls.at(1);
      expect(call.trigger.qpc, t2);
      expect(call.mode, CaptureMode.targeted);
      expect(rig.capture.calls.length, 2, reason: 'no fallback capture');
      expect(rig.coordinator.latest, isNull);
      expect(rig.logs.first['end'], 'superseded');
    });
  });
}
