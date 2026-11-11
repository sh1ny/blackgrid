import 'dart:async';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/live_map_data_controller.dart';
import 'package:blackgrid/application/progress_controller.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/data/tracker_client.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_failure.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/theme_access.dart';
import 'package:blackgrid/ui/settings/commit_field.dart';
import 'package:blackgrid/ui/settings/settings_page.dart';
import 'package:blackgrid/ui/settings/settings_row.dart';
import 'package:blackgrid/ui/settings/settings_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';
import '../support/raid_timer_support.dart';
import 'support/live_map_settings_rig.dart';
import 'support/scan_ui_support.dart';

const _windowHeight = 941.0;

/// Creates the services a page test runs on, in the real zone.
///
/// A null [mode] only loads the saved settings, so a test can start from the
/// state the database was left in.
Future<M1Harness> _harness(
  WidgetTester tester, {
  GameMode? mode = GameMode.pvp,
  ScanFakePorts? ports,
  BlackgridDatabase? database,
}) async {
  final h = (await tester.runAsync(() async {
    final result = M1Harness(scanPorts: ports, database: database);
    if (mode == null) {
      await result.services.initialize();
    } else {
      await result.initialize(mode: mode);
    }
    return result;
  }))!;
  addTearDown(h.dispose);
  return h;
}

