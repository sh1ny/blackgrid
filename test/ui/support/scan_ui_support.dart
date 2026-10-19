import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/capture/input_trigger_source.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:blackgrid/data/scan_timing_log.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_image.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/catalog_store.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../application/support/fake_scan_ports.dart';

/// The item the Scanner panel tests accept, with a catalog name.
const scanItemId = '5449016a4bdc2d6f028b456f';

/// Name of [scanItemId] in [scanSnapshot].
const scanItemName = 'Salewa First Aid Kit';

/// A second catalog item, used as the best rejected candidate.
const scanOtherId = 'item-x';

/// Name of [scanOtherId] in [scanSnapshot].
const scanOtherName = 'Rejected Candidate Item';

/// A tiny catalog with the two items the panel tests mention.
CatalogSnapshot scanSnapshot([GameMode mode = GameMode.pvp]) => CatalogSnapshot(
  mode: mode,
  revision: 'r1',
  observedAt: DateTime.utc(2026, 1, 1),
  items: {
    scanItemId: CatalogItem(
      id: scanItemId,
      name: scanItemName,
      normalizedName: 'salewa-first-aid-kit',
    ),
    scanOtherId: CatalogItem(
      id: scanOtherId,
      name: scanOtherName,
      normalizedName: 'rejected-candidate-item',
    ),
  },
  traders: const {},
  requirements: const [],
);

class _Store implements CatalogStore {
  _Store(this.snapshot);

  final CatalogSnapshot snapshot;

  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async =>
      mode == snapshot.mode ? snapshot : null;

  @override
  Future<void> commitCatalog(CatalogSnapshot snapshot) async {}
}

/// A 4 by 4 gray crop, one byte per pixel.
Uint8List grayCrop() => Uint8List.fromList(List<int>.filled(16, 7));

/// An evidence entry with a tiny synthetic crop.
InspectionEvidence scanEvidence({
  String text = scanItemName,
  double score = 0.93,
  int base = 0,
  bool withCrop = true,
}) => InspectionEvidence(
  markerScore: score,
  markerX: 10 + base,
  markerY: 20,
  titleRect: const TitleRegion(x: 1, y: 2, width: 30, height: 8),
  titleStatus: InspectionTitleStatus.read,
  text: text,
  crop: withCrop ? grayCrop() : Uint8List(0),
  cropWidth: withCrop ? 4 : 0,
  cropHeight: withCrop ? 4 : 0,
  cropDownscaled: false,
  qpcMarker: base + 1,
  qpcTitle: base + 2,
  qpcPreprocess: base + 3,
  qpcOcr: base + 4,
);

/// A recognition holding [evidence].
InspectionRecognised scanRecognised(
  InspectionFrameKind kind,
  List<InspectionEvidence> evidence,
) => InspectionRecognised(
  kind: kind,
  scale: 1,
  bestMarkerScore: evidence.isEmpty ? 0.2 : evidence.first.markerScore,
  evidence: evidence,
);

/// An accepted outcome for [id].
OutcomeAccepted<InspectionEvidence> scanAccepted(
  InspectionEvidence evidence, {
  String id = scanItemId,
}) => OutcomeAccepted<InspectionEvidence>(
  TitleAccepted(
    bestId: id,
    normalisedTitle: 'salewa first aid kit',
    bestScore: 0.97,
    runnerUpId: scanOtherId,
    runnerUpScore: 0.31,
    margin: 0.66,
    confirmedBy: null,
    mode: GameMode.pvp,
    revision: 'r1',
  ),
  evidence,
);

/// A `belowSimilarity` rejection whose best candidate is [bestId] at [score].
OutcomeRejected<InspectionEvidence> scanBelowSimilarity(
  InspectionEvidence evidence, {
  String bestId = scanOtherId,
  double score = 0.41,
}) => OutcomeRejected<InspectionEvidence>(
  OutcomeRejectReason.belowSimilarity,
  evidence: evidence,
  match: TitleRejected(
    reason: TitleRejectReason.belowSimilarity,
    normalisedTitle: 'rejected candidate',
    bestId: bestId,
    bestScore: score,
    runnerUpId: scanItemId,
    runnerUpScore: 0.2,
    margin: score - 0.2,
    mode: GameMode.pvp,
    revision: 'r1',
  ),
  targetedBestMarkerScore: evidence.markerScore,
);

/// A timing log sink that can be told to fail.
final class FailingSink implements ScanTimingFileSink {
  /// Whether appends throw.
  bool failing = false;

  @override
  Future<int> length() async => 0;

  @override
  Future<void> append(List<int> bytes) async {
    if (failing) throw StateError('scan-timings.jsonl is not writable');
  }

  @override
  Future<void> rotate() async {}
}

