import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _toggleKey = Key('panel-toggle');

Widget _host({
  required bool expanded,
  required ValueChanged<bool> onChanged,
  Widget? child,
  int Function()? onBuild,
}) => MaterialApp(
  theme: blackgridTheme(),
  home: Scaffold(
    body: CollapsibleGridPanel(
      title: 'Inputs',
      icon: Icons.tune,
      expanded: expanded,
      onExpandedChanged: onChanged,
      toggleKey: _toggleKey,
      child: Builder(
        builder: (_) {
          onBuild?.call();
          return child ?? const Text('content');
        },
      ),
    ),
  ),
);

void main() {
  testWidgets('child is not built while collapsed', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      _host(expanded: false, onChanged: (_) {}, onBuild: () => ++builds),
    );
    expect(find.text('content'), findsNothing);
    expect(builds, 0);
  });

  testWidgets('child is built when expanded', (tester) async {
    await tester.pumpWidget(_host(expanded: true, onChanged: (_) {}));
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('tapping the header reports the negated flag', (tester) async {
    final calls = <bool>[];
    await tester.pumpWidget(_host(expanded: true, onChanged: calls.add));
    await tester.tap(find.byKey(_toggleKey));
    expect(calls, [false]);

    calls.clear();
    await tester.pumpWidget(_host(expanded: false, onChanged: calls.add));
    await tester.tap(find.byKey(_toggleKey));
    expect(calls, [true]);
  });

  testWidgets('toggleKey is carried by the header InkWell', (tester) async {
    await tester.pumpWidget(_host(expanded: true, onChanged: (_) {}));
    expect(
      find.descendant(
        of: find.byType(CollapsibleGridPanel),
        matching: find.byWidgetPredicate(
          (w) => w is InkWell && w.key == _toggleKey,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('semantics report a button with expanded state and label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final expanded in [true, false]) {
      await tester.pumpWidget(_host(expanded: expanded, onChanged: (_) {}));
      expect(
        tester.getSemantics(find.byKey(_toggleKey)),
        isSemantics(
          label: 'Inputs',
          isButton: true,
          hasExpandedState: true,
          isExpanded: expanded,
          hasTapAction: true,
        ),
      );
    }
    handle.dispose();
  });

  testWidgets('title and icon render like GridPanel', (tester) async {
    await tester.pumpWidget(_host(expanded: true, onChanged: (_) {}));
    expect(find.text('Inputs'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.tune));
    expect(icon.color, GridColors.gold);
    expect(icon.size, 26);
    final title = tester.widget<Text>(find.text('Inputs'));
    expect(
      title.style,
      Theme.of(tester.element(find.text('Inputs'))).textTheme.titleMedium,
    );
  });
}
