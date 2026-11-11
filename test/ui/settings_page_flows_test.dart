import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/ember/ember_toggle_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/m1_widget_harness.dart';
import '../support/raid_timer_support.dart';
import 'support/scan_ui_support.dart';

import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/settings/settings_page.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_failure.dart';
import 'package:blackgrid/data/scan_frame_recorder.dart';

import 'dart:async';
import 'dart:io';

/// Opens the Settings page from the top bar.
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Settings'));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsPage), findsOneWidget);
}

/// Whether the switch row [row] is on.
bool _on(WidgetTester tester, Finder row) => tester
    .widget<EmberToggleSwitch>(
      find.descendant(of: row, matching: find.byType(EmberToggleSwitch)),
    )
    .on;

/// The press handler of the switch row [row], or `null` while it is disabled.
VoidCallback? _tap(WidgetTester tester, Finder row) => tester
    .widget<InkWell>(
      find.descendant(of: row, matching: find.byType(InkWell)).first,
    )
    .onTap;

void main() {
  testWidgets('scanner-evidence: Setting cannot be saved', (tester) async {
    final h = await pumpM1(tester, scanPorts: ScanFakePorts());
    await tester.runAsync(
      () => h.db.customStatement(
        "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      ),
    );
    await _openSettings(tester);
    final toggle = find.descendant(
      of: find.byKey(const Key('settings-live-scan')),
      matching: find.byKey(const Key('live-scan-switch')),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tapM1Async(tester, toggle, () => h.services.scanner.error != null);
    expect(_on(tester, toggle), isFalse);
    expect(h.services.scanner.status.state, LiveScanState.off);
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-live-scan')),
        matching: find.textContaining('preference was not saved'),
      ),
      findsOneWidget,
    );
  });
  testWidgets('scanner-evidence: Setting cannot be saved when switching off', (
    tester,
  ) async {
    final h = await pumpM1(tester, scanPorts: ScanFakePorts());
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
    });
    await tester.runAsync(
      () => h.db.customStatement(
        "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      ),
    );
    await _openSettings(tester);
    final toggle = find.descendant(
      of: find.byKey(const Key('settings-live-scan')),
      matching: find.byKey(const Key('live-scan-switch')),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tapM1Async(tester, toggle, () => h.services.scanner.error != null);
    expect(_on(tester, toggle), isFalse);
    expect(h.services.scanner.status.state, LiveScanState.off);
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-live-scan')),
        matching: find.textContaining('preference was not saved'),
      ),
      findsOneWidget,
    );
  });
  testWidgets('scanner-evidence: Registered hotkey', (tester) async {
    final h = await pumpM1(tester, scanPorts: ScanFakePorts());
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
    });
    await _openSettings(tester);
    final panel = find.byKey(const Key('settings-live-scan'));
    final picker = find.descendant(
      of: panel,
      matching: find.byKey(const Key('scan-hotkey-picker')),
    );
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DropdownButton<ScanHotkey>>(picker).value,
      ScanHotkey.f9,
    );
    expect(find.textContaining('F9 scans at the cursor'), findsOneWidget);
  });
  testWidgets('scanner-evidence: Hotkey held by another application', (
    tester,
  ) async {
    final ports = ScanFakePorts()..heldKeys.add(ScanHotkey.f9);
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
    });
    await _openSettings(tester);
    final picker = find.descendant(
      of: find.byKey(const Key('settings-live-scan')),
      matching: find.byKey(const Key('scan-hotkey-picker')),
    );
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    expect(find.textContaining('mouse scans still work'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-live-scan')),
        matching: find.textContaining('Win32 error 1409'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<DropdownButton<ScanHotkey>>(picker).onChanged,
      isNotNull,
    );
  });
  testWidgets('scanner-evidence: Live scan starting', (tester) async {
    final gate = Completer<InspectionTemplatesResult>();
    final ports = ScanFakePorts()..markerGate = gate.future;
    final h = await pumpM1(tester, scanPorts: ports);
    await _openSettings(tester);
    final panel = find.byKey(const Key('settings-live-scan'));
    final toggle = find.descendant(
      of: panel,
      matching: find.byKey(const Key('live-scan-switch')),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tapM1Async(
      tester,
      toggle,
      () => h.services.scanner.status.state == LiveScanState.starting,
    );
    final picker = find.descendant(
      of: panel,
      matching: find.byKey(const Key('scan-hotkey-picker')),
    );
    expect(tester.widget<DropdownButton<ScanHotkey>>(picker).onChanged, isNull);
    gate.complete(await ports.markerLoader(''));
    await tester.runAsync(() => h.services.scanner.settled);
  });
  testWidgets('scanner-evidence: Recording runs', (tester) async {
    final root = Directory.systemTemp.createTempSync(
      'blackgrid-answer-strip-recording-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final writers = <FakeRecordWriter>[];
    final recorder = ScanFrameRecorder(
      root: root.path,
      writerFactory:
          ({required folder, required token, required onAnswer}) async {
            final writer = FakeRecordWriter(token, onAnswer);
            writers.add(writer);
            return writer;
          },
    );
    final h = await pumpM1(
      tester,
      scanPorts: ScanFakePorts(),
      scanFrameRecorder: recorder,
    );
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
    });
    await _openSettings(tester);
    final panel = find.byKey(const Key('settings-live-scan'));
    final toggle = find.descendant(
      of: panel,
      matching: find.byKey(const Key('record-frames-switch')),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tapM1Async(
      tester,
      toggle,
      () => recorder.status.value.state == ScanRecordingState.on,
    );
    for (var n = 1; n <= 12; n++) {
      recorder.record(recordedScan('s$n'));
      writers.single.ack('s$n');
    }
    recorder.record(recordedScan('s13'));
    recorder.record(recordedScan('s14'));
    recorder.record(recordedScan('s15'));
    await tester.pump();
    final status = tester
        .widget<Text>(find.byKey(const Key('record-frames-status')))
        .data!;
    expect(status, contains('12 written'));
    expect(status, contains('1 dropped'));
    expect(status, contains(recorder.status.value.folder!));
  });
  testWidgets('scanner-evidence: Switching on from Scanner', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await _openSettings(tester);
    final target = find.byKey(const Key('settings-live-scan'));
    expect(target, findsOneWidget);
    final toggle = find.descendant(
      of: target,
      matching: find.byKey(const Key('live-scan-switch')),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tapM1Async(
      tester,
      toggle,
      () => h.services.scanner.status.state == LiveScanState.ready,
    );
    expect(h.services.scanner.status.state, LiveScanState.ready);
    expect(_on(tester, toggle), isTrue);
    expect(find.text('Live scan is ready'), findsOneWidget);
  });
  testWidgets('scanner-evidence: Unavailable runtime', (tester) async {
    final ports = ScanFakePorts()
      ..markerOverride = const InspectionTemplatesUnavailable(
        VisionMissingFile('synthetic-missing.pgm'),
      );
    final h = await pumpM1(tester, scanPorts: ports);
    await _openSettings(tester);
    final target = find.byKey(const Key('settings-live-scan'));
    expect(target, findsOneWidget);
    final toggle = find.descendant(
      of: target,
      matching: find.byKey(const Key('live-scan-switch')),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tapM1Async(
      tester,
      toggle,
      () => h.services.scanner.status.state == LiveScanState.unavailable,
    );
    expect(_on(tester, toggle), isTrue);
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-live-scan')),
        matching: find.textContaining('synthetic-missing.pgm'),
      ),
      findsOneWidget,
    );
  });
  testWidgets('scanner-evidence: Live scan off', (tester) async {
    await pumpM1(tester, scanPorts: ScanFakePorts());
    await _openSettings(tester);
    final target = find.byKey(const Key('settings-live-scan'));
    expect(target, findsOneWidget);
    final picker = find.descendant(
      of: target,
      matching: find.byKey(const Key('scan-hotkey-picker')),
    );
    await tester.ensureVisible(picker);
    expect(
      tester.widget<DropdownButton<ScanHotkey>>(picker).value,
      ScanHotkey.f9,
    );
    expect(
      tester.widget<DropdownButton<ScanHotkey>>(picker).onChanged,
      isNotNull,
    );
    expect(find.textContaining('while live scan is on'), findsOneWidget);
  });
  testWidgets('scanner-evidence: Live scan not ready', (tester) async {
    final gate = Completer<InspectionTemplatesResult>();
    final ports = ScanFakePorts()..markerGate = gate.future;
    final h = await pumpM1(tester, scanPorts: ports);
    await _openSettings(tester);
    final target = find.byKey(const Key('settings-live-scan'));
    expect(target, findsOneWidget);
    final record = find.descendant(
      of: target,
      matching: find.byKey(const Key('record-frames-switch')),
    );
    await tester.ensureVisible(record);
    expect(_on(tester, record), isFalse);
    expect(_tap(tester, record), isNull);
    final toggle = find.descendant(
      of: target,
      matching: find.byKey(const Key('live-scan-switch')),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tapM1Async(
      tester,
      toggle,
      () => h.services.scanner.status.state == LiveScanState.starting,
    );
    expect(_on(tester, record), isFalse);
    expect(_tap(tester, record), isNull);
    gate.complete(
      const InspectionTemplatesUnavailable(
        VisionMissingFile('synthetic-missing.pgm'),
      ),
    );
    await tester.runAsync(() => h.services.scanner.settled);
    await tester.pumpAndSettle();
    expect(h.services.scanner.status.state, LiveScanState.unavailable);
    expect(_on(tester, record), isFalse);
    expect(_tap(tester, record), isNull);
  });
  testWidgets(
    'Map file inputs persist independently of the Follow logs preference',
    (tester) async {
      final h = await pumpM1(tester);
      await _openSettings(tester);
      final settings = h.services.settings;
      Future<void> commit(
        String label,
        String text,
        bool Function() saved,
      ) async {
        final field = find.widgetWithText(TextField, label);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, text);
        // A saved folder binds watchers, so the commit starts in the real zone.
        await tester.runAsync(
          () => tester.testTextInput.receiveAction(TextInputAction.done),
        );
        await tester.pump();
        await pumpUntil(tester, saved);
      }

      await commit(
        'Game log folder',
        ' C:/blackgrid-synthetic-missing/logs ',
        () =>
            settings.settings.gameLogDirectory ==
            'C:/blackgrid-synthetic-missing/logs',
      );
      await commit(
        'Screenshot folder',
        ' C:/blackgrid-synthetic-missing/screenshots ',
        () =>
            settings.settings.screenshotDirectory ==
            'C:/blackgrid-synthetic-missing/screenshots',
      );
      final follow = find.text('Follow logs');
      await tester.ensureVisible(follow);
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        follow,
        () => !h.services.settings.settings.followGameLogs,
      );
      final persisted = (await tester.runAsync(
        () => h.services.database.readSettings(),
      ))!.settings;
      expect(persisted.gameLogDirectory, 'C:/blackgrid-synthetic-missing/logs');
      expect(
        persisted.screenshotDirectory,
        'C:/blackgrid-synthetic-missing/screenshots',
      );
      expect(persisted.followGameLogs, isFalse);
      expect(
        h.services.settings.settings.gameLogDirectory,
        persisted.gameLogDirectory,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'configuration masks active-mode token saves and removes through controller',
    (tester) async {
      final h = await pumpM1(tester);
      await _openSettings(tester);
      final field = find.widgetWithText(
        TextField,
        'Tracker token (current game mode)',
      );
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'PVP_SYNTHETIC_LOCAL_ONLY');
      await tester.ensureVisible(find.text('Save token'));
      await tester.pumpAndSettle();
      await tapM1Async(
        tester,
        find.text('Save token'),
        () => find.text('Tracker token saved').evaluate().isNotEmpty,
      );
      expect(h.credentials.values[GameMode.pvp], 'PVP_SYNTHETIC_LOCAL_ONLY');
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(find.text('Tracker token saved'), findsOneWidget);
      await tapM1Async(
        tester,
        find.text('Remove token'),
        () => h.credentials.values[GameMode.pvp] == null,
      );
      expect(h.credentials.values[GameMode.pvp], isNull);
      expect(h.services.progress.snapshot, isNull);
    },
  );
  testWidgets(
    'mode and catalog refresh configuration are working supporting controls',
    (tester) async {
      final h = await pumpM1(tester);
      await _openSettings(tester);
      await tapM1Async(
        tester,
        find.descendant(
          of: find.byType(SegmentedButton<GameMode>),
          matching: find.text('PvE'),
        ),
        () =>
            h.services.catalog.mode == GameMode.pve &&
            !h.services.catalog.loading,
      );
      expect(h.services.catalog.mode, GameMode.pve);
      await tapM1Async(
        tester,
        find.widgetWithText(OutlinedButton, 'Refresh item data'),
        () =>
            h.services.catalog.snapshot?.mode == GameMode.pve &&
            !h.services.catalog.loading,
      );
      expect(h.services.catalog.snapshot?.mode, GameMode.pve);
      expect(h.requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
