import 'package:blackgrid/domain/raid_timers.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/raid_timer_support.dart';

const _strip = Key('raid-timer-strip');
const _scavTooltip =
    'Base 25:00 × Fence 1.00 × hideout 1.00\n'
    'No Tracker progress for this mode: no hideout bonuses';

Finder _inStrip(Finder matching) =>
    find.descendant(of: find.byKey(_strip), matching: matching);

void main() {
  testWidgets('strip shows all three entries on Map and Scanner', (
    tester,
  ) async {
    final h = await pumpTimerApp(tester);
    await useLogLines(tester, h, runningRaidLines);
    await pumpUntil(
      tester,
      () => h.services.raidTimers.view.entries.any(
        (e) => e.text == 'In raid 12:34',
      ),
    );
    for (final nav in const ['nav-map', 'nav-scanner']) {
      await tester.tap(find.byKey(Key(nav)));
      await tester.pumpAndSettle();
      expect(_inStrip(find.text('In raid 12:34')), findsOneWidget);
      expect(_inStrip(find.text('Run-through done')), findsOneWidget);
      expect(_inStrip(find.text('Scav ready')), findsOneWidget);
      // Only the scav entry explains itself; hovering shows its inputs.
      expect(find.byTooltip(_scavTooltip), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('timers off hides the strip', (tester) async {
    final h = await pumpTimerApp(tester);
    await useLogLines(tester, h, runningRaidLines);
    await pumpUntil(tester, () => h.services.raidTimers.view.moving);
    expect(find.byKey(_strip), findsOneWidget);
    expect(_inStrip(find.byType(Text)), findsWidgets);

    await tester.runAsync(
      () =>
          h.services.settings.setRaidTimers(RaidTimerSettings(enabled: false)),
    );
    await tester.pumpAndSettle();

    for (final nav in const ['nav-map', 'nav-scanner']) {
      await tester.tap(find.byKey(Key(nav)));
      await tester.pumpAndSettle();
      expect(_inStrip(find.byType(Text)), findsNothing);
      expect(find.byTooltip(_scavTooltip), findsNothing);
      expect(find.textContaining('In raid'), findsNothing);
      expect(find.textContaining('Run-through'), findsNothing);
    }
    final view = h.services.raidTimers.view;
    expect(view.entries, isEmpty);
    // No periodic update: a view that does not move keeps no timer.
    expect(view.moving, isFalse);
  });

  testWidgets('only the chosen entry shows', (tester) async {
    final h = await pumpTimerApp(tester);
    await tester.runAsync(
      () => h.services.settings.setRaidTimers(
        RaidTimerSettings(showTimeInRaid: false, showRunThrough: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(h.services.raidTimers.view.entries.single.kind, RaidTimerKind.scav);
    expect(_inStrip(find.text('Scav ready')), findsOneWidget);
    expect(_inStrip(find.byType(Text)), findsOneWidget);
    expect(find.textContaining('In raid'), findsNothing);
    expect(find.textContaining('Last raid'), findsNothing);
    expect(find.textContaining('Run-through'), findsNothing);
  });
}
