import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:blackgrid/ui/answer_strip.dart';
import 'package:blackgrid/ui/scanner_sections.dart';
import 'package:blackgrid/ui/labels.dart' show localTimeLabel;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';

/// A movable clock, so the price age can pass without waiting.
class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
}

/// The local time the fixture's price is quoted at.
final _quote = DateTime(2026, 10, 6, 11, 8);

/// The services the running test opened, closed by [_tagTest].
final _open = <M1Harness>[];

/// A widget test that closes its services before the pending-timer check.
///
/// The check runs before tear-downs, and the selection's 30 s timer is
/// cancelled only when the services are disposed.
void _tagTest(String name, Future<void> Function(WidgetTester) body) {
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

/// Pumps the answer strip and the Prices section on a fake clock for an item priced at [quote].
///
/// The services are built under the test's fake async, so the selection's 30 s
/// age timer is the one `tester.pump` advances. Only the database and the
/// catalog work run in the real zone.
Future<M1Harness> _pumpSurfaces(
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
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              AnswerStrip(services: h.services),
              PricesSection(selection: h.services.selection),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

/// Where a freshness tag can be shown: the answer strip's price block and the
/// Prices section's Updated row.
final _scopes = [
  find.byKey(const Key('answer-price')),
  find.byKey(const Key('prices-updated')),
];

Finder _tagIn(Finder scope) => find.descendant(
  of: scope,
  matching: find.byKey(const Key('freshness-tag')),
);

/// The tag's words, its text colour and its fill, read from the widget tree.
({String text, Color? ink, Color? fill}) _look(
  WidgetTester tester,
  Finder tag,
) {
  final text = tester.widget<Text>(
    find.descendant(of: tag, matching: find.byType(Text)),
  );
  final box = tester.widget<Container>(tag).decoration as BoxDecoration?;
  return (text: text.data!, ink: text.style?.color, fill: box?.color);
}

void main() {
  final ember = EmberColors.dark;

  /// Runs [check] on the tag of the strip and then on the tag of Prices.
  void eachTag(
    WidgetTester tester,
    void Function(({String text, Color? ink, Color? fill}) look) check,
  ) {
    for (final scope in _scopes) {
      final tag = _tagIn(scope);
      expect(tag, findsOneWidget, reason: '$scope');
      check(_look(tester, tag));
    }
  }

  _tagTest('fresh tag reads Prices and time', (tester) async {
    final clock = _Clock(DateTime(2026, 10, 6, 11, 40));
    await _pumpSurfaces(tester, clock, quote: _quote);

    eachTag(tester, (look) {
      expect(look.text, 'Prices 11:08');
      expect(look.text, 'Prices ${localTimeLabel(_quote, now: clock.now)}');
      expect(look.ink, ember.inkTertiary);
      expect(look.fill, isNull);
    });
  });

  _tagTest('stale tag uses warning style', (tester) async {
    final clock = _Clock(DateTime(2026, 10, 6, 14, 18));
    final h = await _pumpSurfaces(tester, clock, quote: _quote);

    eachTag(tester, (look) {
      expect(look.text, 'price 3 h old');
      expect(look.ink, ember.warnInk);
      expect(look.fill, ember.warnBg);
    });
    // A tag: the 6px tag radius and the Label type role (DESIGN.md X3).
    for (final scope in _scopes) {
      final tag = _tagIn(scope);
      final box = tester.widget<Container>(tag).decoration! as BoxDecoration;
      expect(box.borderRadius, BorderRadius.circular(EmberRadius.s));
      final style = tester
          .widget<Text>(find.descendant(of: tag, matching: find.byType(Text)))
          .style!;
      expect(style.fontFamily, EmberType.label.fontFamily);
      expect(style.fontSize, EmberType.label.fontSize);
      expect(style.fontWeight, EmberType.label.fontWeight);
    }

    clock.now = DateTime(2026, 10, 8, 11, 8);
    h.services.selection.setFir(h.services.selection.fir);
    await tester.pump();
    eachTag(tester, (look) {
      expect(look.text, 'price 2 d old');
      expect(look.ink, ember.warnInk);
      expect(look.fill, ember.warnBg);
    });
  });

  _tagTest('missing price time reads price time unknown', (tester) async {
    final clock = _Clock(DateTime(2026, 10, 6, 11, 40));
    await _pumpSurfaces(tester, clock, quote: null);

    // The strip and the Prices Updated row both say it.
    eachTag(tester, (look) {
      expect(look.text, 'price time unknown');
      expect(look.ink, ember.warnInk);
      expect(look.fill, ember.warnBg);
    });
  });

  _tagTest('future price time reads price time unknown', (tester) async {
    final clock = _Clock(DateTime(2026, 10, 6, 11, 0));
    await _pumpSurfaces(tester, clock, quote: _quote);

    eachTag(tester, (look) {
      expect(look.text, 'price time unknown');
      expect(look.ink, ember.warnInk);
      expect(look.fill, ember.warnBg);
    });
  });

  _tagTest('tag turns stale on the age notify with a fake clock', (
    tester,
  ) async {
    final clock = _Clock(DateTime(2026, 10, 6, 11, 40));
    await _pumpSurfaces(tester, clock, quote: _quote);
    eachTag(tester, (look) => expect(look.text, 'Prices 11:08'));

    // Past 12:08, nothing else changes: only the 30 s timer fires.
    clock.now = DateTime(2026, 10, 6, 12, 9);
    await tester.pump(const Duration(seconds: 30));

    eachTag(tester, (look) {
      expect(look.text, 'price 1 h old');
      expect(look.ink, ember.warnInk);
      expect(look.fill, ember.warnBg);
    });
  });

  _tagTest('no tag on the price row', (tester) async {
    final clock = _Clock(DateTime(2026, 10, 6, 11, 40));
    await _pumpSurfaces(tester, clock, quote: null, noFlea: true);

    // An item that cannot be sold on the Flea says so in the strip and in the
    // Prices section, and carries no freshness tag in either.
    expect(find.text("Can't be sold on the Flea"), findsNWidgets(2));
    expect(find.byKey(const Key('freshness-tag')), findsNothing);
    expect(find.textContaining('price time'), findsNothing);
    expect(find.textContaining(RegExp(r'^Prices \d')), findsNothing);
    expect(find.textContaining(' old'), findsNothing);
    // The Check plate is warning-filled; the price rows are not.
    for (final scope in [..._scopes, find.byKey(const Key('prices-flea'))]) {
      expect(scope, findsOneWidget);
      final filled = find.descendant(
        of: scope,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == ember.warnBg,
        ),
      );
      expect(filled, findsNothing, reason: '$scope');
    }
  });
}
