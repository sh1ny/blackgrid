import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blackgrid/data/raid_panel_ocr.dart';
import 'package:blackgrid/domain/map_session.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import '../support/map_widget_harness.dart';
import 'support/scan_ui_support.dart';

/// An OCR whose recognition never finishes until [gate] is completed.
final class _GatedOcr extends RaidPanelOcr {
  final gate = Completer<RaidPanelEvidence>();

  @override
  Future<RaidPanelEvidence> recognize(Uint8List imageBytes) => gate.future;
}

Finder _panel(String title) =>
    find.byWidgetPredicate((w) => w is GridPanel && w.title == title);

/// The decision card, whose title depends on the current selection.
Finder get _decisionCard => find.byWidgetPredicate(
  (w) => w is GridPanel && w.icon == Icons.center_focus_strong,
);

Finder get _inputStatus => find.byKey(const Key('map-input-status'));

/// The rail scroll offset at which [section] starts, independent of how far
/// the rail or the page is currently scrolled.
Future<double> _railOffset(WidgetTester tester, Finder section) async {
  await scrollMapRailTo(tester, section);
  final box = tester.renderObject(section);
  return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
}

Future<void> _expectRailOrder(WidgetTester tester) async {
  final offsets = <String, double>{
    'Active map': await _railOffset(tester, _panel('Active map')),
    'decision card': await _railOffset(tester, _decisionCard),
    'Marker preferences': await _railOffset(
      tester,
      _panel('Marker preferences'),
    ),
    'Manual item search': await _railOffset(
      tester,
      _panel('Manual item search'),
    ),
    'Map saved-file inputs': await _railOffset(tester, mapInputsHeader),
  };
  final names = offsets.keys.toList();
  final values = offsets.values.toList();
  for (var i = 1; i < values.length; i++) {
    expect(
      values[i],
      greaterThan(values[i - 1]),
      reason: '${names[i]} must come after ${names[i - 1]}: $offsets',
    );
  }
}

void _expectInputsCollapsed() {
  expect(find.text('Map saved-file inputs'), findsOneWidget);
  expect(find.textContaining('Logs:'), findsNothing);
  expect(find.textContaining('Screenshots:'), findsNothing);
  expect(find.widgetWithText(SwitchListTile, 'Follow logs'), findsNothing);
  expect(find.text('Read Latest'), findsNothing);
  expect(_inputStatus, findsNothing);
}

void _expectInputsExpanded() {
  expect(find.textContaining('Logs:'), findsOneWidget);
  expect(find.textContaining('Screenshots:'), findsOneWidget);
  expect(find.widgetWithText(SwitchListTile, 'Follow logs'), findsOneWidget);
  expect(find.text('Read Latest'), findsOneWidget);
  expect(_inputStatus, findsOneWidget);
}

/// Writes a tiny PNG modified an hour ago into a new temporary directory.
Future<File> _savedScreenshot(WidgetTester tester) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('blackgrid-map-rail-'),
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

