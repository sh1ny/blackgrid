import 'dart:async';
import 'dart:typed_data';

import 'package:blackgrid/application/recognition_matcher.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:blackgrid/data/vision/inspection_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogItem _item(String id, String name) => CatalogItem(
  id: id,
  name: name,
  normalizedName: name.toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
);

CatalogSnapshot _snapshot() => CatalogSnapshot(
  mode: GameMode.pvp,
  revision: 'r1',
  observedAt: DateTime.utc(2026, 1, 1),
  items: {
    for (final i in [
      _item('kit', 'Salewa First Aid Kit'),
      _item('bolts', 'Steel Hex Bolts'),
    ])
      i.id: i,
  },
  traders: const {},
  requirements: const [],
);

InspectionEvidence _evidence(String text, {double score = 0.9}) =>
    InspectionEvidence(
      markerScore: score,
      markerX: 1,
      markerY: 2,
      titleRect: const TitleRegion(x: 0, y: 0, width: 10, height: 5),
      titleStatus: InspectionTitleStatus.read,
      text: text,
      crop: Uint8List.fromList([1, 2, 3]),
      cropWidth: 3,
      cropHeight: 1,
      cropDownscaled: false,
      qpcMarker: 0,
      qpcTitle: 0,
      qpcPreprocess: 0,
      qpcOcr: 0,
    );

InspectionRecognised _recognised(
  InspectionFrameKind kind,
  List<InspectionEvidence> evidence, {
  double best = 0.9,
}) => InspectionRecognised(
  kind: kind,
  scale: 1,
  bestMarkerScore: best,
  evidence: evidence,
);

Future<R> _throwingRunner<R>(FutureOr<R> Function() computation) =>
    Future<R>.error(StateError('isolate died'));

