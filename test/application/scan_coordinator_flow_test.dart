@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/capture/mouse_release_trigger_source.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_image.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/catalog_store.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/m1_harness.dart';
import 'support/fake_scan_ports.dart';

class _Store implements CatalogStore {
  _Store(this.snapshots);

  final Map<GameMode, CatalogSnapshot> snapshots;

  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async => snapshots[mode];

  @override
  Future<void> commitCatalog(CatalogSnapshot snapshot) async {}
}

CatalogSnapshot _snapshot(GameMode mode, String revision) => CatalogSnapshot(
  mode: mode,
  revision: revision,
  observedAt: DateTime.utc(2026, 1, 1),
  items: {
    'kit': CatalogItem(
      id: 'kit',
      name: 'Salewa First Aid Kit',
      normalizedName: 'salewa-first-aid-kit',
    ),
  },
  traders: const {},
  requirements: const [],
);

final _marker = VisionTemplate(
  'inspectionMarker',
  VisionImage(Uint8List(1), width: 1, height: 1, stride: 1, channels: 1),
);

InspectionEvidence _ev({
  String text = 'Salewa First Aid Kit',
  double score = 0.93,
  int base = 0,
}) => InspectionEvidence(
  markerScore: score,
  markerX: 10 + base,
  markerY: 20,
  titleRect: const TitleRegion(x: 1, y: 2, width: 30, height: 8),
  titleStatus: InspectionTitleStatus.read,
  text: text,
  crop: Uint8List.fromList(List<int>.filled(16, 7)),
  cropWidth: 4,
  cropHeight: 4,
  cropDownscaled: false,
  qpcMarker: base + 1,
  qpcTitle: base + 2,
  qpcPreprocess: base + 3,
  qpcOcr: base + 4,
);

InspectionRecognised _recognised(
  InspectionFrameKind kind,
  List<InspectionEvidence> evidence,
) => InspectionRecognised(
  kind: kind,
  scale: 1,
  bestMarkerScore: evidence.isEmpty ? 0.2 : evidence.first.markerScore,
  evidence: evidence,
);

TitleAccepted _titleAccepted(String id) => TitleAccepted(
  bestId: id,
  normalisedTitle: 'salewa first aid kit',
  bestScore: 0.97,
  runnerUpId: null,
  runnerUpScore: 0,
  margin: 0.97,
  confirmedBy: null,
  mode: GameMode.pvp,
  revision: 'r1',
);

OutcomeAccepted<InspectionEvidence> _accepted(
  InspectionEvidence evidence, [
  String id = 'kit',
]) => OutcomeAccepted<InspectionEvidence>(_titleAccepted(id), evidence);

OutcomeRejected<InspectionEvidence> _rejected(
  OutcomeRejectReason reason, [
  InspectionEvidence? evidence,
]) => OutcomeRejected<InspectionEvidence>(
  reason,
  evidence: evidence,
  targetedBestMarkerScore: 0.5,
);

/// Everything one flow test needs: the coordinator over real settings and
/// catalog controllers, and hand-written ports that wait for the test.
final class _Rig {
  _Rig({
    required this.settings,
    required this.catalog,
    this.onDispose,
    ScanEpoch Function()? epoch,
  }) {
    coordinator = ScanCoordinator(
      settings: settings,
      catalog: catalog,
      appendLogLine: logs.add,
      runtimeDirectory: r'C:\fake\bundle',
      closeTimeout: const Duration(milliseconds: 500),
      indexBuilder: builder.call,
      matcher: matcher.call,
      markerLoader: (_) async => MarkerTemplateLoaded(_marker),
      captureFactory: () {
        final created = FakeScanCapture(events);
        captures.add(created);
        return created;
      },
      visionFactory: (_, _) {
        final created = FakeScanVision(events);
        visions.add(created);
        return created;
      },
      platformFactory: () => platform = FakeScanPlatform(events),
      waiter: waiter.call,
      epoch: epoch,
    );
    coordinator.addListener(_observe);
  }

  static Future<_Rig> standalone({
    Map<GameMode, CatalogSnapshot> snapshots = const {},
    ScanEpoch Function()? epoch,
  }) async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    final settings = SettingsController(db);
    await settings.load();
    final catalog = CatalogController(
      store: _Store(snapshots),
      client: CatalogClient(
        client: MockClient((_) async => http.Response('', 500)),
      ),
    );
    return _Rig(
      settings: settings,
      catalog: catalog,
      epoch: epoch,
      onDispose: () async {
        settings.dispose();
        catalog.dispose();
        await db.close();
      },
    );
  }

  final SettingsController settings;
  final CatalogController catalog;
  final Future<void> Function()? onDispose;
  late final ScanCoordinator coordinator;

  final ScanEventLog events = [];
  final FakeScanFrames frames = FakeScanFrames();
  final FakeScanMatcher matcher = FakeScanMatcher();
  final FakeIndexBuilder builder = FakeIndexBuilder();
  final FakeScanWaiter waiter = FakeScanWaiter();
  final CallLog<Map<String, Object?>> logs = CallLog<Map<String, Object?>>();
  final CallLog<ScanReport> published = CallLog<ScanReport>();
  final List<ScanPhase> phases = [];
  final List<FakeScanCapture> captures = [];
  final List<FakeScanVision> visions = [];
  FakeScanPlatform? platform;
  int notifications = 0;

  ScanPhase _lastPhase = ScanPhase.idle;
  ScanReport? _lastLatest;

  FakeScanCapture get capture => captures.last;
  FakeScanVision get vision => visions.last;
  FakeScanClock get clock => platform!.clock;
  FakeScanTrigger get trigger => platform!.trigger;

  void _observe() {
    notifications++;
    final phase = coordinator.phase;
    if (phase != _lastPhase) {
      _lastPhase = phase;
      phases.add(phase);
      events.add('phase.${phase.name}');
    }
    final latest = coordinator.latest;
    if (latest != null && !identical(latest, _lastLatest)) {
      _lastLatest = latest;
      published.add(latest);
    }
  }

  /// Loads the catalog snapshot of [mode] from the store.
  Future<void> loadCatalog(GameMode mode) => catalog.setMode(mode);

  Future<void> ready() async {
    await coordinator.setLiveScan(true);
    await coordinator.settled;
    expect(coordinator.status.state, LiveScanState.ready);
  }

  void fire(int qpc, {int dropped = 0}) => trigger.emit(
    ScanTrigger(
      TriggerEvent(x: 10, y: 20, hwnd: 1, pid: 2, tid: 3, qpc: qpc),
      dropped,
    ),
  );

  /// Drives scan number [n] (counting from 0, every earlier scan having made
  /// one capture, vision and match call) to an accepted targeted result.
  Future<ScanReport> acceptTargeted(int n, int qpc, [String id = 'kit']) async {
    fire(qpc);
    (await capture.calls.at(n)).succeed(frames.frame());
    final evidence = _ev();
    (await vision.calls.at(n))
        .deliver(_recognised(InspectionFrameKind.targeted, [evidence]));
    (await matcher.calls.at(n)).complete(_accepted(evidence, id));
    return published.at(n);
  }

  /// Drives a targeted scan to its matching stage and returns the held match.
  Future<FakeMatchCall> toMatching(int n, int qpc) async {
    fire(qpc);
    (await capture.calls.at(n)).succeed(frames.frame());
    (await vision.calls.at(n))
        .deliver(_recognised(InspectionFrameKind.targeted, [_ev()]));
    return matcher.calls.at(n);
  }

  Future<void> dispose() async {
    await coordinator.dispose();
    await onDispose?.call();
  }
}

