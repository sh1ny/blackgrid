import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blackgrid/data/raid_panel_ocr.dart';
import 'package:blackgrid/domain/map_session.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/map_diagnostics.dart';
import 'package:blackgrid/ui/ember/ember_toggle_switch.dart';
import 'package:blackgrid/ui/settings/settings_page.dart';
import 'package:blackgrid/ui/settings/settings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/map_widget_harness.dart';

/// An OCR whose recognition never finishes until [gate] is completed.
final class _GatedOcr extends RaidPanelOcr {
  final gate = Completer<RaidPanelEvidence>();

  @override
  Future<RaidPanelEvidence> recognize(Uint8List imageBytes) => gate.future;
}

Finder get _toggle => find.byKey(const Key('settings-diagnostics-toggle'));
Finder get _status => find.byType(MapDiagnostics);
Finder get _follow => find.ancestor(
  of: find.text('Follow logs'),
  matching: find.byType(SettingsRow),
);

/// Whether the Follow logs switch is on.
bool _followOn(WidgetTester tester) => tester
    .widget<EmberToggleSwitch>(
      find.descendant(of: _follow, matching: find.byType(EmberToggleSwitch)),
    )
    .on;

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Settings'));
  await tester.pumpAndSettle();
}

/// Scrolls the Diagnostics title row into view, failing if it is not built.
///
/// Assertions about the section's absence must call this first so that they
/// cannot pass vacuously.
Future<void> _showTitle(WidgetTester tester) async {
  expect(_toggle, findsOneWidget);
  await tester.ensureVisible(_toggle);
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester) async {
  await _showTitle(tester);
  await tester.tap(_toggle);
  await tester.pumpAndSettle();
}

void _expectCollapsed() {
  expect(find.byKey(const Key('settings-title-diagnostics')), findsOneWidget);
  expect(find.textContaining('Logs:'), findsNothing);
  expect(find.textContaining('Screenshots:'), findsNothing);
  expect(_status, findsNothing);
}

void _expectExpanded() {
  expect(find.textContaining('Logs:'), findsOneWidget);
  expect(find.textContaining('Screenshots:'), findsOneWidget);
  expect(_status, findsOneWidget);
  // Read Latest lives in the map picker, never in Diagnostics.
  expect(find.text('Read Latest'), findsNothing);
}

/// Writes a tiny PNG modified an hour ago into a new temporary directory.
Future<File> _savedScreenshot(WidgetTester tester) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('blackgrid-map-diagnostics-'),
  ))!;
  addTearDown(() => directory.delete(recursive: true));
  final screenshot = File(
    '${directory.path}${Platform.pathSeparator}saved-panel.png',
  );
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.black, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(8, 8);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await screenshot.writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
    await screenshot.setLastModified(
      DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    );
    image.dispose();
    picture.dispose();
  });
  return screenshot;
}

Future<void> _useScreenshots(
  WidgetTester tester,
  MapWidgetHarness h,
  File screenshot,
) async {
  await tester.runAsync(
    () => h.services.settings.setMapInputs(
      screenshotDirectory: screenshot.parent.path,
      followGameLogs: false,
    ),
  );
  await settleMapFixture(tester, h);
}

/// Pumps until [done], letting real I/O progress between frames.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  final elapsed = Stopwatch()..start();
  while (!done()) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError('Map session did not reach the expected state.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Writes a session folder whose application log holds [messages], one line
/// each a second apart, and points the log input at it.
///
/// The backend log is empty; there is no push-notifications log.
Future<void> _useLogFolder(
  WidgetTester tester,
  MapWidgetHarness h,
  List<String> messages,
) async {
  final root = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('blackgrid-map-raid-'),
  ))!;
  addTearDown(() => root.delete(recursive: true));
  await tester.runAsync(() async {
    final folder = await Directory(
      '${root.path}${Platform.pathSeparator}log_2026.10.31_22-00-00_1.3.0.0.48484',
    ).create();
    final lines = StringBuffer();
    for (final (i, message) in messages.indexed) {
      final second = (i + 1).toString().padLeft(2, '0');
      lines.writeln(
        '2026-10-31 22:00:$second.000|1.3.0.0.48484|Info|application|$message',
      );
    }
    await File('${folder.path}${Platform.pathSeparator}application_000.log')
        .writeAsString(lines.toString(), flush: true);
    await File('${folder.path}${Platform.pathSeparator}backend_000.log')
        .writeAsString('', flush: true);
    await h.services.settings.setMapInputs(gameLogDirectory: root.path);
  });
}

