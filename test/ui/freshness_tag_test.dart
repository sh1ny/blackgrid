import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:blackgrid/ui/item_decision_card.dart';
import 'package:blackgrid/ui/labels.dart' show localTimeLabel;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';

/// A movable clock, so the card's age can pass without waiting.
class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
}

/// The local time the fixture's price is quoted at.
final _quote = DateTime(2026, 10, 6, 11, 8);

/// The services the running test opened, closed by [_cardTest].
final _open = <M1Harness>[];

/// A widget test that closes its services before the pending-timer check.
///
/// The check runs before tear-downs, and the selection's 30 s timer is
/// cancelled only when the services are disposed.
void _cardTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      for (final h in _open) {
        await _finish(tester, h.dispose());
      }
      _open.clear();
    }
  });
}

/// Waits for [work], started under the fake async, to finish.
///
/// Its database calls finish in the real zone, so the loop alternates between
/// letting that zone run and flushing the fake zone's microtasks.
Future<void> _finish(WidgetTester tester, Future<void> work) async {
  var done = false;
  work.whenComplete(() => done = true).ignore();
  final elapsed = Stopwatch()..start();
  while (!done) {
    if (elapsed.elapsed > const Duration(seconds: 20)) {
      throw StateError('Fixture work did not finish within 20 seconds.');
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

/// Pumps the decision card on a fake clock for an item priced at [quote].
///
/// The services are built under the test's fake async, so the selection's 30 s
/// age timer is the one `tester.pump` advances. Only the database and the
/// catalog work run in the real zone.
Future<M1Harness> _pumpCard(
  WidgetTester tester,
  _Clock clock, {
  required DateTime? quote,
  bool noFlea = false,
}) async {
  final db = (await tester.runAsync(
    () async => BlackgridDatabase(NativeDatabase.memory()),
  ))!;
  final h = M1Harness(
    database: db,
    clock: clock.call,
    shapeWire: (wire) {
      final item = wire['items']['data']['items']['item-a'] as Map;
      item.remove('lastScan');
      if (quote == null) {
        item.remove('lastScanISO');
      } else {
        item['lastScanISO'] = quote.toUtc().toIso8601String();
      }
      if (noFlea) item['types'] = ['noFlea'];
    },
  );
  _open.add(h);
  await _finish(tester, h.initialize());
  await _finish(
    tester,
    h.services.selection.selectManual(
      h.services.catalog.snapshot!.items['item-a']!,
    ),
  );
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(Brightness.dark),
      home: Scaffold(body: ItemDecisionCard(services: h.services)),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

final _tag = find.byKey(const Key('freshness-tag'));

/// The tag's words, its text colour and its fill, read from the widget tree.
({String text, Color? ink, Color? fill}) _look(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.descendant(of: _tag, matching: find.byType(Text)),
  );
  final box = tester.widget<Container>(_tag).decoration as BoxDecoration?;
  return (text: text.data!, ink: text.style?.color, fill: box?.color);
}

void main() {
  final ember = EmberColors.dark;

  _cardTest('fresh tag reads Prices and time', (tester) async {
    final clock = _Clock(DateTime(2026, 10, 6, 11, 40));
    await _pumpCard(tester, clock, quote: _quote);

    final look = _look(tester);
    expect(look.text, 'Prices 11:08');
    expect(look.text, 'Prices ${localTimeLabel(_quote, now: clock.now)}');
    expect(look.ink, ember.inkTertiary);
    expect(look.fill, isNull);
  });

  _cardTest('stale tag uses warning style', (tester) async {
    final clock = _Clock(DateTime(2026, 10, 6, 14, 18));
    final h = await _pumpCard(tester, clock, quote: _quote);

    var look = _look(tester);
    expect(look.text, 'price 3 h old');
    expect(look.ink, ember.warnInk);
    expect(look.fill, ember.warnBg);

    clock.now = DateTime(2026, 10, 8, 11, 8);
    h.services.selection.setFir(h.services.selection.fir);
    await tester.pump();
    look = _look(tester);
    expect(look.text, 'price 2 d old');
    expect(look.ink, ember.warnInk);
    expect(look.fill, ember.warnBg);
  });

  _cardTest('missing price time reads price time unknown', (tester) async {
    final clock = _Clock(DateTime(2026, 10, 6, 11, 40));
    await _pumpCard(tester, clock, quote: null);

    final look = _look(tester);
    expect(look.text, 'price time unknown');
    expect(look.ink, ember.warnInk);
    expect(look.fill, ember.warnBg);
  });

  _cardTest('future price time reads price time unknown', (tester) async {
    final clock = _Clock(DateTime(2026, 10, 6, 11, 0));
    await _pumpCard(tester, clock, quote: _quote);

    final look = _look(tester);
    expect(look.text, 'price time unknown');
    expect(look.ink, ember.warnInk);
    expect(look.fill, ember.warnBg);
  });

  _cardTest('tag turns stale on the age notify with a fake clock', (
    tester,
  ) async {
    final clock = _Clock(DateTime(2026, 10, 6, 11, 40));
    await _pumpCard(tester, clock, quote: _quote);
    expect(_look(tester).text, 'Prices 11:08');

    // Past 12:08, nothing else changes: only the 30 s timer fires.
    clock.now = DateTime(2026, 10, 6, 12, 9);
    await tester.pump(const Duration(seconds: 30));

    final look = _look(tester);
    expect(look.text, 'price 1 h old');
    expect(look.ink, ember.warnInk);
    expect(look.fill, ember.warnBg);
  });

  _cardTest('no tag on the price row', (tester) async {
    final clock = _Clock(DateTime(2026, 10, 6, 11, 40));
    await _pumpCard(tester, clock, quote: null, noFlea: true);

    expect(find.text('Flea price'), findsOneWidget);
    expect(_tag, findsNothing);
    expect(find.textContaining('price time'), findsNothing);
    expect(find.textContaining(RegExp(r'^Prices \d')), findsNothing);
    expect(find.textContaining(' old'), findsNothing);
    final row = find.byKey(const Key('price-row'));
    expect(row, findsOneWidget);
    // The Check plate above the row is warning-filled; the row itself is not.
    final filled = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == ember.warnBg,
      ),
    );
    expect(filled, findsNothing);
  });
}
