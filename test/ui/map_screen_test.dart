import 'dart:io';
import 'dart:ui' as ui;

import 'package:blackgrid/domain/map_session.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';
import 'package:blackgrid/ui/pin_editor.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import '../support/map_widget_harness.dart';

Finder get _savedPins => find.textContaining('saved pin records');

void main() {
  testWidgets(
    'Read Latest exposes assumed file provenance without filename player metadata',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('blackgrid-map-ui-evidence-'),
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
      final h = await pumpMapFixture(tester);
      await tester.runAsync(
        () => h.services.settings.setMapInputs(
          screenshotDirectory: directory.path,
          followGameLogs: false,
        ),
      );
      await settleMapFixture(tester, h);
      final read = find.text('Read Latest');
      await tester.ensureVisible(read);
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        read,
        () =>
            h.services.mapSession.state.savedScreenshotPath ==
                screenshot.path &&
            !h.services.mapSession.state.readingLatest &&
            h.services.mapSession.state.raidEvidence != null,
      );
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
      expect(evidence.extractNames, isEmpty);
      expect(evidence.transitNames, isEmpty);
      expect(h.services.mapSession.state.raidHighlightIds, isEmpty);
      expect(find.text('Raid panel: ${evidence.state.name}'), findsOneWidget);
      expect(find.textContaining('Filename sample:'), findsNothing);
      await tester.runAsync(screenshot.delete);
      await tester.ensureVisible(find.text('Read Latest'));
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        find.text('Read Latest'),
        () =>
            h.services.mapSession.state.screenshotStatus ==
                MapInputStatus.empty &&
            !h.services.mapSession.state.readingLatest,
      );
      expect(h.services.mapSession.state.raidEvidence, same(evidence));
      expect(h.services.mapSession.state.raidHighlightIds, isEmpty);
      expect(
        find.text('Previous raid panel: ${evidence.state.name}'),
        findsOneWidget,
      );
      expect(find.text('No saved screenshots found.'), findsOneWidget);
      expect(
        find.text('Saved evidence source: ${screenshot.path}'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Assumed saved evidence for the selected map; not confirmed raid association.',
        ),
        findsOneWidget,
      );
      expect(h.services.scans.hasAcceptedScan, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'marker search survives show/hide-all and dimmed targets remain eligible',
    (tester) async {
      final h = await pumpMapFixture(tester);
      await tester.runAsync(
        () => h.services.settings.save(
          h.services.settings.settings.copyWith(saveMarkerFilters: true),
        ),
      );
      final search = find.byKey(const ValueKey('marker-search'));
      await tester.scrollUntilVisible(
        search,
        160,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('map-rail-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      await tester.enterText(search, 'exit, tunnel');
      await tester.pumpAndSettle();
      expect(h.services.maps.search, 'exit, tunnel');
      expect(
        h.services.maps
            .visibleMarkers()
            .where((marker) => marker.dimmed)
            .map((marker) => marker.marker.id),
        ['ground-hazard'],
      );
      final hide = find.widgetWithText(TextButton, 'Hide all');
      await Scrollable.ensureVisible(tester.element(hide), alignment: .5);
      await tester.pumpAndSettle();
      expect(hide.hitTestable(), findsOneWidget);
      await tapM1Async(
        tester,
        hide,
        () => h.services.maps.visibleMarkers().isEmpty,
      );
      expect(h.services.maps.search, 'exit, tunnel');
      final hidden = (await tester.runAsync(
        () => h.services.database.readSettings(),
      ))!;
      expect(hidden.markerFilters['PmcExtracts'], isFalse);
      expect(hidden.markerFilters, isNot(contains('extracts')));
      expect(hidden.markerFilters, isNot(contains('hazards')));
      await tester.runAsync(h.services.settings.load);
      await tester.pumpAndSettle();
      expect(h.services.maps.visibleMarkers(), isEmpty);
      final extracts = find.widgetWithText(FilterChip, 'PmcExtracts');
      await Scrollable.ensureVisible(tester.element(extracts), alignment: .5);
      await tester.pumpAndSettle();
      expect(extracts.hitTestable(), findsOneWidget);
      await tapM1Async(
        tester,
        extracts,
        () => h.services.maps.visibleMarkers().length == 1,
      );
      expect(h.services.maps.visibleMarkers().single.marker.id, 'ground-exit');
      final show = find.widgetWithText(TextButton, 'Show all');
      await Scrollable.ensureVisible(tester.element(show), alignment: .5);
      await tester.pumpAndSettle();
      expect(show.hitTestable(), findsOneWidget);
      await tapM1Async(
        tester,
        show,
        () => h.services.maps.visibleMarkers().length == 2,
      );
      expect(
        h.services.maps.visibleMarkers().map((marker) => marker.marker.id),
        ['ground-exit', 'ground-hazard'],
      );
      final shown = (await tester.runAsync(
        () => h.services.database.readSettings(),
      ))!;
      expect(shown.markerFilters['PmcExtracts'], isTrue);
      expect(shown.markerFilters, isNot(contains('extracts')));
      expect(shown.markerFilters, isNot(contains('hazards')));
      await tester.runAsync(h.services.settings.load);
      await tester.pumpAndSettle();
      expect(h.services.maps.visibleMarkers(), hasLength(2));
      expect(h.services.maps.visibleMarkers().last.dimmed, isTrue);
      expect(
        h.services.maps
            .hitTestMarker(h.services.maps.visibleMarkers().last.viewportPoint)!
            .marker
            .id,
        'ground-hazard',
      );
      expect(h.services.scans.hasAcceptedScan, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual map authority is explicit and Follow logs does not overwrite stored manual selection',
    (tester) async {
      final h = await pumpMapFixture(tester);
      await tester.runAsync(() => h.services.settings.setMap('thelab'));
      await settleMapFixture(tester, h);
      expect(find.text('Manual map · The Lab'), findsOneWidget);
      final follow = find.widgetWithText(SwitchListTile, 'Follow logs');
      await tester.ensureVisible(follow);
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        follow,
        () => h.services.settings.settings.followGameLogs,
      );
      expect(
        find.text('Follow logs (manual fallback) · The Lab'),
        findsOneWidget,
      );
      final stored = (await tester.runAsync(
        () => h.services.database.readSettings(),
      ))!;
      expect(stored.selectedMap, 'thelab');
      expect(stored.followGameLogs, isTrue);
      expect(h.services.maps.selectedMapId, 'thelab');
      expect(h.services.scans.hasAcceptedScan, isFalse);
    },
  );

  testWidgets(
    'Map keeps a broad workspace beside the status rail without accepting a scan',
    (tester) async {
      final h = await pumpMapFixture(tester);
      final workspace = tester.getRect(
        find.byWidgetPredicate((w) => w is GridPanel && w.title == 'SHORELINE'),
      );
      final active = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is GridPanel && w.title == 'Active map',
        ),
      );
      expect(workspace.width, greaterThan(1912 * .6));
      expect(active.left, greaterThan(workspace.right));
      expect(h.services.maps.scene, isNotNull);
      expect(find.text('No accepted scan this session'), findsOneWidget);
      expect(h.services.scans.hasAcceptedScan, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final map in ['shoreline', 'thelab']) {
    testWidgets(
      '$map saved-pin browser edits and removes finite off-map pins without reframing them',
      (tester) async {
        final h = await pumpMapFixture(tester);
        if (map != 'shoreline') {
          await tester.runAsync(() => h.services.settings.setMap(map));
          await settleMapFixture(tester, h);
        }
        await tester.tap(find.text('Add pin'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Pin label'),
          'Durable off-map marker',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Normalized X'),
          'not a coordinate',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Normalized Y'),
          '1.5',
        );
        await tester.tap(find.text('Save pin'));
        await tester.pumpAndSettle();
        expect(find.byType(PinEditor), findsOneWidget);
        expect(
          find.textContaining('finite normalized coordinates'),
          findsOneWidget,
        );
        expect(h.services.settings.pins, isEmpty);
        await tester.enterText(
          find.widgetWithText(TextField, 'Normalized X'),
          '-.2',
        );
        await tapM1Async(
          tester,
          find.text('Save pin'),
          () => h.services.settings.pins.isNotEmpty,
        );
        final original = h.services.settings.pins.single;
        expect(original.mapId, map);
        expect(original.x, -.2);
        expect(original.y, 1.5);
        expect(
          original.frame,
          map == 'thelab' ? 'labs-native-normalized' : 'legacy-normalized',
        );
        expect(original.frameRevision, map == 'thelab' ? 1 : 0);
        expect(find.byType(PinEditor), findsNothing);
        // Off-map records remain discoverable even when no glyph is visible.
        await tester.tap(_savedPins);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, original.label));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'Normalized X'))
              .controller!
              .text,
          '-0.2',
        );
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'Normalized Y'))
              .controller!
              .text,
          '1.5',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Pin label'),
          'Renamed off-map marker',
        );
        await tapM1Async(
          tester,
          find.text('Save pin'),
          () =>
              h.services.settings.pins.single.label == 'Renamed off-map marker',
        );
        final edited = h.services.settings.pins.single;
        expect(edited.id, original.id);
        expect(edited.mapId, original.mapId);
        expect(edited.x, original.x);
        expect(edited.y, original.y);
        expect(edited.frame, original.frame);
        expect(edited.frameRevision, original.frameRevision);
        expect(find.widgetWithText(ListTile, edited.label), findsOneWidget);
        await tester.tap(find.byTooltip('Remove pin ${edited.label}'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(h.services.settings.pins.single.id, original.id);
        await tester.tap(find.byTooltip('Remove pin ${edited.label}'));
        await tester.pumpAndSettle();
        await tapM1Async(
          tester,
          find.widgetWithText(FilledButton, 'Remove'),
          () => h.services.settings.pins.isEmpty,
        );
        expect(find.widgetWithText(ListTile, edited.label), findsNothing);
        expect(h.services.scans.hasAcceptedScan, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final layout in [
    (name: 'wide', size: const Size(1912, 823), scale: 1.0),
    (name: 'compact', size: const Size(760, 900), scale: 1.0),
    (name: 'compact enlarged text', size: const Size(760, 900), scale: 2.0),
  ]) {
    testWidgets('${layout.name} map controls remain reachable and usable', (
      tester,
    ) async {
      final h = await pumpMapFixture(
        tester,
        size: layout.size,
        scale: layout.scale,
      );
      final fit = find.widgetWithText(OutlinedButton, 'Fit map');
      await tester.ensureVisible(fit);
      await tester.pumpAndSettle();
      expect(fit.hitTestable(), findsOneWidget);
      await tester.tap(fit);
      await settleMapFixture(tester, h);
      final fitScale = h.services.maps.transform.scale;
      await tester.tap(find.byTooltip('Zoom in'));
      await settleMapFixture(tester, h);
      expect(h.services.maps.transform.scale, greaterThan(fitScale));
      await tester.tap(fit);
      await settleMapFixture(tester, h);
      expect(h.services.maps.transform.scale, closeTo(fitScale, 1e-9));
      final upper = find.widgetWithText(FilterChip, 'Upper');
      await tester.ensureVisible(upper);
      await tester.pumpAndSettle();
      expect(upper.hitTestable(), findsOneWidget);
      await tester.tap(upper);
      await settleMapFixture(tester, h);
      expect(h.services.maps.floorSelection!.isLayerVisible('upper'), isTrue);
      final addPin = find.widgetWithText(OutlinedButton, 'Add pin');
      await tester.ensureVisible(addPin);
      await tester.pumpAndSettle();
      expect(addPin.hitTestable(), findsOneWidget);
      await tester.tap(addPin);
      await tester.pumpAndSettle();
      final label = find.widgetWithText(TextField, 'Pin label');
      await tester.ensureVisible(label);
      await tester.enterText(label, 'Reachable controls');
      final x = find.widgetWithText(TextField, 'Normalized X');
      await tester.ensureVisible(x);
      await tester.enterText(x, '.5');
      final y = find.widgetWithText(TextField, 'Normalized Y');
      await tester.ensureVisible(y);
      await tester.enterText(y, '.5');
      await tapM1Async(
        tester,
        find.text('Save pin'),
        () => h.services.settings.pins.isNotEmpty,
      );
      await tester.ensureVisible(_savedPins);
      await tester.pumpAndSettle();
      expect(_savedPins.hitTestable(), findsOneWidget);
      await tester.tap(_savedPins);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(ListTile, 'Reachable controls'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
