import 'package:blackgrid/application/task_log_progress_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/progress_wipe_store.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/settings/local_progress_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 11, 12);
const _modes = [GameMode.pvp, GameMode.pve, GameMode.seasonal];

class _ProgressSource extends ChangeNotifier implements TaskLogProgressSource {
  @override
  Map<GameMode, ProgressWipe> wipes = {};
  @override
  Set<GameMode> unavailableModes = {};
  @override
  bool running = false;
  @override
  String? disabledReason;
  @override
  TaskLogRunResult? lastResult;
  @override
  String? error;
  @override
  String? currentReadFolder;
  @override
  DateTime? oldestFolderDate;

  final replays = <(GameMode, DateTime)>[];
  final newWipes = <(GameMode, DateTime)>[];

  @override
  Future<void> replay(GameMode mode, DateTime date) async {
    replays.add((mode, date));
  }

  @override
  Future<void> startNewWipe(GameMode mode, DateTime date) async {
    newWipes.add((mode, date));
  }

  void changed() => notifyListeners();
}

ProgressWipe _wipe(GameMode mode, {String? lastFolder}) => ProgressWipe(
  mode: mode,
  cycleId: 'cycle-${mode.name}',
  startDate: DateTime(2026, 11, 1),
  lastFolder: lastFolder,
  updatedAtMs: 0,
);

Finder _key(String prefix, GameMode mode) =>
    find.byKey(Key('$prefix-${mode.name}'));

String _textWithin(Finder parent, WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: parent, matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .join(' ');

Future<void> _pump(WidgetTester tester, _ProgressSource source) async {
  tester.view.physicalSize = const Size(1800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(source.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LocalProgressSettings(controller: source, clock: () => _today),
        ),
      ),
    ),
  );
}

Future<void> _openDatePicker(
  WidgetTester tester,
  String prefix,
  GameMode mode,
) async {
  await tester.ensureVisible(_key(prefix, mode));
  await tester.tap(_key(prefix, mode));
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsOneWidget);
}

Future<void> _pickDay(WidgetTester tester, int day) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('$day'),
        )
        .first,
  );
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String prefix, GameMode mode) =>
    tester.widget<ButtonStyleButton>(_key(prefix, mode)).onPressed != null;

