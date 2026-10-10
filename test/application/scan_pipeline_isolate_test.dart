/// The scan coordinator over the real capture and vision services, each with
/// its own worker isolate, on holdable fakes in shared native memory.
///
/// Both tests run in well under a second and need no native DLLs, so they stay
/// in the fast loop.
@Timeout(Duration(seconds: 20))
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/capture/capture_service.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/capture/mouse_release_trigger_source.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/vision/inspection_recognition.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:blackgrid/data/vision/vision_service.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/catalog_store.dart';
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../data/capture/support/fake_capture_platform.dart';
import '../data/capture/support/holdable_capture_platform.dart';
import '../data/vision/support/clock_capture_platform.dart';
import '../data/vision/support/holdable_vision_native.dart';
import '../data/vision/support/shared_frame_registry.dart';
import 'support/fake_scan_ports.dart';

/// A recognition job that makes one held, counted native call and then reports
/// a marker-less frame, so no matcher or catalog is needed. Top-level so the
/// worker isolate can build it.
final class _HeldRecognitionJob
    implements VisionJob<InspectionRequest, InspectionRecognition> {
  const _HeldRecognitionJob();

  @override
  InspectionRecognition run(
    VisionJobContext context,
    VisionJobInput input,
    InspectionRequest params,
  ) => input.withImage(
    (image) => switch (context.recognise(image)) {
      VisionOk() => InspectionRecognised(
        kind: params.kind,
        scale: 1,
        bestMarkerScore: 0.5,
        evidence: const [],
      ),
      VisionFailed(:final failure) => throw VisionJobAbort(failure),
    },
  );
}

VisionJob<InspectionRequest, InspectionRecognition> _heldJobFactory() =>
    const _HeldRecognitionJob();

class _EmptyStore implements CatalogStore {
  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async => null;

  @override
  Future<void> commitCatalog(CatalogSnapshot snapshot) async {}
}

/// The coordinator over real services, and the shared native state behind them.
final class _Rig {
  _Rig({required Duration closeDrain, required Duration closeTimeout})
    : vision = VisionControlBlock(),
      frames = FakeFrameRegistry.create(),
      captureControl = allocateControl(),
      runtimeDir = createFakeRuntimeDirectory(),
      db = BlackgridDatabase(NativeDatabase.memory()) {
    settings = SettingsController(db);
    catalog = CatalogController(
      store: _EmptyStore(),
      client: CatalogClient(
        client: MockClient((_) async => http.Response('', 500)),
      ),
    );
    final marker = VisionTemplate(
      'inspectionMarker',
      VisionImage(
        Uint8List.fromList([0, 255, 255, 0]),
        width: 2,
        height: 2,
        stride: 2,
        channels: 1,
      ),
    );
    coordinator = ScanCoordinator(
      settings: settings,
      catalog: catalog,
      appendLogLine: logs.add,
      runtimeDirectory: runtimeDir.path,
      closeTimeout: closeTimeout,
      markerLoader: (_) async => MarkerTemplateLoaded(marker),
      captureFactory: () {
        final service = CaptureService(
          platformFactory: holdableFactory(
            frames.address,
            captureControl.address,
          ),
          registryFactory: sharedFrameRegistryFactory(frames.address),
          closeDrain: closeDrain,
        );
        captureServices.add(service);
        return scanCapturePort(service);
      },
      visionFactory: (marker, directory) {
        final service = VisionService<InspectionRequest, InspectionRecognition>(
          runtimeDirectory: directory,
          jobFactory: _heldJobFactory,
          templates: [marker],
          opener: holdableVisionOpener(vision.address),
          platformFactory: clockPlatformFactory(vision.address),
          registryFactory: sharedFrameRegistryFactory(frames.address),
          qpcNow: vision.clock.now,
          deadline: const Duration(seconds: 10),
          closeDrain: closeDrain,
        );
        visionServices.add(service);
        return scanVisionPort(service);
      },
      platformFactory: () => platform = FakeScanPlatform(events),
    );
    coordinator.addListener(_observe);
  }

  final VisionControlBlock vision;
  final FakeFrameRegistry frames;
  final Pointer<Int64> captureControl;
  final Directory runtimeDir;
  final BlackgridDatabase db;
  late final SettingsController settings;
  late final CatalogController catalog;
  late final ScanCoordinator coordinator;

  final ScanEventLog events = [];
  final CallLog<Map<String, Object?>> logs = CallLog<Map<String, Object?>>();
  final CallLog<ScanReport> published = CallLog<ScanReport>();
  final List<CaptureService> captureServices = [];
  final List<VisionService<InspectionRequest, InspectionRecognition>>
  visionServices = [];
  FakeScanPlatform? platform;
  int notifications = 0;
  ScanReport? _lastLatest;

  void _observe() {
    notifications++;
    final latest = coordinator.latest;
    if (latest != null && !identical(latest, _lastLatest)) {
      _lastLatest = latest;
      published.add(latest);
    }
  }

