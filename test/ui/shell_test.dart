import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import 'support/scan_ui_support.dart';

void main() {
  for (final size in [
    const Size(1672, 941),
    const Size(1912, 823),
    const Size(960, 640),
  ]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      testWidgets(
        'two retained surfaces avoid overflow at $size scale $scale',
        (tester) async {
          await pumpM1(tester, size: size, scale: scale);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('nav-scanner')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('No capture • no game interaction'), findsOneWidget);
          expect(find.text('Scanner Ready'), findsNothing);
          expect(find.text('Auto-scan'), findsNothing);
          expect(find.text('Capture Preview'), findsNothing);
          expect(find.text('High confidence'), findsNothing);
        },
      );
    }
  }
  testWidgets('reference panel positions and proportions at Scanner aspect', (
    tester,
  ) async {
    await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    Rect panel(String title) => tester.getRect(
      find.byWidgetPredicate((w) => w is GridPanel && w.title == title),
    );
    final left = panel('Scanner'),
        current = panel('Current manual inspection'),
        history = panel('Recent item activity');
    expect(left.left, 14);
    expect(current.left, greaterThan(left.right));
    expect(history.left, greaterThan(current.right));
    final width = left.width + current.width + history.width;
    expect(left.width / width, closeTo(.19, .01));
    expect(current.width / width, closeTo(.57, .01));
    expect(history.width / width, closeTo(.24, .01));
    final needs = panel('Requirements & uses'),
        source = panel('Source authority');
    expect(needs.top, greaterThan(current.bottom));
    expect(source.top, needs.top);
    expect(
      Theme.of(tester.element(find.byKey(const Key('nav-map'))))
          .scaffoldBackgroundColor,
      GridColors.background,
    );
  });
  testWidgets('scan evidence survives Map and back', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => publishTargetedScan(
        h.services.scanner,
        ports,
        text: 'Alternative component',
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.widget<Text>(find.byKey(const Key('scan-item'))).data;
    expect(before, contains('Alternative component'));

    await tester.tap(find.byKey(const Key('nav-map')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('scan-item'))).data,
      before,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('scan-end'))).data,
      'Accepted',
    );
  });
  for (final size in [const Size(1672, 941), const Size(960, 640)]) {
    testWidgets('scan evidence panel does not overflow at $size', (
      tester,
    ) async {
      final ports = ScanFakePorts();
      final h = await pumpM1(tester, size: size, scale: 1.5, scanPorts: ports);
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => publishTargetedScan(
          h.services.scanner,
          ports,
          text: 'Alternative component',
        ),
      );
      await tester.pumpAndSettle();
      if (size.width < 1100) {
        // Compact layout: the evidence panel is further down the list.
        // Dragging would start on the manual results list at the viewport
        // centre, so move the outer list directly past the first panel.
        final outer = find
            .descendant(
              of: find.byKey(const PageStorageKey('scanner-compact-scroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(outer).position.jumpTo(1200);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('scan-item')), findsOneWidget);
    });
  }
}
