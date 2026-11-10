import 'package:blackgrid/domain/inspection_context.dart' show FirState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';

/// Every string the answer strip shows, joined for substring checks.
String _stripText(WidgetTester tester) {
  final texts = find.descendant(
    of: find.byKey(const Key('answer-strip')),
    matching: find.byType(Text),
  );
  return [
    for (final element in texts.evaluate())
      (element.widget as Text).data ??
          (element.widget as Text).textSpan?.toPlainText() ??
          '',
  ].join('\n');
}

void main() {
  testWidgets('unknown found in raid is said in words', (tester) async {
    final h = await pumpM1(tester);
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();

    final text = _stripText(tester);
    // The strip names the question in words and marks the answer Unknown.
    expect(text, contains('Found in raid'));
    final choice = tester.widget<SegmentedButton<FirState>>(
      find.descendant(
        of: find.byKey(const Key('answer-strip')),
        matching: find.byType(SegmentedButton<FirState>),
      ),
    );
    expect(choice.selected, {FirState.unknown});
    expect(
      find.descendant(
        of: find.byKey(const Key('answer-strip')),
        matching: find.text('Unknown'),
      ),
      findsOneWidget,
    );
    for (final banned in [
      'FIR: unknown',
      'gross RUB',
      'Requirement remainder',
      'Values are gross, not profit',
      'Shared item decision',
      'not an accepted scan',
      'Current manual inspection',
      'Identity retained',
    ]) {
      expect(text, isNot(contains(banned)), reason: banned);
    }
    expect(find.textContaining('FIR: unknown'), findsNothing);
  });
}
