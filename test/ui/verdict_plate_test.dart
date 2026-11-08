import 'dart:convert';

import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/ui/ember/blackgrid_tokens.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:blackgrid/ui/item_decision_card.dart';
import 'package:blackgrid/ui/labels.dart' show recommendationLabel;
import 'package:blackgrid/ui/verdict_plate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/m1_harness.dart';
import '../support/map_widget_harness.dart';

const _rooms = [Brightness.dark, Brightness.light];

EmberColors _ember(Brightness room) =>
    room == Brightness.dark ? EmberColors.dark : EmberColors.light;

BlackgridColors _blackgrid(Brightness room) =>
    room == Brightness.dark ? BlackgridColors.dark : BlackgridColors.light;

ItemDecision _decision(Recommendation recommendation) => ItemDecision(
  recommendation: recommendation,
  reasons: const [],
  warnings: const [],
  // Both prices are set, so a plate that must not show one is caught.
  fleaGross: 38277,
  traderGross: 7695,
  traderName: 'Therapist',
);

Future<void> _pumpPlate(
  WidgetTester tester,
  Brightness room,
  ItemDecision decision,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(room),
      home: Scaffold(
        body: Center(child: VerdictPlate(decision: decision)),
      ),
    ),
  );
  // A changed theme animates; settle so the new room's roles are in place.
  await tester.pumpAndSettle();
}

/// What a plate looks like, read from the widget tree.
({
  Color? fill,
  Color? border,
  Color? dashed,
  Color? text,
  Color? price,
  double height,
})
_look(WidgetTester tester) {
  final plate = find.byKey(const Key('verdict-plate'));
  final box = tester.widget<Container>(plate).decoration as BoxDecoration?;
  final border = box?.border;
  final painters = tester
      .widgetList<CustomPaint>(
        find.descendant(of: plate, matching: find.byType(CustomPaint)),
      )
      .map((p) => p.painter)
      .whereType<DashedBorderPainter>();
  final word = tester.widget<Text>(find.byKey(const Key('recommendation')));
  final price = find.byKey(const Key('verdict-price'));
  return (
    fill: box?.color,
    border: border is Border ? border.top.color : null,
    dashed: painters.isEmpty ? null : painters.single.color,
    text: word.style?.color,
    price: price.evaluate().isEmpty
        ? null
        : tester.widget<Text>(price).style?.color,
    height: tester.getSize(plate).height,
  );
}

Set<Color> _used(
  ({
    Color? fill,
    Color? border,
    Color? dashed,
    Color? text,
    Color? price,
    double height,
  })
  look,
) => {?look.fill, ?look.border, ?look.dashed, ?look.text, ?look.price};