/// Hand-written capture, vision and platform fakes that record what the
/// coordinator asked, shared by the standalone rig and AppServices tests.
final class ScanFakePorts {
  /// Every event the fakes recorded, in order.
  final ScanEventLog events = [];

  /// The frame registry.
  final FakeScanFrames frames = FakeScanFrames();

  /// Every capture service created.
  final List<FakeScanCapture> captures = [];

  /// Every vision service created.
  final List<FakeScanVision> visions = [];

  /// The platform, once opened.
  FakeScanPlatform? platform;

  /// The marker template loader.
  Future<MarkerTemplateResult> markerLoader(String directory) async =>
      MarkerTemplateLoaded(
        VisionTemplate(
          'inspectionMarker',
          VisionImage(
            Uint8List(1),
            width: 1,
            height: 1,
            stride: 1,
            channels: 1,
          ),
        ),
      );

  /// What the marker loader answers instead, when set.
  MarkerTemplateResult? markerOverride;

  /// When set, the loader waits for it before answering.
  Future<MarkerTemplateResult>? markerGate;

  /// The capture factory.
  ScanCaptureFactory get captureFactory => () {
    final created = FakeScanCapture(events);
    captures.add(created);
    return created;
  };

  /// The vision factory.
  ScanVisionFactory get visionFactory => (_, _) {
    final created = FakeScanVision(events);
    visions.add(created);
    return created;
  };

  /// The platform factory.
  ScanPlatformFactory get platformFactory =>
      () => platform = FakeScanPlatform(events);

  /// The waiter to hand to the coordinator: it never waits.
  ScanWaiter get waiter => immediateScanWaiter;

  /// The loader to hand to the coordinator, honouring [markerOverride].
  ScanMarkerLoader get loader =>
      (directory) async =>
          await markerGate ?? markerOverride ?? await markerLoader(directory);

  FakeScanCapture get capture => captures.last;
  FakeScanVision get vision => visions.last;
  FakeScanClock get clock => platform!.clock;

  /// Emits a trigger at [qpc], a mouse release unless [source] says otherwise.
  void fire(int qpc, {TriggerSource source = TriggerSource.mouse}) =>
      platform!.trigger.emit(
        ScanTrigger(
          TriggerEvent(
            x: 10,
            y: 20,
            hwnd: 1,
            pid: 2,
            tid: 3,
            qpc: qpc,
            source: source,
          ),
          0,
        ),
      );

  /// Answers capture call [n] with a frame, with the clock at [at].
  Future<void> captureOk(int n, {int? at}) async {
    final call = await capture.calls.at(n);
    if (at != null) clock.now = at;
    call.succeed(frames.frame());
  }

  /// Delivers [result] for vision call [n], finishing at [at].
  Future<void> visionDeliver(
    int n,
    InspectionRecognition result, {
    int at = 0,
  }) async {
    final call = await vision.calls.at(n);
    clock.now = at;
    call.deliver(result, finished: at);
  }

  /// Answers vision call [n] with a deadline failure.
  Future<void> visionTimeout(int n) async =>
      (await vision.calls.at(n))
          .answer(const VisionDeadlineExceeded<InspectionRecognition>(5));
}

/// A recording writer whose answers the test delivers by hand.
final class FakeRecordWriter implements ScanFrameWriter {
  /// Creates a writer for the session [token] answering through [onAnswer].
  FakeRecordWriter(this.token, this.onAnswer);

  /// The session token the recorder gave this writer.
  final int token;

  /// Delivers an answer to the recorder.
  final void Function(ScanFrameWriterAnswer) onAnswer;

  @override
  void write(RecordedScan scan) {}

  @override
  void kill() {}

  /// Acknowledges the scan [id] as written.
  void ack(String id) => onAnswer(ScanFrameAck(token, id));

  /// Fails the scan [id] with [error].
  void fail(String id, String error) =>
      onAnswer(ScanFrameFailure(token, id, error));
}

/// A scan with no frames, enough to hand to the recorder.
RecordedScan recordedScan(String id) => RecordedScan(
  id: id,
  kind: RecordedScanKind.targeted,
  outcome: RecordedOutcome.failed,
  failure: 'captureBusy',
);

