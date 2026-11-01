import 'package:blackgrid/domain/catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';
import '../support/raid_timer_support.dart';

const _runThroughMessage =
    'The run-through length must be between 1:00 and 30:00.';
const _reputationMessage =
    'The Fence reputation must be between −7.00 and 6.00.';
const _chooseMode = 'Choose a game mode first.';

final _runThrough = find.widgetWithText(TextField, 'Run-through length (m:ss)');
final _reputation = find.widgetWithText(TextField, 'Fence reputation');

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  expect(find.text('Raid timers'), findsOneWidget);
}

/// Types [text] in [field] and commits it the way a user does: the keyboard's
/// done action. Leaving the field commits too (see the focus-loss test).
Future<void> _enterAndSubmit(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  testWidgets('valid run-through length is saved', (tester) async {
    final h = await pumpTimerApp(tester);
    await _openSettings(tester);
    // The field starts at the default 7:10.
    expect(tester.widget<TextField>(_runThrough).controller!.text, '7:10');

    await _enterAndSubmit(tester, _runThrough, '8:00');
    await pumpUntil(
      tester,
      () => h.services.settings.settings.raidTimers.runThroughSeconds == 480,
    );
    expect(find.text(_runThroughMessage), findsNothing);

    // Moving to another field commits what was typed, with no Save button.
    await tester.ensureVisible(_runThrough);
    await tester.enterText(_runThrough, '9:00');
    await tester.ensureVisible(_reputation);
    await tester.tap(_reputation);
    await tester.pump();
    await pumpUntil(
      tester,
      () => h.services.settings.settings.raidTimers.runThroughSeconds == 540,
    );
    final stored = await tester.runAsync(h.services.database.readSettings);
    expect(stored!.settings.raidTimers.runThroughSeconds, 540);
  });

  testWidgets('invalid run-through lengths are refused', (tester) async {
    final h = await pumpTimerApp(tester);
    await _openSettings(tester);
    final before = h.services.settings.settings.raidTimers.runThroughSeconds;
    for (final bad in const ['0:30', '31:00', 'abc']) {
      await _enterAndSubmit(tester, _runThrough, bad);
      expect(find.text(_runThroughMessage), findsOneWidget, reason: bad);
      expect(
        h.services.settings.settings.raidTimers.runThroughSeconds,
        before,
        reason: bad,
      );
    }
    // Editing again clears the message.
    await tester.enterText(_runThrough, '8');
    await tester.pumpAndSettle();
    expect(find.text(_runThroughMessage), findsNothing);
    expect(h.services.settings.settings.raidTimers.runThroughSeconds, before);
  });

  testWidgets('out-of-range reputation is refused', (tester) async {
    final h = await pumpTimerApp(tester);
    await _openSettings(tester);
    await _enterAndSubmit(tester, _reputation, '7.5');
    expect(find.text(_reputationMessage), findsOneWidget);
    expect(h.services.settings.settings.raidTimers.fenceReputation, isEmpty);
    await _enterAndSubmit(tester, _reputation, '-7.01');
    expect(find.text(_reputationMessage), findsOneWidget);
    expect(h.services.settings.settings.raidTimers.fenceReputation, isEmpty);
    await _enterAndSubmit(tester, _reputation, 'abc');
    expect(find.text(_reputationMessage), findsOneWidget);
    expect(h.services.settings.settings.raidTimers.fenceReputation, isEmpty);
  });

  testWidgets('reputation edits the active mode\'s value', (tester) async {
    // Nothing is saved as the mode; the logs say the session is PvP.
    final h = await pumpTimerApp(tester, mode: GameMode.unknown);
    await useLogLines(tester, h, const [
      ('22:00:10.000', 'Session mode: Regular'),
    ]);
    await pumpUntil(tester, () => h.services.catalog.mode == GameMode.pvp);
    expect(h.services.settings.settings.mode, GameMode.unknown);

    await _openSettings(tester);
    await _enterAndSubmit(tester, _reputation, '2.50');
    await pumpUntil(
      tester,
      () =>
          h.services.settings.settings.raidTimers.fenceReputation[GameMode
              .pvp] ==
          2.5,
    );
    expect(h.services.settings.settings.raidTimers.fenceReputation, {
      GameMode.pvp: 2.5,
    });
    expect(tester.widget<TextField>(_reputation).controller!.text, '2.50');
  });

  testWidgets('reputation field disabled without a mode', (tester) async {
    await _noModeDialog(tester);
    expect(tester.widget<TextField>(_reputation).enabled, isFalse);
    expect(find.text(_chooseMode), findsOneWidget);
  });

  testWidgets('timer switches are saved', (tester) async {
    final h = await pumpTimerApp(tester);
    await _openSettings(tester);
    for (final (label, read) in <(String, bool Function())>[
      ('Time in raid', () => h.services.settings.raidTimers.showTimeInRaid),
      ('Run-through', () => h.services.settings.raidTimers.showRunThrough),
      ('Scav cooldown', () => h.services.settings.raidTimers.showScavCooldown),
    ]) {
      final box = find.widgetWithText(CheckboxListTile, label);
      await tester.ensureVisible(box);
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(box));
      await pumpUntil(tester, () => !read());
    }
    final toggle = find.widgetWithText(SwitchListTile, 'Show raid timers');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(toggle));
    await pumpUntil(tester, () => !h.services.settings.raidTimers.enabled);
    final stored = await tester.runAsync(h.services.database.readSettings);
    expect(stored!.settings.raidTimers.enabled, isFalse);
    expect(stored.settings.raidTimers.showScavCooldown, isFalse);
  });
}

Future<M1Harness> _noModeDialog(WidgetTester tester) async {
  final h = await pumpTimerApp(tester, mode: GameMode.unknown);
  expect(h.services.catalog.mode, GameMode.unknown);
  await _openSettings(tester);
  await tester.ensureVisible(_reputation);
  await tester.pumpAndSettle();
  return h;
}
