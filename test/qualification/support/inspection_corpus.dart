/// Pure parts of the inspection corpus runner: corpus and baseline parsing,
/// the targeted capture region, PNG conversion, per-case evaluation, report
/// building and baseline comparison.
///
/// Nothing here loads the vision runtime. The recogniser and the matcher are
/// injected, so the whole flow runs offline with fakes; the qualification
/// test supplies the real service.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/output_path_guard.dart';
import 'package:blackgrid/data/capture/capture_geometry.dart';
import 'package:blackgrid/data/capture/capture_snapshot.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:image/image.dart' as img;

/// The full-client job deadline the report is measured against.
const int fullClientDeadlineMs = 1500;

/// The expected outcome that means "no item may be accepted".
const String rejectOutcome = 'reject';

/// The corpus subdirectory the run writes its report and crops into.
const String corpusOutputDir = 'out';

/// The first of [inputs], paths relative to [corpusDir], that is its
/// [corpusOutputDir] or lies inside it, or null when none does.
///
/// Each input is compared canonically through `unsafeOutputReason`: links and
/// junctions are resolved, `.` and `..` segments collapse, and case is ignored
/// on Windows. An input that is itself a link or sits below one is named too,
/// since its real location cannot be trusted to stay outside the output. The
/// run refuses to write anything when this is not null, so it never
/// overwrites an input.
String? inputInsideOutput(String corpusDir, Iterable<String> inputs) {
  final sep = Platform.pathSeparator;
  final output = '$corpusDir$sep$corpusOutputDir';
  for (final input in inputs) {
    final reason = unsafeOutputReason(
      '$corpusDir$sep$input',
      protectedDirectories: [output],
    );
    if (reason != null) return input;
  }
  return null;
}

/// Why [image] cannot stand for case [c], or null when its size is the
/// declared client size the scale, capture region and report derive from.
String? clientSizeMismatch(CorpusCase c, BgrxImage image) =>
    image.width == c.clientWidth && image.height == c.clientHeight
    ? null
    : '${c.id}: image ${image.width}x${image.height} does not match the '
          'declared client ${c.clientWidth}x${c.clientHeight}';

/// One corpus entry.
final class CorpusCase {
  /// Creates a case.
  const CorpusCase({
    required this.id,
    required this.image,
    required this.clientWidth,
    required this.clientHeight,
    required this.kind,
    required this.expected,
    this.cursorX,
    this.cursorY,
  });

  /// Unique case name.
  final String id;

  /// Image path, relative to the corpus directory.
  final String image;

  /// Game client width in pixels; the image is the whole client.
  final int clientWidth;

  /// Game client height in pixels.
  final int clientHeight;

  /// Whether the case is read through the targeted region or the whole client.
  final InspectionFrameKind kind;

  /// Cursor x in client pixels; set for targeted cases.
  final int? cursorX;

  /// Cursor y in client pixels; set for targeted cases.
  final int? cursorY;

  /// The expected item ID, or [rejectOutcome].
  final String expected;

  /// The resolution family, `WIDTHxHEIGHT`.
  String get family => '${clientWidth}x$clientHeight';
}

Never _bad(String message) => throw FormatException(message);

T _field<T>(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is T) return value;
  _bad('$where: "$key" must be a $T');
}

/// Parses `corpus.json`: an object with a `cases` list. Each case has `id`,
/// `image`, `client` (`width`, `height`), `kind` (`targeted` or `fullClient`),
/// `expected` (an item ID or `reject`) and, for targeted cases, `cursor`
/// (`x`, `y`, in client pixels).
///
/// Throws [FormatException] on any malformed or inconsistent entry.
List<CorpusCase> parseCorpus(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, Object?>) _bad('corpus must be a JSON object');
  final list = root['cases'];
  if (list is! List) _bad('corpus needs a "cases" list');
  final seen = <String>{};
  return [
    for (final (index, raw) in list.indexed) _parseCase(index, raw, seen),
  ];
}

