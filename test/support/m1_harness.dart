import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/item_icon_cache.dart';
import 'package:blackgrid/application/progress_authority.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/local_progress_store.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../ui/support/scan_ui_support.dart';

class M1Harness {
  M1Harness({
    BlackgridDatabase? database,
    ScanFakePorts? scanPorts,
    ItemIconCache? itemIcons,
    ScanFrameRecorder? scanFrameRecorder,
    DateTime Function()? clock,
    void Function(Map<String, dynamic> wire)? shapeWire,
  }) {
    final wire = wireFixture();
    shapeWire?.call(wire);
    db = database ?? BlackgridDatabase(NativeDatabase.memory());
    if (scanPorts != null) {
      scanLogs = Directory.systemTemp.createTempSync('blackgrid-m1-scan-');
    }
    services = AppServices(
      database: db,
      clock: clock ?? () => fixtureNow,
      client: MockClient((request) async {
        requests.add(request);
        if (failNetwork) return http.Response('synthetic unavailable', 503);
        final key = request.url.pathSegments.last;
        if (wire.containsKey(key)) {
          return http.Response(jsonEncode(wire[key]), 200);
        }
        return http.Response('{}', 404);
      }),
      itemIcons: itemIcons,
      scanFrameRecorder: scanFrameRecorder,
      scanLogDirectory: scanLogs,
      scanRuntimeDirectory: scanPorts == null ? null : r'C:\fake\bundle',
      scanTemplatesLoader: scanPorts?.loader,
      scanCaptureFactory: scanPorts?.captureFactory,
      scanVisionFactory: scanPorts?.visionFactory,
      scanPlatformFactory: scanPorts?.platformFactory,
      scanWaiter: scanPorts?.waiter,
    );
  }
  late final BlackgridDatabase db;
  late final AppServices services;
  Directory? scanLogs;
  final requests = <http.Request>[];
  bool failNetwork = false;
  Future<void> initialize({
    GameMode mode = GameMode.pvp,
    bool refresh = true,
  }) async {
    await services.initialize();
    await services.setMode(mode);
    if (refresh && mode != GameMode.unknown) await services.catalog.refresh();
  }

  /// Completes once local progress is published for the applied mode.
  ///
  /// Waits on the authority's own notifications, so nothing sleeps.
  Future<void> progressReady() {
    final progress = services.progress;
    bool ready() =>
        progress.status == ProgressAuthorityStatus.local &&
        progress.mode == services.catalog.mode;
    if (ready()) return Future.value();
    final done = Completer<void>();
    void listener() {
      if (!ready()) return;
      progress.removeListener(listener);
      done.complete();
    }

    progress.addListener(listener);
    return done.future;
  }

  /// Records the player [level] in the applied mode's wipe by hand and
  /// completes once the authority publishes it.
  Future<void> recordPlayerLevel(int level) async {
    final progress = services.progress;
    final result = await services.localProgress.appendManual(
      services.catalog.mode,
      const ProgressTarget(
        kind: ProgressEntityKind.player,
        id: 'self',
        field: ProgressField.level,
      ),
      ProgressInteger(level),
    );
    if (result is! ProgressSuccess<ProgressEvent>) {
      throw StateError('Recording the level failed: $result');
    }
    bool ready() =>
        progress.status == ProgressAuthorityStatus.local &&
        progress.facts?.level == level;
    if (ready()) return;
    final done = Completer<void>();
    void listener() {
      if (!ready()) return;
      progress.removeListener(listener);
      done.complete();
    }

    progress.addListener(listener);
    await done.future;
  }

  Future<void> dispose() async {
    await services.dispose();
    final logs = scanLogs;
    if (logs != null && logs.existsSync()) logs.deleteSync(recursive: true);
  }
}
