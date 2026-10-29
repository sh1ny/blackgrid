import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owns the expanded flag the way a screen does, and counts builder calls.
class _Host extends StatefulWidget {
  const _Host({required this.onBuild, required this.onChanged});

  final VoidCallback onBuild;
  final ValueChanged<bool> onChanged;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: DetailsSection(
        expanded: _expanded,
        onExpandedChanged: (value) {
          widget.onChanged(value);
          setState(() => _expanded = value);
        },
        builder: (context) {
          widget.onBuild();
          return const Text('Inner content');
        },
      ),
    ),
  );
}

void main() {
  testWidgets('collapsed shows only the title and never builds the content', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(_Host(onBuild: () => builds++, onChanged: (_) {}));

    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Inner content'), findsNothing);
    expect(builds, 0);
  });

  testWidgets('tapping the Details title builds the content', (tester) async {
    var builds = 0;
    final changes = <bool>[];
    await tester.pumpWidget(
      _Host(onBuild: () => builds++, onChanged: changes.add),
    );

    await tester.tap(find.text('Details'));
    await tester.pump();

    expect(changes, [true]);
    expect(builds, greaterThan(0));
    expect(find.text('Inner content'), findsOneWidget);
  });
}
