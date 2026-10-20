import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_image.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/domain/credential_store.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/m1_harness.dart';
import '../ui/support/scan_ui_support.dart';
import 'support/fake_scan_ports.dart';
import 'support/history_wait.dart';

class _EmptyCredentials implements CredentialStore {
  @override
  Future<String?> readCredential(GameMode mode) async => null;
  @override
  Future<void> writeCredential(GameMode mode, String token) async {}
  @override
  Future<void> removeCredential(GameMode mode) async {}
}

final _marker = VisionTemplate(
  'inspectionMarker',
  VisionImage(Uint8List(1), width: 1, height: 1, stride: 1, channels: 1),
);

/// An [AppServices] over an in-memory database whose scan factories only
/// record what they were asked to build.
class _Rig {
  _Rig({this.liveScanSaved = false}) {
    database = BlackgridDatabase(NativeDatabase.memory());
    logs = Directory.systemTemp.createTempSync('blackgrid-app-scan-');
    services = AppServices(
      database: database,
      credentials: _EmptyCredentials(),
      client: MockClient((_) async => http.Response('', 503)),
      scanLogDirectory: logs,
      scanRuntimeDirectory: runtimeDirectory,
      scanMarkerLoader: (directory) async {
        events.add('template');
        return MarkerTemplateLoaded(_marker);
      },
      scanCaptureFactory: () {
        events.add('capture.create');
        return FakeScanCapture(events);
      },
      scanVisionFactory: (marker, directory) {
        events.add('vision.create');
        visionDirectories.add(directory);
        return FakeScanVision(events);
      },
      scanPlatformFactory: () {
        events.add('platform.open');
        return FakeScanPlatform(events);
      },
    );
  }

  static const runtimeDirectory = r'C:\fake\bundle';

  late final BlackgridDatabase database;
  late final Directory logs;
  late final AppServices services;
  final bool liveScanSaved;
  final ScanEventLog events = [];
  final List<String> visionDirectories = [];

  Future<void> start() async {
    if (liveScanSaved) {
      await services.settings.save(AppSettings(liveScan: true));
    }
    await services.initialize();
    await services.scanner.settled;
  }

  Future<void> dispose() async {
    await services.dispose();
    await logs.delete(recursive: true);
  }
}

void main() {
  test(
    'launch with live scan off starts no worker, hook or vision runtime',
    () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.start();
      expect(rig.events, isEmpty);
      expect(rig.visionDirectories, isEmpty);
      expect(rig.services.scanner.status.state, LiveScanState.off);
      expect(rig.events.where((e) => e.startsWith('hotkey.')), isEmpty);
      expect(rig.services.scanner.hotkeyState, const ScanHotkeyInactive());
    },
  );

  test(
    'launch with live scan saved on starts exactly one vision service',
    () async {
      final rig = _Rig(liveScanSaved: true);
      addTearDown(rig.dispose);
      await rig.start();
      expect(rig.events.where((e) => e == 'vision.create'), hasLength(1));
      expect(rig.events.where((e) => e == 'platform.open'), hasLength(1));
      expect(rig.services.scanner.status.state, LiveScanState.ready);
      // Re-initialising (for example after an import) starts nothing more.
      await rig.services.initialize();
      await rig.services.scanner.settled;
      expect(rig.events.where((e) => e == 'vision.create'), hasLength(1));
    },
  );

  test(
    'live scan on opens the runtime only through the vision service opener',
    () async {
      final rig = _Rig(liveScanSaved: true);
      addTearDown(rig.dispose);
      await rig.start();
      // The vision factory is the one entry that would load the runtime, and
      // it receives the bundle runtime directory.
      expect(rig.visionDirectories, [_Rig.runtimeDirectory]);
      expect(rig.services.scanner.runtimeDirectory, _Rig.runtimeDirectory);
    },
  );

  test('accepted scan through AppServices selects and records once', () async {
    final ports = ScanFakePorts();
    final h = M1Harness(scanPorts: ports);
    addTearDown(h.dispose);
    await h.initialize();

    final report = await publishTargetedScan(
      h.services.scanner,
      ports,
      text: 'Alternative component',
    );
    expect((report.end as ScanAccepted).itemId, 'item-b');
    await untilRow(
      h.services.history,
      (row) => row.itemId == 'item-b' && row.source == ActivitySource.scan,
    );

    final selection = h.services.selection;
    expect(selection.selectedId, 'item-b');
    expect(selection.scan?.reportId, report.id);
    expect(h.services.history.rows, hasLength(1));
    final recorded = h.services.history.rows.single;

    // A phase change notifies the scanner without a new accepted scan.
    await h.services.scanner.setLiveScan(false);
    await h.services.scanner.settled;

    expect(selection.scan?.reportId, report.id);
    expect(h.services.history.rows.single.observedAt, recorded.observedAt);
    expect(h.services.history.rows, hasLength(1));
  });

  test('session change through AppServices retires the scan', () async {
    final ports = ScanFakePorts();
    final h = M1Harness(scanPorts: ports);
    addTearDown(h.dispose);
    await h.initialize();
    final logs = Directory.systemTemp.createTempSync('blackgrid-app-session-');
    addTearDown(() => logs.delete(recursive: true));

    await publishTargetedScan(
      h.services.scanner,
      ports,
      text: 'Alternative component',
    );
    await untilRow(
      h.services.history,
      (row) => row.itemId == 'item-b' && row.source == ActivitySource.scan,
    );
    final selection = h.services.selection;
    selection.setFir(FirState.yes);
    expect(h.services.scans.hasAcceptedScan, isTrue);
    final session = h.services.mapSession.state.sessionEpoch;

    // A new game-log directory is a new session in the same mode.
    await h.services.settings.setMapInputs(gameLogDirectory: logs.path);

    expect(h.services.mapSession.state.sessionEpoch, greaterThan(session));
    expect(h.services.catalog.mode, GameMode.pvp);
    expect(selection.scan, isNull);
    expect(selection.scanRetired, isTrue);
    expect(selection.fir, FirState.unknown);
    expect(h.services.history.rows, hasLength(1));
    expect(h.services.scans.hasAcceptedScan, isFalse);
    expect(h.services.scans.latest, isNull);
  });

  test('latest scan starts empty with scan history present', () async {
    final ports = ScanFakePorts();
    final first = M1Harness(scanPorts: ports);
    addTearDown(first.dispose);
    await first.initialize();
    await publishTargetedScan(
      first.services.scanner,
      ports,
      text: 'Alternative component',
    );
    await untilRow(
      first.services.history,
      (row) => row.itemId == 'item-b' && row.source == ActivitySource.scan,
    );
    expect(first.services.scans.hasAcceptedScan, isTrue);

    // A restart over the same database holds the scan row but no latest scan.
    final second = M1Harness(database: first.db, scanPorts: ScanFakePorts());
    addTearDown(second.dispose);
    await second.initialize();

    expect(
      second.services.history.rows.any(
        (row) => row.itemId == 'item-b' && row.source == ActivitySource.scan,
      ),
      isTrue,
    );
    expect(second.services.scans.latest, isNull);
    expect(second.services.scans.hasAcceptedScan, isFalse);
  });
}