  Future<void> ready() async {
    await coordinator.setLiveScan(true);
    await coordinator.settled;
    expect(
      coordinator.status.state,
      LiveScanState.ready,
      reason: coordinator.status.reason,
    );
  }

  void fire(int qpc) => platform!.trigger.emit(
    ScanTrigger(
      TriggerEvent(
        x: 900,
        y: 500,
        hwnd: holdableHwnd,
        pid: holdablePid,
        tid: holdableTid,
        qpc: qpc,
      ),
      0,
    ),
  );

  /// Releases every hold, closes everything and frees the shared memory once
  /// no worker can touch it any more.
  Future<void> dispose() async {
    vision.held = false;
    await coordinator.dispose();
    for (final service in visionServices) {
      await service.workerExit.timeout(const Duration(seconds: 5));
    }
    for (final service in captureServices) {
      await service.workerExit.timeout(const Duration(seconds: 5));
    }
    settings.dispose();
    catalog.dispose();
    await db.close();
    expect(frames.liveCount, 0, reason: 'live frames at teardown');
    vision.free();
    calloc.free(captureControl);
    runtimeDir.deleteSync(recursive: true);
  }
}

void main() {
  test('trigger during vision invalidates, never overlaps native calls, '
      'never publishes the old result', () async {
    final rig = _Rig(
      closeDrain: const Duration(seconds: 2),
      closeTimeout: const Duration(seconds: 3),
    );
    addTearDown(rig.dispose);
    await rig.ready();

    // Scan 1 reaches the vision worker and blocks inside the native call.
    rig.vision.held = true;
    rig.fire(1000);
    await eventually(() => rig.vision.concurrent == 1);
    expect(Isolate.current.debugName, isNot('bgv_worker'));

    // Trigger 2 invalidates scan 1 at once and starts scan 2, whose frame
    // waits in the service's pending slot behind the held call.
    rig.fire(2000);
    final superseded = await rig.logs.at(0);
    expect(superseded['end'], 'superseded');
    expect(rig.coordinator.latest, isNull, reason: 'scan 1 never publishes');
    expect(rig.vision.operationCount, 1, reason: 'no second native call yet');

    rig.vision.held = false;
    final report = await rig.published.at(0);

    expect(report.timeline.trigger, 2000, reason: 'scan 2 published');
    expect(report.id, 2);
    expect(report.end, isA<ScanRejected>());
    expect(
      (report.end as ScanRejected).reason,
      ScanRejectReason.catalogUnavailable,
    );
    expect(rig.published.length, 1, reason: 'the old result is discarded');
    expect(rig.coordinator.recent, hasLength(1));
    expect(rig.logs.length, 2);
    expect(rig.logs[1]['end'], 'rejected');
    expect(rig.vision.operationCount, 2, reason: 'one native call per scan');
    expect(rig.vision.maxConcurrent, 1, reason: 'native calls never overlap');
    expect(rig.vision.concurrent, 0);
    await eventually(() => rig.frames.liveCount == 0);
    expect(rig.frames.effectiveReleases, 2, reason: 'each frame once');
  });

  test('dispose with a held native call completes after the drain and '
      'publishes nothing', () async {
    const drain = Duration(milliseconds: 150);
    final rig = _Rig(
      closeDrain: drain,
      closeTimeout: const Duration(milliseconds: 400),
    );
    addTearDown(rig.dispose);
    await rig.ready();

    rig.vision.held = true;
    rig.fire(1000);
    await eventually(() => rig.vision.concurrent == 1);
    final before = rig.notifications;

    final elapsed = Stopwatch()..start();
    await rig.coordinator.dispose();
    elapsed.stop();

    expect(
      elapsed.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 100)),
      reason: 'dispose waited for the drain',
    );
    expect(
      elapsed.elapsed,
      lessThan(const Duration(seconds: 3)),
      reason: 'and was bounded by it',
    );
    expect(rig.notifications, before, reason: 'no listener after dispose');
    expect(rig.published.length, 0);
    expect(rig.coordinator.latest, isNull);
    expect(rig.coordinator.recent, isEmpty);
    expect(rig.coordinator.status.stopWarning, isNotNull);
    expect((await rig.logs.at(0))['end'], 'superseded');
    expect(rig.vision.concurrent, 1, reason: 'the held call was not killed');
    expect(
      rig.vision.engineDisposeCount,
      0,
      reason: 'the runtime is never disposed under a running call',
    );

    // Releasing the call lets the worker dispose its runtime and exit by
    // itself; it must still publish nothing.
    rig.vision.held = false;
    await rig.visionServices.single.workerExit.timeout(
      const Duration(seconds: 5),
    );
    expect(rig.vision.engineDisposeCount, 1);
    expect(rig.vision.maxConcurrent, 1);
    expect(rig.notifications, before);
    expect(rig.published.length, 0);
  });
}
