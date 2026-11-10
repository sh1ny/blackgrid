import 'package:blackgrid/ui/app_logo.dart';
import 'package:blackgrid/ui/brand_lockup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget lockup) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: lockup),
    ),
  ),
);

void main() {
  testWidgets(
    'top bar variant sets a 32x32 logo beside the wordmark and tagline',
    (tester) async {
      await _pump(tester, const BrandLockup.topBar());

      final logo = find.byType(AppLogo);
      expect(tester.widget<AppLogo>(logo).size, 32);
      expect(tester.getSize(logo), const Size(32, 32));
      final word = find.text('BLACKGRID');
      final tagline = find.text('TRACK. PLAN. SURVIVE.');
      expect(word, findsOneWidget);
      expect(tagline, findsOneWidget);
      expect(
        tester.getRect(logo).right,
        lessThan(tester.getRect(word).left),
        reason: 'the logo sits beside the text',
      );
      expect(
        tester.getRect(word).bottom,
        lessThanOrEqualTo(tester.getRect(tagline).top + 1),
        reason: 'the tagline sits under the wordmark',
      );
    },
  );

  testWidgets('the compact top bar variant keeps only the logo', (
    tester,
  ) async {
    await _pump(tester, const BrandLockup.topBar(compact: true));

    expect(tester.getSize(find.byType(AppLogo)), const Size(32, 32));
    expect(find.text('BLACKGRID'), findsNothing);
    expect(find.text('TRACK. PLAN. SURVIVE.'), findsNothing);
  });

  testWidgets('startup variant stacks a 54x54 logo, wordmark and tagline', (
    tester,
  ) async {
    await _pump(tester, const BrandLockup.startup());

    final logo = find.byType(AppLogo);
    expect(tester.getSize(logo), const Size(54, 54));
    final word = find.text('BLACKGRID');
    final tagline = find.text('TRACK. PLAN. SURVIVE.');
    expect(tester.getRect(logo).bottom, lessThan(tester.getRect(word).top));
    expect(tester.getRect(word).bottom, lessThan(tester.getRect(tagline).top));
  });

  testWidgets('the lockup adds only its two texts to the semantics tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const BrandLockup.startup());

    expect(
      find.descendant(
        of: find.byType(AppLogo),
        matching: find.byType(Semantics),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel('BLACKGRID'), findsOneWidget);
    handle.dispose();
  });
}