/// Shows the page alone over [services], the way the shell will.
Future<void> _pump(
  WidgetTester tester,
  AppServices services, {
  SettingsSection? section,
  int request = 0,
  SettingsFlushController? flush,
  String? version,
  Size size = const Size(1672, _windowHeight),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = flush ?? SettingsFlushController();
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(Brightness.dark),
      home: Scaffold(
        body: version == null
            ? SettingsPage(
                services: services,
                backLabel: 'Back to Map',
                onBack: () {},
                flush: controller,
                section: section,
                request: request,
              )
            : SettingsPage(
                services: services,
                backLabel: 'Back to Map',
                onBack: () {},
                flush: controller,
                section: section,
                request: request,
                version: version,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<M1Harness> _pumpHarness(
  WidgetTester tester, {
  GameMode? mode = GameMode.pvp,
  ScanFakePorts? ports,
  SettingsSection? section,
  int request = 0,
  String? version,
  Size size = const Size(1672, _windowHeight),
}) async {
  final h = await _harness(tester, mode: mode, ports: ports);
  await _pump(
    tester,
    h.services,
    section: section,
    request: request,
    version: version,
    size: size,
  );
  return h;
}

Finder _title(SettingsSection section) =>
    find.byKey(Key('settings-title-${section.name}'));

Finder _nav(SettingsSection section) =>
    find.byKey(Key('settings-nav-${section.name}'));

Future<void> _show(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

bool _inView(WidgetTester tester, Finder target) {
  final rect = tester.getRect(target);
  return rect.top >= 0 && rect.bottom <= _windowHeight;
}

bool _holdsFocus(WidgetTester tester, Finder title) =>
    Focus.of(tester.element(title)).hasPrimaryFocus;

/// The tap handler of a switch row, or `null` while the row is disabled.
VoidCallback? _rowTap(WidgetTester tester, Finder row) => tester
    .widget<InkWell>(
      find.descendant(of: row, matching: find.byType(InkWell)).first,
    )
    .onTap;

Finder _rowNamed(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(SettingsRow));

AppSettings _settings(M1Harness h) => h.services.settings.settings;

/// Types [text] in the field labelled [label] and commits it with the done
/// action, the way a user presses Enter.
Future<void> _typeAndSubmit(
  WidgetTester tester,
  String label,
  String text,
) async {
  final field = find.widgetWithText(TextField, label);
  await _show(tester, field);
  await tester.enterText(field, text);
  // A saved folder binds its watchers, so the commit starts in the real zone.
  await tester.runAsync(
    () => tester.testTextInput.receiveAction(TextInputAction.done),
  );
  await tester.pump();
}

/// Makes every settings save fail, as a broken database would.
Future<void> _breakSettingsSaves(WidgetTester tester, M1Harness h) =>
    tester.runAsync(
      () => h.db.customStatement(
        "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences "
        "BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      ),
    );

/// A progress controller whose token actions throw, which the real one never
/// does: it turns a failed credential store into an error line instead.
class _ThrowingProgress extends ProgressController {
  _ThrowingProgress()
    : super(
        store: MemoryCredentials(),
        client: TrackerClient(
          client: MockClient((_) async => http.Response('{}', 404)),
        ),
      );

  @override
  Future<void> saveCredential(String token) =>
      Future.error(StateError('synthetic credential failure'));
}

/// Services whose Tracker progress controller is [_ThrowingProgress].
class _ThrowingTokenServices extends AppServices {
  _ThrowingTokenServices({
    required super.database,
    required super.credentials,
    required super.client,
  });

  final _throwing = _ThrowingProgress();

  @override
  ProgressController get progress => _throwing;
}

void main() {
  group('sections', () {
    testWidgets('settings-page: Sidebar order', (tester) async {
      await _pumpHarness(tester);
      final texts = [
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('settings-sidebar')),
            matching: find.byType(Text),
          ),
        ))
          text.data,
      ];
      expect(texts, [
        'Back to Map',
        'General',
        'Live scan',
        'Item and map data',
        'Tracker progress',
        'Game files',
        'Raid timers',
        'Map',
        'Diagnostics',
      ]);
      // The scrolling column lists the same sections in the same order.
      final tops = [
        for (final section in SettingsSection.values)
          tester.getTopLeft(_title(section)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(SettingsSection.values, hasLength(8));
    });

    testWidgets('settings-page: Jump to a section', (tester) async {
      await _pumpHarness(tester);
      final title = _title(SettingsSection.raidTimers);
      expect(tester.getTopLeft(title).dy, greaterThan(_windowHeight));

      await tester.tap(_nav(SettingsSection.raidTimers));
      await tester.pumpAndSettle();

      expect(_inView(tester, title), isTrue);
      expect(_holdsFocus(tester, title), isTrue);
    });

    testWidgets('settings-page: Jump to Diagnostics', (tester) async {
      await _pumpHarness(tester);
      expect(find.text('Map inputs'), findsNothing);

      await tester.tap(_nav(SettingsSection.diagnostics));
      await tester.pumpAndSettle();

      expect(find.text('Map inputs'), findsOneWidget);
      expect(find.text('Data sources'), findsOneWidget);
      expect(
        _inView(tester, find.byKey(const Key('settings-diagnostics-toggle'))),
        isTrue,
      );
      expect(_inView(tester, _title(SettingsSection.diagnostics)), isTrue);
    });

    testWidgets('a requested section is shown and focused on mount', (
      tester,
    ) async {
      await _pumpHarness(tester, section: SettingsSection.tracker, request: 1);
      final title = _title(SettingsSection.tracker);
      expect(_inView(tester, title), isTrue);
      expect(_holdsFocus(tester, title), isTrue);
      expect(find.text('Map inputs'), findsNothing);
    });

    testWidgets('a higher request number for the same section scrolls again', (
      tester,
    ) async {
      final h = await _pumpHarness(
        tester,
        section: SettingsSection.raidTimers,
        request: 1,
      );
      final scrollable = find
          .ancestor(
            of: find.byKey(const Key('settings-column')),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_inView(tester, _title(SettingsSection.raidTimers)), isFalse);

      await _pump(
        tester,
        h.services,
        section: SettingsSection.raidTimers,
        request: 2,
      );

      expect(_inView(tester, _title(SettingsSection.raidTimers)), isTrue);
    });

    testWidgets('requesting Diagnostics expands it', (tester) async {
      await _pumpHarness(
        tester,
        section: SettingsSection.diagnostics,
        request: 1,
      );
      expect(find.text('Map inputs'), findsOneWidget);
    });

    testWidgets('without a section the page title holds focus', (tester) async {
      await _pumpHarness(tester);
      final title = find.byKey(const Key('settings-page-title'));
      expect(_holdsFocus(tester, title), isTrue);
    });
  });

  group('rows', () {
    group('Item and map data', () {
      testWidgets('catalog-authority: Item names that could not be loaded', (
        tester,
      ) async {
        final h = await _harness(tester);
        h.services.catalog.snapshot = CatalogSnapshot(
          mode: GameMode.pvp,
          revision: 'names-revision',
          observedAt: DateTime.utc(2026, 11, 10),
          items: const {},
          traders: const {},
          requirements: const [],
          localizationErrors: const ['items'],
        );
        await _pump(tester, h.services);
        final section = find.byKey(const Key('settings-item-data'));
        await _show(tester, section);

        final message = find.descendant(
          of: section,
          matching: find.textContaining(
            'Some item names could not be loaded: items',
          ),
        );
        expect(message, findsOneWidget);
        expect(
          tester.widget<Text>(message).style?.color,
          tester.element(message).ember.errInk,
        );
      });
    });

    testWidgets('settings-page: Toggle by row', (tester) async {
      final h = await _pumpHarness(tester);
      final before = _settings(h).followGameLogs;
      final name = find.text('Follow logs');
      await _show(tester, name);

      await tester.tap(name);
      await pumpUntil(tester, () => _settings(h).followGameLogs == !before);

      final stored = (await tester.runAsync(h.services.database.readSettings))!;
      expect(stored.settings.followGameLogs, !before);
    });

    testWidgets('settings-page: Wide window', (tester) async {
      await _pumpHarness(tester, size: const Size(1920, 1080));
      final width = tester
          .getSize(find.byKey(const Key('settings-column')))
          .width;
      expect(width, lessThanOrEqualTo(720));
      expect(width, greaterThan(400));
    });

    testWidgets('settings-page: Setting disabled while saving', (tester) async {
      final h = await _harness(tester);
      final follow = _settings(h).followGameLogs;
      final filters = _settings(h).saveMarkerFilters;
      // A save is in flight when the page opens.
      h.services.settings.busy = true;
      await _pump(tester, h.services);

      for (final name in ['Follow logs', 'Save marker filters']) {
        await _show(tester, find.text(name));
        expect(_rowTap(tester, _rowNamed(name)), isNull, reason: name);
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
      }

      expect(_settings(h).followGameLogs, follow);
      expect(_settings(h).saveMarkerFilters, filters);
      final stored = (await tester.runAsync(h.services.database.readSettings))!;
      expect(stored.settings.followGameLogs, follow);
      expect(stored.settings.saveMarkerFilters, filters);
    });

    testWidgets('settings-page: Switch saves at once', (tester) async {
      final h = await _pumpHarness(tester);
      final before = _settings(h).saveMarkerFilters;
      await _show(tester, find.text('Save marker filters'));

      await tester.tap(find.text('Save marker filters'));
      await pumpUntil(tester, () => _settings(h).saveMarkerFilters == !before);

      final stored = (await tester.runAsync(h.services.database.readSettings))!;
      expect(stored.settings.saveMarkerFilters, !before);
    });

    testWidgets('settings-page: Settings could not be read', (tester) async {
      final db = BlackgridDatabase(NativeDatabase.memory());
      await tester.runAsync(
        () => db.customStatement(
          "INSERT INTO preferences (id, payload) VALUES (1, '{not json')",
        ),
      );
      final h = await _harness(tester, mode: null, database: db);
      await _pump(tester, h.services);

      final notice = find.text(
        'Your saved settings could not be read. '
        'Default settings are in use until you change one.',
      );
      expect(notice, findsOneWidget);
      expect(
        tester.getTopLeft(notice).dy,
        lessThan(tester.getTopLeft(_title(SettingsSection.general)).dy),
      );
    });
  });

  group('General, Live scan and Map', () {
    testWidgets('settings-page: Game mode', (tester) async {
      final h = await _pumpHarness(tester);
      final choice = find.descendant(
        of: find.byType(SegmentedButton<GameMode>),
        matching: find.text('PvE'),
      );

      await tester.runAsync(() => tester.tap(choice));
      await pumpUntil(
        tester,
        () =>
            h.services.catalog.mode == GameMode.pve &&
            !h.services.catalog.loading,
      );

      expect(h.services.catalog.mode, GameMode.pve);
      expect(_settings(h).mode, GameMode.pve);
    });

    testWidgets('settings-page: Scan key refused', (tester) async {
      final ports = ScanFakePorts();
      final h = await _harness(tester, ports: ports);
      await tester.runAsync(() async {
        await h.services.scanner.setLiveScan(true);
        await h.services.scanner.settled;
      });
      ports.platform!.trigger.heldKeys.add(ScanHotkey.f10);
      await _pump(tester, h.services);
      final picker = find.byKey(const Key('scan-hotkey-picker'));
      await _show(tester, picker);

      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        find.text('F10').last,
        () => h.services.scanner.hotkeyError != null,
      );

      expect(
        find.textContaining('F10 could not be registered'),
        findsOneWidget,
      );
      expect(
        tester.widget<DropdownButton<ScanHotkey>>(picker).value,
        ScanHotkey.f9,
      );
      expect(find.textContaining('F9 scans at the cursor'), findsOneWidget);
    });

    testWidgets('settings-page: Live scan unavailable', (tester) async {
      final ports = ScanFakePorts()
        ..markerOverride = const InspectionTemplatesUnavailable(
          VisionMissingFile('synthetic-missing.pgm'),
        );
      final h = await _harness(tester, ports: ports);
      await tester.runAsync(() async {
        await h.services.scanner.setLiveScan(true);
        await h.services.scanner.settled;
      });
      await _pump(tester, h.services);
      final status = find.byKey(const Key('live-scan-status'));
      await _show(tester, status);

      final text = tester.widget<Text>(status).data!;
      expect(text, contains('unavailable'));
      expect(text, contains('synthetic-missing.pgm'));
    });

    testWidgets('settings-page: Disabled rule kept', (tester) async {
      final ports = ScanFakePorts();
      final h = await _harness(tester, ports: ports);
      await _pump(tester, h.services);
      final record = find.byKey(const Key('record-frames-switch'));
      await _show(tester, record);
      expect(h.services.scanner.status.state, LiveScanState.off);
      expect(_rowTap(tester, record), isNull);

      await tester.runAsync(() async {
        await h.services.scanner.setLiveScan(true);
        await h.services.scanner.settled;
      });
      await tester.pumpAndSettle();
      expect(h.services.scanner.status.state, LiveScanState.ready);
      expect(_rowTap(tester, record), isNotNull);
    });

    testWidgets('release-versioning: Release build shows its version', (
      tester,
    ) async {
      await _pumpHarness(tester, version: '0.2.0+120');
      final version = find.text('0.2.0+120');
      expect(version, findsOneWidget);
      expect(
        tester.getTopLeft(version).dy,
        lessThan(tester.getTopLeft(_title(SettingsSection.liveScan)).dy),
      );
    });

    testWidgets('release-versioning: Development build', (tester) async {
      await _pumpHarness(tester);
      expect(find.text('dev'), findsOneWidget);
    });
  });

  group('Item and map data', () {
    Future<SettingsRig> rig(
      WidgetTester tester, {
      required GameMode mode,
      bool withPack = true,
      bool selectMapMode = true,
      ControlledMapClient? client,
    }) async {
      final made = (await tester.runAsync(() async {
        final rig = await SettingsRig.create(
          client: client ?? ControlledMapClient(),
        );
        await rig.services.catalog.setMode(mode);
        if (selectMapMode) {
          final settled = rig.whenState(
            (state) =>
                !state.refreshing && (state.failure != null || !withPack),
          );
          unawaited(
            rig.controller.selectMode(
              mode: mode,
              pack: withPack ? settingsPack : null,
            ),
          );
          await settled.future;
        }
        return rig;
      }))!;
      addTearDown(made.close);
      return made;
    }

    OutlinedButton button(WidgetTester tester, String label) => tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));

    testWidgets('settings-page: Refresh map data', (tester) async {
      final client = ControlledMapClient();
      final r = await rig(tester, mode: GameMode.pvp, client: client);
      await _pump(tester, r.services);
      final refresh = find.widgetWithText(OutlinedButton, 'Refresh map data');
      await _show(tester, refresh);
      expect(button(tester, 'Refresh map data').onPressed, isNotNull);
      client.holdMapRequests = true;
      final before = client.mapRequests;

      await tester.runAsync(() async {
        final started = client.whenMapRequests(before + 1);
        await tester.tap(refresh);
        await started.future;
      });
      await tester.pump();

      expect(find.text('Refreshing map data…'), findsWidgets);
      final running = find.widgetWithText(
        OutlinedButton,
        'Refreshing map data…',
      );
      expect(tester.widget<OutlinedButton>(running).onPressed, isNull);

      await tester.runAsync(() async {
        final done = r.whenState((state) => !state.refreshing);
        client.release.complete(http.Response('synthetic unavailable', 503));
        await done.future;
      });
      await tester.pump();

      expect(find.text('Refreshing map data…'), findsNothing);
      expect(button(tester, 'Refresh map data').onPressed, isNotNull);
    });

    testWidgets('settings-page: Unknown mode', (tester) async {
      final r = await rig(tester, mode: GameMode.unknown, selectMapMode: false);
      await _pump(tester, r.services);
      await _show(tester, find.text('Refresh map data'));

      expect(button(tester, 'Refresh item data').onPressed, isNull);
      expect(button(tester, 'Refresh map data').onPressed, isNull);
    });

    testWidgets('settings-page: No map data available', (tester) async {
      final r = await rig(tester, mode: GameMode.pvp, withPack: false);
      expect(r.controller.state.source, LiveMapDataSource.unavailable);
      await _pump(tester, r.services);
      await _show(tester, find.text('Refresh map data'));

      expect(button(tester, 'Refresh map data').onPressed, isNull);
      expect(button(tester, 'Refresh item data').onPressed, isNotNull);
    });

    testWidgets('catalog-authority: Failure shown in the panel', (
      tester,
    ) async {
      final h = await _harness(tester);
      h.failNetwork = true;
      await tester.runAsync(h.services.catalog.refresh);
      expect(h.services.catalog.status, CatalogStatus.stale);
      await _pump(tester, h.services);
      final section = find.byKey(const Key('settings-item-data'));
      await _show(tester, section);

      expect(
        find.descendant(of: section, matching: find.text('Out of date')),
        findsOneWidget,
      );
      final error = find.descendant(
        of: section,
        matching: find.text(
          'Item data could not be downloaded: tarkov.dev answered with an '
          'error. The last item data is still in use.',
        ),
      );
      expect(error, findsOneWidget);
      expect(
        tester.widget<Text>(error).style?.color,
        tester.element(error).ember.errInk,
      );
    });

    testWidgets('catalog-authority: Error cleared by a successful refresh', (
      tester,
    ) async {
      final h = await _harness(tester);
      h.failNetwork = true;
      await tester.runAsync(h.services.catalog.refresh);
      await _pump(tester, h.services);
      final section = find.byKey(const Key('settings-item-data'));
      await _show(tester, section);
      expect(
        find.descendant(
          of: section,
          matching: find.textContaining('Item data could not be'),
        ),
        findsOneWidget,
      );

      h.failNetwork = false;
      await tester.runAsync(h.services.catalog.refresh);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: section, matching: find.text('Up to date')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: section,
          matching: find.textContaining('Item data could not be'),
        ),
        findsNothing,
      );
    });

    testWidgets('settings-page: Map data refresh fails', (tester) async {
      final r = await rig(tester, mode: GameMode.pve);
      expect(r.controller.state.failure, isNotNull);
      await _pump(tester, r.services);
      final section = find.byKey(const Key('settings-item-data'));
      await _show(tester, section);

      expect(
        find.descendant(
          of: section,
          matching: find.textContaining('Map data refresh failed'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: section,
          matching: find.textContaining('keeps the data it had'),
        ),
        findsOneWidget,
      );
      // The raw failure never reaches the page.
      expect(find.textContaining('synthetic map source'), findsNothing);
    });
  });

  group('Tracker progress', () {
    final tokenField = find.widgetWithText(
      TextField,
      'Tracker token (current game mode)',
    );

    testWidgets('settings-page: Save token', (tester) async {
      final h = await _pumpHarness(tester);
      await _show(tester, tokenField);
      expect(tester.widget<TextField>(tokenField).obscureText, isTrue);
      await tester.enterText(tokenField, 'PVP_SYNTHETIC_LOCAL_ONLY');
      await _show(tester, find.text('Save token'));

      await tapM1Async(
        tester,
        find.text('Save token'),
        () => find.text('Tracker token saved').evaluate().isNotEmpty,
      );

      expect(h.credentials.values[GameMode.pvp], 'PVP_SYNTHETIC_LOCAL_ONLY');
      expect(find.text('Saved for PvP'), findsOneWidget);
      expect(tester.widget<TextField>(tokenField).controller!.text, isEmpty);
    });

    testWidgets('settings-page: Token action fails', (tester) async {
      final services = (await tester.runAsync(() async {
        final made = _ThrowingTokenServices(
          database: BlackgridDatabase(NativeDatabase.memory()),
          credentials: MemoryCredentials(),
          client: MockClient((_) async => http.Response('{}', 404)),
        );
        await made.catalog.setMode(GameMode.pvp);
        return made;
      }))!;
      addTearDown(services.dispose);
      await _pump(tester, services);
      await _show(tester, tokenField);
      await tester.enterText(tokenField, 'PVP_SYNTHETIC_LOCAL_ONLY');
      await _show(tester, find.text('Save token'));

      await tester.tap(find.text('Save token'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Tracker token operation failed. Nothing was stored as plain text.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(tokenField).controller!.text, isEmpty);
    });

    testWidgets('settings-page: No mode', (tester) async {
      await _pumpHarness(tester, mode: GameMode.unknown);
      await _show(tester, find.text('Save token'));

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save token'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Remove token'),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('Game files', () {
    testWidgets('settings-page: Save a folder on Enter', (tester) async {
      final h = await _pumpHarness(tester);
      final logsBefore = _settings(h).gameLogDirectory;

      await _typeAndSubmit(
        tester,
        'Screenshot folder',
        'C:/blackgrid-synthetic-missing/screenshots',
      );
      await pumpUntil(
        tester,
        () =>
            _settings(h).screenshotDirectory ==
            'C:/blackgrid-synthetic-missing/screenshots',
      );

      // Only the folder that was typed in changed.
      expect(_settings(h).gameLogDirectory, logsBefore);
      final stored = (await tester.runAsync(h.services.database.readSettings))!;
      expect(
        stored.settings.screenshotDirectory,
        'C:/blackgrid-synthetic-missing/screenshots',
      );
      expect(find.text('Save map files'), findsNothing);
    });

    testWidgets('settings-page: Save on leaving', (tester) async {
      final h = await _pumpHarness(tester);
      final logs = find.widgetWithText(TextField, 'Game log folder');
      await _show(tester, logs);
      await tester.enterText(logs, 'C:/blackgrid-synthetic-missing/logs');

      // Moving to another field commits what was typed.
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(TextField, 'Screenshot folder')),
      );
      await tester.pump();
      await pumpUntil(
        tester,
        () =>
            _settings(h).gameLogDirectory ==
            'C:/blackgrid-synthetic-missing/logs',
      );

      expect(_settings(h).screenshotDirectory, isEmpty);
    });

    testWidgets('settings-page: Save fails', (tester) async {
      final h = await _pumpHarness(tester);
      final before = _settings(h).screenshotDirectory;
      await _breakSettingsSaves(tester, h);

      await _typeAndSubmit(
        tester,
        'Screenshot folder',
        'C:/blackgrid-synthetic-missing/screenshots',
      );
      await pumpUntil(
        tester,
        () => find.text('Not saved. Try again.').evaluate().isNotEmpty,
      );

      final field = find.widgetWithText(TextField, 'Screenshot folder');
      expect(
        tester.widget<TextField>(field).controller!.text,
        'C:/blackgrid-synthetic-missing/screenshots',
      );
      expect(_settings(h).screenshotDirectory, before);
    });

    testWidgets('an empty folder saves as the default location', (
      tester,
    ) async {
      final h = await _pumpHarness(tester);
      await _typeAndSubmit(
        tester,
        'Game log folder',
        'C:/blackgrid-synthetic-missing/logs',
      );
      await pumpUntil(
        tester,
        () =>
            _settings(h).gameLogDirectory ==
            'C:/blackgrid-synthetic-missing/logs',
      );

      await _typeAndSubmit(tester, 'Game log folder', '');
      await pumpUntil(tester, () => _settings(h).gameLogDirectory.isEmpty);
    });

    testWidgets('the flush controller commits a pending edit', (tester) async {
      final flush = SettingsFlushController();
      final h = await _harness(tester);
      await _pump(tester, h.services, flush: flush);
      final field = find.widgetWithText(TextField, 'Screenshot folder');
      await _show(tester, field);
      await tester.enterText(
        field,
        'C:/blackgrid-synthetic-missing/screenshots',
      );

      await tester.runAsync(() async => unawaited(flush.flush()));
      await pumpUntil(
        tester,
        () =>
            _settings(h).screenshotDirectory ==
            'C:/blackgrid-synthetic-missing/screenshots',
      );
    });
  });

  group('reachability', () {
    testWidgets('settings-page: All controls present', (tester) async {
      await _pumpHarness(tester, ports: ScanFakePorts());
      // Open Diagnostics so its toggle sits in the tree with the rest.
      Future<void> present(Finder finder, String what) async {
        expect(finder, findsOneWidget, reason: what);
      }

      await present(find.byType(SegmentedButton<ThemeChoice>), 'theme');
      await present(find.byType(SegmentedButton<GameMode>), 'game mode');
      await present(
        find.widgetWithText(OutlinedButton, 'Refresh item data'),
        'refresh item data',
      );
      await present(
        find.widgetWithText(OutlinedButton, 'Refresh map data'),
        'refresh map data',
      );
      await present(
        find.widgetWithText(TextField, 'Game log folder'),
        'game log folder',
      );
      await present(
        find.widgetWithText(TextField, 'Screenshot folder'),
        'screenshot folder',
      );
      for (final name in [
        'Follow logs',
        'Save marker filters',
        'Show raid timers',
        'Time in raid',
        'Run-through',
        'Scav cooldown',
        'Use Tracker progress',
      ]) {
        await present(_rowNamed(name), name);
      }
      await present(
        find.widgetWithText(TextField, 'Run-through length (m:ss)'),
        'run-through length',
      );
      await present(
        find.widgetWithText(TextField, 'Fence reputation'),
        'fence reputation',
      );
      await present(find.byKey(const Key('live-scan-switch')), 'live scan');
      await present(
        find.byKey(const Key('record-frames-switch')),
        'record scan frames',
      );
      await present(find.byKey(const Key('scan-hotkey-picker')), 'scan key');
      await present(
        find.widgetWithText(TextField, 'Tracker token (current game mode)'),
        'token field',
      );
      await present(
        find.widgetWithText(FilledButton, 'Save token'),
        'save token',
      );
      await present(
        find.widgetWithText(OutlinedButton, 'Remove token'),
        'remove token',
      );
      await present(
        find.widgetWithText(OutlinedButton, 'Refresh progress'),
        'refresh progress',
      );
      await present(
        find.byKey(const Key('settings-diagnostics-toggle')),
        'diagnostics',
      );
      // The ink-only switch is the only switch on the page.
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      // The keys other screens and tests use are kept.
      for (final key in [
        'settings-item-data',
        'settings-live-scan',
        'settings-tracker',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
    });
  });
}
