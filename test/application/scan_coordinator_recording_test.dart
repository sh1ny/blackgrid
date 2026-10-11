@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/capture/mouse_release_trigger_source.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_image.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/catalog_store.dart';
import 'package:blackgrid/domain/credential_store.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_scan_ports.dart';

class _Store implements CatalogStore {
  _Store(this.snapshots);

  final Map<GameMode, CatalogSnapshot> snapshots;

  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async => snapshots[mode];

  @override
  Future<void> commitCatalog(CatalogSnapshot snapshot) async {}
}

CatalogSnapshot _snapshot(GameMode mode) => CatalogSnapshot(
  mode: mode,
  revision: 'r1',
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

InspectionEvidence _ev({String text = 'Salewa First Aid Kit', double? score}) =>
    InspectionEvidence(
      markerScore: score ?? 0.93,
      markerX: 10,
      markerY: 20,
      titleRect: const TitleRegion(x: 1, y: 2, width: 30, height: 8),
      titleStatus: InspectionTitleStatus.read,
      text: text,
      crop: Uint8List.fromList(List<int>.filled(16, 7)),
      cropWidth: 4,
      cropHeight: 4,
      cropDownscaled: false,
      qpcMarker: 1,
      qpcTitle: 2,
      qpcPreprocess: 3,
      qpcOcr: 4,
    );

InspectionRecognised _recognised(
  InspectionFrameKind kind,
  InspectionEvidence evidence,
) => InspectionRecognised(
  kind: kind,
  scale: 1,
  bestMarkerScore: evidence.markerScore,
  evidence: [evidence],
);

OutcomeAccepted<InspectionEvidence> _accepted(
  InspectionEvidence evidence, [
  String id = 'kit',
]) => OutcomeAccepted<InspectionEvidence>(
  TitleAccepted(
    bestId: id,
    normalisedTitle: 'salewa first aid kit',
    bestScore: 0.97,
    runnerUpId: null,
    runnerUpScore: 0,
    margin: 0.97,
    confirmedBy: null,
    mode: GameMode.pvp,
    revision: 'r1',
  ),
  evidence,
);

OutcomeRejected<InspectionEvidence> _rejected(
  OutcomeRejectReason reason,
  InspectionEvidence evidence,
) => OutcomeRejected<InspectionEvidence>(
  reason,
  evidence: evidence,
  targetedBestMarkerScore: 0.5,
);

/// BGRX test frames are 8x4 with 4 padding bytes per row.
const int _w = 8;
const int _h = 4;
const int _stride = 36;

Uint8List _bytes(int seed) => Uint8List.fromList([
  for (var i = 0; i < _stride * _h; i++) (i + seed) & 0xff,
]);

/// A writer whose answers the test delivers by hand. With [persist] it also
/// appends each line to `frames.jsonl`, as the real writer does.
final class _Writer implements ScanFrameWriter {
  _Writer(this.folder, this.token, this.onAnswer, this.sink, this.persist);

  final String folder;
  final int token;
  final void Function(ScanFrameWriterAnswer) onAnswer;
  final CallLog<RecordedScan> sink;
  final bool persist;
  int kills = 0;

  @override
  void write(RecordedScan scan) {
    sink.add(scan);
    if (persist) {
      File('$folder/$scanFramesFileName').writeAsStringSync(
        '${encodeScanFrameLine(scan)}\n',
        mode: FileMode.append,
      );
    }
  }

  @override
  void kill() => kills++;

  void ack(RecordedScan scan) => onAnswer(ScanFrameAck(token, scan.id));
}

/// A Tracker token saved on this machine, which no recorded file may hold.
const String _token = 'tracker-token-SECRET-0123456789';

/// A credential store with one Tracker token, in memory.
final class _MemoryCredentials implements CredentialStore {
  final Map<GameMode, String> tokens = {GameMode.pvp: _token};

  @override
  Future<String?> readCredential(GameMode mode) async => tokens[mode];

  @override
  Future<void> writeCredential(GameMode mode, String token) async =>
      tokens[mode] = token;

  @override
  Future<void> removeCredential(GameMode mode) async => tokens.remove(mode);
}

/// The key structure of a log line, without its values.
Object? _keys(Object? value) => value is Map
    ? {for (final entry in value.entries) entry.key: _keys(entry.value)}
    : null;

final class _Rig {
  _Rig._(
    this.db,
    this.settings,
    this.catalog,
    this.temp, {
    bool persist = false,
  }) {
    root = '${temp.path}/scan-frames';
    recorder = ScanFrameRecorder(
      root: root,
      clock: () => DateTime(2026, 10, 10, 14, 3, 7),
      writerFactory:
          ({required folder, required token, required onAnswer}) async {
            final writer = _Writer(folder, token, onAnswer, recorded, persist);
            writers.add(writer);
            return writer;
          },
    );
    coordinator = ScanCoordinator(
      settings: settings,
      catalog: catalog,
      appendLogLine: (line) {
        logs.add(line);
        events.add('log');
      },
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
      recorder: recorder,
    );
    coordinator.addListener(_observe);
  }

  static Future<_Rig> create({
    bool catalogLoaded = true,
    bool persist = false,
  }) async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    final settings = SettingsController(db);
    await settings.load();
    final catalog = CatalogController(
      store: _Store({GameMode.pvp: _snapshot(GameMode.pvp)}),
      client: CatalogClient(
        client: MockClient((_) async => http.Response('', 500)),
      ),
    );
    final temp = Directory.systemTemp.createTempSync('scan_recording_test');
    final rig = _Rig._(db, settings, catalog, temp, persist: persist);
    if (catalogLoaded) await catalog.setMode(GameMode.pvp);
    await rig.coordinator.setLiveScan(true);
    await rig.coordinator.settled;
    expect(rig.coordinator.status.state, LiveScanState.ready);
    return rig;
  }

  final BlackgridDatabase db;
  final SettingsController settings;
  final CatalogController catalog;
  final Directory temp;
  late final String root;
  late final ScanFrameRecorder recorder;
  late final ScanCoordinator coordinator;

  final ScanEventLog events = [];
  late final FakeScanFrames frames = FakeScanFrames(events);
  final FakeScanMatcher matcher = FakeScanMatcher();
  final FakeIndexBuilder builder = FakeIndexBuilder();
  final FakeScanWaiter waiter = FakeScanWaiter();
  final CallLog<Map<String, Object?>> logs = CallLog<Map<String, Object?>>();
  final CallLog<ScanReport> published = CallLog<ScanReport>();
  final CallLog<RecordedScan> recorded = CallLog<RecordedScan>();
  final List<_Writer> writers = [];
  final List<FakeScanCapture> captures = [];
  final List<FakeScanVision> visions = [];
  FakeScanPlatform? platform;

  int _captureIx = 0;
  int _visionIx = 0;
  int _matchIx = 0;
  int _publishedIx = 0;
  ScanReport? _lastLatest;

  FakeScanCapture get capture => captures.last;
  FakeScanVision get vision => visions.last;
  FakeScanTrigger get trigger => platform!.trigger;

  void _observe() {
    final latest = coordinator.latest;
    if (latest != null && !identical(latest, _lastLatest)) {
      _lastLatest = latest;
      published.add(latest);
      events.add('published');
    }
  }

  Future<FakeCaptureCall> nextCapture() => capture.calls.at(_captureIx++);
  Future<FakeVisionCall> nextVision() => vision.calls.at(_visionIx++);
  Future<FakeMatchCall> nextMatch() => matcher.calls.at(_matchIx++);
  Future<ScanReport> nextPublished() => published.at(_publishedIx++);

  ScanRecordingState get state => recorder.status.value.state;

  String get folderName =>
      recorder.status.value.folder!.split(RegExp(r'[\\/]')).last;

  Future<void> startRecording() async {
    await coordinator.setRecording(true);
    expect(state, ScanRecordingState.on);
  }

  /// A changing set of BGRX frames: [seed] tells them apart.
  CaptureFrame pixelFrame({
    int seed = 1,
    int clientWidth = 2560,
    int clientHeight = 1440,
    int desktopLeft = 0,
    int desktopTop = 0,
    CaptureRect? captured,
    bool clipped = false,
    DateTime? capturedAtUtc,
  }) => frames.frame(
    pixels: true,
    seed: seed,
    width: _w,
    height: _h,
    stride: _stride,
    clientWidth: clientWidth,
    clientHeight: clientHeight,
    desktopLeft: desktopLeft,
    desktopTop: desktopTop,
    captured: captured,
    clipped: clipped,
    capturedAtUtc: capturedAtUtc,
  );

  void fire(int qpc, {int x = 10, int y = 20}) => trigger.emit(
    ScanTrigger(TriggerEvent(x: x, y: y, hwnd: 1, pid: 2, tid: 3, qpc: qpc), 0),
  );

  /// Drives a scan to a targeted acceptance and returns its published report.
  Future<ScanReport> acceptTargeted({
    int qpc = 1000,
    CaptureFrame? strip,
    InspectionEvidence? evidence,
  }) async {
    final ev = evidence ?? _ev();
    fire(qpc);
    (await nextCapture()).succeed(strip ?? pixelFrame());
    (await nextVision()).deliver(_recognised(InspectionFrameKind.targeted, ev));
    (await nextMatch()).complete(_accepted(ev));
    return nextPublished();
  }

  /// Drives a scan through both passes and returns its published report.
  ///
  /// The targeted pass fails with [targetedFailure] when given, else it reads
  /// [targetedEvidence] and is rejected `belowSimilarity`.
  Future<ScanReport> fallbackScan({
    int qpc = 1000,
    int x = 10,
    int y = 20,
    CaptureFailure? targetedFailure,
    CaptureFrame? strip,
    CaptureFrame? full,
    InspectionEvidence? targetedEvidence,
    required InspectionEvidence evidence,
    required RecognitionOutcome<InspectionEvidence> outcome,
  }) async {
    fire(qpc, x: x, y: y);
    final first = await nextCapture();
    if (targetedFailure != null) {
      first.fail(targetedFailure);
    } else {
      final read = targetedEvidence ?? _ev(score: 0.55);
      first.succeed(strip ?? pixelFrame());
      (await nextVision()).deliver(
        _recognised(InspectionFrameKind.targeted, read),
      );
      (await nextMatch()).complete(
        _rejected(OutcomeRejectReason.belowSimilarity, read),
      );
    }
    (await nextCapture()).succeed(full ?? pixelFrame(seed: 2));
    (await nextVision()).deliver(
      _recognised(InspectionFrameKind.fullClient, evidence),
    );
    (await nextMatch()).complete(outcome);
    return nextPublished();
  }

  /// Ends a scan `failed` with `captureBusy` and no frame.
  Future<ScanReport> busyScan({int qpc = 1000}) async {
    fire(qpc);
    (await nextCapture()).fail(const CaptureBusy());
    return nextPublished();
  }

  Future<void> whenState(LiveScanState wanted) {
    final done = Completer<void>();
    void check() {
      if (coordinator.status.state == wanted && !done.isCompleted) {
        done.complete();
      }
    }

    coordinator.addListener(check);
    check();
    return done.future.whenComplete(() => coordinator.removeListener(check));
  }

  Future<void> dispose() async {
    await coordinator.dispose();
    await recorder.close(timeout: Duration.zero);
    frames.freePixels();
    settings.dispose();
    catalog.dispose();
    await db.close();
    temp.deleteSync(recursive: true);
  }
}

