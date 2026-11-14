import 'package:blackgrid/application/progress_controller.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:blackgrid/ui/ember/theme_access.dart';
import 'package:blackgrid/ui/scanner_screen.dart';
import 'package:blackgrid/ui/settings/settings_page.dart';
import 'package:blackgrid/ui/settings/settings_section.dart';
import 'package:blackgrid/ui/map_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import '../support/map_widget_harness.dart';
import '../support/raid_timer_support.dart';
import 'support/scan_ui_support.dart';

/// The synthetic folder the commit tests save, which watchers can bind to
/// without touching the machine.
const _folder = 'C:/blackgrid-synthetic-missing/screenshots';

/// The Settings action in the wide top bar.
Finder get _settingsAction => find.widgetWithText(TextButton, 'Settings');

Finder get _page => find.byType(SettingsPage);

Finder _title(SettingsSection section) =>
    find.byKey(Key('settings-title-${section.name}'));

Finder _back(String area) => find.widgetWithText(TextButton, 'Back to $area');

Finder get _topBar => find.byKey(const Key('shell-top-bar'));

Finder get _statusBar => find.byKey(const Key('shell-status-bar'));

Finder get _answerStrip => find.byKey(const Key('answer-strip'));

Future<void> _open(WidgetTester tester) async {
  final services = tester
      .widget<BlackgridApp>(find.byType(BlackgridApp))
      .services;
  await tester.runAsync(() async {
    await tester.tap(_settingsAction);
    await tester.pumpAndSettle();
    await services.localProgress.settled;
  });
  await tester.pumpAndSettle();
  expect(_page, findsOneWidget, reason: 'the Settings action opens the page');
}

Future<void> _openFromStatus(WidgetTester tester, String key) async {
  final services = tester
      .widget<BlackgridApp>(find.byType(BlackgridApp))
      .services;
  await tester.runAsync(() async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await services.localProgress.settled;
  });
  await tester.pumpAndSettle();
  expect(_page, findsOneWidget, reason: 'the status item opens the page');
}

Future<void> _escape(WidgetTester tester) async {
  // A commit that saves a folder binds watchers, which need the real zone.
  await tester.runAsync(() => tester.sendKeyEvent(LogicalKeyboardKey.escape));
  await tester.pumpAndSettle();
}

bool _inView(WidgetTester tester, Finder target) {
  final rect = tester.getRect(target);
  final page = tester.getRect(_page);
  return rect.top >= page.top && rect.bottom <= page.bottom;
}

bool _holdsFocus(WidgetTester tester, Finder title) =>
    Focus.of(tester.element(title)).hasPrimaryFocus;

Future<void> _expandDiagnostics(WidgetTester tester) async {
  final toggle = find.byKey(const Key('settings-diagnostics-toggle'));
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  expect(find.text('Map inputs'), findsOneWidget);
}

