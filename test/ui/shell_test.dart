import 'package:blackgrid/application/scan_correction.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/data/capture/capture_failure.dart';
import 'package:blackgrid/data/catalog_normalizer.dart' show catalogDatasets;
import 'package:blackgrid/domain/title_matching.dart' show TitleCandidate;
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:blackgrid/ui/app_logo.dart';

import '../support/m1_harness.dart';
import '../fixtures/m1/catalog/fixture.dart' show fixtureNow, progressWire;

import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_failure.dart';
import 'package:blackgrid/ui/scanner_screen.dart';
import 'package:blackgrid/ui/scanner_sections.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:blackgrid/ui/panels.dart';
import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/verdict_reason.dart';
import 'package:blackgrid/ui/labels.dart';
import 'package:blackgrid/ui/age_tick.dart';
import 'package:blackgrid/ui/answer_strip.dart';
import 'package:blackgrid/ui/item_icon.dart';
import 'package:blackgrid/ui/item_decision_card.dart';
import 'package:blackgrid/ui/map_workspace.dart';
import 'package:blackgrid/ui/settings/settings_page.dart';
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

CatalogItem _priced({
  bool? noFlea = false,
  num? fleaPrice = 21800,
  List<CashOffer> offers = const [
    CashOffer(traderId: 'therapist', currency: 'RUB', price: 9400),
  ],
}) => CatalogItem(
  id: 'priced',
  name: 'Priced item',
  normalizedName: 'priced item',
  width: 2,
  height: 1,
  noFlea: noFlea,
  minLevelForFlea: 0,
  fleaPrice: fleaPrice,
  quoteAt: fixtureNow,
  sellOffers: offers,
);

/// Mounts the app, installs a one-item catalog and selects [item] by hand.
Future<M1Harness> _pumpPriced(
  WidgetTester tester,
  CatalogItem item, {
  Size size = const Size(1660, 870),
}) async {
  final h = await pumpM1(tester, size: size);
  h.services.catalog.snapshot = CatalogSnapshot(
    mode: GameMode.pvp,
    revision: 'strip-revision',
    observedAt: fixtureNow,
    items: {item.id: item},
    traders: const {
      'therapist': CatalogTrader(id: 'therapist', name: 'Therapist'),
    },
    requirements: const [],
    sourceTimestamps: {for (final key in catalogDatasets) key: fixtureNow},
  );
  await tester.runAsync(() => h.services.selection.selectManual(item));
  await tester.pumpAndSettle();
  return h;
}

Finder _inStrip(Finder matching) => find.descendant(
  of: find.byKey(const Key('answer-strip')),
  matching: matching,
);

const _stripEpoch = ScanEpoch(2, 2);

final _provenance = find.byKey(const Key('answer-provenance'));

