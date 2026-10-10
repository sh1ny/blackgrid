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
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_scan_ports.dart';

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
}
