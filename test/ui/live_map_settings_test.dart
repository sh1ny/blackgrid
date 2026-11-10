import 'dart:async';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/live_map_data_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/settings/commit_field.dart';
import 'package:blackgrid/ui/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/live_map_settings_rig.dart';

void main() {
  testWidgets(
    'map status stays independent while navigation remains available',
    (tester) async {
      late Completer<void> failed;
      final rig = (await tester.runAsync(() async {
        final client = ControlledMapClient()..holdMapRequests = true;
        final rig = await SettingsRig.create(client: client);
        failed = rig.whenState(
          (state) => !state.refreshing && state.failure != null,
        );
        unawaited(
          rig.controller.selectMode(mode: GameMode.pve, pack: settingsPack),
        );
        await client.firstMapRequest.future;
        return rig;
      }))!;
      final client = rig.client;
      addTearDown(rig.close);
      expect(rig.controller.state.mode, GameMode.pve);
      expect(rig.controller.state.source, LiveMapDataSource.bundled);
      expect(rig.controller.state.refreshing, isTrue);

      var back = 0;
      await _showSettings(tester, rig.services, onBack: () => back++);
      final refreshing = find.widgetWithText(
        OutlinedButton,
        'Refreshing map data…',
      );
      await tester.ensureVisible(refreshing);
      expect(tester.widget<OutlinedButton>(refreshing).onPressed, isNull);
      // The mode and the source are Diagnostics detail, not part of the row.
      expect(_textContaining('bundled'), findsNothing);
      expect(find.text('Selected mode: PvE'), findsNothing);
      final backButton = find.widgetWithText(TextButton, 'Back to Map');
      expect(tester.widget<TextButton>(backButton).onPressed, isNotNull);
      await tester.tap(backButton);
      expect(back, 1);

      await tester.runAsync(() async {
        client.release.complete(
          http.Response('synthetic map source unavailable', 503),
        );
        await failed.future;
      });
      await tester.pump();
      expect(rig.controller.state.mode, GameMode.pve);
      expect(rig.controller.state.dataMode, GameMode.pvp);
      expect(rig.controller.state.source, LiveMapDataSource.bundled);
      expect(rig.controller.state.failure, isNotNull);

      expect(find.textContaining('Map data refresh failed'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Back to Map'))
            .onPressed,
        isNotNull,
      );
      // The detail is one expansion away.
      await _expandDiagnostics(tester);
      expect(find.text('Selected mode: PvE'), findsOneWidget);
      expect(find.text('Map data mode: PvP'), findsOneWidget);
      expect(find.text('Map data source: bundled'), findsOneWidget);
    },
  );

  testWidgets('manual map refresh does not refresh items', (tester) async {
    final rig = (await tester.runAsync(() async {
      final client = ControlledMapClient();
      client.response = http.Response('synthetic map source unavailable', 503);
      final store = SettingsStore(snapshot: cachedSnapshot());
      final rig = await SettingsRig.create(client: client, store: store);
      final failed = rig.whenState(
        (state) => !state.refreshing && state.failure != null,
      );
      unawaited(
        rig.controller.selectMode(mode: GameMode.pve, pack: settingsPack),
      );
      await failed.future;
      return rig;
    }))!;
    final client = rig.client;
    addTearDown(rig.close);
    await _showSettings(tester, rig.services);

    expect(rig.controller.state.source, LiveMapDataSource.cached);
    expect(rig.controller.state.checkedAt, settingsCheckedAt);
    // The row names the check in local words, with the year of an old one.
    expect(find.textContaining('2021'), findsOneWidget);
    expect(find.textContaining('Map data refresh failed'), findsOneWidget);
    final itemLine = find.text('Not downloaded yet');
    expect(itemLine, findsOneWidget);
    final catalogSnapshot = rig.services.catalog.snapshot;
    final itemRequestsBefore = client.itemRequests;
    final mapRequestsBefore = client.mapRequests;
    final mapRefresh = find.text('Refresh map data');
    await tester.ensureVisible(mapRefresh);
    await tester.pumpAndSettle();
    expect(mapRefresh.hitTestable(), findsOneWidget);

    await tester.runAsync(() async {
      final refreshed = rig.whenNextSettled();
      final nextMapBatch = client.whenMapRequests(mapRequestsBefore + 1);
      await tester.tap(mapRefresh);
      await nextMapBatch.future;
      await refreshed.future;
    });
    await tester.pump();

    expect(client.mapRequests, greaterThan(mapRequestsBefore));
    expect(client.itemRequests, itemRequestsBefore);
    expect(rig.services.catalog.snapshot, same(catalogSnapshot));
    expect(rig.controller.state.source, LiveMapDataSource.cached);
    expect(rig.controller.state.checkedAt, settingsCheckedAt);
    expect(itemLine, findsOneWidget);
    expect(find.textContaining('2021'), findsOneWidget);
    await _expandDiagnostics(tester);
    expect(find.text('Map data source: cached'), findsOneWidget);
  });
}

Finder _textContaining(String value) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.data?.toLowerCase().contains(value.toLowerCase()) == true,
);

/// Shows the Settings page alone, scrolled to Item and map data.
Future<void> _showSettings(
  WidgetTester tester,
  AppServices services, {
  VoidCallback? onBack,
}) async {
  tester.view.physicalSize = const Size(1672, 941);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(Brightness.dark),
      home: Scaffold(
        body: SettingsPage(
          services: services,
          backLabel: 'Back to Map',
          onBack: onBack ?? () {},
          flush: SettingsFlushController(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expandDiagnostics(WidgetTester tester) async {
  final toggle = find.byKey(const Key('settings-diagnostics-toggle'));
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}