/// The stamps of [pass] in stage order, absent ones as null.
List<int?> _stages(PassTimeline pass) => [
  pass.captureRequested,
  pass.acquireStart,
  pass.acquireEnd,
  pass.captureAnswered,
  pass.visionSubmitted,
  pass.jobStarted,
  pass.marker,
  pass.title,
  pass.preprocess,
  pass.ocr,
  pass.jobFinished,
  pass.matchStarted,
  pass.matchFinished,
];

void main() {
  late _Rig rig;

  Future<_Rig> readyRig({
    GameMode loaded = GameMode.pvp,
    Map<GameMode, CatalogSnapshot>? snapshots,
    ScanEpoch Function()? epoch,
  }) async {
    rig = await _Rig.standalone(
      epoch: epoch,
      snapshots:
          snapshots ??
          {
            GameMode.pvp: _snapshot(GameMode.pvp, 'r1'),
            GameMode.pve: _snapshot(GameMode.pve, 'r2'),
          },
    );
    if (loaded != GameMode.unknown) await rig.loadCatalog(loaded);
    await rig.ready();
    return rig;
  }

  tearDown(() => rig.dispose());

  test('the epoch is stamped when the scan begins', () async {
    const e0 = ScanEpoch(1, 1);
    const e1 = ScanEpoch(2, 1);
    var current = e0;
    await readyRig(epoch: () => current);
    rig.fire(1000);
    (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
    final evidence = _ev();
    (await rig.vision.calls.at(0))
        .deliver(_recognised(InspectionFrameKind.targeted, [evidence]));
    final match = await rig.matcher.calls.at(0);
    current = e1;
    match.complete(_accepted(evidence));

    final report = await rig.published.at(0);
    expect(report.epoch, e0);
    expect(report.withoutCrops().epoch, e0);
    expect(rig.coordinator.recent.first.epoch, e0);
    expect(rig.logs[0].containsKey('epoch'), isFalse);
  });

  test(
    'a trigger queued behind capture keeps its trigger-time epoch',
    () async {
      const e0 = ScanEpoch(1, 1);
      const e1 = ScanEpoch(2, 1);
      var current = e0;
      await readyRig(epoch: () => current);
      rig.fire(1000);
      final first = await rig.capture.calls.at(0);
      rig.fire(2000);
      // The mode changes while the newer trigger waits for the capture answer.
      current = e1;
      first.succeed(rig.frames.frame());
      (await rig.capture.calls.at(1)).succeed(rig.frames.frame());
      final evidence = _ev();
      (await rig.vision.calls.at(0))
          .deliver(_recognised(InspectionFrameKind.targeted, [evidence]));
      (await rig.matcher.calls.at(0)).complete(_accepted(evidence));

      final report = await rig.published.at(0);
      expect(report.timeline.trigger, 2000);
      expect(report.epoch, e0);
    },
  );

  group('passes', () {
    test('accepted targeted scan requests no fallback', () async {
      await readyRig();
      rig.fire(1000);
      final capture = await rig.capture.calls.at(0);
      expect(capture.mode, CaptureMode.targeted);
      expect(rig.coordinator.phase, ScanPhase.targeted);

      capture.succeed(rig.frames.frame(clientWidth: 2560, clientHeight: 1440));
      final vision = await rig.vision.calls.at(0);
      expect(vision.request.kind, InspectionFrameKind.targeted);
      expect(vision.request.clientWidth, 2560);
      expect(vision.request.clientHeight, 1440);

      final evidence = _ev();
      final recognition = _recognised(InspectionFrameKind.targeted, [evidence]);
      vision.deliver(recognition);
      final match = await rig.matcher.calls.at(0);
      expect(match.targeted, same(recognition));
      expect(match.fullClient, isNull);
      expect(match.mode, GameMode.pvp);
      match.complete(_accepted(evidence));

      final report = await rig.published.at(0);
      expect(report.end, isA<ScanAccepted>());
      expect((report.end as ScanAccepted).itemId, 'kit');
      expect(report.winningPass, ScanPass.targeted);
      expect(report.fallback, isNull);
      expect(rig.capture.calls.length, 1);
      expect(rig.coordinator.phase, ScanPhase.idle);
      expect(rig.coordinator.latest, same(report));
      expect(rig.logs.length, 1);
      expect(rig.logs[0]['end'], 'accepted');
      expect(rig.logs[0]['item'], 'kit');
    });

    test('targetNotForeground ends failed without fallback', () async {
      await readyRig();
      rig.fire(1000);
      (await rig.capture.calls.at(0)).fail(const TargetNotForeground());

      final report = await rig.published.at(0);
      final end = report.end as ScanFailed;
      expect(end.failure.code, ScanFailureCode.targetNotForeground);
      expect(end.targetedFailure, isNull);
      expect(
        report.targeted?.failure?.code,
        ScanFailureCode.targetNotForeground,
      );
      expect(report.fallback, isNull);
      expect(rig.capture.calls.length, 1);
      expect(rig.vision.calls.length, 0);
      expect(rig.matcher.calls.length, 0);
      expect(rig.logs[0]['end'], 'failed');
      expect(rig.logs[0]['reason'], 'targetNotForeground');
    });

    test(
      'noMarker publishes fallback phase then accepts from fallback',
      () async {
        await readyRig();
        rig.fire(1000);
        (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
        final targeted = _recognised(InspectionFrameKind.targeted, []);
        (await rig.vision.calls.at(0)).deliver(targeted);
        (await rig.matcher.calls.at(0))
            .complete(_rejected(OutcomeRejectReason.noMarker));

        final fallbackCapture = await rig.capture.calls.at(1);
        expect(fallbackCapture.mode, CaptureMode.fallback);
        expect(
          fallbackCapture.trigger,
          same((await rig.capture.calls.at(0)).trigger),
        );
        expect(rig.coordinator.phase, ScanPhase.fallback);
        expect(
          rig.events.indexOf('phase.fallback'),
          lessThan(rig.events.indexOf('capture.fallback')),
          reason: 'the fallback phase is published before the capture request',
        );

        fallbackCapture.succeed(
          rig.frames.frame(clientWidth: 1920, clientHeight: 1080),
        );
        final fallbackVision = await rig.vision.calls.at(1);
        expect(fallbackVision.request.kind, InspectionFrameKind.fullClient);
        expect(fallbackVision.request.clientWidth, 1920);
        expect(fallbackVision.request.clientHeight, 1080);
        final evidence = _ev(base: 100);
        final fullClient = _recognised(InspectionFrameKind.fullClient, [
          evidence,
        ]);
        fallbackVision.deliver(fullClient);
        final match = await rig.matcher.calls.at(1);
        expect(match.targeted, same(targeted));
        expect(match.fullClient, same(fullClient));
        match.complete(_accepted(evidence));

        final report = await rig.published.at(0);
        expect(report.end, isA<ScanAccepted>());
        expect(report.winningPass, ScanPass.fallback);
        expect(report.targeted?.recognition, same(targeted));
        expect(report.fallback?.recognition, same(fullClient));
        expect(rig.logs.length, 1);
        expect(rig.logs[0]['pass'], 'fallback');
      },
    );

    test('both passes rejected keeps both evidences', () async {
      await readyRig();
      rig.fire(1000);
      (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
      final targetedEv = _ev(text: 'Salewa Frst Aid');
      final targeted = _recognised(InspectionFrameKind.targeted, [targetedEv]);
      (await rig.vision.calls.at(0)).deliver(targeted);
      (await rig.matcher.calls.at(0))
          .complete(_rejected(OutcomeRejectReason.belowSimilarity, targetedEv));
      (await rig.capture.calls.at(1)).succeed(rig.frames.frame());
      final fallbackEv = _ev(text: 'Sale Fist Kit', base: 100);
      final fullClient = _recognised(InspectionFrameKind.fullClient, [
        fallbackEv,
      ]);
      (await rig.vision.calls.at(1)).deliver(fullClient);
      final outcome = _rejected(OutcomeRejectReason.ambiguous, fallbackEv);
      (await rig.matcher.calls.at(1)).complete(outcome);

      final report = await rig.published.at(0);
      final end = report.end as ScanRejected;
      expect(end.reason, ScanRejectReason.ambiguous);
      expect(end.outcome, same(outcome));
      expect(end.fallbackFailure, isNull);
      expect(report.targeted?.recognition, same(targeted));
      expect(report.fallback?.recognition, same(fullClient));
      expect(report.winningPass, ScanPass.fallback);
      expect(rig.logs[0]['end'], 'rejected');
      expect(rig.logs[0]['reason'], 'ambiguous');
    });

    test('visionTimeout ends failed without fallback', () async {
      await readyRig();
      rig.fire(1000);
      (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
      (await rig.vision.calls.at(0))
          .answer(const VisionDeadlineExceeded<InspectionRecognition>(5));

      final report = await rig.published.at(0);
      expect(
        (report.end as ScanFailed).failure.code,
        ScanFailureCode.visionTimeout,
      );
      expect(rig.capture.calls.length, 1);
      expect(rig.matcher.calls.length, 0);
      expect(report.timeline.targeted?.visionSubmitted, 5);
    });

    test('fallback targetGone keeps the targeted rejection', () async {
      await readyRig();
      rig.fire(1000);
      (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
      final evidence = _ev(text: 'Salewa Frst Aid');
      (await rig.vision.calls.at(0))
          .deliver(_recognised(InspectionFrameKind.targeted, [evidence]));
      final outcome = _rejected(OutcomeRejectReason.belowSimilarity, evidence);
      (await rig.matcher.calls.at(0)).complete(outcome);
      (await rig.capture.calls.at(1)).fail(const TargetGone());

      final report = await rig.published.at(0);
      final end = report.end as ScanRejected;
      expect(end.reason, ScanRejectReason.belowSimilarity);
      expect(end.outcome, same(outcome));
      expect(end.fallbackFailure?.code, ScanFailureCode.targetGone);
      expect(report.fallback?.failure?.code, ScanFailureCode.targetGone);
      expect(rig.matcher.calls.length, 1);
      expect(rig.logs[0]['end'], 'rejected');
    });

    test('blankCapture twice ends failed with both failures', () async {
      await readyRig();
      rig.fire(1000);
      (await rig.capture.calls.at(0)).fail(const BlankCapture());
      expect(rig.matcher.calls.length, 0);
      (await rig.capture.calls.at(1)).fail(const BlankCapture());

      final report = await rig.published.at(0);
      final end = report.end as ScanFailed;
      expect(end.failure.code, ScanFailureCode.blankCapture);
      expect(end.targetedFailure?.code, ScanFailureCode.blankCapture);
      expect(report.targeted?.failure?.code, ScanFailureCode.blankCapture);
      expect(report.fallback?.failure?.code, ScanFailureCode.blankCapture);
      expect(rig.matcher.calls.length, 0);
      expect(rig.vision.calls.length, 0);
    });

    test(
      'targeted capture failure then fallback matches without targeted',
      () async {
        await readyRig();
        rig.fire(1000);
        (await rig.capture.calls.at(0)).fail(const RoiOutsideClient());
        (await rig.capture.calls.at(1)).succeed(rig.frames.frame());
        final evidence = _ev(base: 100);
        (await rig.vision.calls.at(0))
            .deliver(_recognised(InspectionFrameKind.fullClient, [evidence]));
        final match = await rig.matcher.calls.at(0);
        expect(match.targeted, isNull);
        expect(match.fullClient, isNotNull);
        match.complete(_accepted(evidence));

        final report = await rig.published.at(0);
        expect(report.end, isA<ScanAccepted>());
        expect(report.winningPass, ScanPass.fallback);
        expect(
          report.targeted?.failure?.code,
          ScanFailureCode.roiOutsideClient,
        );
      },
    );

    test('catalogModeMismatch requests no fallback', () async {
      await readyRig();
      rig.fire(1000);
      (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
      final evidence = _ev();
      (await rig.vision.calls.at(0))
          .deliver(_recognised(InspectionFrameKind.targeted, [evidence]));
      (await rig.matcher.calls.at(
        0,
      )).complete(_rejected(OutcomeRejectReason.catalogModeMismatch, evidence));

      final report = await rig.published.at(0);
      expect(
        (report.end as ScanRejected).reason,
        ScanRejectReason.catalogModeMismatch,
      );
      expect(rig.capture.calls.length, 1);
      expect(rig.matcher.calls.length, 1);
    });

    test(
      'capture unavailable answer fails the scan and the activation',
      () async {
        await readyRig();
        rig.fire(1000);
        (await rig.capture.calls.at(0)).fail(const CaptureUnavailable('gone'));

        final report = await rig.published.at(0);
        expect(
          (report.end as ScanFailed).failure.code,
          ScanFailureCode.captureUnavailable,
        );
        await rig.coordinator.settled;
        expect(rig.coordinator.status.state, LiveScanState.unavailable);
        expect(
          rig.coordinator.status.reasonCode,
          ScanFailureCode.captureUnavailable,
        );
        expect(rig.capture.calls.length, 1, reason: 'no fallback');
        expect(rig.trigger.installed, isFalse);
      },
    );

    test(
      'vision unavailable answer fails the scan and the activation',
      () async {
        await readyRig();
        rig.fire(1000);
        (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
        (await rig.vision.calls.at(0)).answer(
          const VisionUnavailableAnswer<InspectionRecognition>(
            1,
            'worker died',
          ),
        );

        final report = await rig.published.at(0);
        expect(
          (report.end as ScanFailed).failure.code,
          ScanFailureCode.visionUnavailable,
        );
        await rig.coordinator.settled;
        expect(rig.coordinator.status.state, LiveScanState.unavailable);
        expect(rig.trigger.installed, isFalse);
      },
    );
  });

  group('latest trigger wins', () {
    test('burst during capture keeps only the newest trigger', () async {
      await readyRig();
      rig.fire(1000);
      final first = await rig.capture.calls.at(0);
      rig.fire(2000);
      rig.fire(3000);
      expect(rig.capture.calls.length, 1, reason: 'the pending trigger waits');

      final frame = rig.frames.frame();
      first.succeed(frame);
      final third = await rig.capture.calls.at(1);

      expect(third.trigger.qpc, 3000, reason: 'trigger 2 was dropped');
      expect(rig.frames.released, [frame.frameId]);
      expect(rig.vision.calls.length, 0, reason: 'scan 1 never reached vision');
      expect(rig.coordinator.latest, isNull);
      expect(rig.logs.length, 1);
      expect(rig.logs[0]['end'], 'superseded');
      expect(rig.logs[0]['supersededTriggers'], 2);

      third.succeed(rig.frames.frame());
      final evidence = _ev();
      (await rig.vision.calls.at(0))
          .deliver(_recognised(InspectionFrameKind.targeted, [evidence]));
      (await rig.matcher.calls.at(0)).complete(_accepted(evidence));
      final report = await rig.published.at(0);
      expect(report.supersededTriggers, 1);
      expect(report.timeline.trigger, 3000);
      expect(rig.logs.length, 2);
      expect(rig.logs[1]['end'], 'accepted');
      expect(rig.logs[1]['supersededTriggers'], 1);
    });

    test(
      'pending trigger after captureTimeout fails captureBusy and is logged',
      () async {
        await readyRig();
        rig.fire(1000);
        final first = await rig.capture.calls.at(0);
        rig.fire(2000);

        first.fail(const CaptureTimeout());
        final second = await rig.capture.calls.at(1);
        expect(second.trigger.qpc, 2000, reason: 'it starts at once');
        second.fail(const CaptureBusy());

        final report = await rig.published.at(0);
        expect(
          (report.end as ScanFailed).failure.code,
          ScanFailureCode.captureBusy,
        );
        expect(rig.capture.calls.length, 2, reason: 'no fallback after busy');
        expect(rig.logs.length, 2);
        expect(rig.logs[0]['end'], 'superseded');
        expect(rig.logs[1]['end'], 'failed');
        expect(rig.logs[1]['reason'], 'captureBusy');
      },
    );

    test('trigger during the vision stage invalidates at once', () async {
      await readyRig();
      rig.vision.answerOnInvalidate = false;
      rig.fire(1000);
      (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
      final old = await rig.vision.calls.at(0);
      expect(rig.waiter.requests.length, 1, reason: 'scan 1 settle wait');

      rig.fire(2000);

      expect(rig.vision.invalidations, 1);
      expect(old.isAnswered, isFalse, reason: 'the old job is still running');
      expect(
        rig.waiter.requests.length,
        2,
        reason: 'the new settle wait starts before the old job ends',
      );
      final second = await rig.capture.calls.at(1);
      expect(second.trigger.qpc, 2000);

      old.deliver(_recognised(InspectionFrameKind.targeted, [_ev()]));
      final line = await rig.logs.at(0);
      expect(line['end'], 'superseded');
      expect(
        ((line['ms']! as Map)['targeted']! as Map).keys,
        containsAll(['captureRequested', 'captureAnswered']),
      );
      expect(rig.coordinator.latest, isNull);
      expect(rig.coordinator.phase, ScanPhase.targeted);
    });

    test(
      'a capture answered after a trigger keeps its acquire stamps',
      () async {
        await readyRig();
        rig.fire(1000);
        final old = await rig.capture.calls.at(0);
        rig.fire(2000);

        old.succeed(rig.frames.frame(qpcBefore: 1020, qpcAfter: 1030));

        final line = await rig.logs.at(0);
        expect(line['end'], 'superseded');
        expect(
          ((line['ms']! as Map)['targeted']! as Map).keys,
          containsAll(['acquireStart', 'acquireEnd']),
        );
      },
    );

    test('a recognition delivered before a trigger keeps its stages', () async {
      await readyRig();
      rig.fire(1000);
      (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
      final old = await rig.vision.calls.at(0);

      old.deliver(
        _recognised(InspectionFrameKind.targeted, [_ev(base: 1100)]),
        submitted: 1050,
        started: 1060,
        finished: 1200,
      );
      rig.fire(2000);

      final line = await rig.logs.at(0);
      expect(line['end'], 'superseded');
      expect(
        ((line['ms']! as Map)['targeted']! as Map).keys,
        containsAll([
          'visionSubmitted',
          'jobStarted',
          'marker',
          'title',
          'preprocess',
          'ocr',
          'jobFinished',
        ]),
      );
    });

    test('trigger during matching discards the old match', () async {
      await readyRig();
      final oldMatch = await rig.toMatching(0, 1000);

      rig.fire(2000);
      final second = await rig.capture.calls.at(1);
      expect(second.trigger.qpc, 2000, reason: 'the new scan starts at once');

      oldMatch.complete(_accepted(_ev()));
      final line = await rig.logs.at(0);
      expect(line['end'], 'superseded');
      expect(rig.coordinator.latest, isNull);
      expect(rig.coordinator.recent, isEmpty);
      expect(rig.coordinator.phase, ScanPhase.targeted);
    });

    test('a new match waits for a superseded match still running', () async {
      await readyRig();
      final oldMatch = await rig.toMatching(0, 1000);
      rig.fire(2000);
      (await rig.capture.calls.at(1)).succeed(rig.frames.frame());
      final evidence = _ev();
      (await rig.vision.calls.at(1))
          .deliver(_recognised(InspectionFrameKind.targeted, [evidence]));
      // Let scan 2 run as far as it can: a negative check needs the queue to
      // drain once, because nothing observable happens while it waits.
      await pumpEventQueue();
      expect(rig.matcher.calls.length, 1, reason: 'serialised matching');

      oldMatch.complete(_rejected(OutcomeRejectReason.noMarker));
      final second = await rig.matcher.calls.at(1);
      expect(second.runningWhenCalled, 0);
      second.complete(_accepted(evidence));
      final report = await rig.published.at(0);
      expect(report.end, isA<ScanAccepted>());
      expect(rig.logs.length, 2);
      expect(rig.logs[0]['end'], 'superseded');
    });

    test('droppedBefore is recorded on the scan', () async {
      await readyRig();
      rig.fire(1000, dropped: 4);
      (await rig.capture.calls.at(0)).fail(const TargetGone());

      final report = await rig.published.at(0);
      expect(report.droppedTriggers, 4);
      expect(rig.logs[0]['droppedTriggers'], 4);
    });
  });

  group('publication fences', () {
    test('switch-off during matching discards the result', () async {
      await readyRig();
      final match = await rig.toMatching(0, 1000);
      final before = rig.notifications;

      await rig.coordinator.setLiveScan(false);
      await rig.coordinator.settled;
      expect(rig.coordinator.phase, ScanPhase.idle);
      final afterStop = rig.notifications;
      expect(afterStop, greaterThan(before));
      match.complete(_accepted(_ev()));

      final line = await rig.logs.at(0);
      expect(line['end'], 'superseded');
      expect(rig.coordinator.latest, isNull);
      expect(rig.coordinator.recent, isEmpty);
      expect(rig.published.length, 0);
      expect(rig.notifications, afterStop, reason: 'nothing published');
      expect(rig.capture.calls.length, 1);
    });

    test(
      'capture success after dispose is released without notification',
      () async {
        await readyRig();
        rig.fire(1000);
        final capture = await rig.capture.calls.at(0);
        final frame = rig.frames.frame();

        await rig.coordinator.dispose();
        capture.succeed(frame);

        final line = await rig.logs.at(0);
        expect(line['end'], 'superseded');
        expect(rig.frames.released, [frame.frameId]);
        expect(rig.vision.calls.length, 0);
        expect(rig.published.length, 0);
      },
    );

    test(
      'switch-off during vision stage publishes nothing and releases the frame',
      () async {
        await readyRig();
        rig.fire(1000);
        final frame = rig.frames.frame();
        (await rig.capture.calls.at(0)).succeed(frame);
        final call = await rig.vision.calls.at(0);
        expect(call.frame, same(frame));

        await rig.coordinator.setLiveScan(false);
        await rig.coordinator.settled;

        expect(rig.vision.closeCalls, 1);
        expect(call.isAnswered, isTrue);
        expect(rig.frames.released, [frame.frameId]);
        final line = await rig.logs.at(0);
        expect(line['end'], 'superseded');
        expect(rig.coordinator.latest, isNull);
        expect(rig.published.length, 0);
        expect(rig.matcher.calls.length, 0);
        expect(rig.coordinator.phase, ScanPhase.idle);
      },
    );

    test('a frame still held when the switch is off is released', () async {
      await readyRig();
      rig.fire(1000);
      final capture = await rig.capture.calls.at(0);
      await rig.coordinator.setLiveScan(false);
      await rig.coordinator.settled;

      final frame = rig.frames.frame();
      capture.succeed(frame);

      await rig.logs.at(0);
      expect(rig.frames.released, [frame.frameId]);
      expect(rig.vision.calls.length, 0, reason: 'never handed to vision');
    });
  });

  group('catalog index', () {
    test('outcome records mode and revision of the current snapshot', () async {
      await readyRig();
      final match = await rig.toMatching(0, 1000);
      expect(match.index.mode, GameMode.pvp);
      expect(match.index.revision, 'r1');
      expect(match.mode, GameMode.pvp);
      match.complete(_accepted(_ev()));

      final report = await rig.published.at(0);
      expect(report.catalogMode, GameMode.pvp);
      expect(report.catalogRevision, 'r1');
    });

    test(
      'snapshot change mid-scan keeps the old index for that scan',
      () async {
        await readyRig();
        final first = await rig.toMatching(0, 1000);
        expect(rig.builder.builds.length, 1);

        await rig.catalog.setMode(GameMode.pve);
        await rig.builder.builds.at(1);
        first.complete(_accepted(_ev()));
        final report = await rig.published.at(0);
        expect(report.catalogMode, GameMode.pvp);
        expect(report.catalogRevision, 'r1');

        rig.fire(2000);
        (await rig.capture.calls.at(1)).succeed(rig.frames.frame());
        (await rig.vision.calls.at(1))
            .deliver(_recognised(InspectionFrameKind.targeted, [_ev()]));
        final second = await rig.matcher.calls.at(1);
        expect(second.index.revision, 'r2');
        expect(second.mode, GameMode.pve);
        second.complete(_accepted(_ev()));
        final next = await rig.published.at(1);
        expect(next.catalogMode, GameMode.pve);
        expect(next.catalogRevision, 'r2');
      },
    );

    test('no snapshot rejects catalogUnavailable without fallback', () async {
      await readyRig(loaded: GameMode.unknown);
      rig.fire(1000);
      (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
      final recognition = _recognised(InspectionFrameKind.targeted, [_ev()]);
      (await rig.vision.calls.at(0)).deliver(recognition);

      final report = await rig.published.at(0);
      final end = report.end as ScanRejected;
      expect(end.reason, ScanRejectReason.catalogUnavailable);
      expect(end.outcome, isNull);
      expect(report.targeted?.recognition, same(recognition));
      expect(report.catalogMode, isNull);
      expect(rig.capture.calls.length, 1, reason: 'no fallback');
      expect(rig.matcher.calls.length, 0);
      expect(rig.logs[0]['reason'], 'catalogUnavailable');
    });

    test('failed index build rejects and retries on next snapshot', () async {
      rig = await _Rig.standalone(
        snapshots: {
          GameMode.pvp: _snapshot(GameMode.pvp, 'r1'),
          GameMode.pve: _snapshot(GameMode.pve, 'r2'),
        },
      );
      rig.builder.failNext = true;
      await rig.loadCatalog(GameMode.pvp);
      await rig.ready();
      await rig.builder.builds.at(0);

      rig.fire(1000);
      (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
      (await rig.vision.calls.at(0))
          .deliver(_recognised(InspectionFrameKind.targeted, [_ev()]));
      final failed = await rig.published.at(0);
      expect(
        (failed.end as ScanRejected).reason,
        ScanRejectReason.catalogUnavailable,
      );
      expect(rig.builder.builds.length, 1, reason: 'no retry without a change');

      await rig.catalog.setMode(GameMode.pve);
      await rig.builder.builds.at(1);
      // The first scan never reached the matcher, so call 0 is the next one.
      rig.fire(2000);
      (await rig.capture.calls.at(1)).succeed(rig.frames.frame());
      (await rig.vision.calls.at(1))
          .deliver(_recognised(InspectionFrameKind.targeted, [_ev()]));
      (await rig.matcher.calls.at(0)).complete(_accepted(_ev()));
      final retried = await rig.published.at(1);
      expect(retried.end, isA<ScanAccepted>());
      expect(retried.catalogRevision, 'r2');
    });

    test('the index is built only while live scan is on', () async {
      rig = await _Rig.standalone(
        snapshots: {
          GameMode.pvp: _snapshot(GameMode.pvp, 'r1'),
          GameMode.pve: _snapshot(GameMode.pve, 'r2'),
        },
      );
      await rig.loadCatalog(GameMode.pvp);
      expect(rig.builder.builds.length, 0, reason: 'off: no build');

      await rig.ready();
      expect(rig.builder.builds.length, 1, reason: 'built on activation');
      expect(rig.builder.builds[0].revision, 'r1');

      await rig.catalog.setMode(GameMode.pve);
      expect(rig.builder.builds.length, 2, reason: 'rebuilt on change');
      expect(rig.builder.builds[1].revision, 'r2');

      await rig.coordinator.setLiveScan(false);
      await rig.coordinator.settled;
      await rig.catalog.setMode(GameMode.pvp);
      expect(rig.builder.builds.length, 2, reason: 'off again: no build');
    });

    test('a scan waits for an index still being built', () async {
      rig = await _Rig.standalone(
        snapshots: {GameMode.pvp: _snapshot(GameMode.pvp, 'r1')},
      );
      final hold = rig.builder.hold = Completer<void>();
      await rig.loadCatalog(GameMode.pvp);
      await rig.ready();
      await rig.builder.builds.at(0);

      rig.fire(1000);
      (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
      (await rig.vision.calls.at(0))
          .deliver(_recognised(InspectionFrameKind.targeted, [_ev()]));
      await pumpEventQueue();
      expect(rig.matcher.calls.length, 0, reason: 'index not built yet');

      hold.complete();
      final match = await rig.matcher.calls.at(0);
      match.complete(_accepted(_ev()));
      expect((await rig.published.at(0)).end, isA<ScanAccepted>());
    });

    test(
      'a mode change while the index builds matches in the index mode',
      () async {
        rig = await _Rig.standalone(
          snapshots: {
            GameMode.pvp: _snapshot(GameMode.pvp, 'r1'),
            GameMode.pve: _snapshot(GameMode.pve, 'r2'),
          },
        );
        final hold = rig.builder.hold = Completer<void>();
        await rig.loadCatalog(GameMode.pvp);
        await rig.ready();
        await rig.builder.builds.at(0);

        rig.fire(1000);
        (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
        (await rig.vision.calls.at(0))
            .deliver(_recognised(InspectionFrameKind.targeted, [_ev()]));
        await pumpEventQueue();
        expect(rig.matcher.calls.length, 0, reason: 'index not built yet');

        await rig.catalog.setMode(GameMode.pve);
        hold.complete();
        final match = await rig.matcher.calls.at(0);
        expect(match.index.mode, GameMode.pvp);
        expect(match.mode, GameMode.pvp, reason: 'the awaited index decides');
        match.complete(_accepted(_ev()));
        final report = await rig.published.at(0);
        expect(report.end, isA<ScanAccepted>());
        expect(report.catalogMode, GameMode.pvp);
      },
    );
  });

  group('timings', () {
    test('accepted targeted timeline is complete and ordered', () async {
      await readyRig();
      rig.clock.now = 1010;
      rig.fire(1000);
      final capture = await rig.capture.calls.at(0);
      rig.clock.now = 1040;
      capture.succeed(rig.frames.frame(qpcBefore: 1020, qpcAfter: 1030));
      final vision = await rig.vision.calls.at(0);
      final evidence = InspectionEvidence(
        markerScore: 0.93,
        markerX: 1,
        markerY: 2,
        titleRect: const TitleRegion(x: 1, y: 2, width: 30, height: 8),
        titleStatus: InspectionTitleStatus.read,
        text: 'Salewa First Aid Kit',
        crop: Uint8List.fromList([1, 2, 3, 4]),
        cropWidth: 2,
        cropHeight: 2,
        cropDownscaled: false,
        qpcMarker: 1062,
        qpcTitle: 1064,
        qpcPreprocess: 1066,
        qpcOcr: 1068,
      );
      rig.clock.now = 1080;
      vision.deliver(
        _recognised(InspectionFrameKind.targeted, [evidence]),
        submitted: 1050,
        started: 1060,
        finished: 1070,
      );
      final match = await rig.matcher.calls.at(0);
      rig.clock.now = 1090;
      match.complete(_accepted(evidence));

      final report = await rig.published.at(0);
      final timeline = report.timeline;
      expect(timeline.trigger, 1000);
      expect(timeline.fallback, isNull);
      final targeted = timeline.targeted!;
      expect(_stages(targeted), [
        1010,
        1020,
        1030,
        1040,
        1050,
        1060,
        1062,
        1064,
        1066,
        1068,
        1070,
        1080,
        1090,
      ]);
      expect(timeline.published, 1090);
      final ordered = [
        timeline.trigger,
        ..._stages(targeted).whereType<int>(),
        timeline.published!,
      ];
      expect(ordered, orderedEquals([...ordered]..sort()));
      final ms = rig.logs[0]['ms']! as Map<String, Object?>;
      expect(ms.containsKey('fallback'), isFalse);
      expect((ms['targeted']! as Map).length, 13);
      expect(rig.platform!.clock.frequencyReads, 1);
    });

    test("fallback win keeps the targeted pass's own job stamps", () async {
      await readyRig();
      rig.fire(1000);
      (await rig.capture.calls.at(0)).succeed(rig.frames.frame());
      final targetedEv = _ev(text: 'Salewa Frst', base: 1100);
      (await rig.vision.calls.at(0))
          .deliver(_recognised(InspectionFrameKind.targeted, [targetedEv]));
      (await rig.matcher.calls.at(0))
          .complete(_rejected(OutcomeRejectReason.belowSimilarity, targetedEv));
      (await rig.capture.calls.at(1)).succeed(rig.frames.frame());
      final fallbackEv = _ev(base: 1300);
      (await rig.vision.calls.at(1))
          .deliver(_recognised(InspectionFrameKind.fullClient, [fallbackEv]));
      (await rig.matcher.calls.at(1)).complete(_accepted(fallbackEv));

      final report = await rig.published.at(0);
      expect(report.winningPass, ScanPass.fallback);
      final targeted = report.timeline.targeted!;
      final fallback = report.timeline.fallback!;
      expect(targeted.marker, targetedEv.qpcMarker);
      expect(targeted.title, targetedEv.qpcTitle);
      expect(targeted.preprocess, targetedEv.qpcPreprocess);
      expect(targeted.ocr, targetedEv.qpcOcr);
      expect(fallback.marker, fallbackEv.qpcMarker);
      expect(fallback.ocr, fallbackEv.qpcOcr);
      expect(targeted.matchStarted, isNotNull);
      expect(fallback.captureRequested, isNotNull);
      final ms = rig.logs[0]['ms']! as Map<String, Object?>;
      expect(ms.keys, containsAll(['targeted', 'fallback']));
    });

    test('early capture failure leaves later stages absent', () async {
      await readyRig();
      rig.clock.now = 1010;
      rig.fire(1000);
      final call = await rig.capture.calls.at(0);
      rig.clock.now = 1020;
      call.fail(const TargetGone());

      final report = await rig.published.at(0);
      final targeted = report.timeline.targeted!;
      expect(targeted.captureRequested, 1010);
      expect(targeted.captureAnswered, 1020);
      for (final stamp in [
        targeted.acquireStart,
        targeted.acquireEnd,
        targeted.visionSubmitted,
        targeted.jobStarted,
        targeted.marker,
        targeted.title,
        targeted.preprocess,
        targeted.ocr,
        targeted.jobFinished,
        targeted.matchStarted,
        targeted.matchFinished,
      ]) {
        expect(stamp, isNull);
      }
      expect(report.timeline.fallback, isNull);
      expect(report.timeline.published, isNotNull);
      final ms = rig.logs[0]['ms']! as Map<String, Object?>;
      expect((ms['targeted']! as Map).keys, [
        'captureRequested',
        'captureAnswered',
      ]);
    });
  });

  group('published values', () {
    test('recent list keeps the 10 newest', () async {
      await readyRig();
      for (var n = 0; n < 11; n++) {
        await rig.acceptTargeted(n, 1000 + n, 'item$n');
      }

      final recent = rig.coordinator.recent;
      expect(recent, hasLength(ScanCoordinator.recentLimit));
      expect(recent.length, 10);
      expect(
        [for (final r in recent) (r.end as ScanAccepted).itemId],
        [for (var n = 10; n >= 1; n--) 'item$n'],
      );
      expect(rig.logs.length, 11, reason: 'one line per ended scan');
    });

    test('crop bytes are kept only on the latest report', () async {
      await readyRig();
      await rig.acceptTargeted(0, 1000);
      await rig.acceptTargeted(1, 2000);

      final latest = rig.coordinator.latest!;
      expect(latest.hasCrops, isTrue);
      expect(rig.coordinator.recent, hasLength(2));
      expect(
        rig.coordinator.recent.every((r) => !r.hasCrops),
        isTrue,
        reason: 'summaries only',
      );
      expect(rig.coordinator.recent.first.id, latest.id);
    });

    test('lastAccepted follows the newest accepted scan only', () async {
      await readyRig();
      final a = await rig.acceptTargeted(0, 1000, 'a');
      expect(rig.coordinator.lastAccepted, same(a));

      // Scan 1 is rejected without a fallback.
      rig.fire(2000);
      (await rig.capture.calls.at(1)).succeed(rig.frames.frame());
      final evidence = _ev();
      (await rig.vision.calls.at(1))
          .deliver(_recognised(InspectionFrameKind.targeted, [evidence]));
      (await rig.matcher.calls.at(
        1,
      )).complete(_rejected(OutcomeRejectReason.catalogModeMismatch, evidence));
      expect((await rig.published.at(1)).end, isA<ScanRejected>());
      expect(rig.coordinator.lastAccepted, same(a));

      final b = await rig.acceptTargeted(2, 3000, 'b');
      expect(rig.coordinator.lastAccepted, same(b));

      // Scan 3 fails at its targeted capture, with no fallback.
      rig.fire(4000);
      (await rig.capture.calls.at(3)).fail(const TargetNotForeground());
      expect((await rig.published.at(3)).end, isA<ScanFailed>());
      expect(rig.coordinator.lastAccepted, same(b));
      expect(rig.coordinator.lastAccepted!.hasCrops, isTrue);
    });

    test('the clock frequency is read once per activation', () async {
      await readyRig();
      await rig.acceptTargeted(0, 1000);
      await rig.acceptTargeted(1, 2000);
      expect(rig.platform!.clock.frequencyReads, 1);
    });
  });

  group('evidence never produces a recommendation', () {
    late M1Harness h;
    late _Rig over;

    setUp(() async {
      h = M1Harness();
      await h.initialize();
      h.services.selection.setQuery('Component');
      await h.services.selection.selectManual(
        h.services.selection.results.first,
      );
      over = _Rig(settings: h.services.settings, catalog: h.services.catalog);
      rig = over;
      await over.ready();
    });

    tearDown(() async {
      await over.coordinator.dispose();
      await h.dispose();
    });

    ({String? selected, int history, FirState fir}) state() => (
      selected: h.services.selection.selectedId,
      history: h.services.history.rows.length,
      fir: h.services.selection.fir,
    );

    test('accepted scan changes no selection or history', () async {
      final before = state();
      var changes = 0;
      h.services.selection.addListener(() => changes++);
      h.services.history.addListener(() => changes++);

      final report = await over.acceptTargeted(0, 1000, 'some-other-item');

      expect(report.end, isA<ScanAccepted>());
      expect(state(), before);
      expect(changes, 0);
    });

    test('rejected scan changes no selection or history', () async {
      final before = state();
      var changes = 0;
      h.services.selection.addListener(() => changes++);
      h.services.history.addListener(() => changes++);

      over.fire(1000);
      (await over.capture.calls.at(0)).succeed(over.frames.frame());
      final evidence = _ev();
      (await over.vision.calls.at(0))
          .deliver(_recognised(InspectionFrameKind.targeted, [evidence]));
      (await over.matcher.calls.at(
        0,
      )).complete(_rejected(OutcomeRejectReason.catalogModeMismatch, evidence));
      final report = await over.published.at(0);

      expect(report.end, isA<ScanRejected>());
      expect(report.outcome, isA<OutcomeRejected<InspectionEvidence>>());
      expect(state(), before);
      expect(changes, 0);
    });
  });
}