CorpusCase _parseCase(int index, Object? raw, Set<String> seen) {
  final where = 'case #$index';
  if (raw is! Map<String, Object?>) _bad('$where must be an object');
  final id = _field<String>(raw, 'id', where);
  // Ids name crop files, which collide without case on Windows.
  if (id.isEmpty || !seen.add(id.toLowerCase())) {
    _bad('$where: id "$id" is not unique (compared without case)');
  }
  final client = _field<Map<String, Object?>>(raw, 'client', id);
  final width = _field<int>(client, 'width', id);
  final height = _field<int>(client, 'height', id);
  if (width <= 0 || height <= 0) _bad('$id: client size must be > 0');
  final kind = switch (_field<String>(raw, 'kind', id)) {
    'targeted' => InspectionFrameKind.targeted,
    'fullClient' => InspectionFrameKind.fullClient,
    final other => _bad('$id: unknown kind "$other"'),
  };
  final expected = _field<String>(raw, 'expected', id);
  if (expected.isEmpty) _bad('$id: expected must not be empty');
  int? cx;
  int? cy;
  if (kind == InspectionFrameKind.targeted) {
    final cursor = _field<Map<String, Object?>>(raw, 'cursor', id);
    cx = _field<int>(cursor, 'x', id);
    cy = _field<int>(cursor, 'y', id);
    if (cx < 0 || cy < 0 || cx >= width || cy >= height) {
      _bad('$id: cursor ($cx, $cy) is outside the client');
    }
  }
  return CorpusCase(
    id: id,
    image: _field<String>(raw, 'image', id),
    clientWidth: width,
    clientHeight: height,
    kind: kind,
    expected: expected,
    cursorX: cx,
    cursorY: cy,
  );
}

/// The targeted capture region around the cursor, in client pixels, by the
/// capture spec's rule: `(x - m/2, y - m/2, m + r, m)` with `m = floor(50 s)`
/// and `r = floor(600 s)`, clipped to the client. Null when the region lies
/// outside the client.
CaptureRect? targetedRegion({
  required int clientWidth,
  required int clientHeight,
  required int cursorX,
  required int cursorY,
}) {
  final client = CaptureRect(0, 0, clientWidth, clientHeight);
  final snapshot = WindowSnapshot(
    hwnd: 0,
    pid: 0,
    tid: 0,
    minimised: false,
    foreground: true,
    dpi: 96,
    client: client,
    monitor: client,
    virtualDesktop: client,
    title: 'corpus',
  );
  return switch (planTargeted(snapshot, x: cursorX, y: cursorY)) {
    PlanOk(:final plan) => plan.captured,
    PlanFailure() => null,
  };
}

/// A decoded image as tightly packed BGRX bytes.
final class BgrxImage {
  /// Creates an image of [width] by [height] over [bytes] (4 per pixel).
  const BgrxImage(this.bytes, this.width, this.height);

  /// Blue, green, red, opaque, per pixel.
  final Uint8List bytes;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Row stride in bytes.
  int get stride => width * 4;

  /// The sub-image at [rect], which must lie inside the image.
  BgrxImage crop(CaptureRect rect) {
    final out = Uint8List(rect.width * rect.height * 4);
    final rowBytes = rect.width * 4;
    for (var row = 0; row < rect.height; row++) {
      final from = ((rect.top + row) * width + rect.left) * 4;
      out.setRange(row * rowBytes, (row + 1) * rowBytes, bytes, from);
    }
    return BgrxImage(out, rect.width, rect.height);
  }
}

/// Decodes PNG [source] to BGRX. Throws [FormatException] when it is not a
/// decodable image.
BgrxImage decodePngBgrx(Uint8List source) {
  final decoded = img.decodePng(source);
  if (decoded == null) _bad('not a decodable PNG');
  final rgba = decoded.convert(numChannels: 4, format: img.Format.uint8);
  final out = Uint8List(rgba.width * rgba.height * 4);
  var at = 0;
  for (final p in rgba) {
    out[at++] = p.b.toInt();
    out[at++] = p.g.toInt();
    out[at++] = p.r.toInt();
    out[at++] = 255;
  }
  return BgrxImage(out, rgba.width, rgba.height);
}

