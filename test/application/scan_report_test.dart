import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:flutter_test/flutter_test.dart';

/// 10,000 ticks per second: one tick is 0.1 ms.
const _frequency = 10000;
const _trigger = 5000000;

int _t(int ms) => _trigger + ms * 10;

InspectionEvidence _entry({
  required int base,
  double score = 0.93,
  String text = 'Salewa First Aid Kit',
}) => InspectionEvidence(
  markerScore: score,
  markerX: 10,
  markerY: 20,
  titleRect: const TitleRegion(x: 1, y: 2, width: 30, height: 8),
  titleStatus: InspectionTitleStatus.read,
  text: text,
  crop: Uint8List.fromList(List<int>.filled(64, 7)),
  cropWidth: 8,
  cropHeight: 8,
  cropDownscaled: false,
  qpcMarker: _t(base + 1),
  qpcTitle: _t(base + 2),
  qpcPreprocess: _t(base + 3),
  qpcOcr: _t(base + 4),
);

InspectionRecognised _recognised(InspectionEvidence? entry) =>
    InspectionRecognised(
      kind: InspectionFrameKind.targeted,
      scale: 1,
      bestMarkerScore: entry?.markerScore ?? 0.4,
      evidence: [?entry],
    );

/// Walks every key and value, failing on any byte buffer.
void _expectNoBytes(Object? node) {
  switch (node) {
    case Map<Object?, Object?>():
      for (final MapEntry(:key, :value) in node.entries) {
        expect(key, isA<String>());
        expect(key, isNot(contains('crop')));
        _expectNoBytes(value);
      }
    case Uint8List():
      fail('crop bytes in the log line');
    case List<Object?>():
      for (final value in node) {
        _expectNoBytes(value);
      }
    case num() || String() || bool() || null:
      break;
    default:
      fail('unexpected ${node.runtimeType} in the log line');
  }
}