/// A coordinator over real settings and catalog controllers, a fake matcher
/// and a real timing log over a [FailingSink].
final class ScanUiRig {
  ScanUiRig._({
    required this.db,
    required this.settings,
    required this.catalog,
  }) {
    timingLog = ScanTimingLog(
      // Never touched: the sink replaces the real file.
      _unusedDirectory,
      sink: sink,
    );
    recordingRoot = Directory.systemTemp.createTempSync('scan_ui_rig');
    recorder = ScanFrameRecorder(
      root: '${recordingRoot.path}/scan-frames',
      clock: () => DateTime(2026, 10, 10, 14, 3, 7),
      writerFactory:
          ({required folder, required token, required onAnswer}) async {
            await writerGate?.future;
            final writer = FakeRecordWriter(token, onAnswer);
            writers.add(writer);
            return writer;
          },
    );
    coordinator = ScanCoordinator(
      recorder: recorder,
      settings: settings,
      catalog: catalog,
      appendLogLine: timingLog.append,
      runtimeDirectory: r'C:\fake\bundle',
      closeTimeout: const Duration(milliseconds: 500),
      indexBuilder: builder.call,
      matcher: matcher.call,
      markerLoader: ports.loader,
      captureFactory: ports.captureFactory,
      visionFactory: ports.visionFactory,
      platformFactory: ports.platformFactory,
      waiter: immediateScanWaiter,
    );
  }

  /// Creates the rig. Call inside `tester.runAsync`: the database is real.
  static Future<ScanUiRig> create({bool liveScanSaved = false}) async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    if (liveScanSaved) await db.saveSettings(AppSettings(liveScan: true));
    final settings = SettingsController(db);
    await settings.load();
    final catalog = CatalogController(
      store: _Store(scanSnapshot()),
      client: CatalogClient(
        client: MockClient((_) async => http.Response('', 500)),
      ),
    );
    await catalog.setMode(GameMode.pvp);
    return ScanUiRig._(db: db, settings: settings, catalog: catalog);
  }

  final BlackgridDatabase db;
  final SettingsController settings;
  final CatalogController catalog;
  final ScanFakePorts ports = ScanFakePorts();
  final FakeScanMatcher matcher = FakeScanMatcher();
  final FakeIndexBuilder builder = FakeIndexBuilder();
  final FailingSink sink = FailingSink();
  late final ScanTimingLog timingLog;
  late final ScanCoordinator coordinator;

  /// The temporary directory holding the recording folders.
  late final Directory recordingRoot;

  /// The recorder behind [coordinator], over fake writers.
  late final ScanFrameRecorder recorder;

  /// When set, the recording writer is not created until it completes, which
  /// holds a session in `starting`.
  Completer<void>? writerGate;

  /// Every recording writer created, in session order.
  final List<FakeRecordWriter> writers = [];

  static final _unusedDirectory = Directory.systemTemp;

  /// Switches live scan on through the coordinator and waits until settled.
  Future<void> ready() async {
    await coordinator.setLiveScan(true);
    await coordinator.settled;
  }

  /// Makes preference saves fail, as a database error would.
  Future<void> failSaves() => db.customStatement(
    "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences "
    "BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
  );

  /// Completes when [timingLog] reports an unavailable status.
  Future<void> failTimingLog() {
    sink.failing = true;
    final done = Completer<void>();
    void listen() {
      if (timingLog.status.value is ScanTimingUnavailable &&
          !done.isCompleted) {
        done.complete();
      }
    }

    timingLog.status.addListener(listen);
    timingLog.append({'v': 1});
    return done.future.whenComplete(
      () => timingLog.status.removeListener(listen),
    );
  }

  Future<void> dispose() async {
    await coordinator.dispose();
    await recorder.close(timeout: Duration.zero);
    recordingRoot.deleteSync(recursive: true);
    await timingLog.close();
    settings.dispose();
    catalog.dispose();
    await db.close();
  }
}

/// Completes with the latest report once it has [id], waiting on the
/// coordinator's own notifications.
Future<ScanReport> reportPublished(ScanCoordinator scanner, int id) {
  final latest = scanner.latest;
  if (latest != null && latest.id >= id) return Future.value(latest);
  final done = Completer<ScanReport>();
  void listen() {
    final current = scanner.latest;
    if (current != null && current.id >= id && !done.isCompleted) {
      done.complete(current);
    }
  }

  scanner.addListener(listen);
  return done.future.whenComplete(() => scanner.removeListener(listen));
}

/// Switches live scan on and drives one targeted scan to the end, over the
/// fake [ports] and whatever matcher [scanner] uses (the real one for
/// AppServices). Call inside `tester.runAsync`.
Future<ScanReport> publishTargetedScan(
  ScanCoordinator scanner,
  ScanFakePorts ports, {
  required String text,
  int index = 0,
  int qpc = 1000,
}) async {
  if (scanner.status.state != LiveScanState.ready) {
    await scanner.setLiveScan(true);
    await scanner.settled;
  }
  ports.fire(qpc);
  await ports.captureOk(index);
  await ports.visionDeliver(
    index,
    scanRecognised(InspectionFrameKind.targeted, [scanEvidence(text: text)]),
  );
  return reportPublished(scanner, index + 1);
}
