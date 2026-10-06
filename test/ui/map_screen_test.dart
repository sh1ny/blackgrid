import 'package:blackgrid/ui/pin_editor.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import '../support/map_widget_harness.dart';

Finder get _savedPins => find.textContaining('saved pin records');

void main() {
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