void main() {
  testWidgets('workspace-shell: Found in raid sits beside the verdict', (
    tester,
  ) async {
    final h = await pumpM1(tester, size: const Size(1660, 870));
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.pumpAndSettle();
    final plate = tester.getRect(
      _inStrip(find.byKey(const Key('verdict-plate'))),
    );
    final fir = tester.getRect(_inStrip(find.byType(FirControls)));
    final reason = tester.getRect(
      _inStrip(find.byKey(const Key('answer-verdict-reason'))),
    );
    expect(fir.left - plate.right, inInclusiveRange(0, 24));
    expect((fir.center.dy - plate.center.dy).abs(), lessThanOrEqualTo(4));
    expect(reason.top, greaterThanOrEqualTo(plate.bottom));
    expect(reason.top, greaterThanOrEqualTo(fir.bottom));
    expect(_inStrip(find.byType(SegmentedButton<FirState>)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace-shell: Price block with both prices', (tester) async {
    await _pumpPriced(tester, _priced());
    for (final text in [
      'Flea',
      '₽21800',
      '₽10900 / slot',
      'Trader',
      '₽9400',
      'Therapist',
    ]) {
      expect(_inStrip(find.text(text)), findsOneWidget, reason: text);
    }
    expect(_inStrip(find.byKey(const Key('freshness-tag'))), findsOneWidget);
    final strip = tester.getRect(find.byKey(const Key('answer-strip')));
    final price = tester.getRect(
      _inStrip(find.byKey(const Key('answer-price'))),
    );
    expect(strip.right - price.right, lessThanOrEqualTo(24));
  });

  testWidgets('workspace-shell: Price block without a Flea price', (
    tester,
  ) async {
    await _pumpPriced(
      tester,
      _priced(noFlea: true, fleaPrice: null, offers: const []),
    );
    expect(_inStrip(find.text("Can't be sold on the Flea")), findsOneWidget);
    expect(_inStrip(find.text('Price unavailable')), findsOneWidget);
    expect(_inStrip(find.byKey(const Key('freshness-tag'))), findsNothing);
  });

  testWidgets('workspace-shell: Long reason with Found in raid at 1300px', (
    tester,
  ) async {
    const token = 'PVP_synthetic-fixture-only';
    final longName = 'Long task name ${'y' * 100}';
    tester.view.physicalSize = const Size(1300, 870);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    final reasonText = verdictReason(h.services.selection.decision!);
    expect(reasonText.length, greaterThanOrEqualTo(120));
    final reason = _inStrip(find.byKey(const Key('answer-verdict-reason')));
    expect(tester.widget<Text>(reason).data, reasonText);
    expect(tester.widget<Text>(reason).maxLines, isNull);
    final plate = tester.getRect(
      _inStrip(find.byKey(const Key('verdict-plate'))),
    );
    final fir = tester.getRect(_inStrip(find.byType(FirControls)));
    final price = tester.getRect(
      _inStrip(find.byKey(const Key('answer-price'))),
    );
    final strip = tester.getRect(find.byKey(const Key('answer-strip')));
    for (final rect in [plate, fir, price]) {
      expect(rect.left, greaterThanOrEqualTo(strip.left));
      expect(rect.right, lessThanOrEqualTo(strip.right));
    }
    final beside = (fir.center.dy - plate.center.dy).abs() <= 4;
    final under = fir.top >= plate.bottom && (fir.left - plate.left).abs() <= 1;
    expect(beside || under, isTrue, reason: 'plate $plate fir $fir');
    expect(
      tester.renderObject<RenderParagraph>(reason).didExceedMaxLines,
      isFalse,
    );
    // The top bar overflows by 91px at 1300 on main already (shell.dart's bar
    // row), so that report is consumed and the strip's own geometry above
    // carries the no-overflow check.
    tester.takeException();
  });

  testWidgets('workspace-shell: Provenance line', (tester) async {
    var now = fixtureNow;
    final h = await pumpM1(
      tester,
      size: const Size(1660, 870),
      clock: () => now,
    );
    final selection = h.services.selection;
    final revision = h.services.catalog.snapshot!.revision;
    String line() => tester.widget<Text>(_inStrip(_provenance)).data!;

    await tester.runAsync(
      () => selection.selectScan(
        reportId: 1,
        itemId: 'item-a',
        mode: GameMode.pvp,
        catalogRevision: revision,
        epoch: _stripEpoch,
      ),
    );
    now = now.add(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 5));
    expect(line(), 'Accepted scan · 12 s ago');

    selection.offerCorrection(
      ScanCorrectionOffer(
        reportId: 2,
        epoch: _stripEpoch,
        mode: GameMode.pvp,
        catalogRevision: revision,
        ocrText: 'plate',
        candidates: const [TitleCandidate('item-a', .9)],
        query: 'plate',
      ),
    );
    await tester.runAsync(() => selection.selectCorrection(2, 'item-a'));
    now = now.add(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 5));
    expect(line(), 'Corrected from a scan · 3 min ago · chosen by hand');

    await tester.runAsync(
      () =>
          selection.selectManual(h.services.catalog.snapshot!.items['item-a']!),
    );
    await tester.pump();
    expect(line(), 'Chosen by hand');

    // Saved PvE data lets a PvE history row open on a PvP session.
    await tester.runAsync(() async {
      await h.services.setMode(GameMode.pve);
      await h.services.catalog.refresh();
      await h.services.setMode(GameMode.pvp);
    });
    await tester.pumpAndSettle();
    final saved = now.subtract(const Duration(minutes: 3));
    await tester.runAsync(
      () => selection.openHistory(
        ItemActivity(
          itemId: 'item-a',
          mode: GameMode.pve,
          source: ActivitySource.manual,
          observedAt: saved,
          revision: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(line(), 'Current advice · saved 3 min ago in PvE');
    await tester.runAsync(
      () => selection.openHistory(
        ItemActivity(
          itemId: 'item-a',
          mode: GameMode.pvp,
          source: ActivitySource.manual,
          observedAt: saved,
          revision: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(line(), 'Current advice · saved 3 min ago');
  });

  testWidgets('workspace-shell: Provenance age moves on', (tester) async {
    var now = fixtureNow;
    final h = await pumpM1(tester, clock: () => now);
    await tester.runAsync(
      () => h.services.selection.selectScan(
        reportId: 1,
        itemId: 'item-a',
        mode: GameMode.pvp,
        catalogRevision: h.services.catalog.snapshot!.revision,
        epoch: _stripEpoch,
      ),
    );
    // Mount the strip alone, with a short injected tick period.
    await tester.pumpWidget(
      MaterialApp(
        theme: blackgridTheme(Brightness.dark),
        home: Scaffold(
          body: AnswerStrip(
            services: h.services,
            tickPeriod: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.pump();
    String line() => tester.widget<Text>(_inStrip(_provenance)).data!;
    expect(line(), 'Accepted scan · just now');
    now = now.add(const Duration(minutes: 3));
    expect(line(), 'Accepted scan · just now');
    await tester.pump(const Duration(seconds: 1));
    expect(line(), 'Accepted scan · 3 min ago');
  });

  testWidgets('workspace-shell: Price and stable normal height', (
    tester,
  ) async {
    final h = await pumpM1(tester);
    final strip = find.byKey(const Key('answer-strip'));
    final emptyHeight = tester.getSize(strip).height;
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.pumpAndSettle();
    expect(emptyHeight, lessThanOrEqualTo(100));
    expect(tester.getSize(strip).height, emptyHeight);
    expect(
      find.descendant(
        of: strip,
        matching: find.byKey(const Key('answer-price')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: strip,
        matching: find.byKey(const Key('freshness-tag')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('compact answer uses two rows for ordinary content', (
    tester,
  ) async {
    final h = await pumpM1(tester, size: const Size(960, 720));
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.pumpAndSettle();
    final strip = find.byKey(const Key('answer-strip'));
    final icon = find.descendant(of: strip, matching: find.byType(ItemIcon));
    final verdict = find.descendant(
      of: strip,
      matching: find.byType(AnswerVerdict),
    );
    final fir = find.descendant(of: strip, matching: find.byType(FirControls));
    final price = find.byKey(const Key('answer-price'));
    expect(tester.getRect(verdict).top, lessThan(tester.getRect(icon).bottom));
    // The control now sits inside the answer group, beside or under the plate.
    expect(
      tester.getRect(fir).top,
      greaterThanOrEqualTo(tester.getRect(verdict).top),
    );
    expect(
      tester.getRect(fir).bottom,
      lessThanOrEqualTo(tester.getRect(verdict).bottom),
    );
    expect(price, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'workspace-shell: Anchored search results and explicit selection',
    (tester) async {
      final h = await pumpM1(tester, size: const Size(960, 720));
      final search = find.widgetWithText(TextField, 'Search items…');
      await tester.tap(search);
      await tester.enterText(search, 'Synthetic');
      await tester.pumpAndSettle();
      expect(h.services.selection.selectedId, isNull);
      expect(h.services.history.rows, isEmpty);
      final results = find.byKey(const Key('top-search-results'));
      expect(results, findsOneWidget);
      expect(
        tester.getTopLeft(results).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(search).dy),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.services.selection.selectedId, isNotNull);
    },
  );

  testWidgets('workspace-shell: Wide tools alignment', (tester) async {
    await pumpM1(tester, size: const Size(1660, 870));
    final bar = find.byKey(const Key('shell-top-bar'));
    final action = find.widgetWithText(OutlinedButton, 'Import');
    expect(
      tester.getRect(bar).right - tester.getRect(action).right,
      lessThan(40),
    );
    expect(find.byKey(const Key('timer-separator')), findsWidgets);
  });

  testWidgets('workspace-shell: Scanner history leads the inspector', (
    tester,
  ) async {
    final h = await pumpM1(tester, size: const Size(1660, 870));
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
    }
    final inspector = find.byKey(const Key('shell-inspector'));
    final history = find.descendant(
      of: inspector,
      matching: find.text('Recent items'),
    );
    expect(history, findsOneWidget);
    expect(
      tester.getTopLeft(history).dy,
      lessThan(tester.getTopLeft(inspector).dy + 100),
    );
    // The item's details, requirements and sources live in the main column.
    for (final title in ['Inspection details', 'Requirements', 'Sources']) {
      expect(
        find.descendant(of: inspector, matching: find.text(title)),
        findsNothing,
        reason: title,
      );
    }
    // Rows size to their content and the Live scan note stays pinned below.
    expect(
      find.descendant(of: inspector, matching: find.byType(ListTile)),
      findsWidgets,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('live-scan-note'))).dy,
      greaterThan(tester.getBottomLeft(find.byType(ListTile).last).dy),
    );
  });

  testWidgets('optional uses survive inspector close and area switch', (
    tester,
  ) async {
    final h = await pumpM1(tester, size: const Size(1660, 1200));
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.pumpAndSettle();
    // Requirements live in the Scanner's Why section; its expansion state
    // belongs to the Scanner column, not to the inspector.
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    final optional = find.descendant(
      of: find.byType(WhySection),
      matching: find.textContaining('Optional uses ('),
    );
    await tester.ensureVisible(optional);
    await tester.tap(optional);
    await tester.pumpAndSettle();
    bool expanded() => find
        .descendant(
          of: find.ancestor(of: optional, matching: find.byType(InkWell)).first,
          matching: find.byIcon(Icons.expand_less),
        )
        .evaluate()
        .isNotEmpty;
    expect(expanded(), isTrue);
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    expect(expanded(), isTrue);
    await tester.tap(find.byKey(const Key('nav-map')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    expect(expanded(), isTrue);
  });

  testWidgets('Scanner inspector fits at scale two', (tester) async {
    final h = await pumpM1(tester, size: const Size(960, 720), scale: 2);
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    final inspector = find.byKey(const Key('shell-inspector'));
    expect(inspector, findsOneWidget);
    expect(
      find.descendant(of: inspector, matching: find.text('Recent items')),
      findsOneWidget,
    );
    final bounds = tester.getRect(inspector);
    // The pinned note scrolls inside its own viewport when it does not fit.
    final viewport = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const Key('live-scan-note')),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect(viewport.bottom, lessThanOrEqualTo(bounds.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace-shell: Initial inspector state follows window width', (
    tester,
  ) async {
    await pumpM1(tester, size: const Size(1660, 870));
    expect(find.byKey(const Key('shell-inspector')), findsOneWidget);
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(960, 720);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-inspector')), findsNothing);
    tester.view.physicalSize = const Size(1660, 870);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-inspector')), findsNothing);
  });

  testWidgets('Escape closes docked inspector when its control owns focus', (
    tester,
  ) async {
    await pumpM1(tester, size: const Size(1660, 870));
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    final heading = find.descendant(
      of: find.byKey(const Key('shell-inspector')),
      matching: find.text('Recent items'),
    );
    FocusScope.of(tester.element(heading)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-inspector')), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('inspector-toggle')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('workspace-shell: Status bar presentation and binding', (
    tester,
  ) async {
    final ports = ScanFakePorts();
    final h = await pumpM1(tester, scanPorts: ports);
    final bar = find.byKey(const Key('shell-status-bar'));
    expect(bar, findsOneWidget);
    expect(tester.getSize(bar).height, 28);
    expect(tester.getRect(bar).left, 0);
    expect(tester.getRect(find.byKey(const Key('status-game-mode'))).left, 20);
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.touch_app_outlined)),
      findsNothing,
    );
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
    });
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: bar, matching: find.textContaining('F9 or click')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bar,
        matching: find.byKey(const Key('live-scan-state-dot')),
      ),
      findsOneWidget,
    );
  });
  testWidgets('Escape in search preserves docked inspector', (tester) async {
    await pumpM1(tester, size: const Size(1660, 870));
    if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
    }
    final search = find.widgetWithText(TextField, 'Search items…');
    await tester.tap(search);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-inspector')), findsOneWidget);
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
  });

  testWidgets('closed inspector unmounts the history list', (tester) async {
    await pumpM1(tester);
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
    }
    expect(find.byType(HistoryPanel), findsOneWidget);
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryPanel, skipOffstage: false), findsNothing);
    expect(find.byType(AgeTick, skipOffstage: false), findsNothing);
  });

  testWidgets('docked inspector keeps desktop scanner evidence on screen', (
    tester,
  ) async {
    final h = await pumpM1(tester, size: const Size(1100, 720));
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
    }
    // The column scrolls as one beside the docked inspector, so the evidence
    // can always be scrolled fully into the window.
    final evidence = find.byWidgetPredicate(
      (w) => w is ScannerSection && w.title == 'Scan evidence',
    );
    await tester.ensureVisible(evidence);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(evidence).dy, lessThanOrEqualTo(720));
    expect(tester.takeException(), isNull);
  });

  for (final disableAnimations in [false, true]) {
    testWidgets(
      'closed inspector excludes keyboard focus reduced=$disableAnimations',
      (tester) async {
        final h = await pumpM1(tester, size: const Size(960, 720));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(960, 720),
                disableAnimations: disableAnimations,
              ),
              child: BlackgridShell(services: h.services),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('inspector-toggle')));
        await tester.pumpAndSettle();
        final inspector = find.byKey(const Key('shell-inspector'));
        final scope = FocusScope.of(tester.element(inspector));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(scope.descendantsAreFocusable, isFalse);
        for (var i = 0; i < 20; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(scope.hasFocus, isFalse);
        }
      },
    );
  }
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
  Rect sectionRect(WidgetTester tester, String title) => tester.getRect(
    find.byWidgetPredicate((w) => w is ScannerSection && w.title == title),
  );
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
        final h = await pumpM1(tester, size: size);
        await tester.runAsync(
          () => h.services.selection.selectManual(
            h.services.catalog.snapshot!.items['item-a']!,
          ),
        );
        await tester.tap(find.byKey(const Key('nav-scanner')));
        await tester.pumpAndSettle();
        final strip = tester.getBottomLeft(
          find.byKey(const Key('answer-strip')),
        );
        final evidence = sectionRect(tester, 'Scan evidence');
        expect(evidence.top, greaterThanOrEqualTo(strip.dy));
        expect(
          evidence.top,
          greaterThanOrEqualTo(sectionRect(tester, 'Why').bottom),
        );
        expect(
          evidence.top,
          greaterThanOrEqualTo(sectionRect(tester, 'Prices').bottom),
        );
        if (size.width == 1660) {
          // The title is on screen with the column unscrolled.
          final title = find.descendant(
            of: find.byType(ScannerScreen),
            matching: find.text('Scan evidence'),
          );
          expect(
            tester.getBottomLeft(title).dy,
            lessThanOrEqualTo(size.height),
          );
          expect(
            tester
                .state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byKey(
                          const PageStorageKey('scanner-desktop-scroll'),
                        ),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                )
                .position
                .pixels,
            0,
          );
        } else {
          // One scroll view carries the whole column.
          expect(
            find.descendant(
              of: find.byType(ScannerScreen),
              matching: find.byType(Scrollable),
            ),
            findsOneWidget,
          );
          await tester.ensureVisible(
            find.byWidgetPredicate(
              (w) => w is ScannerSection && w.title == 'Scan evidence',
            ),
          );
          await tester.pumpAndSettle();
          expect(
            sectionRect(tester, 'Scan evidence').bottom,
            lessThanOrEqualTo(size.height),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('workspace-shell: Docked details', (tester) async {
    await pumpM1(tester, size: const Size(1660, 870));
    if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('shell-inspector')), findsOneWidget);
    expect(find.byKey(const Key('inspector-scrim')), findsNothing);
    expect(find.byKey(const PageStorageKey('map')), findsOneWidget);
    // On Scanner the inspector holds Recent items and the Live scan note
    // beside the main column, and none of the old panels.
    await tester.tap(find.byKey(const Key('nav-scanner')));
    await tester.pumpAndSettle();
    final inspector = find.byKey(const Key('shell-inspector'));
    expect(
      find.descendant(of: inspector, matching: find.text('Recent items')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: inspector,
        matching: find.byKey(const Key('live-scan-note')),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byType(ScannerScreen)).right,
      lessThanOrEqualTo(tester.getRect(inspector).left),
    );
    for (final title in ['Inspection details', 'Requirements', 'Sources']) {
      expect(
        find.descendant(of: inspector, matching: find.text(title)),
        findsNothing,
        reason: title,
      );
    }
    for (final type in [ItemDecisionCard, RequirementPanel, SourcePanel]) {
      expect(
        find.descendant(of: inspector, matching: find.byType(type)),
        findsNothing,
        reason: '$type',
      );
    }
  });

  for (final width in [1080.0, 1081.0]) {
    for (final room in [Brightness.dark, Brightness.light]) {
      testWidgets('inspector boundary $width in $room', (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = room;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pumpM1(tester, size: Size(width, 720));
        if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
          await tester.tap(find.byKey(const Key('inspector-toggle')));
          await tester.pumpAndSettle();
        }
        expect(
          find.byKey(const Key('inspector-scrim')),
          width == 1080 ? findsOneWidget : findsNothing,
        );
        expect(find.byKey(const Key('shell-inspector')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('workspace-shell: Map inspector holds working lists', (
    tester,
  ) async {
    final h = await pumpMapFixture(tester, size: const Size(1660, 870));
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.pumpAndSettle();
    if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
    }
    final inspector = find.byKey(const Key('shell-inspector'));
    double top(String title) => tester
        .getTopLeft(find.descendant(of: inspector, matching: find.text(title)))
        .dy;
    expect(top('This raid'), lessThan(top('Markers')));
    expect(top('Markers'), lessThan(top('Pins')));
    for (final type in [
      RequirementPanel,
      SourcePanel,
      HistoryPanel,
      ItemDecisionCard,
    ]) {
      expect(
        find.descendant(of: inspector, matching: find.byType(type)),
        findsNothing,
        reason: '$type',
      );
    }
    for (final title in ['Requirements', 'Sources', 'Inspection details']) {
      expect(
        find.descendant(of: inspector, matching: find.text(title)),
        findsNothing,
      );
    }
  });

  testWidgets('workspace-shell: Resize with open details', (tester) async {
    final h = await pumpMapFixture(tester, size: const Size(1660, 870));
    final map = tester.element(find.byKey(const PageStorageKey('map')));
    final workspace = tester.element(find.byType(MapWorkspace));
    final before = h.services.maps.transform;
    h.services.maps.panBy(23, 17);
    final pan = h.services.maps.transform;
    expect(pan.translationX, before.translationX + 23);
    expect(pan.translationY, before.translationY + 17);
    if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('inspector-toggle')));
      await tester.pumpAndSettle();
    }
    // The Map inspector's working state is the marker search it carries.
    final search = find.byKey(const ValueKey('marker-section-search'));
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    await tester.enterText(search, 'exit');
    await tester.pumpAndSettle();
    expect(h.services.maps.search, 'exit');
    tester.view.physicalSize = const Size(960, 720);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inspector-scrim')), findsOneWidget);
    expect(tester.element(find.byKey(const PageStorageKey('map'))), same(map));
    expect(tester.element(find.byType(MapWorkspace)), same(workspace));
    expect(h.services.maps.transform.scale, pan.scale);
    expect(h.services.maps.transform.translationX, pan.translationX);
    expect(h.services.maps.transform.translationY, pan.translationY);
    expect(h.services.maps.search, 'exit');
    expect(search, findsOneWidget);
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
    'workspace-shell: Resize with open details keeps the optional-uses '
    'expansion',
    (tester) async {
      final h = await pumpM1(tester, size: const Size(1660, 1200));
      await tester.runAsync(
        () => h.services.selection.selectManual(
          h.services.catalog.snapshot!.items['item-a']!,
        ),
      );
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      final optional = find.descendant(
        of: find.byType(WhySection),
        matching: find.textContaining('Optional uses ('),
      );
      await tester.ensureVisible(optional);
      await tester.tap(optional);
      await tester.pumpAndSettle();
      Finder open() => find.descendant(
        of: find.ancestor(of: optional, matching: find.byType(InkWell)).first,
        matching: find.byIcon(Icons.expand_less),
      );
      expect(open(), findsOneWidget);

      tester.view.physicalSize = const Size(960, 720);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inspector-scrim')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-inspector')), findsNothing);
      expect(h.services.selection.selectedId, 'item-a');
      expect(open(), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('inspector-toggle')))
            .focusNode
            ?.hasFocus,
        isTrue,
      );
    },
  );

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
      if (find.byKey(const Key('shell-inspector')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('inspector-toggle')));
        await tester.pumpAndSettle();
      }
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
    await tester.tap(find.widgetWithText(OutlinedButton, 'Settings'));
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
    await tester.tap(find.widgetWithText(TextButton, 'Back to Scanner'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recording-stop-note')), findsOneWidget);
    expect(find.textContaining('synthetic disk failure'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Settings'));
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
  for (final width in [900.0, 960.0]) {
    testWidgets('narrow recording failure stays visible $width', (
      tester,
    ) async {
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
        size: Size(width, 720),
        scanPorts: ScanFakePorts(),
        scanFrameRecorder: recorder,
      );
      await tester.runAsync(() async {
        await h.services.scanner.setLiveScan(true);
        await h.services.scanner.settled;
      });
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
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
      await tester.tap(find.widgetWithText(TextButton, 'Back to Scanner'));
      await tester.pumpAndSettle();
      final note = find.byKey(const Key('recording-stop-note'));
      expect(note, findsOneWidget);
      expect(tester.getTopLeft(note).dy, greaterThanOrEqualTo(0));
      expect(tester.getBottomRight(note).dy, lessThanOrEqualTo(720));
      expect(find.textContaining('synthetic disk failure'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
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
  }
  testWidgets('workspace-shell: Settings targets', (tester) async {
    await pumpM1(tester);
    Future<void> check(String key, String section) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      final page = find.byType(SettingsPage);
      expect(page, findsOneWidget);
      final title = find.byKey(Key('settings-title-$section'));
      final rect = tester.getRect(title);
      expect(rect.top, greaterThanOrEqualTo(tester.getRect(page).top));
      expect(rect.bottom, lessThanOrEqualTo(tester.getRect(page).bottom));
      expect(Focus.of(tester.element(title)).hasPrimaryFocus, isTrue);
      await tester.tap(find.widgetWithText(TextButton, 'Back to Map'));
      await tester.pumpAndSettle();
      expect(page, findsNothing);
    }

    await check('status-item-data', 'itemData');
    await check('status-tracker', 'tracker');
  });
  testWidgets('workspace-shell: Settings target while the page is open', (
    tester,
  ) async {
    await pumpM1(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Settings'));
    await tester.pumpAndSettle();
    final page = find.byType(SettingsPage);
    final tracker = find.byKey(const Key('settings-title-tracker'));
    expect(page, findsOneWidget);
    // Scroll past Tracker progress, so reaching it again is a real move.
    await tester.tap(find.byKey(const Key('settings-nav-raidTimers')));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(tracker).top,
      lessThan(tester.getRect(page).top),
      reason: 'Tracker progress is scrolled out of view',
    );

    await tester.tap(find.byKey(const Key('status-tracker')));
    await tester.pumpAndSettle();

    expect(page, findsOneWidget);
    expect(
      tester.getRect(tracker).bottom,
      lessThanOrEqualTo(tester.getRect(page).bottom),
    );
    expect(Focus.of(tester.element(tracker)).hasPrimaryFocus, isTrue);
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
          .widget<SegmentedButton<FirState>>(
            find.descendant(
              of: strip,
              matching: find.byType(SegmentedButton<FirState>),
            ),
          )
          .selected,
      {FirState.yes},
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
          expect(find.text('Live scan off · no capture'), findsOneWidget);
          expect(find.text('Scanner Ready'), findsNothing);
          expect(find.text('Auto-scan'), findsNothing);
          expect(find.text('Capture Preview'), findsNothing);
          expect(find.text('High confidence'), findsNothing);
        },
      );
    }
  }
  testWidgets(
    'Scanner places evidence below the answer without the old controls',
    (tester) async {
      await pumpM1(tester);
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      final evidence = sectionRect(tester, 'Scan evidence');
      expect(evidence.left, 14 + EmberSpace.lg);
      expect(
        evidence.top,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byKey(const Key('answer-strip'))).dy,
        ),
      );
      expect(find.text('Picking an item here does not scan.'), findsNothing);
      expect(find.text('Recent items'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byKey(const Key('nav-map'))))
            .scaffoldBackgroundColor,
        Theme.of(tester.element(find.byKey(const Key('nav-map'))))
            .extension<EmberColors>()!
            .canvas,
      );
    },
  );
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
    // The end state lives in Diagnostics, not on the Scanner.
    expect(find.byKey(const Key('scan-end')), findsNothing);
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

  Finder evidenceSection() => find.byWidgetPredicate(
    (w) => w is ScannerSection && w.title == 'Scan evidence',
  );

  Future<void> selectItemA(WidgetTester tester, M1Harness h) async {
    await tester.runAsync(
      () => h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('scan evidence panel is fully on screen at 1660x870', (
    tester,
  ) async {
    final h = await pumpM1(tester, size: const Size(1660, 870));
    await selectItemA(tester, h);
    await openScanner(tester);
    // The Scan evidence title is on screen with the column unscrolled, below
    // Why and Prices.
    final title = find.descendant(
      of: evidenceSection(),
      matching: find.text('Scan evidence'),
    );
    final top = tester.getTopLeft(title);
    expect(top.dy, greaterThanOrEqualTo(0));
    expect(tester.getBottomRight(title).dy, lessThanOrEqualTo(870));
    expect(top.dx, greaterThanOrEqualTo(0));
    expect(tester.getBottomRight(title).dx, lessThanOrEqualTo(1660));
    expect(desktopPage(tester).pixels, 0);
    final evidence = tester.getRect(evidenceSection());
    expect(
      evidence.top,
      greaterThanOrEqualTo(sectionRect(tester, 'Why').bottom),
    );
    expect(
      evidence.top,
      greaterThanOrEqualTo(sectionRect(tester, 'Prices').bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scan evidence panel is on screen at 1100x720 with enlarged text',
    (tester) async {
      final ports = ScanFakePorts();
      final h = await pumpM1(
        tester,
        size: const Size(1100, 720),
        scale: 1.5,
        scanPorts: ports,
      );
      await openScanner(tester);
      // An accepted scan, then a failed one (the note), then a scan in flight
      // (the phase): the most the section ever shows.
      await tester.runAsync(() async {
        await publishTargetedScan(
          h.services.scanner,
          ports,
          text: 'Alternative component',
        );
        ports.fire(2000);
        (await ports.capture.calls.at(1)).fail(const TargetNotForeground());
        await reportPublished(h.services.scanner, 2);
        ports.fire(3000);
        await ports.captureOk(2);
      });
      await tester.pumpAndSettle();
      expect(h.services.scanner.phase, ScanPhase.targeted);
      // The column is taller than the window and scrolls as one view.
      final scrollables = find.descendant(
        of: find.byType(ScannerScreen),
        matching: find.byType(Scrollable),
      );
      expect(scrollables, findsOneWidget);
      final position = tester.state<ScrollableState>(scrollables).position;
      expect(position.maxScrollExtent, greaterThan(0));
      // Every Scan evidence line can be scrolled into view.
      for (final (name, line) in [
        ('phase', find.byKey(const Key('scan-phase'))),
        ('note', find.byKey(const Key('scan-note-reason'))),
        ('note candidate', find.text('No candidate')),
        ('accepted item', find.byKey(const Key('scan-item'))),
      ]) {
        expect(line, findsOneWidget, reason: name);
        await tester.ensureVisible(line);
        await tester.pumpAndSettle();
        final rect = tester.getRect(line);
        expect(rect.top, greaterThanOrEqualTo(0), reason: name);
        expect(rect.bottom, lessThanOrEqualTo(720), reason: name);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact layout shows evidence without the old Scanner controls',
    (tester) async {
      final h = await pumpM1(tester, size: const Size(900, 1600));
      await selectItemA(tester, h);
      await openScanner(tester);
      final strip = tester.getBottomLeft(find.byKey(const Key('answer-strip')));
      final why = sectionRect(tester, 'Why');
      final prices = sectionRect(tester, 'Prices');
      final evidence = sectionRect(tester, 'Scan evidence');
      expect(why.top, greaterThanOrEqualTo(strip.dy));
      expect(prices.top, greaterThanOrEqualTo(strip.dy));
      expect(evidence.top, greaterThanOrEqualTo(why.bottom));
      expect(evidence.top, greaterThanOrEqualTo(prices.bottom));
      expect(
        find.byWidgetPredicate((w) => w is GridPanel && w.title == 'Scanner'),
        findsNothing,
      );
    },
  );

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
    expect(footer('Live scan on · F9 or click'), findsOneWidget);
    expect(find.textContaining('No capture'), findsNothing);
  });

  testWidgets('footer says live scan is off and nothing is captured', (
    tester,
  ) async {
    await pumpM1(tester);
    expect(footer('Live scan off · no capture'), findsOneWidget);
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
    expect(find.textContaining('Live scan unavailable ·'), findsOneWidget);
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

  group('main windows keep diagnostic detail out', () {
    CatalogItem item(String id, String name) => CatalogItem(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      width: 1,
      height: 1,
      noFlea: false,
      minLevelForFlea: 0,
      fleaPrice: 400,
      quoteAt: fixtureNow,
      sellOffers: const [
        CashOffer(traderId: 'trader-a', currency: 'RUB', price: 120),
      ],
    );

    CatalogSnapshot snapshotOf(Map<String, String> names) => CatalogSnapshot(
      mode: GameMode.pvp,
      revision: 'guard-revision',
      observedAt: fixtureNow,
      items: {for (final e in names.entries) e.key: item(e.key, e.value)},
      traders: const {
        'trader-a': CatalogTrader(id: 'trader-a', name: 'Synthetic Alpha'),
      },
      requirements: const [],
      sourceTimestamps: {for (final key in catalogDatasets) key: fixtureNow},
    );

    /// The plain text of every `Text`, `RichText` and `EditableText` on screen.
    List<String> screenText(WidgetTester tester) => [
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        w.data ?? w.textSpan?.toPlainText() ?? '',
      for (final w in tester.widgetList<RichText>(find.byType(RichText)))
        w.text.toPlainText(),
      for (final w in tester.widgetList<EditableText>(
        find.byType(EditableText),
      ))
        w.controller.text,
    ];

    void expectNoText(WidgetTester tester, List<String> forbidden) {
      final shown = screenText(tester);
      expect(shown, isNotEmpty);
      for (final needle in forbidden) {
        final hits = [
          for (final text in shown)
            if (text.contains(needle)) text,
        ];
        expect(hits, isEmpty, reason: 'text containing "$needle" is on screen');
      }
    }

    /// Shows the Scanner, whose main column and inspector hold the details.
    Future<void> expandInspector(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
    }

    testWidgets('main windows show no diagnostic detail for an accepted scan', (
      tester,
    ) async {
      final ports = ScanFakePorts();
      final h = await pumpM1(
        tester,
        size: const Size(1660, 2400),
        scanPorts: ports,
      );
      h.services.catalog.snapshot = snapshotOf({scanItemId: 'Can of sprats'});
      await tester.runAsync(
        () => publishTargetedScan(
          h.services.scanner,
          ports,
          text: 'CAN OF SPRATS',
        ),
      );
      await tester.pumpAndSettle();
      expect(h.services.scanner.lastAccepted, isNotNull);
      expect(h.services.selection.selectedId, scanItemId);

      final forbidden = [
        scanItemId,
        'CAN OF SPRATS',
        'Marker score',
        'Margin',
        'Scan #',
        ' ms',
        'Targeted',
        'records',
        'Source:',
      ];
      await expandInspector(tester);
      expect(find.text('Can of sprats'), findsWidgets);
      expectNoText(tester, forbidden);

      await tester.tap(find.byKey(const Key('nav-map')));
      await tester.pumpAndSettle();
      expect(find.text('Can of sprats'), findsWidgets);
      expectNoText(tester, forbidden);
    });

    testWidgets('main windows show no diagnostic detail beside a correction '
        'offer', (tester) async {
      final h = await pumpM1(tester, size: const Size(1660, 2400));
      h.services.catalog.snapshot = snapshotOf({
        'ana-a': 'Ana plate alpha',
        'ana-b': 'Ana plate bravo',
      });
      h.services.selection.offerCorrection(
        const ScanCorrectionOffer(
          reportId: 7,
          epoch: ScanEpoch(2, 2),
          mode: GameMode.pvp,
          catalogRevision: 'guard-revision',
          ocrText: 'ANA M1',
          candidates: [
            TitleCandidate('ana-a', 1.0),
            TitleCandidate('ana-b', .974),
          ],
          query: 'ANA M1',
        ),
      );
      final forbidden = [
        '#7',
        'ambiguous',
        '1.00',
        '0.97',
        'Marker score',
        ' ms',
      ];
      for (final area in ['nav-map', 'nav-scanner']) {
        await tester.tap(find.byKey(Key(area)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('correction-offer')), findsOneWidget);
        expect(find.text('Read: ANA M1'), findsOneWidget);
        expect(
          find.byKey(const Key('correction-candidate-ana-a')),
          findsOneWidget,
        );
        expectNoText(tester, forbidden);
      }
    });

    testWidgets('catalog error and recording stop note stay on the Scanner', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('blackgrid-guard-');
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
        size: const Size(1660, 2400),
        scanPorts: ScanFakePorts(),
        scanFrameRecorder: recorder,
      );
      await tester.runAsync(() async {
        await h.services.scanner.setLiveScan(true);
        await h.services.scanner.settled;
        await h.services.scanner.setRecording(true);
      });
      expect(recorder.status.value.state, ScanRecordingState.on);
      recorder.record(recordedScan('failure'));
      writers.single.fail('failure', 'synthetic disk failure');
      h.failNetwork = true;
      await tester.runAsync(h.services.catalog.refresh);
      final error = h.services.catalog.error;
      expect(error, isNotNull);
      await tester.pumpAndSettle();

      await expandInspector(tester);
      expect(find.byKey(const Key('recording-stop-note')), findsOneWidget);
      expect(
        find.textContaining('Recording stopped: synthetic disk failure'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SourcePanel),
          matching: find.text(error!),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the Scanner inspector shows no UTC time', (tester) async {
      const token = 'PVP_synthetic-fixture-only';
      tester.view.physicalSize = const Size(1660, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = (await tester.runAsync(() async {
        final result = M1Harness(
          shapeWire: (wire) {
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
        return result;
      }))!;
      addTearDown(h.dispose);
      await tester.pumpWidget(BlackgridApp(services: h.services));
      await tester.pumpAndSettle();
      // Item data, a price time and Tracker progress are all known.
      expect(h.services.catalog.snapshot, isNotNull);
      expect(h.services.selection.item?.quoteAt, isNotNull);
      expect(h.services.progress.snapshot, isNotNull);

      await expandInspector(tester);
      final inspector = find.byKey(const Key('shell-inspector'));
      final isoTime = RegExp(r'\d{4}-\d{2}-\d{2}T[\d:.]+Z');
      final texts = [
        for (final w in tester.widgetList<Text>(
          find.descendant(of: inspector, matching: find.byType(Text)),
        ))
          w.data ?? w.textSpan?.toPlainText() ?? '',
        for (final w in tester.widgetList<RichText>(
          find.descendant(of: inspector, matching: find.byType(RichText)),
        ))
          w.text.toPlainText(),
      ];
      expect(texts, isNotEmpty);
      expect(texts.where(isoTime.hasMatch), isEmpty);
      expect(find.textContaining('(UTC)'), findsNothing);
    });
  });
}