void main() {
  late _Rig rig;

  tearDown(() => rig.dispose());

  group('opt-in and lifetime', () {
    test(
      'recording is off in a new coordinator and is never saved in settings',
      () async {
        rig = await _Rig.create();
        expect(
          rig.coordinator.recordingStatus.value.state,
          ScanRecordingState.off,
        );

        final before = rig.settings.settings;
        await rig.startRecording();
        await rig.coordinator.setRecording(false);

        expect(rig.state, ScanRecordingState.off);
        expect(rig.settings.settings, same(before));
        expect(rig.coordinator.recordingStatus, same(rig.recorder.status));
      },
    );

    test('recording cannot start before live scan is ready', () async {
      rig = await _Rig.create();
      await rig.coordinator.setLiveScan(false);
      await rig.coordinator.settled;

      await rig.coordinator.setRecording(true);

      expect(rig.state, ScanRecordingState.off);
      expect(rig.writers, isEmpty);
      expect(Directory(rig.root).existsSync(), isFalse);
    });

    test(
      'switching live scan off turns recording off and on again leaves it off',
      () async {
        rig = await _Rig.create();
        await rig.startRecording();

        await rig.coordinator.setLiveScan(false);
        expect(rig.state, ScanRecordingState.off);
        await rig.coordinator.settled;

        await rig.coordinator.setLiveScan(true);
        await rig.coordinator.settled;
        expect(rig.coordinator.status.state, LiveScanState.ready);
        expect(rig.state, ScanRecordingState.off);
        expect(rig.writers, hasLength(1));
      },
    );

    test(
      'worker loss turns recording off and outstanding scans are still written',
      () async {
        rig = await _Rig.create();
        await rig.startRecording();
        await rig.busyScan();
        final handed = await rig.recorded.at(0);

        final lost = rig.whenState(LiveScanState.unavailable);
        rig.vision.crash(
          const ScanFailure(ScanFailureCode.visionUnavailable, 'worker died'),
        );
        await lost;

        expect(rig.state, ScanRecordingState.stopping);
        rig.writers.single.ack(handed);
        expect(rig.state, ScanRecordingState.off);
        expect(rig.recorder.status.value.written, 1);
      },
    );
  });

  group('what a scan records', () {
    test(
      'fallback acceptance records full and targeted PNGs and one line',
      () async {
        rig = await _Rig.create();
        await rig.startRecording();
        final report = await rig.fallbackScan(
          strip: rig.pixelFrame(seed: 1),
          full: rig.pixelFrame(seed: 2),
          targetedEvidence: _ev(score: 0.55),
          evidence: _ev(),
          outcome: _accepted(_ev()),
        );

        final scan = await rig.recorded.at(0);
        expect(report.id, 1);
        expect(scan.id, '${rig.folderName}-0001');
        expect(rig.recorded.length, 1);
        expect(scan.kind, RecordedScanKind.targeted);
        expect(scan.outcome, RecordedOutcome.accepted);
        expect(scan.targetedMarkerScore, 0.55);
        expect(scan.fallbackMarkerScore, 0.93);
        final full = scan.full!;
        final strip = scan.strip!;
        expect((full.width, full.height, full.stride), (_w, _h, _stride));
        expect((strip.width, strip.height, strip.stride), (_w, _h, _stride));
        expect(full.pixels.materialize().asUint8List(), _bytes(2));
        expect(strip.pixels.materialize().asUint8List(), _bytes(1));
        expect(full.clipped, isFalse);
        expect(scan.clientWidth, 2560);
        expect(scan.clientHeight, 1440);
      },
    );

    test('a superseded scan records nothing', () async {
      rig = await _Rig.create();
      await rig.startRecording();
      rig.fire(1000);
      (await rig.nextCapture()).succeed(rig.pixelFrame());
      final first = await rig.nextVision();

      // A second trigger supersedes the scan while vision holds its frame.
      rig.fire(2000);
      expect(first.isAnswered, isTrue);
      (await rig.nextCapture()).fail(const CaptureBusy());
      final report = await rig.nextPublished();

      expect(report.id, 2);
      expect(rig.recorded.length, 1);
      expect((await rig.recorded.at(0)).id, '${rig.folderName}-0002');
    });

    test(
      'failed extra capture records the strip with image null and fullFailure',
      () async {
        rig = await _Rig.create();
        await rig.startRecording();
        final report = await rig.acceptTargeted(strip: rig.pixelFrame(seed: 1));

        final extra = await rig.nextCapture();
        expect(extra.mode, CaptureMode.fallback);
        extra.fail(const TargetChanged());

        final scan = await rig.recorded.at(0);
        expect(report.end, isA<ScanAccepted>());
        expect(scan.outcome, RecordedOutcome.accepted);
        expect(scan.full, isNull);
        expect(scan.strip, isNotNull);
        expect(scan.fullFailure, 'targetChanged');
        final line = jsonDecode(encodeScanFrameLine(scan)) as Map;
        expect(line['image'], isNull);
        expect(line['captured'], isNull);
        expect(line['fullFailure'], 'targetChanged');
      },
    );

    test('catalogUnavailable records the strip with image null', () async {
      rig = await _Rig.create(catalogLoaded: false);
      await rig.startRecording();
      rig.fire(1000);
      (await rig.nextCapture()).succeed(rig.pixelFrame());
      (await rig.nextVision()).deliver(
        _recognised(InspectionFrameKind.targeted, _ev()),
      );
      final report = await rig.nextPublished();

      final scan = await rig.recorded.at(0);
      expect((report.end as ScanRejected).reason.name, 'catalogUnavailable');
      expect(scan.outcome, RecordedOutcome.rejected);
      expect(scan.rejectReason, 'catalogUnavailable');
      expect(scan.strip, isNotNull);
      expect(scan.full, isNull);
      expect(scan.fullFailure, isNull);
      expect(rig.capture.calls.length, 1, reason: 'no extra capture follows');
    });

    test('captureBusy records a line with no frames', () async {
      rig = await _Rig.create();
      await rig.startRecording();
      await rig.busyScan();

      final scan = await rig.recorded.at(0);
      expect(scan.outcome, RecordedOutcome.failed);
      expect(scan.failure, 'captureBusy');
      expect(scan.strip, isNull);
      expect(scan.full, isNull);
      final line = jsonDecode(encodeScanFrameLine(scan)) as Map;
      expect(line['image'], isNull);
      expect(line['strip'], isNull);
      expect(line['client'], isNull, reason: 'no frame gave a client size');
    });

    test(
      'a failed pixel copy is counted dropped and the scan still runs',
      () async {
        rig = await _Rig.create();
        await rig.startRecording();
        // A frame with no pixels behind it makes the copy throw.
        final report = await rig.fallbackScan(
          strip: rig.frames.frame(),
          full: rig.pixelFrame(seed: 2),
          evidence: _ev(),
          outcome: _accepted(_ev()),
        );

        expect(report.end, isA<ScanAccepted>());
        expect(rig.recorded.length, 0);
        expect(rig.recorder.status.value.dropped, 1);
      },
    );
  });

  group('case line fields', () {
    test(
      'targeted line carries the client cursor and no expected field',
      () async {
        rig = await _Rig.create();
        await rig.startRecording();
        // The client origin lies at desktop (100, 50); the click is at client
        // (812, 403), so at desktop (912, 453).
        await rig.fallbackScan(
          x: 912,
          y: 453,
          strip: rig.pixelFrame(
            desktopLeft: 887,
            desktopTop: 428,
            captured: const CaptureRect(787, 378, _w, _h),
          ),
          full: rig.pixelFrame(
            seed: 2,
            desktopLeft: 100,
            desktopTop: 50,
            captured: const CaptureRect(0, 0, _w, _h),
          ),
          evidence: _ev(),
          outcome: _rejected(OutcomeRejectReason.belowSimilarity, _ev()),
        );

        final scan = await rig.recorded.at(0);
        expect(scan.kind, RecordedScanKind.targeted);
        expect((scan.cursorX, scan.cursorY), (812, 403));
        expect(scan.outcome, RecordedOutcome.rejected);
        expect(scan.rejectReason, 'belowSimilarity');
        final line = jsonDecode(encodeScanFrameLine(scan)) as Map;
        expect(line['cursor'], {'x': 812, 'y': 403});
        expect(line['kind'], 'targeted');
        expect(line.containsKey('expected'), isFalse);
      },
    );

    test('roiOutsideClient records kind fullClient without a cursor', () async {
      rig = await _Rig.create();
      await rig.startRecording();
      await rig.fallbackScan(
        targetedFailure: const RoiOutsideClient(),
        evidence: _ev(),
        outcome: _accepted(_ev()),
      );

      final scan = await rig.recorded.at(0);
      expect(scan.kind, RecordedScanKind.fullClient);
      expect(scan.cursorX, isNull);
      expect(scan.cursorY, isNull);
      expect(scan.strip, isNull);
      expect(scan.full, isNotNull);
      final line = jsonDecode(encodeScanFrameLine(scan)) as Map;
      expect(line['kind'], 'fullClient');
      expect(line.containsKey('cursor'), isFalse);
    });

    test(
      'accepted line carries acceptedId, text and null rejectReason',
      () async {
        rig = await _Rig.create();
        await rig.startRecording();
        final evidence = _ev(text: 'AK-74');
        await rig.fallbackScan(
          evidence: evidence,
          outcome: _accepted(evidence, '5755356824597772cb798962'),
        );

        final scan = await rig.recorded.at(0);
        expect(scan.outcome, RecordedOutcome.accepted);
        expect(scan.acceptedId, '5755356824597772cb798962');
        expect(scan.text, 'AK-74');
        expect(scan.rejectReason, isNull);
        final line = jsonDecode(encodeScanFrameLine(scan)) as Map;
        expect(line['acceptedId'], '5755356824597772cb798962');
        expect(line['text'], 'AK-74');
        expect(line['rejectReason'], isNull);
        expect(line.containsKey('expected'), isFalse);
      },
    );

    test('clipped fallback frame records captured and clipped true', () async {
      rig = await _Rig.create();
      await rig.startRecording();
      await rig.fallbackScan(
        strip: rig.pixelFrame(clientWidth: 1920, clientHeight: 1080),
        full: rig.pixelFrame(
          seed: 2,
          clientWidth: 1920,
          clientHeight: 1080,
          captured: const CaptureRect(200, 0, 1720, 1080),
          clipped: true,
        ),
        evidence: _ev(),
        outcome: _accepted(_ev()),
      );

      final scan = await rig.recorded.at(0);
      expect(scan.full!.clipped, isTrue);
      expect(scan.full!.captured, (
        left: 200,
        top: 0,
        width: 1720,
        height: 1080,
      ));
      final line = jsonDecode(encodeScanFrameLine(scan)) as Map;
      expect(line['clipped'], isTrue);
      expect(line['client'], {'width': 1920, 'height': 1080});
      expect(line['captured'], {
        'left': 200,
        'top': 0,
        'width': 1720,
        'height': 1080,
      });
    });

    test('extra frame time is later than the strip time', () async {
      rig = await _Rig.create();
      await rig.startRecording();
      final stripTime = DateTime.utc(2026, 10, 10, 12);
      await rig.acceptTargeted(strip: rig.pixelFrame(capturedAtUtc: stripTime));
      (await rig.nextCapture()).succeed(
        rig.pixelFrame(
          seed: 2,
          capturedAtUtc: stripTime.add(const Duration(milliseconds: 180)),
        ),
      );

      final scan = await rig.recorded.at(0);
      final line = jsonDecode(encodeScanFrameLine(scan)) as Map;
      final strip = DateTime.parse(line['stripCapturedAtUtc'] as String);
      final full = DateTime.parse(line['fullCapturedAtUtc'] as String);
      expect(full.difference(strip), const Duration(milliseconds: 180));
    });
  });

  group('scan path', () {
    test(
      'with recording off no pixels are read and no capture follows',
      () async {
        rig = await _Rig.create();
        await rig.acceptTargeted(strip: rig.pixelFrame());
        expect(rig.frames.viewCalls, 0);

        // The next trigger's capture is the next scan's targeted one, so no
        // extra capture was requested in between.
        rig.fire(2000);
        final next = await rig.nextCapture();
        expect(next.mode, CaptureMode.targeted);
        expect(rig.capture.calls.length, 2);
        expect(rig.recorded.length, 0);
        expect(rig.writers, isEmpty);
      },
    );

    test('a trigger during the extra capture starts after its answer and the frame is recorded', () async {
      rig = await _Rig.create();
      await rig.startRecording();
      await rig.acceptTargeted(strip: rig.pixelFrame(seed: 1));
      final extra = await rig.nextCapture();
      expect(extra.mode, CaptureMode.fallback);

      rig.fire(2000);
      expect(rig.capture.calls.length, 2, reason: 'the trigger waits');

      final full = rig.pixelFrame(seed: 2);
      extra.succeed(full);
      final scan = await rig.recorded.at(0);
      final second = await rig.nextCapture();

      expect(scan.full, isNotNull);
      expect(scan.strip, isNotNull);
      expect(second.mode, CaptureMode.targeted);
      expect(second.trigger.qpc, 2000);
      expect(rig.frames.released, contains(full.frameId));
    });

    test('recorded files never contain the saved Tracker token', () async {
      rig = await _Rig.create(persist: true);
      final credentials = _MemoryCredentials();
      expect(await credentials.readCredential(GameMode.pvp), _token);
      await rig.startRecording();
      await rig.fallbackScan(evidence: _ev(), outcome: _accepted(_ev()));
      final scan = await rig.recorded.at(0);

      expect(encodeScanFrameLine(scan), isNot(contains(_token)));
      final files = Directory(rig.root)
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      expect(files, hasLength(1), reason: 'the persisted case line');
      for (final file in files) {
        expect(latin1.decode(file.readAsBytesSync()), isNot(contains(_token)));
      }
    });

    test('timing log line keys are the same with recording on', () async {
      rig = await _Rig.create();
      await rig.acceptTargeted();
      await rig.startRecording();
      await rig.acceptTargeted(qpc: 2000);
      (await rig.nextCapture()).succeed(rig.pixelFrame(seed: 2));
      await rig.recorded.at(0);

      expect(rig.logs.length, 2);
      expect(_keys(rig.logs[1]), _keys(rig.logs[0]));
      expect(jsonEncode(rig.logs[1]), isNot(contains('pixels')));
    });

    test(
      'both passes are copied before submit and each frame is released once',
      () async {
        rig = await _Rig.create();
        await rig.startRecording();
        final strip = rig.pixelFrame(seed: 1);
        final full = rig.pixelFrame(seed: 2);
        await rig.fallbackScan(
          strip: strip,
          full: full,
          evidence: _ev(),
          outcome: _accepted(_ev()),
        );
        await rig.recorded.at(0);

        final order = rig.events
            .where(
              (e) =>
                  e.startsWith('capture.') ||
                  e == 'frame.view' ||
                  e == 'vision.submit',
            )
            .toList();
        expect(order, [
          'capture.targeted',
          'frame.view',
          'vision.submit',
          'capture.fallback',
          'frame.view',
          'vision.submit',
        ]);
        expect(rig.frames.viewCalls, 2);
        expect([...rig.frames.released]..sort(), [strip.frameId, full.frameId]);
      },
    );

    test(
      'superseded after capture releases the frame and records nothing',
      () async {
        rig = await _Rig.create();
        await rig.startRecording();
        rig.fire(1000);
        final first = await rig.nextCapture();
        rig.fire(2000);
        final frame = rig.pixelFrame();
        first.succeed(frame);
        await rig.frames.releases.at(0);

        expect(rig.frames.released, [frame.frameId]);
        expect(rig.frames.viewCalls, 0, reason: 'a dead scan copies nothing');
        expect(rig.recorded.length, 0);
        (await rig.nextCapture()).fail(const CaptureBusy());
        await rig.nextPublished();
        expect((await rig.recorded.at(0)).id, '${rig.folderName}-0002');
        expect(rig.recorded.length, 1);
      },
    );

    test('targeted acceptance publishes before the extra capture', () async {
      rig = await _Rig.create();
      await rig.startRecording();
      await rig.acceptTargeted();
      await rig.nextCapture();

      final order = rig.events
          .where(
            (e) => e == 'log' || e == 'published' || e == 'capture.fallback',
          )
          .toList();
      expect(order, ['log', 'published', 'capture.fallback']);
      expect(rig.coordinator.latest!.end, isA<ScanAccepted>());
      expect(rig.logs.length, 1);
      expect(rig.logs[0]['end'], 'accepted');
    });

    test('extra captureTimeout fails the pending scan captureBusy and records fullFailure', () async {
      rig = await _Rig.create();
      await rig.startRecording();
      await rig.acceptTargeted();
      final extra = await rig.nextCapture();
      rig.fire(2000);

      extra.fail(const CaptureTimeout());
      (await rig.nextCapture()).fail(const CaptureBusy());
      final pending = await rig.nextPublished();

      expect(
        (pending.end as ScanFailed).failure.code,
        ScanFailureCode.captureBusy,
      );
      expect(rig.logs.length, 2);
      expect(rig.logs[1]['end'], 'failed');
      expect(rig.logs[1]['reason'], 'captureBusy');
      final first = await rig.recorded.at(0);
      expect(first.fullFailure, 'captureTimeout');
      expect(first.full, isNull);
      expect(first.outcome, RecordedOutcome.accepted);
      final second = await rig.recorded.at(1);
      expect(second.failure, 'captureBusy');
    });

    test(
      'stop during the extra capture releases the frame and records nothing',
      () async {
        rig = await _Rig.create();
        await rig.startRecording();
        await rig.acceptTargeted();
        final extra = await rig.nextCapture();

        await rig.coordinator.setLiveScan(false);
        expect(rig.state, ScanRecordingState.off);
        final lateFrame = rig.pixelFrame(seed: 2);
        extra.succeed(lateFrame);
        await rig.frames.releases.at(1);

        expect(rig.frames.released, contains(lateFrame.frameId));
        expect(rig.frames.viewCalls, 1, reason: 'only the strip was copied');
        expect(rig.recorded.length, 0);
      },
    );
  });
}