void main() {
  testWidgets(
    'wipe row shows start date, last folder and default replay date',
    (tester) async {
      const folder = 'log_2026.11.10_19-12-03_1.3.0.0.48484';
      final source = _ProgressSource()
        ..wipes = {GameMode.pve: _wipe(GameMode.pve, lastFolder: folder)}
        ..oldestFolderDate = DateTime(2026, 10, 1);
      await _pump(tester, source);

      for (final mode in _modes) {
        expect(_key('local-progress', mode), findsOneWidget);
      }
      expect(
        _textWithin(_key('local-progress', GameMode.pvp), tester),
        contains('PvP'),
      );
      expect(
        _textWithin(
          _key('local-progress', GameMode.seasonal),
          tester,
        ).toLowerCase(),
        contains('seasonal'),
      );
      final row = _textWithin(_key('local-progress', GameMode.pve), tester);
      expect(row, contains('PvE'));
      expect(row, contains('2026-11-01'));
      expect(row, contains(folder));
      expect(
        _textWithin(_key('replay-date', GameMode.pve), tester),
        contains('2026-11-01'),
      );
      await tester.tap(_key('replay', GameMode.pve));
      await tester.pump();
      expect(source.replays, [(GameMode.pve, DateTime(2026, 11, 1))]);

      await _openDatePicker(tester, 'replay-date', GameMode.pve);
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.initialDate, DateTime(2026, 11, 1));
      expect(picker.firstDate, DateTime(2026, 10, 1));
      expect(picker.lastDate, _today);
      await _pickDay(tester, 7);
      await tester.tap(_key('replay', GameMode.pve));
      await tester.pump();
      expect(source.replays, [
        (GameMode.pve, DateTime(2026, 11, 1)),
        (GameMode.pve, DateTime(2026, 11, 7)),
      ]);
    },
  );

  testWidgets('mode without wipe says No wipe yet', (tester) async {
    final source = _ProgressSource();
    await _pump(tester, source);
    final row = _key('local-progress', GameMode.seasonal);
    expect(_textWithin(row, tester), contains('No wipe yet'));
    expect(
      _textWithin(_key('replay-date', GameMode.seasonal), tester),
      isNot(contains('2026-11-12')),
    );
    expect(_enabled(tester, 'replay', GameMode.seasonal), isFalse);

    await _openDatePicker(tester, 'replay-date', GameMode.seasonal);
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, _today);
    expect(picker.firstDate, DateTime(2017));
    expect(picker.lastDate, _today);
    await _pickDay(tester, 8);
    await tester.tap(_key('replay', GameMode.seasonal));
    await tester.pump();
    expect(source.replays, [(GameMode.seasonal, DateTime(2026, 11, 8))]);
  });

  testWidgets('unavailable wipe is visible in its mode row', (tester) async {
    final source = _ProgressSource()
      ..wipes = {GameMode.pve: _wipe(GameMode.pve)}
      ..unavailableModes = {GameMode.pve};
    await _pump(tester, source);
    expect(
      _textWithin(_key('local-progress', GameMode.pve), tester).toLowerCase(),
      contains('unavailable'),
    );
  });

  testWidgets('last run result is shown with mode and time', (tester) async {
    final source = _ProgressSource()
      ..lastResult = TaskLogRunResult(
        kind: TaskLogRunKind.replay,
        modes: {GameMode.pve},
        finishedAt: DateTime(2026, 11, 12, 14, 35),
        foldersRead: 12,
        eventsRecorded: 9,
        skippedNoMode: 1,
        failure: 'Synthetic read failure',
      );
    await _pump(tester, source);
    final text = _textWithin(find.byType(LocalProgressSettings), tester);
    expect(text, contains('PvE'));
    expect(text, contains('2026-11-12'));
    expect(text, contains('14:35'));
    final counts = text.replaceAll('2026-11-12', '').replaceAll('14:35', '');
    expect(counts, matches(RegExp(r'\b12\b')));
    expect(counts, matches(RegExp(r'\b9\b')));
    expect(counts, matches(RegExp(r'\b1\b')));
    expect(text.toLowerCase(), contains('folder'));
    expect(text.toLowerCase(), contains('event'));
    expect(text.toLowerCase(), contains('skip'));
    expect(text, contains('Synthetic read failure'));

    source
      ..running = true
      ..currentReadFolder = 'log_current_folder'
      ..changed();
    await tester.pump();
    expect(find.textContaining('log_current_folder'), findsOneWidget);
  });

  testWidgets('failed replay shows retry date and closing note', (
    tester,
  ) async {
    final source = _ProgressSource()
      ..lastResult = TaskLogRunResult(
        kind: TaskLogRunKind.replay,
        modes: {GameMode.pve},
        finishedAt: _today,
        failure: 'Could not save',
        lastStoredFolder: 'log_2026.10.21_10-00-00_1.3.0.0.48484',
        retryFrom: DateTime(2026, 10, 20),
      );
    await _pump(tester, source);
    var text = _textWithin(find.byType(LocalProgressSettings), tester);
    expect(text, contains('Closing Blackgrid stops replay'));
    expect(text, contains('replay again from the same date'));
    expect(text, contains('Replay again from 2026-10-20'));

    source
      ..lastResult = TaskLogRunResult(
        kind: TaskLogRunKind.replay,
        modes: {GameMode.pve},
        finishedAt: _today,
        stoppedByRaid: true,
        retryFrom: DateTime(2026, 10, 20),
      )
      ..changed();
    await tester.pump();
    text = _textWithin(find.byType(LocalProgressSettings), tester);
    expect(text, contains('Stopped by a raid'));
    expect(text, contains('Replay again from 2026-10-20'));
  });

  testWidgets('actions disabled in raid with reason', (tester) async {
    final source = _ProgressSource()
      ..wipes = {for (final mode in _modes) mode: _wipe(mode)};
    await _pump(tester, source);

    // Give every new-wipe action a date so its disabled state cannot be
    // explained by a missing selection rather than the controller's reason.
    for (final mode in _modes) {
      await _openDatePicker(tester, 'new-wipe-date', mode);
      await _pickDay(tester, 12);
      expect(_enabled(tester, 'replay', mode), isTrue);
      expect(_enabled(tester, 'new-wipe', mode), isTrue);
    }
    for (final reason in [
      'Not available during a raid',
      'Another log read is running',
      'No game log folder found',
    ]) {
      source
        ..disabledReason = reason
        ..changed();
      await tester.pump();
      expect(find.textContaining(reason), findsWidgets);
      for (final mode in _modes) {
        expect(_enabled(tester, 'replay', mode), isFalse, reason: reason);
        expect(_enabled(tester, 'new-wipe', mode), isFalse, reason: reason);
      }
    }
    expect(source.replays, isEmpty);
    expect(source.newWipes, isEmpty);
  });

  testWidgets('new wipe asks confirmation naming mode and date', (
    tester,
  ) async {
    final source = _ProgressSource()
      ..wipes = {GameMode.pvp: _wipe(GameMode.pvp)};
    await _pump(tester, source);
    expect(_enabled(tester, 'new-wipe', GameMode.pvp), isFalse);
    await _openDatePicker(tester, 'new-wipe-date', GameMode.pvp);
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, _today);
    await _pickDay(tester, 12);
    await tester.tap(_key('new-wipe', GameMode.pvp));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final text = _textWithin(dialog, tester);
    expect(text, contains('PvP'));
    expect(text, contains('2026-11-12'));
    expect(source.newWipes, isEmpty);
    final buttons = find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    expect(buttons, findsNWidgets(2));
    await tester.tap(buttons.last);
    await tester.pumpAndSettle();
    expect(source.newWipes, [(GameMode.pvp, DateTime(2026, 11, 12))]);
    expect(source.replays, isEmpty);
  });

  testWidgets('cancelled confirmation changes nothing', (tester) async {
    final wipe = _wipe(GameMode.pvp);
    final source = _ProgressSource()..wipes = {GameMode.pvp: wipe};
    await _pump(tester, source);
    await _openDatePicker(tester, 'new-wipe-date', GameMode.pvp);
    await _pickDay(tester, 12);
    await tester.tap(_key('new-wipe', GameMode.pvp));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.newWipes, isEmpty);
    expect(source.replays, isEmpty);
    expect(source.wipes[GameMode.pvp], same(wipe));
  });
}