/// Encodes a thresholded one-byte-per-pixel crop as a grayscale PNG.
Uint8List cropToPng(Uint8List crop, int width, int height) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: crop.buffer,
    bytesOffset: crop.offsetInBytes,
    numChannels: 1,
    format: img.Format.uint8,
  );
  return img.encodePng(image);
}

/// A recognition result and the time the job took to produce it.
typedef TimedRecognition = ({InspectionRecognition result, Duration elapsed});

/// Recognises a case as [kind]; the qualification test crops the image for
/// targeted runs and submits the frame to the real service.
typedef CorpusRecogniser = Future<TimedRecognition> Function(
  CorpusCase corpusCase,
  InspectionFrameKind kind,
);

/// Ranks the evidence of one case. `targeted` is null for a full-client
/// case; `fullClient` is null before a fallback.
typedef CorpusMatcher =
    Future<RecognitionOutcome<InspectionEvidence>> Function({
      required InspectionRecognition? targeted,
      InspectionRecognition? fullClient,
    });

/// Stores the crop of the evidence for the case and returns where, or null.
typedef CropWriter = Future<String?> Function(
  String caseId,
  InspectionEvidence evidence,
);

/// What one case produced.
final class CaseReport {
  /// Creates a case report.
  const CaseReport({
    required this.caseId,
    required this.family,
    required this.kind,
    required this.expected,
    required this.outcome,
    required this.usedFallback,
    this.rejectReason,
    this.targetedMarkerScore,
    this.fallbackMarkerScore,
    this.text,
    this.cropPath,
    this.bestId,
    this.bestScore,
    this.runnerUpId,
    this.runnerUpScore,
    this.fullClientMs,
  });

  /// The case name.
  final String caseId;

  /// The resolution family, `WIDTHxHEIGHT`.
  final String family;

  /// The frame kind the case was declared with.
  final InspectionFrameKind kind;

  /// The expected item ID or [rejectOutcome].
  final String expected;

  /// The accepted item ID, or [rejectOutcome].
  final String outcome;

  /// The outcome-level reject reason name, when rejected.
  final String? rejectReason;

  /// Whether the full-client job also ran as the fallback.
  final bool usedFallback;

  /// Best marker score of the targeted (or only) run.
  final double? targetedMarkerScore;

  /// Best marker score of the fallback run.
  final double? fallbackMarkerScore;

  /// The OCR text of the deciding evidence.
  final String? text;

  /// Where the deciding thresholded crop was written.
  final String? cropPath;

  /// Best candidate ID of the deciding match.
  final String? bestId;

  /// Best candidate similarity.
  final double? bestScore;

  /// Runner-up candidate ID.
  final String? runnerUpId;

  /// Runner-up candidate similarity.
  final double? runnerUpScore;

  /// Time of the full-client job in milliseconds, when it ran.
  final int? fullClientMs;

  /// Whether the expected item was accepted.
  bool get correct => expected != rejectOutcome && outcome == expected;

  /// Whether an item was accepted that should not have been.
  bool get falsePositive => outcome != rejectOutcome && outcome != expected;

  /// The JSON form written to `report.json`.
  Map<String, Object?> toJson() => {
    'id': caseId,
    'family': family,
    'kind': kind.name,
    'expected': expected,
    'outcome': outcome,
    'rejectReason': rejectReason,
    'correct': correct,
    'falsePositive': falsePositive,
    'usedFallback': usedFallback,
    'targetedMarkerScore': targetedMarkerScore,
    'fallbackMarkerScore': fallbackMarkerScore,
    'text': text,
    'cropPath': cropPath,
    'bestId': bestId,
    'bestScore': bestScore,
    'runnerUpId': runnerUpId,
    'runnerUpScore': runnerUpScore,
    'fullClientMs': fullClientMs,
  };
}

