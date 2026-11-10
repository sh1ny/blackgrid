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

  testWidgets('a flush saves two pending fields one after the other', (
    tester,
  ) async {
    final commits = <String>[];
    final first = Completer<String?>();
    final flush = SettingsFlushController();
    await tester.pumpWidget(
      _twoFields(
        flush,
        onFirst: (text) {
          commits.add(text);
          return first.future;
        },
        onSecond: (text) async {
          commits.add(text);
          return null;
        },
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'First'), 'one');
    await tester.enterText(find.widgetWithText(TextField, 'Second'), 'two');

    final done = flush.flush();
    // The page closes in the frame that starts the flush.
    await tester.pumpWidget(const SizedBox());
    expect(commits, ['one'], reason: 'the second save waits for the first');

    first.complete(null);
    await done;
    expect(commits, ['one', 'two']);
  });

  testWidgets('a flush waits for the save another field has in flight', (
    tester,
  ) async {
    final commits = <String>[];
    final first = Completer<String?>();
    final flush = SettingsFlushController();
    await tester.pumpWidget(
      _twoFields(
        flush,
        onFirst: (text) {
          commits.add(text);
          return first.future;
        },
        onSecond: (text) async {
          commits.add(text);
          return null;
        },
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'First'), 'one');
    // Moving to the second field commits the first.
    await tester.tap(find.widgetWithText(TextField, 'Second'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Second'), 'two');
    expect(commits, ['one']);

    final done = flush.flush();
    await tester.pumpWidget(const SizedBox());
    expect(commits, ['one'], reason: 'the first save is still running');

    first.complete(null);
    await done;
    expect(commits, ['one', 'two']);
  });

  testWidgets('text typed during a save survives the saved value arriving', (
    tester,
  ) async {
    final saving = Completer<String?>();
    Widget field(String value) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            CommitField(
              label: 'Folder',
              value: value,
              onCommit: (_) => saving.future,
            ),
            const TextField(key: Key('other')),
          ],
        ),
      ),
    );
    await tester.pumpWidget(field('saved'));
    final folder = find.widgetWithText(TextField, 'Folder');
    await tester.enterText(folder, 'one');
    await tester.tap(find.byKey(const Key('other')));
    await tester.pump();
    await tester.enterText(folder, 'one more');

    await tester.pumpWidget(field('one'));
    expect(find.text('one more'), findsOneWidget);

    saving.complete(null);
    await tester.pump();
  });

  testWidgets('an accepted edit shows in its saved form', (tester) async {
    Widget field(String value) => MaterialApp(
      home: Scaffold(
        body: CommitField(
          label: 'Reputation',
          value: value,
          onCommit: (_) async => null,
        ),
      ),
    );
    await tester.pumpWidget(field('0.00'));
    await tester.enterText(find.byType(TextField), '1.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    await tester.pumpWidget(field('1.50'));
    expect(find.text('1.50'), findsOneWidget);
  });
}

/// Two [CommitField]s, labelled First and Second, under one flush scope.
Widget _twoFields(
  SettingsFlushController flush, {
  required Future<String?> Function(String text) onFirst,
  required Future<String?> Function(String text) onSecond,
}) => MaterialApp(
  home: Scaffold(
    body: SettingsFlushScope(
      controller: flush,
      child: Column(
        children: [
          CommitField(label: 'First', value: 'saved', onCommit: onFirst),
          CommitField(label: 'Second', value: 'saved', onCommit: onSecond),
        ],
      ),
    ),
  ),
);
