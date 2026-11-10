import 'dart:async';

import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/scan_evidence_panel.dart';
import 'package:blackgrid/ui/settings/commit_field.dart';
import 'package:blackgrid/ui/settings/settings_page.dart';
import 'package:blackgrid/ui/settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';
import 'support/live_map_settings_rig.dart';
import 'support/scan_ui_support.dart';

Finder get _toggle => find.byKey(const Key('settings-diagnostics-toggle'));

/// Finds [text] inside the Settings dialog only, so the screen behind it
/// cannot satisfy or break an expectation.
Finder _inSettings(String text) =>
    find.descendant(of: find.byType(SettingsDialog), matching: find.text(text));

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  // Fail rather than pass vacuously when the section is not there.
  expect(_toggle, findsOneWidget);
  await tester.ensureVisible(_toggle);
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(_toggle);
  await tester.pumpAndSettle();
}

/// Drives scan [index] + 1 to an accepted end over the fake ports. Item `b`
/// (Alternative component) and item `a` (Synthetic component) alternate.
Future<void> _publish(
  WidgetTester tester,
  M1Harness h,
  ScanFakePorts ports,
  int index,
) async {
  await tester.runAsync(
    () => publishTargetedScan(
      h.services.scanner,
      ports,
      text: index.isEven ? 'Alternative component' : 'Synthetic component',
      index: index,
      qpc: 1000 * (index + 1),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('collapsed Diagnostics builds no scan evidence or crop', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await _publish(tester, h, ports, 0);
    // The scan carries a title crop, so a crop on screen would be visible.
    expect(h.services.scanner.lastAccepted, isNotNull);

    await _openSettings(tester);

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.byType(ScanDiagnostics), findsNothing);
    expect(find.byKey(const Key('scan-crop-image')), findsNothing);
    expect(find.byKey(const Key('scan-crop-placeholder')), findsNothing);
    expect(find.byKey(const Key('scan-item-id')), findsNothing);
    expect(find.byKey(const Key('scan-recent-1')), findsNothing);
    expect(find.textContaining('OCR text'), findsNothing);
    expect(find.textContaining('Marker score'), findsNothing);
    expect(_inSettings('Scans'), findsNothing);
    expect(_inSettings('Data sources'), findsNothing);
    expect(_inSettings('Map inputs'), findsNothing);
  });

  testWidgets('expanding shows the latest scan and every recent scan', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    for (var i = 0; i < 3; i++) {
      await _publish(tester, h, ports, i);
    }
    expect(h.services.scanner.recent, hasLength(3));

    await _openSettings(tester);
    await _expand(tester);

    // Three titled parts, in order.
    final mapInputs = _inSettings('Map inputs');
    final scans = _inSettings('Scans');
    final sources = _inSettings('Data sources');
    expect(mapInputs, findsOneWidget);
    expect(scans, findsOneWidget);
    expect(sources, findsOneWidget);
    expect(
      tester.getTopLeft(mapInputs).dy,
      lessThan(tester.getTopLeft(scans).dy),
    );
    expect(
      tester.getTopLeft(scans).dy,
      lessThan(tester.getTopLeft(sources).dy),
    );

    // The latest scan's evidence.
    expect(find.text('Scan #3'), findsOneWidget);
    expect(find.byKey(const Key('scan-end')), findsOneWidget);
    expect(find.byKey(const Key('scan-item-id')), findsOneWidget);
    expect(find.byKey(const Key('scan-timings-label')), findsOneWidget);
    // Every recent scan.
    for (var id = 1; id <= 3; id++) {
      expect(find.byKey(Key('scan-recent-$id')), findsOneWidget);
      expect(find.byKey(Key('scan-recent-detail-$id')), findsOneWidget);
    }
    expect(find.text('Recent scans'), findsOneWidget);
    expect(find.byType(ScanDiagnostics), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scan published while Diagnostics is open is shown at once', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await _publish(tester, h, ports, 0);
    await _openSettings(tester);
    await _expand(tester);
    expect(find.byKey(const Key('scan-recent-1')), findsOneWidget);
    expect(find.byKey(const Key('scan-recent-2')), findsNothing);

    await _publish(tester, h, ports, 1);

    expect(find.text('Scan #2'), findsOneWidget);
    expect(find.byKey(const Key('scan-recent-2')), findsOneWidget);
    expect(find.byKey(const Key('scan-recent-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('map data detail', () {
    /// A page over services whose map data is the bundled PvP data while PvE
    /// is selected, because the one refresh made failed.
    Future<SettingsRig> pumpPage(
      WidgetTester tester, {
      bool selectMode = true,
    }) async {
      tester.view.physicalSize = const Size(1672, 941);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rig = (await tester.runAsync(() async {
        final rig = await SettingsRig.create(client: ControlledMapClient());
        if (selectMode) {
          final failed = rig.whenState(
            (state) => !state.refreshing && state.failure != null,
          );
          unawaited(
            rig.controller.selectMode(mode: GameMode.pve, pack: settingsPack),
          );
          await failed.future;
        }
        return rig;
      }))!;
      addTearDown(rig.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: blackgridTheme(Brightness.dark),
          home: Scaffold(
            body: SettingsPage(
              services: rig.services,
              backLabel: 'Back to Map',
              onBack: () {},
              flush: SettingsFlushController(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(_toggle);
      await tester.pumpAndSettle();
      await _expand(tester);
      return rig;
    }

    testWidgets('settings-diagnostics: Fallback map data', (tester) async {
      final rig = await pumpPage(tester);
      expect(rig.controller.state.mode, GameMode.pve);
      expect(rig.controller.state.dataMode, GameMode.pvp);

      expect(find.text('Data sources'), findsOneWidget);
      expect(find.text('Selected mode: PvE'), findsOneWidget);
      expect(find.text('Map data mode: PvP'), findsOneWidget);
      expect(find.text('Map data source: bundled'), findsOneWidget);
    });

    testWidgets('settings-diagnostics: Never checked', (tester) async {
      final rig = await pumpPage(tester);
      expect(rig.controller.state.checkedAt, isNull);

      expect(find.text('Map data has not been checked.'), findsOneWidget);
      // The visible Item and map data section shows no source or mode line.
      final section = find.byKey(const Key('settings-item-data'));
      for (final line in ['bundled', 'Selected mode', 'Map data mode', 'PvP']) {
        expect(
          find.descendant(of: section, matching: find.textContaining(line)),
          findsNothing,
          reason: line,
        );
      }
    });
  });
}
