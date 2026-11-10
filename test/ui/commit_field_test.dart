import 'dart:async';

import 'package:blackgrid/ui/settings/commit_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps one [CommitField] inside a [SettingsFlushScope] and returns the
/// scope's controller, recording each committed text in [commits].
Future<SettingsFlushController> _pump(
  WidgetTester tester, {
  required List<String> commits,
  String value = 'saved',
  String? Function(String text)? refuse,
}) async {
  final flush = SettingsFlushController();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SettingsFlushScope(
          controller: flush,
          child: CommitField(
            label: 'Folder',
            value: value,
            onCommit: (text) async {
              commits.add(text);
              return refuse?.call(text);
            },
          ),
        ),
      ),
    ),
  );
  return flush;
}

void main() {
  testWidgets('a flush commits pending valid text', (tester) async {
    final commits = <String>[];
    final flush = await _pump(tester, commits: commits);
    await tester.enterText(find.byType(TextField), 'typed');

    final done = flush.flush();
    expect(commits, ['typed'], reason: 'the commit starts synchronously');
    await done;
    await tester.pump();
    expect(find.text('typed'), findsOneWidget);
  });

  testWidgets('a flush of refused text keeps the saved value', (tester) async {
    final commits = <String>[];
    final flush = await _pump(
      tester,
      commits: commits,
      refuse: (_) => 'Not a folder.',
    );
    await tester.enterText(find.byType(TextField), 'bad');

    await flush.flush();
    await tester.pump();
    expect(commits, ['bad']);
    expect(find.text('Not a folder.'), findsOneWidget);
    expect(find.text('bad'), findsOneWidget);
    expect(tester.widget<CommitField>(find.byType(CommitField)).value, 'saved');
  });

  testWidgets('a flush with no edit commits nothing', (tester) async {
    final commits = <String>[];
    final flush = await _pump(tester, commits: commits);

    await flush.flush();
    await tester.pump();
    expect(commits, isEmpty);
  });

  testWidgets('a flush after the scope unmounts reaches no field', (
    tester,
  ) async {
    final commits = <String>[];
    final flush = await _pump(tester, commits: commits);
    await tester.enterText(find.byType(TextField), 'typed');
    await tester.pumpWidget(const SizedBox());

    await flush.flush();
    expect(commits, isEmpty);
  });

  testWidgets('a flush commits no second time while the same text is saving', (
    tester,
  ) async {
    final commits = <String>[];
    final saving = Completer<String?>();
    final flush = SettingsFlushController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsFlushScope(
            controller: flush,
            child: Column(
              children: [
                CommitField(
                  label: 'Folder',
                  value: 'saved',
                  onCommit: (text) {
                    commits.add(text);
                    return saving.future;
                  },
                ),
                const TextField(key: Key('other')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Folder'), 'typed');
    // Leaving the field commits it, as pressing Back does just before it closes.
    await tester.tap(find.byKey(const Key('other')));
    await tester.pump();
    expect(commits, ['typed']);

    final done = flush.flush();
    expect(commits, ['typed'], reason: 'the same text is already saving');

    saving.complete(null);
    await done;
    await tester.pump();
  });
}