/// Starts Read Latest without the UI and waits until [done].
Future<void> _readLatest(
  WidgetTester tester,
  MapWidgetHarness h,
  bool Function() done,
) async {
  await tester.runAsync(() async {
    unawaited(h.services.mapSession.readLatest());
  });
  await _until(tester, done);
}

/// Reads the latest screenshot and waits until its evidence is applied.
Future<void> _readSaved(WidgetTester tester, MapWidgetHarness h) => _readLatest(
  tester,
  h,
  () =>
      h.services.mapSession.state.savedScreenshotModifiedAt != null &&
      !h.services.mapSession.state.processingScreenshot &&
      !h.services.mapSession.state.readingLatest,
);

void main() {
  testWidgets('map-rail: Collapsed on first show', (tester) async {
    await pumpMapFixture(tester);
    await _openSettings(tester);
    await _showTitle(tester);
    _expectCollapsed();
  });

  testWidgets('map-rail: Diagnostics is the last section of Settings', (
    tester,
  ) async {
    await pumpMapFixture(tester);
    await _openSettings(tester);
    await _showTitle(tester);
    final title = tester.getRect(_toggle);
    for (final text in [
      'Save marker filters',
      'Follow logs',
      'Show raid timers',
      'Use Tracker progress',
    ]) {
      final other = find.descendant(
        of: find.byType(SettingsPage),
        matching: find.text(text),
      );
      expect(other, findsOneWidget, reason: text);
      expect(
        tester.getRect(other).top,
        lessThan(title.top),
        reason: '$text comes before Diagnostics',
      );
    }
  });

  testWidgets('map-rail: Expanding shows the inputs', (tester) async {
    final screenshot = await _savedScreenshot(tester);
    final h = await pumpMapFixture(tester);
    await _useScreenshots(tester, h, screenshot);
    await _openSettings(tester);
    await _expand(tester);
    _expectExpanded();
    expect(_follow, findsOneWidget, reason: 'Follow logs is in Settings');

    // Read Latest still works from the map picker's logic: the evidence it
    // reads shows in the section.
    await _readSaved(tester, h);
    expect(
      find.text('Saved evidence source: ${screenshot.path}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('map-rail: Status lines use labels', (tester) async {
    final h = await pumpMapFixture(tester);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('blackgrid-map-logs-'),
    ))!;
    addTearDown(() => root.delete(recursive: true));
    await tester.runAsync(() async {
      final session = Directory(
        '${root.path}${Platform.pathSeparator}log_2026.10.01_10-00-00',
      );
      await session.create();
      await File('${session.path}${Platform.pathSeparator}application.log')
          .create();
      await h.services.settings.setMapInputs(
        gameLogDirectory: root.path,
        screenshotDirectory:
            '${root.path}${Platform.pathSeparator}no-such-screenshots',
      );
    });
    await _until(
      tester,
      () =>
          h.services.mapSession.state.logStatus == MapInputStatus.watching &&
          h.services.mapSession.state.screenshotStatus ==
              MapInputStatus.missing,
    );
    await _openSettings(tester);
    await _expand(tester);
    // The status is the text before the first folder separator.
    String lineOf(String prefix) {
      final text = tester.widget<Text>(find.textContaining(prefix)).data!;
      return text.split(' · ').first;
    }

    expect(
      lineOf('Logs:'),
      'Logs: ${mapInputStatusLabel(MapInputStatus.watching)}',
    );
    expect(lineOf('Logs:'), isNot('Logs: watching'));
    expect(
      lineOf('Screenshots:'),
      'Screenshots: ${mapInputStatusLabel(MapInputStatus.missing)}',
    );
    expect(lineOf('Screenshots:'), isNot('Screenshots: missing'));
  });

  testWidgets('map-rail: Collapsing keeps settings', (tester) async {
    final h = await pumpMapFixture(tester);
    await tester.runAsync(() => h.services.settings.setMap('thelab'));
    await tester.runAsync(
      () => h.services.settings.setMapInputs(followGameLogs: false),
    );
    await settleMapFixture(tester, h);
    final before = (await tester.runAsync(
      () => h.services.database.readSettings(),
    ))!.settings;
    await _openSettings(tester);
    await _expand(tester);
    expect(_followOn(tester), isFalse);
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    _expectCollapsed();
    final after = (await tester.runAsync(
      () => h.services.database.readSettings(),
    ))!.settings;
    expect(before.followGameLogs, isFalse);
    expect(after.followGameLogs, isFalse);
    expect(after.selectedMap, 'thelab');
    expect(after.selectedMap, before.selectedMap);
    expect(after.screenshotDirectory, before.screenshotDirectory);
    expect(after.gameLogDirectory, before.gameLogDirectory);
    expect(h.services.maps.selectedMapId, 'thelab');
    expect(h.services.settings.settings.followGameLogs, isFalse);
  });

  testWidgets('map-rail: Pending screenshot while collapsed', (tester) async {
    final screenshot = await _savedScreenshot(tester);
    final ocr = _GatedOcr();
    final h = await pumpMapFixture(tester, panelOcr: ocr);
    await _useScreenshots(tester, h, screenshot);
    try {
      await _readLatest(
        tester,
        h,
        () => h.services.mapSession.state.processingScreenshot,
      );
      await _openSettings(tester);
      await _showTitle(tester);
      _expectCollapsed();
      expect(find.textContaining('Processing saved screenshot'), findsNothing);
      await _expand(tester);
      expect(
        find.textContaining('Processing saved screenshot'),
        findsOneWidget,
      );
    } finally {
      // Release the gated recognition so that disposal does not wait on it.
      if (!ocr.gate.isCompleted) {
        ocr.gate.complete(RaidPanelEvidence(state: RaidPanelState.unavailable));
      }
      await _until(
        tester,
        () => !h.services.mapSession.state.processingScreenshot,
      );
    }
  });

  testWidgets('map-rail: No ticking while collapsed', (tester) async {
    final screenshot = await _savedScreenshot(tester);
    final h = await pumpMapFixture(tester);
    await _useScreenshots(tester, h, screenshot);
    await _readSaved(tester, h);
    expect(h.services.mapSession.state.savedScreenshotModifiedAt, isNotNull);
    await _openSettings(tester);
    await _showTitle(tester);
    _expectCollapsed();
    expect(find.textContaining('Saved evidence age:'), findsNothing);
    // Nothing is mounted to tick: a pump over seconds builds no status.
    await tester.pump(const Duration(seconds: 3));
    expect(_status, findsNothing);
  });

  testWidgets('map-rail: Age resumes on expand', (tester) async {
    final screenshot = await _savedScreenshot(tester);
    final h = await pumpMapFixture(tester);
    await _useScreenshots(tester, h, screenshot);
    await _readSaved(tester, h);
    await _openSettings(tester);
    await _expand(tester);
    expect(find.textContaining('Saved evidence age:'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(_status, findsOneWidget);
    expect(find.textContaining('Saved evidence age:'), findsOneWidget);
    // Collapsing unmounts the status again, so its timer goes with it.
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    expect(_status, findsNothing);
  });

  testWidgets('map-rail: Settings opens collapsed every time', (tester) async {
    await pumpMapFixture(tester);
    await _openSettings(tester);
    await _expand(tester);
    _expectExpanded();
    await tester.tap(find.widgetWithText(TextButton, 'Back to Map'));
    await tester.pumpAndSettle();
    await _openSettings(tester);
    await _showTitle(tester);
    _expectCollapsed();
  });

  testWidgets('expanded evidence lines show assumed file provenance', (
    tester,
  ) async {
    final screenshot = await _savedScreenshot(tester);
    final h = await pumpMapFixture(tester);
    await _useScreenshots(tester, h, screenshot);
    await _openSettings(tester);
    await _expand(tester);
    await _readSaved(tester, h);
    expect(h.services.mapSession.state.playerSample, isNull);
    expect(h.services.mapSession.state.assumedAssociation, isTrue);
    expect(
      find.text('Saved evidence source: ${screenshot.path}'),
      findsOneWidget,
    );
    expect(find.textContaining('File modified:'), findsOneWidget);
    expect(find.textContaining('Saved evidence age:'), findsOneWidget);
    expect(
      find.text(
        'Assumed saved evidence for the selected map; not confirmed raid association.',
      ),
      findsOneWidget,
    );
    expect(find.text('No sampled player position'), findsOneWidget);
    final evidence = h.services.mapSession.state.raidEvidence!;
    expect(
      evidence.state,
      isNot(isIn([RaidPanelState.recognized, RaidPanelState.empty])),
    );
    expect(h.services.mapSession.state.raidHighlightIds, isEmpty);
    expect(
      find.text('Raid panel: ${raidPanelStateLabel(evidence.state)}'),
      findsOneWidget,
    );
    expect(find.textContaining('Filename sample:'), findsNothing);

    // The file disappears: the previous evidence is kept and labelled so.
    await tester.runAsync(screenshot.delete);
    await tester.runAsync(h.services.mapSession.readLatest);
    await _until(
      tester,
      () =>
          h.services.mapSession.state.screenshotStatus ==
              MapInputStatus.empty &&
          !h.services.mapSession.state.readingLatest,
    );
    expect(h.services.mapSession.state.raidEvidence, same(evidence));
    expect(
      find.text('Previous raid panel: ${raidPanelStateLabel(evidence.state)}'),
      findsOneWidget,
    );
    expect(find.text('No saved screenshots found.'), findsOneWidget);
    expect(h.services.scans.hasAcceptedScan, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual map authority is explicit and Follow logs keeps it', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await tester.runAsync(() => h.services.settings.setMap('thelab'));
    await settleMapFixture(tester, h);
    await _openSettings(tester);
    await _expand(tester);
    expect(find.text('Manual map · The Lab'), findsOneWidget);
    await tester.ensureVisible(_follow);
    await tester.pumpAndSettle();
    await tester.tap(_follow);
    await _until(tester, () => h.services.settings.settings.followGameLogs);
    expect(
      find.text('Follow logs (manual fallback) · The Lab'),
      findsOneWidget,
    );
    final stored = (await tester.runAsync(
      () => h.services.database.readSettings(),
    ))!.settings;
    expect(stored.selectedMap, 'thelab');
    expect(stored.followGameLogs, isTrue);
    expect(h.services.maps.selectedMapId, 'thelab');
    expect(h.services.scans.hasAcceptedScan, isFalse);
  });

  testWidgets('raid line shows in raid on Customs', (tester) async {
    final h = await pumpMapFixture(tester);
    await _useLogFolder(tester, h, [
      'Matching with group id: 1',
      'scene preset path:maps/bigmap.bundle',
      'MatchingCompleted: 7',
      'GameStarting: 7',
      'GameStarted: 7',
    ]);
    await _until(
      tester,
      () => h.services.raidLifecycle.state.phase == RaidPhase.inRaid,
    );
    await _openSettings(tester);
    await _expand(tester);
    expect(find.text('Raid: in raid on Customs'), findsOneWidget);
    expect(find.textContaining('inRaid'), findsNothing);
    expect(find.textContaining('RaidPhase.'), findsNothing);
  });

  testWidgets('raid line shows matching cancelled', (tester) async {
    final h = await pumpMapFixture(tester);
    await _useLogFolder(tester, h, [
      'Matching with group id: 1',
      'Network game matching cancelled.',
    ]);
    await _until(tester, () => h.services.raidLifecycle.state.lastQueueAborted);
    await _openSettings(tester);
    await _expand(tester);
    expect(find.text('Raid: in menus (matching cancelled)'), findsOneWidget);
  });

  testWidgets('raid line shows unknown without log input', (tester) async {
    final h = await pumpMapFixture(tester);
    expect(h.services.mapSession.state.logDirectory, isEmpty);
    await _openSettings(tester);
    await _expand(tester);
    expect(find.text('Raid: unknown'), findsOneWidget);
    expect(find.textContaining('RaidPhase.'), findsNothing);
    expect(find.textContaining('inRaid'), findsNothing);
    expect(find.textContaining('Raid logs:'), findsNothing);
  });

  testWidgets('raid logs line shows the missing notifications log', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await _useLogFolder(tester, h, ['Matching with group id: 1']);
    await _until(
      tester,
      () => h.services.mapSession.state.raidLogsMessage != null,
    );
    await _openSettings(tester);
    await _expand(tester);
    expect(
      find.text('Raid logs: notifications log not written yet'),
      findsOneWidget,
    );
    // The application log is fine, so the Logs line is unchanged.
    expect(
      find.text(
        'Logs: ${mapInputStatusLabel(MapInputStatus.watching)}'
        ' · ${h.services.mapSession.state.logDirectory}',
      ),
      findsOneWidget,
    );
  });
}
