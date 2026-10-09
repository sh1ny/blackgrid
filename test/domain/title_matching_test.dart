import 'dart:typed_data';

import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rounds [x] to the nearest single-precision value, as the matcher does.
double f32(double x) => (Float32List(1)..[0] = x)[0];

/// The largest single-precision value below [x].
double f32Below(double x) {
  final cell = Float32List(1)..[0] = x;
  final bits = Uint32List.view(cell.buffer);
  bits[0] -= 1;
  return cell[0];
}

/// One catalog entry. [normalized] defaults to the kebab-cased [name]; use
/// it to give the primary matcher a different string than the raw name.
CatalogItem item(String id, String name, {String? normalized}) => CatalogItem(
  id: id,
  name: name,
  normalizedName:
      normalized ?? name.toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
);

CatalogSnapshot snapshot(
  List<CatalogItem> items, {
  GameMode mode = GameMode.pvp,
  String revision = 'r1',
}) => CatalogSnapshot(
  mode: mode,
  revision: revision,
  observedAt: DateTime.utc(2026, 1, 1),
  items: {for (final i in items) i.id: i},
  traders: const {},
  requirements: const [],
);

TitleMatch match(
  List<CatalogItem> items,
  String text, {
  GameMode mode = GameMode.pvp,
}) => matchTitle(TitleMatchIndex.build(snapshot(items)), text, mode);

/// [text] with its first [n] characters replaced by `b`, so that its
/// Levenshtein distance from [text] is exactly [n] (for text of `a`s).
String edited(String text, int n) => 'b' * n + text.substring(n);

TitleRejected rejected(TitleMatch m) => switch (m) {
  TitleRejected() => m,
  TitleAccepted() => fail('expected a rejection, got $m'),
};

TitleAccepted accepted(TitleMatch m) => switch (m) {
  TitleAccepted() => m,
  TitleRejected(:final reason) => fail('expected acceptance, got $reason'),
};

/// Plain dynamic-programming Levenshtein distance over runes.
int referenceDistance(List<int> a, List<int> b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final best = [
        sub,
        prev[j] + 1,
        cur[j - 1] + 1,
      ].reduce((x, y) => x < y ? x : y);
      cur[j] = best;
    }
    prev = cur;
  }
  return prev.last;
}

double _ratio(List<int> a, List<int> b) {
  final longer = a.length > b.length ? a.length : b.length;
  return longer == 0 ? 1.0 : 1 - referenceDistance(a, b) / longer;
}

/// Spec formula: the better of plain and space-free similarity.
double referenceSimilarity(String a, String b) {
  final ra = a.runes.toList(), rb = b.runes.toList();
  final plain = _ratio(ra, rb);
  final compact = _ratio(
    ra.where((c) => c != 0x20).toList(),
    rb.where((c) => c != 0x20).toList(),
  );
  return plain > compact ? plain : compact;
}