void main() {
  testWidgets('each verdict has its plate style in both rooms', (tester) async {
    for (final room in _rooms) {
      final e = _ember(room);
      final b = _blackgrid(room);
      Future<
        ({
          Color? fill,
          Color? border,
          Color? dashed,
          Color? text,
          Color? price,
          double height,
        })
      >
      look(Recommendation r) async {
        await _pumpPlate(tester, room, _decision(r));
        return _look(tester);
      }

      final keep = await look(Recommendation.keep);
      expect(keep.fill, b.okFill, reason: '$room keep fill');
      expect(keep.text, b.okOnFill, reason: '$room keep text');
      expect(keep.height, 44);

      final later = await look(Recommendation.keepForLater);
      expect(later.fill, b.okBg, reason: '$room later fill');
      expect(later.border, b.okLine, reason: '$room later border');
      expect(later.text, b.okStrong, reason: '$room later text');
      expect(later.height, 44);

      final check = await look(Recommendation.check);
      expect(check.fill, e.warnBg, reason: '$room check fill');
      expect(check.border, e.warnLine, reason: '$room check border');
      expect(check.text, e.warnStrong, reason: '$room check text');
      expect(check.height, 44);

      for (final r in [Recommendation.flea, Recommendation.trader]) {
        final sell = await look(r);
        expect(sell.fill, e.raised, reason: '$room $r fill');
        expect(sell.text, e.inkSecondary, reason: '$room $r text');
        expect(sell.dashed, isNull, reason: '$room $r is not dashed');
        expect(sell.height, 44);
      }

      final none = await look(Recommendation.priceUnavailable);
      expect(none.fill, isNull, reason: '$room unavailable has no fill');
      expect(none.border, isNull, reason: '$room unavailable border is dashed');
      expect(none.dashed, e.inkTertiary, reason: '$room unavailable dashes');
      expect(none.text, e.inkTertiary, reason: '$room unavailable text');
      expect(none.height, 44);
    }
  });

  testWidgets('Keep, Flea and Price unavailable differ by fill and border', (
    tester,
  ) async {
    for (final room in _rooms) {
      await _pumpPlate(tester, room, _decision(Recommendation.keep));
      final keep = _look(tester);
      await _pumpPlate(tester, room, _decision(Recommendation.flea));
      final flea = _look(tester);
      await _pumpPlate(
        tester,
        room,
        _decision(Recommendation.priceUnavailable),
      );
      final none = _look(tester);

      expect(keep.fill, isNotNull);
      expect(keep.fill!.a, 1, reason: '$room Keep is a solid fill');
      expect(flea.fill, _ember(room).raised);
      expect(flea.fill, isNot(keep.fill));
      expect(none.fill, isNull, reason: '$room unavailable has no fill');
      expect(none.dashed, isNotNull, reason: '$room unavailable is dashed');
      expect(keep.dashed, isNull);
      expect(flea.dashed, isNull);
    }
  });

  testWidgets('no plate uses accent or accent-text', (tester) async {
    for (final room in _rooms) {
      final e = _ember(room);
      for (final r in Recommendation.values) {
        await _pumpPlate(tester, room, _decision(r));
        final used = _used(_look(tester));
        expect(used, isNotEmpty);
        expect(used, isNot(contains(e.accent)), reason: '$room $r accent');
        expect(
          used,
          isNot(contains(e.accentText)),
          reason: '$room $r accent text',
        );
      }
    }
  });

  testWidgets('Flea plate shows its gross price in ink', (tester) async {
    for (final room in _rooms) {
      await _pumpPlate(tester, room, _decision(Recommendation.flea));
      expect(find.text('Flea'), findsOneWidget);
      expect(find.text('₽38277'), findsOneWidget);
      final look = _look(tester);
      expect(look.price, _ember(room).ink, reason: '$room price ink');
      expect(look.text, _ember(room).inkSecondary);

      await _pumpPlate(tester, room, _decision(Recommendation.trader));
      expect(find.text('Trader'), findsOneWidget);
      expect(find.text('₽7695'), findsOneWidget);
      expect(_look(tester).price, _ember(room).ink);
    }
  });

  testWidgets('plates without a price show only the word', (tester) async {
    for (final room in _rooms) {
      for (final r in [
        Recommendation.keep,
        Recommendation.keepForLater,
        Recommendation.check,
        Recommendation.priceUnavailable,
      ]) {
        await _pumpPlate(tester, room, _decision(r));
        final texts = find.descendant(
          of: find.byKey(const Key('verdict-plate')),
          matching: find.byType(Text),
        );
        expect(texts, findsOneWidget, reason: '$room $r');
        expect(find.byKey(const Key('verdict-price')), findsNothing);
        expect(find.textContaining('₽'), findsNothing);
        expect(
          tester.widget<Text>(texts).data,
          recommendationLabel(r),
          reason: '$room $r',
        );
      }
    }
  });

  testWidgets('long reason wraps in the compact inspector card at 960 px', (
    tester,
  ) async {
    const token = 'PVP_synthetic-fixture-only';
    final source = 'Long task name ' * 5; // 75 characters
    final longName = '${source}end'.padRight(80, 'x'); // 80 characters
    expect(longName.length, 80);
    final wire = wireFixture();
    wire['tasks_en'] = {
      'data': {'task-a name': longName},
    };
    wire['token'] = {
      'success': true,
      'permissions': ['GP'],
      'token': token,
      'owner': 'synthetic-owner',
      'note': 'Synthetic',
      'calls': 0,
      'gameMode': 'pvp',
    };
    wire['progress'] = progressWire();
    final credentials = MemoryCredentials()..values[GameMode.pvp] = token;
    final h = await pumpMapFixture(
      tester,
      size: const Size(960, 900),
      credentials: credentials,
      client: MockClient((request) async {
        final value = wire[request.url.pathSegments.last];
        return http.Response(
          jsonEncode(value ?? {}),
          value == null ? 404 : 200,
        );
      }),
    );
    await tester.runAsync(() async {
      await h.services.progress.refresh();
      await h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      );
    });
    h.services.selection.setFir(FirState.yes);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 352,
              height: 600,
              child: ItemDecisionCard(services: h.services, compact: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byType(ItemDecisionCard);
    expect(card, findsOneWidget);
    expect(tester.widget<ItemDecisionCard>(card).compact, isTrue);
    final reason = find.byKey(const Key('verdict-reason'));
    await tester.ensureVisible(reason);
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(reason);
    expect(text.data, contains(longName));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(text.softWrap, isNot(false));
    final paragraph = tester.renderObject<RenderParagraph>(reason);
    expect(paragraph.didExceedMaxLines, isFalse);
    final lines = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.data!.length),
        )
        .map((box) => box.top.round())
        .toSet();
    expect(lines.length, greaterThanOrEqualTo(2), reason: 'wraps');
    expect(tester.takeException(), isNull);
  });
}