/// Runs one case: the declared recognition, then, for a targeted case that is
/// not accepted, the full-client recognition as the fallback.
///
/// A full-client case is matched as full-client evidence with no targeted
/// result, so every peak is ranked and the best accepted one wins.
Future<CaseReport> evaluateCase(
  CorpusCase corpusCase, {
  required CorpusRecogniser recognise,
  required CorpusMatcher match,
  required CropWriter writeCrop,
}) async {
  final first = await recognise(corpusCase, corpusCase.kind);
  var outcome = corpusCase.kind == InspectionFrameKind.fullClient
      ? await match(targeted: null, fullClient: first.result)
      : await match(targeted: first.result);
  TimedRecognition? fallback;
  var fullClientElapsed = corpusCase.kind == InspectionFrameKind.fullClient
      ? first.elapsed
      : null;
  if (corpusCase.kind == InspectionFrameKind.targeted &&
      outcome is! OutcomeAccepted<InspectionEvidence>) {
    fallback = await recognise(corpusCase, InspectionFrameKind.fullClient);
    fullClientElapsed = fallback.elapsed;
    outcome = await match(targeted: first.result, fullClient: fallback.result);
  }

  final (
    String item,
    String? reason,
    InspectionEvidence? evidence,
    decided,
  ) = switch (outcome) {
    OutcomeAccepted(:final match, :final evidence) => (
      match.bestId!,
      null,
      evidence,
      match as TitleMatch?,
    ),
    OutcomeRejected(:final reason, :final evidence, :final match) => (
      rejectOutcome,
      reason.name,
      evidence,
      match,
    ),
  };
  return CaseReport(
    caseId: corpusCase.id,
    family: corpusCase.family,
    kind: corpusCase.kind,
    expected: corpusCase.expected,
    outcome: item,
    rejectReason: reason,
    usedFallback: fallback != null,
    targetedMarkerScore: _bestScore(first.result),
    fallbackMarkerScore: fallback == null ? null : _bestScore(fallback.result),
    text: evidence?.text,
    cropPath: evidence == null
        ? null
        : await writeCrop(corpusCase.id, evidence),
    bestId: decided?.bestId,
    bestScore: decided?.bestScore,
    runnerUpId: decided?.runnerUpId,
    runnerUpScore: decided?.runnerUpScore,
    fullClientMs: fullClientElapsed?.inMilliseconds,
  );
}

double? _bestScore(InspectionRecognition r) => switch (r) {
  InspectionRecognised(:final bestMarkerScore) => bestMarkerScore,
  InspectionRejected(:final bestMarkerScore) => bestMarkerScore,
};

/// Reference per-case outcomes: item ID or [rejectOutcome].
final class Baseline {
  /// Creates a baseline.
  const Baseline(this.outcomes);

  /// Outcome by case ID.
  final Map<String, String> outcomes;
}

/// Parses `baseline.json`: `{"cases": {"<case id>": "<item id>|reject"}}`.
Baseline parseBaseline(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, Object?>) _bad('baseline must be a JSON object');
  final cases = root['cases'];
  if (cases is! Map) _bad('baseline needs a "cases" object');
  final outcomes = <String, String>{};
  for (final MapEntry(:key, :value) in cases.entries) {
    if (key is! String || value is! String) {
      _bad('baseline entry "$key" must map a string to a string');
    }
    outcomes[key] = value;
  }
  return Baseline(outcomes);
}

/// Coverage and false-positive counts over a set of outcomes.
final class Tally {
  /// Creates a tally.
  const Tally({
    required this.expectedItemCases,
    required this.correct,
    required this.falsePositives,
  });

  /// Cases that expect an item.
  final int expectedItemCases;

  /// Cases whose expected item was accepted.
  final int correct;

  /// Cases that accepted something they should not have.
  final int falsePositives;

  /// Correct over expected; 1 when no case expects an item.
  double get coverage =>
      expectedItemCases == 0 ? 1 : correct / expectedItemCases;

  /// The JSON form.
  Map<String, Object?> toJson() => {
    'expectedItemCases': expectedItemCases,
    'correct': correct,
    'coverage': coverage,
    'falsePositives': falsePositives,
  };
}