void main() {
  testWidgets('wide rail orders Active map, card, markers, search, inputs', (
    tester,
  ) async {
    await pumpMapFixture(tester);
    await _expectRailOrder(tester);
  });

  testWidgets('compact rail keeps the same order with inputs last', (
    tester,
  ) async {
    await pumpMapFixture(tester, size: const Size(760, 900));
    await _expectRailOrder(tester);
  });

  testWidgets('Active map row stays alone with an accepted scan', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpMapFixture(tester, scanPorts: ports);
    await tester.runAsync(
      () => publishTargetedScan(
        h.services.scanner,
        ports,
        text: 'Alternative component',
      ),
    );
    await tester.pumpAndSettle();
    final active = tester.getRect(_panel('Active map'));
    final card = tester.getRect(_panel('Accepted scan'));
    expect(card.top, greaterThanOrEqualTo(active.bottom));
    for (final element
        in find.byWidgetPredicate((w) => w is GridPanel).evaluate()) {
      final panel = element.widget as GridPanel;
      final rect = tester.getRect(find.byWidget(panel));
      final inRail =
          rect.left >= active.left - 1 && rect.right <= active.right + 1;
      if (!inRail || panel.title == 'Active map') continue;
      expect(
        rect.top >= active.bottom || rect.bottom <= active.top,
        isTrue,
        reason: '${panel.title} shares the Active map row',
      );
    }
    expect(find.text('Latest accepted scan'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inputs section starts collapsed', (tester) async {
    await pumpMapFixture(tester);
    await showMapInputsHeader(tester);
    _expectInputsCollapsed();
  });

  testWidgets('expanding shows status, Follow logs and a working Read Latest', (
    tester,
  ) async {
    final screenshot = await _savedScreenshot(tester);
    final h = await pumpMapFixture(tester);
    await _useScreenshots(tester, h, screenshot);
    await expandMapInputs(tester);
    _expectInputsExpanded();
    final read = find.text('Read Latest');
    await tester.ensureVisible(read);
    await tester.pumpAndSettle();
    await tapM1Async(
      tester,
      read,
      () =>
          h.services.mapSession.state.savedScreenshotPath == screenshot.path &&
          !h.services.mapSession.state.readingLatest &&
          h.services.mapSession.state.raidEvidence != null,
    );
    expect(
      find.text('Saved evidence source: ${screenshot.path}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expand then collapse keeps Follow logs and the maps', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester);
    await tester.runAsync(() => h.services.settings.setMap('thelab'));
    await tester.runAsync(
      () => h.services.settings.setMapInputs(followGameLogs: false),
    );
    await settleMapFixture(tester, h);
    final before = (await tester.runAsync(
      () => h.services.database.readSettings(),
    ))!.settings;
    await expandMapInputs(tester);
    final follow = find.widgetWithText(SwitchListTile, 'Follow logs');
    expect(tester.widget<SwitchListTile>(follow).value, isFalse);
    await tester.tap(mapInputsHeader);
    await tester.pumpAndSettle();
    _expectInputsCollapsed();
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

  testWidgets('pending screenshot keeps the section collapsed', (tester) async {
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
      await showMapInputsHeader(tester);
      _expectInputsCollapsed();
      expect(find.textContaining('Processing saved screenshot'), findsNothing);
      await expandMapInputs(tester);
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

  testWidgets('expanded status lines use labels, not state names', (
    tester,
  ) async {
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
    await expandMapInputs(tester);
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
    await expandMapInputs(tester);
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
    await expandMapInputs(tester);
    expect(find.text('Raid: in menus (matching cancelled)'), findsOneWidget);
  });

  testWidgets('raid line shows unknown without log input', (tester) async {
    final h = await pumpMapFixture(tester);
    expect(h.services.mapSession.state.logDirectory, isEmpty);
    await expandMapInputs(tester);
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
    await expandMapInputs(tester);
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

  testWidgets('collapsed section does not mount the saved-file status', (
    tester,
  ) async {
    final screenshot = await _savedScreenshot(tester);
    final h = await pumpMapFixture(tester);
    await _useScreenshots(tester, h, screenshot);
    await _readLatest(
      tester,
      h,
      () =>
          h.services.mapSession.state.savedScreenshotModifiedAt != null &&
          !h.services.mapSession.state.processingScreenshot &&
          !h.services.mapSession.state.readingLatest,
    );
    expect(h.services.mapSession.state.savedScreenshotModifiedAt, isNotNull);
    await showMapInputsHeader(tester);
    _expectInputsCollapsed();
    expect(find.textContaining('Saved evidence age:'), findsNothing);
  });

  testWidgets('expanding shows the saved evidence age', (tester) async {
    final screenshot = await _savedScreenshot(tester);
    final h = await pumpMapFixture(tester);
    await _useScreenshots(tester, h, screenshot);
    await _readLatest(
      tester,
      h,
      () =>
          h.services.mapSession.state.savedScreenshotModifiedAt != null &&
          !h.services.mapSession.state.processingScreenshot &&
          !h.services.mapSession.state.readingLatest,
    );
    await expandMapInputs(tester);
    expect(find.textContaining('Saved evidence age:'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(_inputStatus, findsOneWidget);
    expect(find.textContaining('Saved evidence age:'), findsOneWidget);
  });

  testWidgets('expansion survives Scanner and back', (tester) async {
    await pumpMapFixture(tester);
    await expandMapInputs(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-map')));
    await tester.pumpAndSettle();
    await showMapInputsHeader(tester);
    _expectInputsExpanded();
  });

  testWidgets('expansion survives the compact breakpoint', (tester) async {
    await pumpMapFixture(tester);
    await expandMapInputs(tester);
    tester.view.physicalSize = const Size(760, 900);
    await tester.pumpAndSettle();
    await showMapInputsHeader(tester);
    _expectInputsExpanded();
    tester.view.physicalSize = const Size(1912, 823);
    await tester.pumpAndSettle();
    await showMapInputsHeader(tester);
    _expectInputsExpanded();
  });

  testWidgets('a new app starts collapsed', (tester) async {
    final h = await pumpMapFixture(tester);
    await expandMapInputs(tester);
    await tester.pumpWidget(
      BlackgridApp(key: UniqueKey(), services: h.services),
    );
    await settleMapFixture(tester, h);
    await showMapInputsHeader(tester);
    _expectInputsCollapsed();
  });
}