void main() {
  group('normalisation', () {
    test('normalise folds punctuation and spacing', () {
      expect(normaliseTitle('SR-2M 9x21 (20 pcs)'), 'sr 2m 9x21 20 pcs');
    });

    test('normalise applies NFKC to full-width text', () {
      expect(normaliseTitle('ＡＫ－７４'), 'ak 74');
    });

    test('normalise of separators only is empty', () {
      expect(normaliseTitle('  - . ( ) !  '), '');
    });
  });

  group('index', () {
    test('index results report snapshot mode and revision', () {
      final index = TitleMatchIndex.build(
        snapshot(
          [item('a1', 'Gas analyzer')],
          mode: GameMode.pve,
          revision: 'r42',
        ),
      );
      for (final text in ['Gas analyzer', 'ak', 'Subject Search', 'qqqqqqqq']) {
        final m = matchTitle(index, text, GameMode.pve);
        expect(m.mode, GameMode.pve, reason: text);
        expect(m.revision, 'r42', reason: text);
      }
    });

    test('kebab-case normalizedName becomes spaced candidate', () {
      final m = match([
        item('k1', 'Salewa FAK', normalized: 'salewa-first-aid-kit'),
      ], 'Salewa first aid kit');
      final a = accepted(m);
      expect(a.bestId, 'k1');
      expect(a.bestScore, 1.0);
    });

    test('empty catalog rejects emptyCatalog', () {
      expect(
        rejected(match(const [], 'Gas analyzer')).reason,
        TitleRejectReason.emptyCatalog,
      );
    });

    test('a different mode rejects catalogModeMismatch', () {
      final m = match(
        [item('a1', 'Gas analyzer')],
        'Gas analyzer',
        mode: GameMode.pve,
      );
      expect(rejected(m).reason, TitleRejectReason.catalogModeMismatch);
      expect(m.bestId, isNull);
    });
  });

  group('similarity', () {
    test('compact similarity ignores spaces', () {
      expect(titleSimilarity('comtac ii', 'comtacii'), 1.0);
    });

    test('one substitution in six scores 5/6', () {
      expect(titleSimilarity('salewa', 'salewo'), f32(1 - 1 / 6));
    });

    test('two empty strings are fully similar', () {
      expect(titleSimilarity('', ''), 1.0);
    });
  });

  group('pre-match rejection', () {
    test('normalised length 3 is matched', () {
      final m = match([item('m1', 'M4A')], 'm4a');
      expect(accepted(m).bestId, 'm1');
    });

    test('normalised length 2 rejects titleTooShort', () {
      final m = match([item('a1', 'AK')], 'AK');
      expect(rejected(m).reason, TitleRejectReason.titleTooShort);
    });

    test('localised chrome labels reject uiChrome', () {
      const labels = [
        'Subject Search',
        'поиск предмета',
        'rechercher un objet',
        'buscar objeto',
        'procurar item',
        'cerca oggetto',
        'szukaj przedmiotu',
        '搜索物品',
        '아이템 검색',
        'アイテム検索',
      ];
      final index = TitleMatchIndex.build(
        snapshot([item('s1', 'Search kit'), item('s2', 'subject search')]),
      );
      for (final label in labels) {
        expect(
          rejected(matchTitle(index, label, GameMode.pvp)).reason,
          TitleRejectReason.uiChrome,
          reason: label,
        );
      }
    });
  });

  group('best and runner-up', () {
    test(
      'duplicate normalised names keep the smaller id and skip runner-up',
      () {
        final m = accepted(
          match([
            item('b2', 'Gas analyzer'),
            item('a1', 'Gas analyzer'),
          ], 'Gas analyzer'),
        );
        expect(m.bestId, 'a1');
        expect(m.bestScore, 1.0);
        expect(m.runnerUpId, isNull);
      },
    );

    test('distinct names at equal score give margin 0', () {
      final m = rejected(
        match([
          item('x1', 'one', normalized: 'bbaaaaaaaa'),
          item('x2', 'two', normalized: 'aaaaaaaabb'),
        ], 'aaaaaaaaaa'),
      );
      expect(m.bestScore, f32(0.8));
      expect(m.runnerUpScore, f32(0.8));
      expect(m.margin, 0.0);
      expect(m.reason, TitleRejectReason.ambiguous);
    });
  });

  group('single precision', () {
    test('float32 margin of 0.95 vs 0.90 is accepted at the gate', () {
      final title = 'a' * 20;
      final m = accepted(
        match([
          // Primary best (.95); the confirming matcher prefers m2.
          item('m1', 'q' * 20, normalized: edited(title, 1)),
          item('m2', title, normalized: edited(title, 2)),
        ], title),
      );
      final margin = f32(f32(0.95) - f32(0.90));
      expect(margin, closeTo(0.0500000119, 1e-9));
      expect(m.bestId, 'm1');
      expect(m.runnerUpId, 'm2');
      expect(m.margin, margin);
      expect(m.margin >= recognitionGates.margin, isTrue);
      expect(m.confirmedBy?.id, 'm2');
    });

    test('float32 margin one ulp below .05 goes to the near-tie rule', () {
      final below = f32Below(recognitionGates.margin);
      expect(below < recognitionGates.margin, isTrue);
      expect(
        gateRejection(
          bestScore: 0.95,
          margin: below,
          confirmationConfidence: null,
          quantityAgrees: false,
        ),
        TitleRejectReason.ambiguous,
      );
      expect(
        gateRejection(
          bestScore: 0.95,
          margin: below,
          confirmationConfidence: 0.7,
          quantityAgrees: false,
        ),
        isNull,
      );
    });

    test('gates are stored as single-precision values', () {
      expect(recognitionGates.markerScore, f32(0.82));
      expect(recognitionGates.similarity, f32(0.55));
      expect(recognitionGates.margin, f32(0.05));
      expect(recognitionGates.closeMargin, f32(0.03));
      expect(recognitionGates.chromeSimilarity, f32(0.85));
      expect(recognitionGates.minTitleLength, 3);
      expect(recognitionGates.minQuantity, 10);
      expect(recognitionGates.quantityCap, 100000);
    });
  });

  group('acceptance gates', () {
    test('similarity .90 over .60 is accepted with margin .30', () {
      final title = 'a' * 10;
      final m = accepted(
        match([
          item('c1', 'zzz', normalized: edited(title, 1)),
          item('c2', 'yyy', normalized: edited(title, 4)),
        ], title),
      );
      expect(m.bestId, 'c1');
      expect(m.bestScore, f32(0.9));
      expect(m.runnerUpScore, f32(0.6));
      expect(m.margin, singleMargin(0.9, 0.6));
      expect(m.margin, closeTo(0.3, 1e-6));
    });

    test('similarity .5499 rejects belowSimilarity', () {
      expect(
        gateRejection(
          bestScore: 0.5499,
          margin: singleMargin(0.5499, 0),
          confirmationConfidence: 1.0,
          quantityAgrees: true,
        ),
        TitleRejectReason.belowSimilarity,
      );
      // End to end around the gate: 11/20 is accepted, 10/20 is not.
      final title = 'a' * 20;
      expect(
        accepted(
          match([item('g1', 'zzz', normalized: edited(title, 9))], title),
        ).bestScore,
        f32(0.55),
      );
      final low = rejected(
        match([item('g1', 'zzz', normalized: edited(title, 10))], title),
      );
      expect(low.reason, TitleRejectReason.belowSimilarity);
      expect(low.bestScore, f32(0.5));
    });

    test('margin .0499 without confirmation rejects ambiguous', () {
      expect(
        gateRejection(
          bestScore: 0.80,
          margin: singleMargin(0.80, 0.7501),
          confirmationConfidence: null,
          quantityAgrees: false,
        ),
        TitleRejectReason.ambiguous,
      );
      expect(singleMargin(0.80, 0.7501), closeTo(0.0499, 1e-6));
      // End to end: .80 over .76 with the confirming matcher on the runner-up.
      final title = 'a' * 25;
      final m = rejected(
        match([
          item('t1', 'q' * 25, normalized: edited(title, 5)),
          item('t2', title, normalized: edited(title, 6)),
        ], title),
      );
      expect(m.reason, TitleRejectReason.ambiguous);
      expect(m.margin, singleMargin(0.8, 0.76));
    });

    test('margin .04 with confirmation is accepted', () {
      expect(
        gateRejection(
          bestScore: 0.80,
          margin: singleMargin(0.80, 0.76),
          confirmationConfidence: 0.70,
          quantityAgrees: false,
        ),
        isNull,
      );
      final title = 'a' * 25;
      final m = accepted(
        match([
          item('t1', edited(title, 5), normalized: edited(title, 5)),
          item('t2', edited(title, 6), normalized: edited(title, 6)),
        ], title),
      );
      expect(m.bestId, 't1');
      expect(m.confirmedBy?.id, 't1');
      expect(m.confirmedBy?.confidence, f32(0.8));
    });

    test('margin .01 with confirmation and quantity 20 is accepted', () {
      final title = '${'a' * 97} 20';
      final names = [
        '${edited('a' * 97, 20)} 20',
        '${edited('a' * 97, 21)} 20',
      ];
      expect(
        gateRejection(
          bestScore: 0.80,
          margin: singleMargin(0.80, 0.79),
          confirmationConfidence: 0.80,
          quantityAgrees: true,
        ),
        isNull,
      );
      final m = accepted(
        match([item('q1', names[0]), item('q2', names[1])], title),
      );
      expect(m.bestId, 'q1');
      expect(m.margin, singleMargin(0.8, 0.79));
      expect(m.margin < recognitionGates.closeMargin, isTrue);
    });

    test('margin .01 without quantity rejects ambiguous', () {
      final title = 'a' * 100;
      final m = rejected(
        match([
          item('q1', edited(title, 20)),
          item('q2', edited(title, 21)),
        ], title),
      );
      expect(m.reason, TitleRejectReason.ambiguous);
      expect(m.confirmedBy?.id, 'q1');
      expect(
        gateRejection(
          bestScore: 0.80,
          margin: singleMargin(0.80, 0.79),
          confirmationConfidence: 0.80,
          quantityAgrees: false,
        ),
        TitleRejectReason.ambiguous,
      );
    });
  });

  group('confirming matcher', () {
    test('confirming matcher picks the exact raw name', () {
      final index = TitleMatchIndex.build(
        snapshot([
          item('g1', 'Grizzly medical kit'),
          item('s1', 'Salewa first aid kit'),
        ]),
      );
      final c = confirmTitle(index, ' Salewa first aid kit ');
      expect(c?.id, 's1');
      expect(c?.confidence, 1.0);
    });

    test('confirming matcher reports none within .85 of chrome', () {
      final index = TitleMatchIndex.build(
        snapshot([item('c1', 'Subject Serch')]),
      );
      expect(confirmTitle(index, 'Subject Serch'), isNull);
      expect(confirmTitle(index, 'Subject Search'), isNull);
    });

    test('an upper-case Cyrillic near-chrome title reports none', () {
      // One edit from "поиск предмета"; its capitals О, С, К, Р and Е have
      // Latin look-alikes, which must not hide it from the chrome check.
      final index = TitleMatchIndex.build(
        snapshot([item('r1', 'ПОИСК ПРЕДМЕТX')]),
      );
      expect(confirmTitle(index, 'ПОИСК ПРЕДМЕТX'), isNull);
    });

    test('confirming matcher maps Cyrillic capitals to Latin', () {
      // U+0410 and U+041A look like Latin A and K.
      final index = TitleMatchIndex.build(snapshot([item('k1', 'AK-74N')]));
      final c = confirmTitle(index, 'АК-74N');
      expect(c?.id, 'k1');
      expect(c?.confidence, 1.0);
      final mapped = TitleMatchIndex.build(snapshot([item('k2', 'АК-74N')]));
      expect(confirmTitle(mapped, 'ak-74n')?.confidence, 1.0);
    });
  });

  group('quantity', () {
    test('i2@ reads as quantity 120', () {
      expect(parseTitleQuantity('5.56x45 (i2@ pcs)'), 120);
    });

    test('quantity token edge cases', () {
      expect(parseTitleQuantity('no digits'), isNull);
      expect(parseTitleQuantity('ammo (l5 pcs)'), 15);
      expect(parseTitleQuantity('ammo 12 x 30'), 30);
      expect(parseTitleQuantity('ammo 99999999'), 999999);
      expect(parseTitleQuantity('ammo 1234567890'), 123456);
    });

    test('quantity 200 restricts to the 200 pcs variant', () {
      final m = accepted(
        match([
          // Scores 1.0 against the title but names a 20 pcs variant.
          item('p20', 'Ammo pack (20 pcs)', normalized: 'ammo-pack-200-pcs'),
          item('p200', 'Ammo pack (200 pcs)', normalized: 'ammo-pack-200-pc'),
        ], 'Ammo pack (200 pcs)'),
      );
      expect(m.bestId, 'p200');
      expect(m.runnerUpId, isNull);
    });

    test('quantity without a matching candidate applies no restriction', () {
      final m = match([
        item('p20', 'Ammo pack (20 pcs)'),
        item('p200', 'Ammo pack (200 pcs)'),
      ], 'Ammo pack (2000 pcs)');
      expect(m.bestId, 'p200');
      expect(m.runnerUpId, 'p20');
    });
  });

  group('bit-parallel distance', () {
    test('matches the reference distance on pseudo-random strings', () {
      var seed = 12345;
      int next(int n) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed % n;
      }

      String word(int maxLen) => String.fromCharCodes([
        for (var i = 0, n = next(maxLen + 1); i < n; i++)
          [97, 98, 99, 32, 0x439, 0x4e2d][next(6)],
      ]);
      for (var i = 0; i < 400; i++) {
        final a = word(i.isEven ? 30 : 90);
        final b = word(i.isEven ? 30 : 90);
        expect(
          titleSimilarity(a, b),
          f32(referenceSimilarity(a, b)),
          reason: '"$a" vs "$b"',
        );
      }
    });
  });
  group('outcome ranking', () {
    final index = TitleMatchIndex.build(
      snapshot([
        item('a1', 'Gas analyzer'),
        item('k1', 'Salewa first aid kit'),
        item('h1', 'Comtac headset'),
      ]),
    );

    RankableEvidence<String> entry(
      String evidence,
      String text, {
      double marker = 0.9,
      int order = 0,
      bool emptyRegion = false,
    }) => RankableEvidence<String>(
      evidence: evidence,
      markerScore: marker,
      text: text,
      emptyTitleRegion: emptyRegion,
      peakOrder: order,
    );

    RecognitionResultInput<String> result(
      List<RankableEvidence<String>> entries, {
      double? best,
    }) =>
        RecognitionResultInput<String>(entries: entries, bestMarkerScore: best);

    RecognitionOutcome<String> rank(
      RecognitionResultInput<String> targeted, {
      RecognitionResultInput<String>? fallback,
      TitleMatchIndex? using,
      GameMode mode = GameMode.pvp,
    }) => rankOutcome<String>(
      using ?? index,
      targeted: targeted,
      fallback: fallback,
      mode: mode,
    );

    OutcomeAccepted<String> won(RecognitionOutcome<String> o) => switch (o) {
      OutcomeAccepted<String>() => o,
      OutcomeRejected<String>(:final reason) => fail('rejected: $reason'),
    };

    OutcomeRejected<String> lost(RecognitionOutcome<String> o) => switch (o) {
      OutcomeRejected<String>() => o,
      OutcomeAccepted<String>() => fail('expected a rejection'),
    };

    test('accepted targeted evidence wins without consulting fallback', () {
      // The fallback holds an exact match that would outrank the targeted
      // near match if it were ranked.
      final o = won(
        rank(
          result([entry('targeted', 'Gas analyzr', marker: 0.85)]),
          fallback: result([
            entry('fallback', 'Salewa first aid kit', marker: 0.99),
          ]),
        ),
      );
      expect(o.evidence, 'targeted');
      expect(o.match.bestId, 'a1');
    });

    test('ranking prefers accepted over higher marker score', () {
      final o = won(
        rank(
          result(const [], best: null),
          fallback: result([
            entry('unaccepted', 'qqqqqqqq', marker: 0.95, order: 0),
            entry('accepted', 'Gas analyzer', marker: 0.85, order: 1),
          ]),
        ),
      );
      expect(o.evidence, 'accepted');
    });

    test(
      'nothing accepted is a rejection with top evidence and no accepted id',
      () {
        final o = lost(
          rank(
            result([entry('t', 'Gas an', marker: 0.9)]),
            fallback: result([entry('f', 'qqqqqqqq', marker: 0.95)]),
          ),
        );
        // Both unaccepted: the higher similarity ('Gas an') ranks first.
        expect(o.evidence, 't');
        expect(o.reason, OutcomeRejectReason.belowSimilarity);
        expect(o.match, isA<TitleRejected>());
        expect(o.match!.bestScore, greaterThan(0));
      },
    );

    test('no evidence anywhere rejects noMarker with both best scores', () {
      final o = lost(
        rank(
          result(const [], best: 0.4),
          fallback: result(const [], best: 0.6),
        ),
      );
      expect(o.reason, OutcomeRejectReason.noMarker);
      expect(o.evidence, isNull);
      expect(o.match, isNull);
      expect(o.targetedBestMarkerScore, 0.4);
      expect(o.fallbackBestMarkerScore, 0.6);
    });

    test('no evidence without a fallback leaves its best score null', () {
      final o = lost(rank(result(const [], best: 0.4)));
      expect(o.reason, OutcomeRejectReason.noMarker);
      expect(o.targetedBestMarkerScore, 0.4);
      expect(o.fallbackBestMarkerScore, isNull);
    });

    test('index from another mode rejects catalogModeMismatch', () {
      final o = lost(
        rank(
          result([entry('t', 'Gas analyzer')], best: 0.9),
          fallback: result([entry('f', 'Gas analyzer')], best: 0.8),
          mode: GameMode.pve,
        ),
      );
      expect(o.reason, OutcomeRejectReason.catalogModeMismatch);
      expect(o.targetedBestMarkerScore, 0.9);
      expect(o.fallbackBestMarkerScore, 0.8);
    });

    test('an empty title region is matched as an empty title', () {
      final o = lost(
        rank(result([entry('t', 'Gas analyzer', emptyRegion: true)])),
      );
      expect(o.reason, OutcomeRejectReason.titleTooShort);
      expect(o.evidence, 't');
    });

    test('rejection copies best scores from both results', () {
      final o = lost(
        rank(
          result([entry('t', 'qqqqqqqq')], best: 0.91),
          fallback: result(const [], best: 0.7),
        ),
      );
      expect(o.targetedBestMarkerScore, 0.91);
      expect(o.fallbackBestMarkerScore, 0.7);
    });

    test('higher similarity ranks before marker score', () {
      final o = won(
        rank(
          result(const []),
          fallback: result([
            entry('near', 'Gas analyzr', marker: 0.99, order: 0),
            entry('exact', 'Salewa first aid kit', marker: 0.83, order: 1),
          ]),
        ),
      );
      expect(o.evidence, 'exact');
    });

    test('similarity tie is broken by marker score', () {
      final o = won(
        rank(
          result(const []),
          fallback: result([
            entry('low', 'Gas analyzer', marker: 0.85, order: 0),
            entry('high', 'Gas analyzer', marker: 0.95, order: 1),
          ]),
        ),
      );
      expect(o.evidence, 'high');
    });

    test('marker tie is broken by lower peak order', () {
      final o = won(
        rank(
          result(const []),
          fallback: result([
            entry('second', 'Gas analyzer', order: 1),
            entry('first', 'Gas analyzer', order: 0),
          ]),
        ),
      );
      expect(o.evidence, 'first');
    });

    test('a full tie keeps the targeted entry first', () {
      final o = lost(
        rank(
          result([entry('targeted', 'qqqqqqqq')]),
          fallback: result([entry('fallback', 'qqqqqqqq')]),
        ),
      );
      expect(o.evidence, 'targeted');
    });

    test('outcome rejection reasons cover every title rejection reason', () {
      for (final reason in TitleRejectReason.values) {
        expect(OutcomeRejectReason.fromTitle(reason).name, reason.name);
      }
    });
  });
}