void main() {
  group('recognitionInputFor', () {
    test('numbers entries by their position in the evidence list', () {
      final input = recognitionInputFor(
        _recognised(InspectionFrameKind.fullClient, [
          _evidence('a', score: 0.95),
          _evidence('b', score: 0.85),
        ], best: 0.95),
      );
      expect(input.bestMarkerScore, 0.95);
      expect([for (final e in input.entries) e.peakOrder], [0, 1]);
      expect(input.entries[1].text, 'b');
      expect(input.entries[1].markerScore, 0.85);
      expect(input.entries[1].emptyTitleRegion, isFalse);
    });

    test('flags an empty title region', () {
      final empty = InspectionEvidence(
        markerScore: 0.9,
        markerX: 0,
        markerY: 0,
        titleRect: const TitleRegion(x: 0, y: 0, width: 0, height: 0),
        titleStatus: InspectionTitleStatus.emptyTitleRegion,
        text: '',
        crop: Uint8List(0),
        cropWidth: 0,
        cropHeight: 0,
        cropDownscaled: false,
        qpcMarker: 0,
        qpcTitle: 0,
        qpcPreprocess: 0,
        qpcOcr: 0,
      );
      final input = recognitionInputFor(
        _recognised(InspectionFrameKind.targeted, [empty]),
      );
      expect(input.entries.single.emptyTitleRegion, isTrue);
    });

    test('a rejected result contributes no entries and keeps its score', () {
      const rejected = InspectionRejected(
        kind: InspectionFrameKind.targeted,
        scale: 1,
        reason: InspectionRejection.markerPeaksOverflow,
        bestMarkerScore: 0.4,
      );
      final input = recognitionInputFor(rejected);
      expect(input.entries, isEmpty);
      expect(input.bestMarkerScore, 0.4);
      expect(
        recognitionInputFor(
          const InspectionRejected(
            kind: InspectionFrameKind.targeted,
            scale: 1,
            reason: InspectionRejection.scaleOutOfRange,
          ),
        ).bestMarkerScore,
        isNull,
      );
    });
  });

  group('off-UI adapters', () {
    test(
      'builds an index and accepts a targeted title in real isolates',
      () async {
        final index = await buildTitleMatchIndexOffUi(_snapshot());
        final outcome = await matchRecognitionOffUi(
          index,
          targeted: _recognised(InspectionFrameKind.targeted, [
            _evidence('Salewa First Aid Kit'),
          ]),
          mode: GameMode.pvp,
        );
        final accepted = outcome as OutcomeAccepted<InspectionEvidence>;
        expect(accepted.match.bestId, 'kit');
        expect(accepted.evidence.text, 'Salewa First Aid Kit');
      },
    );

    test(
      'falls back to the full-client result when targeted is rejected',
      () async {
        final index = await buildTitleMatchIndexOffUi(_snapshot());
        final outcome = await matchRecognitionOffUi(
          index,
          targeted: _recognised(InspectionFrameKind.targeted, [
            _evidence('zzzz qqqq'),
          ]),
          fullClient: _recognised(InspectionFrameKind.fullClient, [
            _evidence('zzzz qqqq', score: 0.86),
            _evidence('Steel Hex Bolts', score: 0.85),
          ]),
          mode: GameMode.pvp,
        );
        final accepted = outcome as OutcomeAccepted<InspectionEvidence>;
        expect(accepted.match.bestId, 'bolts');
      },
    );

    test(
      'ranks every full-client peak when there is no targeted result',
      () async {
        final index = await buildTitleMatchIndexOffUi(_snapshot());
        final outcome = await matchRecognitionOffUi(
          index,
          targeted: null,
          fullClient: _recognised(InspectionFrameKind.fullClient, [
            _evidence('Steel Hex Boltz', score: 0.95),
            _evidence('Salewa First Aid Kit', score: 0.85),
          ], best: 0.95),
          mode: GameMode.pvp,
        );
        final accepted = outcome as OutcomeAccepted<InspectionEvidence>;
        expect(accepted.match.bestId, 'kit');
        expect(accepted.evidence.text, 'Salewa First Aid Kit');
      },
    );

    test('no targeted result and no peaks is noMarker with no targeted '
        'score', () async {
      final index = await buildTitleMatchIndexOffUi(_snapshot());
      final outcome = await matchRecognitionOffUi(
        index,
        targeted: null,
        fullClient: _recognised(InspectionFrameKind.fullClient, [], best: 0.4),
        mode: GameMode.pvp,
      );
      final rejected = outcome as OutcomeRejected<InspectionEvidence>;
      expect(rejected.reason, OutcomeRejectReason.noMarker);
      expect(rejected.targetedBestMarkerScore, isNull);
      expect(rejected.fallbackBestMarkerScore, 0.4);
    });

    test('a rejected targeted result with no fallback is noMarker with its '
        'score', () async {
      final index = await buildTitleMatchIndexOffUi(_snapshot());
      final outcome = await matchRecognitionOffUi(
        index,
        targeted: const InspectionRejected(
          kind: InspectionFrameKind.targeted,
          scale: 1,
          reason: InspectionRejection.scaleOutOfRange,
          bestMarkerScore: 0.3,
        ),
        mode: GameMode.pvp,
      );
      final rejected = outcome as OutcomeRejected<InspectionEvidence>;
      expect(rejected.reason, OutcomeRejectReason.noMarker);
      expect(rejected.targetedBestMarkerScore, 0.3);
    });

    test(
      'an isolate error is matcherFailed carrying both marker scores',
      () async {
        final index = TitleMatchIndex.build(_snapshot());
        final outcome = await matchRecognitionOffUi(
          index,
          targeted: _recognised(InspectionFrameKind.targeted, [
            _evidence('x'),
          ], best: 0.61),
          fullClient: const InspectionRejected(
            kind: InspectionFrameKind.fullClient,
            scale: 1,
            reason: InspectionRejection.markerPeaksOverflow,
            bestMarkerScore: 0.72,
          ),
          mode: GameMode.pvp,
          runner: _throwingRunner,
        );
        final rejected = outcome as OutcomeRejected<InspectionEvidence>;
        expect(rejected.reason, OutcomeRejectReason.matcherFailed);
        expect(rejected.targetedBestMarkerScore, 0.61);
        expect(rejected.fallbackBestMarkerScore, 0.72);
      },
    );

    test('an index build error propagates from the injected runner', () {
      expect(
        buildTitleMatchIndexOffUi(_snapshot(), runner: _throwingRunner),
        throwsStateError,
      );
    });
  });
}