void main() {
  group('ScanReport.toLogLine', () {
    test('accepted fallback report encodes a v1 line with per-pass ms', () {
      final targetedEntry = _entry(base: 20, score: 0.88, text: 'Salewa');
      final fallbackEntry = _entry(base: 120);
      final targeted = _recognised(targetedEntry);
      final fallback = InspectionRecognised(
        kind: InspectionFrameKind.fullClient,
        scale: 1,
        bestMarkerScore: 0.93,
        evidence: [fallbackEntry],
      );
      final accepted = TitleAccepted(
        bestId: 'kit',
        normalisedTitle: 'salewa first aid kit',
        bestScore: 0.97,
        runnerUpId: 'bolts',
        runnerUpScore: 0.31,
        margin: 0.66,
        confirmedBy: null,
        mode: GameMode.pvp,
        revision: 'r1',
      );
      final report = ScanReport(
        id: 7,
        utc: DateTime.utc(2026, 10, 10, 12, 30, 15),
        end: ScanAccepted(
          itemId: 'kit',
          outcome: OutcomeAccepted<InspectionEvidence>(accepted, fallbackEntry),
        ),
        winningPass: ScanPass.fallback,
        targeted: PassReport(recognition: targeted),
        fallback: PassReport(recognition: fallback),
        catalogMode: GameMode.pvp,
        catalogRevision: 'r1',
        timeline: ScanTimeline(
          trigger: _trigger,
          published: _t(200),
          targeted: PassTimeline(
            captureRequested: _t(1),
            acquireStart: _t(2),
            acquireEnd: _t(10),
            captureAnswered: _t(11),
            visionSubmitted: _t(12),
            jobStarted: _t(13),
            jobFinished: _t(30),
            matchStarted: _t(31),
            matchFinished: _t(35),
          ).withEvidenceStamps(targeted),
          fallback: PassTimeline(
            captureRequested: _t(100),
            acquireStart: _t(101),
            acquireEnd: _t(110),
            captureAnswered: _t(111),
            visionSubmitted: _t(112),
            jobStarted: _t(113),
            jobFinished: _t(150),
            matchStarted: _t(151),
            matchFinished: _t(160),
          ).withEvidenceStamps(fallback, winner: fallbackEntry),
        ),
        droppedTriggers: 2,
        supersededTriggers: 1,
      );

      final line = report.toLogLine(_frequency);

      expect(line['v'], 1);
      expect(line['utc'], '2026-10-10T12:30:15.000Z');
      expect(line['end'], 'accepted');
      expect(line['item'], 'kit');
      expect(line['pass'], 'fallback');
      expect(line['droppedTriggers'], 2);
      expect(line['supersededTriggers'], 1);
      expect(line.containsKey('reason'), isFalse);

      final ms = line['ms']! as Map<String, Object?>;
      expect(ms['trigger'], 0);
      expect(ms['published'], 200.0);
      expect(ms['targeted'], <String, Object?>{
        'captureRequested': 1.0,
        'acquireStart': 2.0,
        'acquireEnd': 10.0,
        'captureAnswered': 11.0,
        'visionSubmitted': 12.0,
        'jobStarted': 13.0,
        // The targeted pass keeps its own evidence stamps.
        'marker': 21.0,
        'title': 22.0,
        'preprocess': 23.0,
        'ocr': 24.0,
        'jobFinished': 30.0,
        'matchStarted': 31.0,
        'matchFinished': 35.0,
      });
      expect(ms['fallback'], <String, Object?>{
        'captureRequested': 100.0,
        'acquireStart': 101.0,
        'acquireEnd': 110.0,
        'captureAnswered': 111.0,
        'visionSubmitted': 112.0,
        'jobStarted': 113.0,
        'marker': 121.0,
        'title': 122.0,
        'preprocess': 123.0,
        'ocr': 124.0,
        'jobFinished': 150.0,
        'matchStarted': 151.0,
        'matchFinished': 160.0,
      });

      final targetedLine = line['targeted']! as Map<String, Object?>;
      expect(targetedLine['bestMarker'], 0.88);
      expect(targetedLine['text'], 'Salewa');
      expect(targetedLine.containsKey('candidates'), isFalse);
      final fallbackLine = line['fallback']! as Map<String, Object?>;
      expect(fallbackLine['text'], 'Salewa First Aid Kit');
      expect(fallbackLine['candidates'], [
        {'id': 'kit', 'score': 0.97},
        {'id': 'bolts', 'score': 0.31},
      ]);

      _expectNoBytes(line);
      expect(jsonDecode(jsonEncode(line)), isA<Map<String, Object?>>());
    });

    test('superseded report encodes only the stages reached', () {
      final report = ScanReport(
        id: 8,
        utc: DateTime.utc(2026, 10, 10),
        end: const ScanSuperseded(),
        targeted: const PassReport(),
        timeline: ScanTimeline(
          trigger: _trigger,
          targeted: PassTimeline(
            captureRequested: _t(1),
            captureAnswered: _t(40),
            visionSubmitted: _t(41),
          ),
        ),
        droppedTriggers: 0,
        supersededTriggers: 0,
      );

      final line = report.toLogLine(_frequency);

      expect(line['v'], 1);
      expect(line['end'], 'superseded');
      for (final key in ['item', 'reason', 'pass', 'fallback']) {
        expect(line.containsKey(key), isFalse, reason: key);
      }
      final ms = line['ms']! as Map<String, Object?>;
      expect(ms['trigger'], 0);
      expect(ms.containsKey('published'), isFalse);
      expect(ms.containsKey('fallback'), isFalse);
      expect(ms['targeted'], <String, Object?>{
        'captureRequested': 1.0,
        'captureAnswered': 40.0,
        'visionSubmitted': 41.0,
      });
      _expectNoBytes(line);
    });

    test('a pass without a marker has no sub-stage stamps', () {
      final stamps = PassTimeline(jobStarted: _t(1))
          .withEvidenceStamps(_recognised(null));
      expect(stamps.jobStarted, _t(1));
      expect(stamps.marker, isNull);
      expect(stamps.title, isNull);
      expect(stamps.preprocess, isNull);
      expect(stamps.ocr, isNull);
    });

    test('line holds no crop bytes and withoutCrops drops them', () {
      final entry = _entry(base: 1);
      final recognition = _recognised(entry);
      final report = ScanReport(
        id: 1,
        utc: DateTime.utc(2026),
        end: ScanRejected(
          reason: ScanRejectReason.belowSimilarity,
          outcome: OutcomeRejected<InspectionEvidence>(
            OutcomeRejectReason.belowSimilarity,
            evidence: entry,
            match: const TitleRejected(
              reason: TitleRejectReason.belowSimilarity,
              normalisedTitle: 'salewa',
              bestId: 'kit',
              bestScore: 0.41,
              mode: GameMode.pvp,
              revision: 'r1',
            ),
          ),
        ),
        winningPass: ScanPass.targeted,
        targeted: PassReport(recognition: recognition),
        timeline: ScanTimeline(trigger: _trigger),
        droppedTriggers: 0,
        supersededTriggers: 0,
      );

      final line = report.toLogLine(_frequency);
      expect(line['reason'], 'belowSimilarity');
      _expectNoBytes(line);
      jsonEncode(line);

      final stripped = report.withoutCrops();
      final recognised =
          stripped.targeted!.recognition! as InspectionRecognised;
      expect(recognised.evidence.single.crop, isEmpty);
      expect(recognised.evidence.single.text, entry.text);
      final outcome = (stripped.end as ScanRejected).outcome!;
      expect(outcome.evidence!.crop, isEmpty);
      expect(report.hasCrops, isTrue);
      expect(stripped.hasCrops, isFalse);
    });
  });
}