/// Counts [outcomes] (case ID to outcome) against [expected] (case ID to
/// expected), over the case IDs in both.
Tally tallyOutcomes(
  Map<String, String> expected,
  Map<String, String> outcomes,
) {
  var items = 0;
  var correct = 0;
  var falsePositives = 0;
  for (final MapEntry(:key, :value) in outcomes.entries) {
    final want = expected[key];
    if (want == null) continue;
    if (want != rejectOutcome) {
      items++;
      if (value == want) correct++;
    }
    if (value != rejectOutcome && value != want) falsePositives++;
  }
  return Tally(
    expectedItemCases: items,
    correct: correct,
    falsePositives: falsePositives,
  );
}

/// The comparison of a run with a baseline, over the cases in both.
final class BaselineComparison {
  /// Creates a comparison.
  const BaselineComparison({
    required this.baseline,
    required this.current,
    required this.regressions,
    required this.newFalsePositives,
    required this.improvements,
  });

  /// The baseline's tally.
  final Tally baseline;

  /// This run's tally.
  final Tally current;

  /// Cases the baseline got right and this run did not.
  final List<String> regressions;

  /// Cases this run accepted wrongly and the baseline did not.
  final List<String> newFalsePositives;

  /// Cases this run got right and the baseline did not.
  final List<String> improvements;

  /// Whether coverage is no lower and false positives are no higher.
  bool get passed =>
      current.correct >= baseline.correct &&
      current.falsePositives <= baseline.falsePositives;

  /// The JSON form.
  Map<String, Object?> toJson() => {
    'passed': passed,
    'baseline': baseline.toJson(),
    'current': current.toJson(),
    'regressions': regressions,
    'newFalsePositives': newFalsePositives,
    'improvements': improvements,
  };
}

/// Compares [reports] with [baseline] per case.
BaselineComparison compareWithBaseline(
  List<CaseReport> reports,
  Baseline baseline,
) {
  final shared = [
    for (final r in reports)
      if (baseline.outcomes.containsKey(r.caseId)) r,
  ];
  final expected = {for (final r in shared) r.caseId: r.expected};
  final regressions = <String>[];
  final newFalsePositives = <String>[];
  final improvements = <String>[];
  for (final r in shared) {
    final reference = baseline.outcomes[r.caseId]!;
    final referenceCorrect =
        r.expected != rejectOutcome && reference == r.expected;
    final referenceWrong =
        reference != rejectOutcome && reference != r.expected;
    if (referenceCorrect && !r.correct) regressions.add(r.caseId);
    if (!referenceCorrect && r.correct) improvements.add(r.caseId);
    if (r.falsePositive && !referenceWrong) newFalsePositives.add(r.caseId);
  }
  return BaselineComparison(
    baseline: tallyOutcomes(expected, baseline.outcomes),
    current: tallyOutcomes(expected, {
      for (final r in shared) r.caseId: r.outcome,
    }),
    regressions: regressions,
    newFalsePositives: newFalsePositives,
    improvements: improvements,
  );
}

/// The full report written to `report.json`.
///
/// Per resolution family it lists the full-client job times against
/// [deadlineMs]; with a [baseline] it adds the per-case comparison.
Map<String, Object?> buildReport(
  List<CaseReport> reports, {
  Baseline? baseline,
  int deadlineMs = fullClientDeadlineMs,
}) {
  final tally = tallyOutcomes(
    {for (final r in reports) r.caseId: r.expected},
    {for (final r in reports) r.caseId: r.outcome},
  );
  final timesByFamily = <String, List<int>>{};
  for (final r in reports) {
    final ms = r.fullClientMs;
    if (ms != null) timesByFamily.putIfAbsent(r.family, () => []).add(ms);
  }
  final comparison = baseline == null
      ? null
      : compareWithBaseline(reports, baseline);
  return {
    'summary': tally.toJson(),
    'families': [
      for (final MapEntry(:key, :value) in timesByFamily.entries)
        {
          'client': key,
          'fullClientRuns': value.length,
          'fullClientMs': value,
          'maxMs': value.reduce((a, b) => a > b ? a : b),
          'deadlineMs': deadlineMs,
          'withinDeadline': value.every((ms) => ms <= deadlineMs),
        },
    ],
    'cases': [for (final r in reports) r.toJson()],
    'baseline': comparison?.toJson(),
  };
}
