import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:blackgrid/ui/app_logo.dart';

import '../support/m1_harness.dart';
import '../fixtures/m1/catalog/fixture.dart' show fixtureNow, progressWire;

import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_failure.dart';
import 'package:blackgrid/ui/scan_evidence_panel.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:blackgrid/ui/panels.dart';
import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/verdict_reason.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/answer_strip.dart';
import 'package:blackgrid/ui/map_workspace.dart';
import 'package:blackgrid/ui/shell.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/vision/inspection_evidence.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';

import 'dart:async';

import 'package:flutter/services.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';

import '../support/m1_widget_harness.dart';
import '../support/map_widget_harness.dart';
import 'support/scan_ui_support.dart';

class _HeldCatalogDatabase extends BlackgridDatabase {
  _HeldCatalogDatabase() : super(NativeDatabase.memory());
  Completer<void>? gate;
  final entered = Completer<void>();

  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async {
    if (gate case final held?) {
      entered.complete();
      await held.future;
      gate = null;
    }
    return super.loadCatalog(mode);
  }
}

void main() {
  testWidgets('one shared FIR selector stays visible in both workspaces', (
    tester,
  ) async {
    final h = await pumpM1(tester);
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.pumpAndSettle();
    for (final area in ['nav-map', 'nav-scanner']) {
      await tester.tap(find.byKey(Key(area)));
      await tester.pumpAndSettle();
      expect(find.byType(FirControls), findsOneWidget);
    }
  });

  for (final room in [Brightness.dark, Brightness.light]) {
    testWidgets('inspector at scale two in $room', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = room;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final h = await pumpM1(tester, size: const Size(960, 720), scale: 2);
      await tester.runAsync(
        () => h.services.selection.selectManual(
          h.services.catalog.snapshot!.items['item-a']!,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shell-inspector')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [
    const Size(1660, 870),
    const Size(1100, 720),
    const Size(900, 720),
  ]) {
    testWidgets(
      size.width == 1660
          ? 'scanner-evidence: Desktop window'
          : size.width == 1100
          ? 'scanner-evidence: Short desktop window'
          : 'scanner-evidence: Narrow window',
      (tester) async {
        await pumpM1(tester, size: size);
        await tester.tap(find.byKey(const Key('nav-scanner')));
        await tester.pumpAndSettle();
        final evidence = find.byType(ScanEvidencePanel);
        expect(evidence, findsOneWidget);
        expect(
          tester.getTopLeft(evidence).dy,
          greaterThanOrEqualTo(
            tester.getBottomLeft(find.byKey(const Key('answer-strip'))).dy,
          ),
        );
        if (size.width >= 1100) {
          expect(
            tester.getBottomRight(evidence).dy,
            lessThanOrEqualTo(size.height),
          );
          final scroller = find
              .descendant(
                of: find.byKey(const PageStorageKey('scanner-desktop-scroll')),
                matching: find.byType(Scrollable),
              )
              .first;
          expect(
            tester.state<ScrollableState>(scroller).position.maxScrollExtent,
            0,
          );
        }
      },
    );
  }
  testWidgets('workspace-shell: Docked details', (tester) async {
    await pumpM1(tester, size: const Size(1660, 870));
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-inspector')), findsOneWidget);
    expect(find.byKey(const Key('inspector-scrim')), findsNothing);
    expect(find.byKey(const PageStorageKey('map')), findsOneWidget);
  });

  for (final width in [1080.0, 1081.0]) {
    for (final room in [Brightness.dark, Brightness.light]) {
      testWidgets('inspector boundary $width in $room', (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = room;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pumpM1(tester, size: Size(width, 720));
        await tester.tap(find.byKey(const Key('inspector-toggle')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('inspector-scrim')),
          width == 1080 ? findsOneWidget : findsNothing,
        );
        expect(find.byKey(const Key('shell-inspector')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('workspace-shell: Resize with open details', (tester) async {
    final h = await pumpMapFixture(tester, size: const Size(1660, 870));
    final map = tester.element(find.byKey(const PageStorageKey('map')));
    final workspace = tester.element(find.byType(MapWorkspace));
    final before = h.services.maps.transform;
    h.services.maps.panBy(23, 17);
    final pan = h.services.maps.transform;
    expect(pan.translationX, before.translationX + 23);
    expect(pan.translationY, before.translationY + 17);
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    final inspector = find.byKey(const Key('shell-inspector'));
    final inspectorScroll = find
        .descendant(of: inspector, matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(inspectorScroll).position.jumpTo(800);
    await tester.pumpAndSettle();
    final source = find.byType(SourcePanel);
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();
    final details = find.descendant(of: source, matching: find.text('Details'));
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.textContaining('Data is treated as old after'), findsOneWidget);
    tester.view.physicalSize = const Size(960, 720);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inspector-scrim')), findsOneWidget);
    expect(tester.element(find.byKey(const PageStorageKey('map'))), same(map));
    expect(tester.element(find.byType(MapWorkspace)), same(workspace));
    expect(h.services.maps.transform.scale, pan.scale);
    expect(h.services.maps.transform.translationX, pan.translationX);
    expect(h.services.maps.transform.translationY, pan.translationY);
    expect(find.textContaining('Data is treated as old after'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-inspector')), findsNothing);
    expect(tester.element(find.byKey(const PageStorageKey('map'))), same(map));
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('inspector-toggle')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
  });

  testWidgets(
    'inspector respects reduced motion and uses panel motion otherwise',
    (tester) async {
      final h = await pumpM1(tester, size: const Size(960, 720));
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
      final animated = find.ancestor(
        of: find.byKey(const Key('shell-inspector')),
        matching: find.byType(AnimatedPositioned),
      );
      expect(
        tester.widget<AnimatedPositioned>(animated).duration,
        EmberMotion.panel,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(960, 720),
              disableAnimations: true,
            ),
            child: BlackgridShell(services: h.services),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pump();
      expect(
        tester.widget<AnimatedPositioned>(animated).duration,
        Duration.zero,
      );
    },
  );
  testWidgets(
    'top-bar inspector toggle opens and closes details without replacing the workspace',
    (tester) async {
      final h = await pumpM1(tester);
      await tester.runAsync(
        () => h.services.selection.selectManual(
          h.services.catalog.snapshot!.items['item-a']!,
        ),
      );
      await tester.pumpAndSettle();
      final map = find.byKey(const PageStorageKey('map'));
      expect(map, findsOneWidget);
      final before = tester.element(map);
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shell-inspector')), findsOneWidget);
      expect(tester.element(map), same(before));
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shell-inspector')), findsNothing);
      expect(tester.element(map), same(before));
    },
  );
  testWidgets('long catalog reason wraps fully inside the shared strip', (
    tester,
  ) async {
    const token = 'PVP_synthetic-fixture-only';
    final longName = '${'Long task name ' * 5}end'.padRight(80, 'x');
    tester.view.physicalSize = const Size(960, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final h = (await tester.runAsync(() async {
      final result = M1Harness(
        shapeWire: (wire) {
          wire['tasks_en'] = {
            'data': {'task-a name': longName},
          };
          wire['token'] = {
            'success': true,
            'permissions': ['GP'],
            'token': token,
            'owner': 'synthetic-owner',
            'note': 'Synthetic',
            'calls': 0,
            'gameMode': 'pvp',
          };
          wire['progress'] = progressWire();
        },
      );
      result.credentials.values[GameMode.pvp] = token;
      await result.initialize();
      await result.services.progress.refresh();
      await result.services.selection.selectManual(
        result.services.catalog.snapshot!.items['item-a']!,
      );
      result.services.selection.setFir(FirState.yes);
      return result;
    }))!;
    addTearDown(h.dispose);
    await tester.pumpWidget(BlackgridApp(services: h.services));
    await tester.pumpAndSettle();
    final strip = find.byKey(const Key('answer-strip'));
    final reason = find.descendant(
      of: strip,
      matching: find.byKey(const Key('answer-verdict-reason')),
    );
    final text = tester.widget<Text>(reason);
    expect(text.data, contains(longName));
    expect(text.data, verdictReason(h.services.selection.decision!));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    final paragraph = tester.renderObject<RenderParagraph>(reason);
    expect(paragraph.didExceedMaxLines, isFalse);
    final lines = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.data!.length),
        )
        .map((box) => box.top.round())
        .toSet();
    expect(lines.length, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('search accepts Ctrl K and picks the first result', (
    tester,
  ) async {
    final h = await pumpM1(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final search = find.widgetWithText(TextField, 'Search items…');
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    await tester.enterText(search, 'item-a');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(h.services.selection.selectedId, 'item-a');
  });
  testWidgets(
    'answer strip presents history loading while a different mode loads',
    (tester) async {
      final db = _HeldCatalogDatabase();
      final h = await pumpM1(tester, database: db);
      final gate = db.gate = Completer<void>();
      final row = ItemActivity(
        itemId: 'item-a',
        mode: GameMode.pve,
        source: ActivitySource.manual,
        observedAt: fixtureNow,
        revision: 1,
      );
      late Future<void> opening;
      await tester.runAsync(() async {
        opening = h.services.selection.openHistory(row);
        await db.entered.future;
      });
      await tester.pump();
      final strip = find.byKey(const Key('answer-strip'));
      expect(
        find.descendant(
          of: strip,
          matching: find.text('Opening saved item data…'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: strip,
          matching: find.byKey(const Key('verdict-plate')),
        ),
        findsNothing,
      );
      gate.complete();
      await tester.runAsync(() => opening);
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'answer strip renders all six verdicts and a full long reason in both rooms',
    (tester) async {
      final requirement = ItemRequirement(
        kind: RequirementKind.task,
        sourceId: 'task',
        sourceName: List.filled(24, 'A long task name').join(' '),
        id: 'need',
        itemIds: ['item-a'],
        progressIds: [],
        gate: RequirementGate(),
      );
      for (final room in [Brightness.dark, Brightness.light]) {
        for (final recommendation in Recommendation.values) {
          final decision = ItemDecision(
            recommendation: recommendation,
            reasons: [
              NeedReason(
                requirement: requirement,
                state: NeedState.actionable,
                message: '',
                detail: '',
                remaining: 3,
              ),
            ],
            warnings: const [],
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: blackgridTheme(room),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: SizedBox(
                      width: 300,
                      child: AnswerVerdict(decision: decision, maxWidth: 300),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(recommendationLabel(recommendation)),
            findsOneWidget,
          );
          final reason = tester.widget<Text>(
            find.byKey(const Key('answer-verdict-reason')),
          );
          expect(reason.data, verdictReason(decision));
          expect(reason.maxLines, isNull);
          expect(reason.overflow, isNull);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
  testWidgets('workspace-shell: Failed live scan save', (tester) async {
    final h = await pumpM1(tester, scanPorts: ScanFakePorts());
    await tester.runAsync(
      () => h.db.customStatement(
        "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      ),
    );
    await tapM1Async(
      tester,
      find.byKey(const Key('status-live-scan')),
      () => h.services.scanner.error != null,
    );
    expect(h.services.scanner.switchOn, isFalse);
    expect(h.services.scanner.status.state, LiveScanState.off);
    expect(find.byKey(const Key('status-live-scan-error')), findsOneWidget);
    await tester.runAsync(
      () => h.db.customStatement('DROP TRIGGER preference_failure'),
    );
    await tapM1Async(
      tester,
      find.byKey(const Key('status-live-scan')),
      () => h.services.scanner.status.state == LiveScanState.ready,
    );
    await tester.runAsync(
      () => h.db.customStatement(
        "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      ),
    );
    await tapM1Async(
      tester,
      find.byKey(const Key('status-live-scan')),
      () => h.services.scanner.error != null,
    );
    expect(h.services.scanner.switchOn, isFalse);
    expect(h.services.scanner.status.state, LiveScanState.off);
    expect(find.textContaining('preference was not saved'), findsWidgets);
  });
  testWidgets('scanner-evidence: Write failure', (tester) async {
    final root = Directory.systemTemp.createTempSync(
      'blackgrid-answer-strip-failure-',
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
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
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
    recorder.record(recordedScan('failure'));
    writers.single.fail('failure', 'synthetic disk failure');
    await tester.pump();
    final folder = recorder.status.value.folder!;
    expect(
      find.descendant(
        of: panel,
        matching: find.textContaining('synthetic disk failure'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.textContaining(folder)),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recording-stop-note')), findsOneWidget);
    expect(find.textContaining('synthetic disk failure'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-live-scan')),
        matching: find.textContaining(folder),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-live-scan')),
        matching: find.textContaining('synthetic disk failure'),
      ),
      findsOneWidget,
    );
  });
  testWidgets('workspace-shell: Settings targets', (tester) async {
    await pumpM1(tester);
    await tester.tap(find.byKey(const Key('status-item-data')));
    await tester.pumpAndSettle();
    final itemTarget = find.byKey(const Key('settings-item-data'));
    expect(itemTarget, findsOneWidget);
    expect(
      tester.getTopLeft(itemTarget).dy,
      greaterThanOrEqualTo(tester.getTopLeft(find.byType(AlertDialog)).dy),
    );
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('status-tracker')));
    await tester.pumpAndSettle();
    final trackerTarget = find.byKey(const Key('settings-tracker'));
    expect(trackerTarget, findsOneWidget);
    expect(
      tester.getTopLeft(trackerTarget).dy,
      lessThan(tester.getBottomLeft(find.byType(AlertDialog)).dy),
    );
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
  });
  for (final size in [
    const Size(1660, 870),
    const Size(1100, 720),
    const Size(960, 720),
    const Size(900, 720),
  ]) {
    for (final room in [Brightness.dark, Brightness.light]) {
      testWidgets('workspace-shell: Answer first in both areas $size $room', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = room;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final h = await pumpM1(tester, size: size);
        final item = h.services.catalog.snapshot!.items['item-a']!;
        await tester.runAsync(() => h.services.selection.selectManual(item));
        await tester.pumpAndSettle();
        final expected = h.services.selection.decision!;
        for (final area in ['nav-map', 'nav-scanner']) {
          await tester.tap(find.byKey(Key(area)));
          await tester.pumpAndSettle();
          final strip = find.byKey(const Key('answer-strip'));
          expect(strip, findsOneWidget);
          expect(
            tester.getTopLeft(strip).dy,
            tester.getBottomLeft(find.byKey(const Key('shell-top-bar'))).dy,
          );
          expect(tester.getBottomLeft(strip).dy, lessThan(size.height));
          expect(
            find.descendant(of: strip, matching: find.text(item.name)),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: strip,
              matching: find.text(recommendationLabel(expected.recommendation)),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: strip,
              matching: find.text(verdictReason(expected)),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: strip,
              matching: find.byKey(const Key('verdict-plate')),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: strip, matching: find.text('Found in raid')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: strip, matching: find.text('item-a')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
  testWidgets('workspace-shell: Missing item and long reason', (tester) async {
    final h = await pumpM1(tester, size: const Size(960, 720), scale: 2);
    final strip = find.byKey(const Key('answer-strip'));
    expect(
      find.descendant(of: strip, matching: find.text('Find an item')),
      findsOneWidget,
    );
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: strip,
        matching: find.byKey(const Key('answer-verdict-reason')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('workspace-shell: Selection changes across areas', (
    tester,
  ) async {
    final h = await pumpM1(tester);
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.pumpAndSettle();
    final strip = find.byKey(const Key('answer-strip'));
    final yes = find.descendant(of: strip, matching: find.text('Yes'));
    await tester.tap(yes);
    await tester.pumpAndSettle();
    expect(h.services.selection.fir, FirState.yes);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(
            find.ancestor(of: yes, matching: find.byType(ChoiceChip)),
          )
          .selected,
      isTrue,
    );
    expect(h.services.selection.fir, FirState.yes);
  });
  testWidgets('workspace-shell: History and later rejected scan', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
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
    final historyRow = h.services.history.rows.firstWhere(
      (r) => r.itemId == 'item-a',
    );
    await tester.runAsync(() => h.services.selection.openHistory(historyRow));
    await tester.pumpAndSettle();
    expect(h.services.selection.isHistory, isTrue);
    await tester.runAsync(() async {
      ports.fire(2000);
      await ports.captureOk(1);
      await ports.visionDeliver(
        1,
        scanRecognised(InspectionFrameKind.targeted, []),
      );
      await ports.captureOk(2);
      await ports.visionDeliver(
        2,
        scanRecognised(InspectionFrameKind.fullClient, []),
      );
      await reportPublished(h.services.scanner, 2);
    });
    await tester.pumpAndSettle();
    expect(h.services.selection.isHistory, isTrue);
    expect(h.services.selection.selectedId, 'item-a');
    expect(h.services.scans.latest, accepted);
    final strip = find.byKey(const Key('answer-strip'));
    await tester.tap(
      find.descendant(
        of: strip,
        matching: find.byTooltip('Close history inspection'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: strip, matching: find.text('Back to latest scan')),
    );
    await tester.pumpAndSettle();
    expect(h.services.selection.selectedId, accepted!.itemId);
  });
  testWidgets('workspace-shell: Wide navigation', (tester) async {
    final h = await pumpM1(tester, size: const Size(1660, 870));
    final bar = find.byKey(const Key('shell-top-bar'));
    expect(tester.getSize(bar).height, 44);
    expect(
      find.descendant(of: bar, matching: find.text('Settings')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.text('Stats')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.text('Import')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bar,
        matching: find.byKey(const Key('raid-timer-strip')),
      ),
      findsOneWidget,
    );
    expect(h.services.raidTimers.view.entries, hasLength(3));
    for (final entry in h.services.raidTimers.view.entries) {
      expect(
        find.descendant(of: bar, matching: find.text(entry.text)),
        findsOneWidget,
      );
    }
  });
  testWidgets('workspace-shell: Narrow navigation and disabled timers', (
    tester,
  ) async {
    final h = await pumpM1(tester, size: const Size(960, 720), scale: 2);
    await tester.runAsync(
      () => h.services.settings.setRaidTimers(
        h.services.settings.raidTimers.copyWith(showRunThrough: false),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.byKey(const Key('shell-top-bar'));
    expect(h.services.raidTimers.view.entries, hasLength(2));
    for (final entry in h.services.raidTimers.view.entries) {
      expect(
        find.descendant(of: bar, matching: find.text(entry.text)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: bar, matching: find.textContaining('Run-through')),
      findsNothing,
    );
    expect(find.byKey(const Key('shell-top-bar')), findsOneWidget);
    expect(find.byTooltip('Settings'), findsWidgets);
    expect(find.byTooltip('Stats'), findsWidgets);
    expect(find.byTooltip('Import'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(1672, 941),
    const Size(1912, 823),
    const Size(960, 640),
  ]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      testWidgets(
        'two retained surfaces avoid overflow at $size scale $scale',
        (tester) async {
          await pumpM1(tester, size: size, scale: scale);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('nav-scanner')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Live scan off • no capture'), findsOneWidget);
          expect(find.text('Scanner Ready'), findsNothing);
          expect(find.text('Auto-scan'), findsNothing);
          expect(find.text('Capture Preview'), findsNothing);
          expect(find.text('High confidence'), findsNothing);
        },
      );
    }
  }
  testWidgets('Scanner places evidence beside controls below the answer', (
    tester,
  ) async {
    await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    Rect panel(String title) => tester.getRect(
      find.byWidgetPredicate((w) => w is GridPanel && w.title == title),
    );
    final left = panel('Scanner'), evidence = panel('Scan evidence');
    expect(left.left, 14);
    expect(evidence.left, greaterThan(left.right));
    expect(evidence.top, left.top);
    expect(find.text('Picked item'), findsNothing);
    expect(find.text('Recent item activity'), findsNothing);
    expect(
      Theme.of(tester.element(find.byKey(const Key('nav-map'))))
          .scaffoldBackgroundColor,
      Theme.of(tester.element(find.byKey(const Key('nav-map'))))
          .extension<EmberColors>()!
          .canvas,
    );
  });
  testWidgets('scan evidence survives Map and back', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => publishTargetedScan(
        h.services.scanner,
        ports,
        text: 'Alternative component',
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.widget<Text>(find.byKey(const Key('scan-item'))).data;
    expect(before, contains('Alternative component'));

    await tester.tap(find.byKey(const Key('nav-map')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('scan-item'))).data,
      before,
    );
    // The end state now lives inside the collapsed Details section.
    expect(find.byKey(const Key('scan-end')), findsNothing);
  });
  testWidgets('scan evidence Details stays expanded across Map and back', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => publishTargetedScan(
        h.services.scanner,
        ports,
        text: 'Alternative component',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ScanEvidencePanel),
        matching: find.text('Details'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-marker')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-map')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan-marker')), findsOneWidget);
    expect(find.byKey(const Key('scan-timing-total')), findsOneWidget);
  });
  for (final size in [const Size(1672, 941), const Size(960, 640)]) {
    testWidgets('scan evidence panel does not overflow at $size', (
      tester,
    ) async {
      final ports = ScanFakePorts();
      final h = await pumpM1(tester, size: size, scale: 1.5, scanPorts: ports);
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => publishTargetedScan(
          h.services.scanner,
          ports,
          text: 'Alternative component',
        ),
      );
      await tester.pumpAndSettle();
      // The compact layout puts evidence first; it is already on screen.
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('scan-item')), findsOneWidget);
    });
  }

  Future<void> openScanner(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
  }

  Rect evidenceFrame(WidgetTester tester) => tester.getRect(
    find.byWidgetPredicate((w) => w is GridPanel && w.title == 'Scan evidence'),
  );

  ScrollPosition desktopPage(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const PageStorageKey('scanner-desktop-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets('scan evidence panel is fully on screen at 1660x870', (
    tester,
  ) async {
    await pumpM1(tester, size: const Size(1660, 870));
    await openScanner(tester);
    final frame = evidenceFrame(tester);
    expect(frame.top, greaterThanOrEqualTo(0));
    expect(frame.bottom, lessThanOrEqualTo(870));
    expect(frame.left, greaterThanOrEqualTo(0));
    expect(frame.right, lessThanOrEqualTo(1660));
    // The page has nothing to scroll at this size.
    expect(desktopPage(tester).maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scan evidence panel is on screen at 1100x720 with a long recent list',
    (tester) async {
      final ports = ScanFakePorts();
      final h = await pumpM1(
        tester,
        size: const Size(1100, 720),
        scanPorts: ports,
      );
      await openScanner(tester);
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await publishTargetedScan(
            h.services.scanner,
            ports,
            text: 'Alternative component $i',
            index: i,
            qpc: 1000 * (i + 1),
          );
        }
      });
      await tester.pumpAndSettle();
      expect(h.services.scanner.recent, hasLength(10));
      // Desktop layout, read with the page unscrolled.
      expect(desktopPage(tester).pixels, 0);
      final frame = evidenceFrame(tester);
      final scannerPanel = tester.getRect(
        find.byWidgetPredicate((w) => w is GridPanel && w.title == 'Scanner'),
      );
      expect(frame.left, greaterThan(scannerPanel.right));
      expect(frame.top, greaterThanOrEqualTo(0));
      expect(frame.bottom, lessThanOrEqualTo(720));
      // Expand detail evidence so the combined contents exceed the frame.
      await tester.tap(
        find.descendant(
          of: find.byType(ScanEvidencePanel),
          matching: find.text('Details'),
        ),
      );
      await tester.pumpAndSettle();
      // The evidence list scrolls inside its fixed frame.
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ScanEvidencePanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact layout puts evidence before Scanner controls', (
    tester,
  ) async {
    await pumpM1(tester, size: const Size(900, 1600));
    await openScanner(tester);
    final scanner = tester.getRect(
      find.byWidgetPredicate((w) => w is GridPanel && w.title == 'Scanner'),
    );
    final evidence = evidenceFrame(tester);
    expect(scanner.top, evidence.bottom + 14);
    expect(evidence.left, scanner.left);
  });

  Finder footer(String text) => find.text(text);

  testWidgets('footer says live scan is on when ready', (tester) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
    });
    await tester.pumpAndSettle();
    expect(h.services.scanner.status.state, LiveScanState.ready);
    expect(footer('Live scan on • captures on click'), findsOneWidget);
    expect(find.textContaining('No capture'), findsNothing);
  });

  testWidgets('footer says live scan is off and nothing is captured', (
    tester,
  ) async {
    await pumpM1(tester);
    expect(footer('Live scan off • no capture'), findsOneWidget);
  });

  testWidgets('footer says live scan is unavailable', (tester) async {
    final ports = ScanFakePorts()
      ..markerOverride = const MarkerTemplateUnavailable(
        VisionMissingFile('data/vision/inspection_marker.pgm'),
      );
    final h = await pumpM1(tester, scanPorts: ports);
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
    });
    await tester.pumpAndSettle();
    expect(h.services.scanner.status.state, LiveScanState.unavailable);
    expect(footer('Live scan unavailable'), findsOneWidget);
  });

  testWidgets(
    'footer says item data is out of date when the catalog is stale',
    (tester) async {
      var now = fixtureNow;
      tester.view.physicalSize = const Size(1672, 941);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = (await tester.runAsync(() async {
        final result = M1Harness(clock: () => now);
        await result.initialize();
        return result;
      }))!;
      addTearDown(h.dispose);
      now = fixtureNow.add(const Duration(days: 3));
      h.services.catalog.updateAge();
      expect(h.services.catalog.status, CatalogStatus.stale);
      await tester.pumpWidget(BlackgridApp(services: h.services));
      await tester.pumpAndSettle();

      expect(find.textContaining('Item data out of date'), findsOneWidget);
      expect(find.textContaining('stale', findRichText: true), findsNothing);
      expect(find.textContaining('Catalog stale'), findsNothing);
    },
  );

  testWidgets('search hint asks for an item name without canonical', (
    tester,
  ) async {
    await pumpM1(tester);
    final hint = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.decoration?.hintText)
        .whereType<String>()
        .toList();
    expect(hint, contains('Search items…'));
    expect(hint.any((h) => h.toLowerCase().contains('canonical')), isFalse);
  });

  testWidgets('search still finds an item by its tarkov.dev id', (
    tester,
  ) async {
    final h = await pumpM1(tester);
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText != null,
    );
    await tester.enterText(field.first, 'item-a');
    await tester.pumpAndSettle();
    expect(h.services.selection.results.map((i) => i.id), contains('item-a'));
  });

  testWidgets('the header Stats button opens the Stats dialog', (tester) async {
    await pumpM1(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Stats'));
    await tester.pumpAndSettle();

    expect(find.text('PvP stats'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header shows the 32x32 app logo and no hub icon', (
    tester,
  ) async {
    await pumpM1(tester);
    final logo = find.byType(AppLogo);
    expect(logo, findsOneWidget);
    expect(tester.widget<AppLogo>(logo).size, 32);
    expect(tester.getSize(logo), const Size(32, 32));
    expect(
      tester.getRect(logo).right,
      lessThan(tester.getRect(find.text('BLACKGRID')).left),
    );
    expect(find.byIcon(Icons.hub_outlined), findsNothing);
  });
}