void main() {
  testWidgets('settings-page: Open and go back', (tester) async {
    final h = await pumpMapFixture(tester);
    await tester.runAsync(() => h.services.settings.setMap('thelab'));
    await tester.pumpAndSettle();
    final workspace = tester.element(find.byType(MapWorkspace));
    final selected = h.services.maps.selectedMapId;
    expect(selected, 'thelab');

    await _open(tester);
    expect(_topBar, findsOneWidget);
    expect(_statusBar, findsOneWidget);
    expect(_answerStrip, findsNothing);
    expect(find.byType(MapWorkspace), findsNothing);

    await tester.tap(_back('Map'));
    await tester.pumpAndSettle();

    expect(_page, findsNothing);
    expect(_topBar, findsOneWidget);
    expect(_statusBar, findsOneWidget);
    expect(_answerStrip, findsOneWidget);
    expect(tester.element(find.byType(MapWorkspace)), same(workspace));
    expect(h.services.maps.selectedMapId, selected);
  });

  testWidgets('settings-page: Inspector hidden while open', (tester) async {
    await pumpM1(tester, size: const Size(1660, 870));
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('shell-inspector')), findsOneWidget);

    await _open(tester);
    expect(find.byKey(const Key('shell-inspector')), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('inspector-toggle')))
          .onPressed,
      isNull,
    );

    await _escape(tester);

    expect(_page, findsNothing);
    expect(find.byType(ScannerScreen), findsOneWidget);
    expect(find.byKey(const Key('shell-inspector')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('inspector-toggle')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('settings-page: Switch area from Settings', (tester) async {
    await pumpM1(tester);
    await _open(tester);
    expect(find.byType(ScannerScreen), findsNothing);

    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();

    expect(_page, findsNothing);
    expect(find.byType(ScannerScreen), findsOneWidget);
    expect(find.byType(MapWorkspace), findsNothing);
  });

  testWidgets('settings-page: Choose the area Settings was opened from', (
    tester,
  ) async {
    await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await _open(tester);
    expect(find.byType(ScannerScreen), findsNothing);
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .selected,
      isEmpty,
      reason: 'neither area is selected while Settings is open',
    );

    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();

    expect(_page, findsNothing);
    expect(find.byType(ScannerScreen), findsOneWidget);
    expect(find.byType(MapWorkspace), findsNothing);
  });

  testWidgets('settings-page: Item search from Settings', (tester) async {
    final h = await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await _open(tester);
    final item = h.services.catalog.snapshot!.items['item-a']!;

    final search = find.widgetWithText(TextField, 'Search items…');
    await tester.tap(search);
    await tester.enterText(search, 'item-a');
    await tester.pumpAndSettle();
    expect(_page, findsOneWidget, reason: 'typing alone does not close it');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(h.services.selection.selectedId, 'item-a');
    expect(_page, findsNothing);
    expect(find.byType(ScannerScreen), findsOneWidget);
    expect(
      find.descendant(of: _answerStrip, matching: find.text(item.name)),
      findsOneWidget,
    );
  });

  testWidgets('settings-page: Escape with an unsaved invalid edit', (
    tester,
  ) async {
    final h = await pumpM1(tester);
    final before = h.services.settings.raidTimers.runThroughSeconds;
    await _open(tester);
    final field = find.widgetWithText(TextField, 'Run-through length (m:ss)');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, '0:30');

    await _escape(tester);

    expect(_page, findsNothing);
    expect(h.services.settings.raidTimers.runThroughSeconds, before);
    expect(h.services.settings.error, isNull);
  });

  testWidgets('settings-page: Map keys while Settings is open', (tester) async {
    final h = await pumpMapFixture(tester);
    h.services.maps.setSelectedMarker('ground-exit');
    await tester.pumpAndSettle();
    final selected = h.services.maps.selectedMarkerProjection;
    expect(selected, isNotNull, reason: 'a marker is selected');
    final workspace = tester.element(find.byType(MapWorkspace));
    await _open(tester);

    for (final key in [
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.delete,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(_page, findsOneWidget, reason: '$key leaves Settings open');
      expect(find.byType(Dialog), findsNothing, reason: '$key');
      expect(find.byType(BottomSheet), findsNothing, reason: '$key');
    }
    await _escape(tester);

    expect(_page, findsNothing);
    expect(tester.element(find.byType(MapWorkspace)), same(workspace));
    expect(
      h.services.maps.selectedMarkerProjection?.marker.id,
      selected!.marker.id,
    );
  });

  testWidgets('settings-page: Escape with a valid edit', (tester) async {
    final h = await pumpM1(tester);
    await _open(tester);
    final field = find.widgetWithText(TextField, 'Screenshot folder');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, _folder);

    await _escape(tester);
    await pumpUntil(
      tester,
      () => h.services.settings.settings.screenshotDirectory == _folder,
    );

    expect(_page, findsNothing);
    final stored = (await tester.runAsync(h.services.database.readSettings))!;
    expect(stored.settings.screenshotDirectory, _folder);
  });

  testWidgets('settings-page: Scan while Settings is open', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await _open(tester);

    await tester.runAsync(
      () => publishTargetedScan(
        h.services.scanner,
        ports,
        text: 'Alternative component',
      ),
    );
    await tester.pumpAndSettle();

    final accepted = h.services.scans.latest;
    expect(accepted, isNotNull);
    expect(_page, findsOneWidget);
    await tester.tap(_back('Map'));
    await tester.pumpAndSettle();

    expect(_page, findsNothing);
    final item = h.services.catalog.snapshot!.items[accepted!.itemId]!;
    expect(
      find.descendant(of: _answerStrip, matching: find.text(item.name)),
      findsOneWidget,
    );
  });

  testWidgets('settings-page: Settings action while open', (tester) async {
    await pumpM1(tester);
    await _openFromStatus(tester, 'status-tracker');
    final tracker = _title(SettingsSection.tracker);
    final position = tester.getTopLeft(tracker);
    expect(_inView(tester, tracker), isTrue);

    await tester.tap(_settingsAction);
    await tester.pumpAndSettle();

    expect(_page, findsOneWidget);
    expect(tester.getTopLeft(tracker), position);
    expect(_holdsFocus(tester, tracker), isTrue);
  });

  testWidgets('settings-page: Status bar Tracker', (tester) async {
    await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();

    await _openFromStatus(tester, 'status-tracker');

    final tracker = _title(SettingsSection.tracker);
    expect(_inView(tester, tracker), isTrue);
    expect(_holdsFocus(tester, tracker), isTrue);
    await tester.tap(_back('Scanner'));
    await tester.pumpAndSettle();
    expect(_page, findsNothing);
    expect(find.byType(ScannerScreen), findsOneWidget);
  });

  testWidgets('settings-diagnostics: Tracker error stays reachable', (
    tester,
  ) async {
    final h = await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    const failure = 'Tracker refresh failed: synthetic fixture failure';
    h.services.progress.error = failure;
    h.services.progress.status = ProgressStatus.failed;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('status-tracker')), findsOneWidget);
    expect(find.textContaining(failure), findsNothing);

    await _openFromStatus(tester, 'status-tracker');

    final line = find.text('Tracker problem: $failure');
    expect(line, findsOneWidget);
    expect(_inView(tester, line), isTrue);
    expect(
      tester.widget<Text>(line).style?.color,
      tester.element(line).ember.errInk,
    );
  });

  testWidgets('settings-page: Already open', (tester) async {
    await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await _open(tester);
    await tester.tap(find.byKey(const Key('settings-nav-raidTimers')));
    await tester.pumpAndSettle();
    final itemData = _title(SettingsSection.itemData);
    expect(_inView(tester, itemData), isFalse);

    await tester.tap(find.byKey(const Key('status-item-data')));
    await tester.pumpAndSettle();

    expect(_page, findsOneWidget);
    expect(_inView(tester, itemData), isTrue);
    expect(_holdsFocus(tester, itemData), isTrue);
    expect(_back('Scanner'), findsOneWidget);
    await tester.tap(_back('Scanner'));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerScreen), findsOneWidget);
  });

  testWidgets('settings-page: Reopen', (tester) async {
    await pumpM1(tester);
    await _open(tester);
    await _expandDiagnostics(tester);

    await tester.tap(_back('Map'));
    await tester.pumpAndSettle();
    await _open(tester);

    expect(find.text('Map inputs'), findsNothing);
  });

  testWidgets('settings-page: Open at a section', (tester) async {
    await pumpM1(tester);

    await _openFromStatus(tester, 'status-tracker');

    expect(_inView(tester, _title(SettingsSection.tracker)), isTrue);
    expect(find.text('Map inputs'), findsNothing);
  });
}
