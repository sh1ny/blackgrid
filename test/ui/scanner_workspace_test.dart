import 'dart:io';

import 'package:blackgrid/application/selection_controller.dart';
import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/ember/ember_tokens.dart';
import 'package:blackgrid/ui/ember/theme_access.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/freshness_tag.dart';
import 'package:blackgrid/ui/panels.dart';
import 'package:blackgrid/ui/scanner_screen.dart';
import 'package:blackgrid/ui/scanner_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart' show fixtureNow;
import '../support/m1_harness.dart';
import '../support/m1_widget_harness.dart';
import 'support/scan_ui_support.dart';

/// The warning the engine adds when found in raid is unknown.
const _firWarning = 'Found in raid unknown for this item';

/// A selection serving a fixed item and decision, so a section is driven
/// without a database, catalog download or decision engine.
class _FakeSelection with ChangeNotifier implements SelectionController {
  @override
  String? selectedId;

  @override
  CatalogItem? item;

  ItemDecision? _decision;

  @override
  ItemDecision? get decision => _decision;

  @override
  CatalogSnapshot? get inspectionCatalog => null;

  @override
  DateTime Function() get clock =>
      () => fixtureNow;

  /// Selects [id] showing [item] and [decision].
  void show(String id, CatalogItem? item, ItemDecision? decision) {
    selectedId = id;
    this.item = item;
    _decision = decision;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

CatalogItem _item({DateTime? quoteAt}) => CatalogItem(
  id: 'item-x',
  name: 'Item X',
  normalizedName: 'item x',
  width: 2,
  height: 1,
  quoteAt: quoteAt ?? fixtureNow,
);

NeedReason _medstation({NeedState state = NeedState.unresolved}) => NeedReason(
  requirement: ItemRequirement(
    kind: RequirementKind.hideout,
    sourceId: 'medstation',
    sourceName: 'Medstation',
    id: 'medstation-1',
    itemIds: const ['item-x'],
    progressIds: const [],
    count: 1,
    gate: RequirementGate(),
    stationLevel: 1,
    foundInRaid: true,
  ),
  state: state,
  message: 'Medstation: needs it found in raid',
  detail: 'needs it found in raid',
  remaining: 1,
);

ItemDecision _decision({
  List<NeedReason> reasons = const [],
  List<String> warnings = const [],
  num? fleaGross,
  num? traderGross,
  String? traderName,
  num? fleaPerSlot,
  num? traderPerSlot,
  num? firNeed,
  num? nonFirNeed,
  bool? fleaEligible = true,
}) => ItemDecision(
  recommendation: Recommendation.check,
  reasons: reasons,
  warnings: warnings,
  fleaGross: fleaGross,
  traderGross: traderGross,
  traderName: traderName,
  fleaPerSlot: fleaPerSlot,
  traderPerSlot: traderPerSlot,
  firNeed: firNeed,
  nonFirNeed: nonFirNeed,
  fleaEligible: fleaEligible,
);

/// Mounts [build] over [selection] in a themed, tall window.
Future<void> _mount(
  WidgetTester tester,
  _FakeSelection selection,
  Widget Function(RequirementExpansion expansion) build,
) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final expansion = RequirementExpansion(selection);
  addTearDown(expansion.dispose);
  addTearDown(selection.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(Brightness.dark),
      home: Scaffold(body: SingleChildScrollView(child: build(expansion))),
    ),
  );
}

Future<void> _mountWhy(WidgetTester tester, _FakeSelection selection) => _mount(
  tester,
  selection,
  (expansion) => WhySection(selection: selection, expansion: expansion),
);

Future<void> _mountPrices(WidgetTester tester, _FakeSelection selection) =>
    _mount(tester, selection, (_) => PricesSection(selection: selection));

Finder _section(String title) => find.byWidgetPredicate(
  (w) => w is ScannerSection && w.title == title,
  description: 'ScannerSection "$title"',
);

/// Opens Scanner with [id] picked by hand, at [size].
Future<M1Harness> _scannerWithItem(
  WidgetTester tester,
  Size size, {
  double scale = 1,
  ScanFakePorts? ports,
  ScanFrameRecorder? recorder,
}) async {
  final h = await pumpM1(
    tester,
    size: size,
    scale: scale,
    scanPorts: ports,
    scanFrameRecorder: recorder,
  );
  await tester.runAsync(
    () => h.services.selection.selectManual(
      h.services.catalog.snapshot!.items['item-a']!,
    ),
  );
  await tester.tap(find.byKey(const Key('nav-scanner')));
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('scanner-workspace: Wide window places Why beside Prices', (
    tester,
  ) async {
    await _scannerWithItem(tester, const Size(1660, 870));
    final column = tester.getRect(find.byType(ScannerScreen));
    final why = tester.getRect(_section('Why'));
    final prices = tester.getRect(_section('Prices'));
    final evidence = tester.getRect(_section('Scan evidence'));

    expect(why.left, column.left + EmberSpace.lg);
    expect(prices.left, greaterThanOrEqualTo(why.right));
    expect(prices.top, why.top);
    expect(
      evidence.top,
      greaterThanOrEqualTo(
        why.bottom > prices.bottom ? why.bottom : prices.bottom,
      ),
    );
    for (final rect in [why, prices, evidence]) {
      expect(rect.left, greaterThanOrEqualTo(column.left));
      expect(rect.right, lessThanOrEqualTo(column.right));
      expect(rect.top, greaterThanOrEqualTo(column.top));
      expect(rect.bottom, lessThanOrEqualTo(column.bottom));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('scanner-workspace: Narrow window stacks the sections', (
    tester,
  ) async {
    // The docked inspector leaves the main column 706 wide at 1100, under
    // the 720 side-by-side width.
    await _scannerWithItem(tester, const Size(1100, 720));
    final column = tester.getRect(find.byType(ScannerScreen));
    expect(column.width, lessThan(720));
    final why = tester.getRect(_section('Why'));
    final prices = tester.getRect(_section('Prices'));
    final evidence = tester.getRect(_section('Scan evidence'));

    expect(why.left, column.left + EmberSpace.lg);
    expect(prices.left, why.left);
    expect(evidence.left, why.left);
    expect(prices.width, why.width);
    expect(evidence.width, why.width);
    expect(why.width, column.width - 2 * EmberSpace.lg);
    expect(prices.top, greaterThanOrEqualTo(why.bottom));
    expect(evidence.top, greaterThanOrEqualTo(prices.bottom));

    // The column scrolls as one when the sections do not fit.
    await tester.ensureVisible(_section('Scan evidence'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_section('Scan evidence')).bottom,
      lessThanOrEqualTo(720),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('scanner-workspace: Side by side from 720 pixels of column', (
    tester,
  ) async {
    // A 748 pixel window leaves the main column exactly 720 wide.
    await _scannerWithItem(tester, const Size(748, 720));
    expect(tester.getRect(find.byType(ScannerScreen)).width, 720);
    expect(
      tester.getTopLeft(_section('Prices')).dy,
      tester.getTopLeft(_section('Why')).dy,
    );
    expect(
      tester.getTopLeft(_section('Prices')).dx,
      greaterThan(tester.getTopLeft(_section('Why')).dx),
    );
  });

  for (final size in [const Size(1660, 870), const Size(740, 720)]) {
    testWidgets(
      size.width == 1660
          ? 'scanner-workspace: No bordered card'
          : 'scanner-workspace: No bordered card at narrow width',
      (tester) async {
        await _scannerWithItem(tester, size);
        final screen = find.byType(ScannerScreen);
        expect(
          find.descendant(of: screen, matching: find.byType(GridPanel)),
          findsNothing,
        );
        // Nothing between the column and a section paints a border or a fill.
        for (final type in [
          DecoratedBox,
          ColoredBox,
          Material,
          Card,
          PhysicalModel,
        ]) {
          final boxes = find.descendant(
            of: screen,
            matching: find.byType(type),
          );
          for (final box in boxes.evaluate()) {
            expect(
              find.descendant(
                of: find.byWidget(box.widget),
                matching: find.byType(ScannerSection),
              ),
              findsNothing,
              reason: 'a $type wraps a section',
            );
          }
        }
        expect(find.byType(ScannerSection), findsNWidgets(3));
      },
    );
  }

  testWidgets('scanner-workspace: Needs for a selected item', (tester) async {
    final selection = _FakeSelection()
      ..show(
        'item-x',
        _item(),
        _decision(reasons: [_medstation()], firNeed: 1, nonFirNeed: 0),
      );
    await _mountWhy(tester, selection);

    expect(
      tester.widget<Text>(find.byKey(const Key('why-summary'))).data,
      'Still needed · Found in raid 1 · Not found in raid 0',
    );
    expect(find.text('Medstation level 1'), findsOneWidget);
    expect(find.text("Hideout • Can't confirm"), findsOneWidget);
  });

  testWidgets('scanner-workspace: No item or unavailable item data', (
    tester,
  ) async {
    final none = _FakeSelection();
    await _mountWhy(tester, none);
    expect(find.text('Pick or scan an item to see its needs.'), findsOneWidget);
    expect(find.byKey(const Key('why-summary')), findsNothing);
    expect(find.textContaining('Optional uses'), findsNothing);

    final unavailable = _FakeSelection()..selectedId = 'item-x';
    await _mountWhy(tester, unavailable);
    expect(find.text('Item data unavailable'), findsOneWidget);
    expect(find.text('Pick or scan an item to see its needs.'), findsNothing);
    expect(find.byKey(const Key('why-summary')), findsNothing);

    final noPrices = _FakeSelection()..selectedId = 'item-x';
    await _mountPrices(tester, noPrices);
    expect(find.text('Item data unavailable'), findsOneWidget);
    expect(find.byKey(const Key('prices-flea')), findsNothing);
  });

  testWidgets(
    'scanner-workspace: Warning that repeats the found-in-raid question',
    (tester) async {
      const other = 'Tracker progress missing or out of date';
      final selection = _FakeSelection()
        ..show(
          'item-x',
          _item(),
          _decision(
            reasons: [_medstation()],
            warnings: const [_firWarning, other],
          ),
        );
      await _mountWhy(tester, selection);

      expect(find.text(other), findsOneWidget);
      expect(find.text(_firWarning), findsNothing);
      final style = tester.widget<Text>(find.text(other)).style!;
      expect(style.color, tester.element(find.text(other)).ember.warnInk);
    },
  );

  testWidgets('scanner-workspace: Recording stopped', (tester) async {
    final ports = ScanFakePorts();
    final writers = <FakeRecordWriter>[];
    final root = Directory.systemTemp.createTempSync('blackgrid-workspace-');
    addTearDown(() => root.deleteSync(recursive: true));
    final recorder = ScanFrameRecorder(
      root: root.path,
      writerFactory:
          ({required folder, required token, required onAnswer}) async {
            final writer = FakeRecordWriter(token, onAnswer);
            writers.add(writer);
            return writer;
          },
    );
    final h = await _scannerWithItem(
      tester,
      const Size(1660, 870),
      ports: ports,
      recorder: recorder,
    );
    await tester.runAsync(() async {
      await h.services.scanner.setLiveScan(true);
      await h.services.scanner.settled;
      await h.services.scanner.setRecording(true);
    });
    recorder.record(recordedScan('failure'));
    writers.single.fail('failure', 'synthetic disk failure');
    await tester.pumpAndSettle();

    final note = find.byKey(const Key('recording-stop-note'));
    expect(note, findsOneWidget);
    expect(
      find.textContaining('Recording stopped: synthetic disk failure'),
      findsOneWidget,
    );
    final why = tester.getRect(_section('Why'));
    final prices = tester.getRect(_section('Prices'));
    final evidence = tester.getRect(_section('Scan evidence'));
    expect(tester.getRect(note).bottom, lessThanOrEqualTo(why.top));
    expect(tester.getRect(note).bottom, lessThanOrEqualTo(prices.top));
    expect(prices.top, why.top);
    expect(evidence.top, greaterThanOrEqualTo(why.bottom));
    expect(evidence.top, greaterThanOrEqualTo(prices.bottom));
    addTearDown(
      () => tester.runAsync(() => recorder.close(timeout: Duration.zero)),
    );
  });

  testWidgets('scanner-workspace: Needs unknown', (tester) async {
    final selection = _FakeSelection()
      ..show('item-x', _item(), _decision(reasons: [_medstation()]));
    await _mountWhy(tester, selection);

    expect(
      tester.widget<Text>(find.byKey(const Key('why-summary'))).data,
      'Still needed · Found in raid Unknown · Not found in raid Unknown',
    );
  });

  testWidgets('scanner-workspace: Item with both prices', (tester) async {
    final selection = _FakeSelection()
      ..show(
        'item-x',
        _item(),
        _decision(
          fleaGross: 21800,
          traderGross: 9400,
          traderName: 'Therapist',
          fleaPerSlot: 10900,
          traderPerSlot: 4700,
        ),
      );
    await _mountPrices(tester, selection);

    Finder inRow(String key, String text) =>
        find.descendant(of: find.byKey(Key(key)), matching: find.text(text));
    expect(inRow('prices-flea', 'Flea'), findsOneWidget);
    expect(inRow('prices-flea', '24 h average'), findsOneWidget);
    expect(inRow('prices-flea', '₽21800'), findsOneWidget);
    expect(inRow('prices-trader', 'Trader'), findsOneWidget);
    expect(inRow('prices-trader', 'Therapist'), findsOneWidget);
    expect(inRow('prices-trader', '₽9400'), findsOneWidget);
    expect(inRow('prices-per-slot-flea', 'Per slot'), findsOneWidget);
    expect(inRow('prices-per-slot-flea', 'Flea'), findsOneWidget);
    expect(inRow('prices-per-slot-flea', '₽10900'), findsOneWidget);
    expect(inRow('prices-per-slot-trader', 'Trader'), findsOneWidget);
    expect(inRow('prices-per-slot-trader', '₽4700'), findsOneWidget);
    expect(inRow('prices-updated', 'Updated'), findsOneWidget);
    expect(inRow('prices-updated', 'tarkov.dev'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('prices-updated')),
        matching: find.byType(FreshnessTag),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('freshness-tag')), findsOneWidget);
    // Values are right-aligned in one column.
    final right = tester.getTopRight(find.text('₽21800')).dx;
    for (final value in ['₽9400', '₽10900', '₽4700']) {
      expect(tester.getTopRight(find.text(value)).dx, right);
    }
    final section = tester.widget<ScannerSection>(_section('Prices'));
    expect(section.subtitle, contains('per item and per slot'));
    expect(section.subtitle, contains('before Flea fees'));
  });

  testWidgets('scanner-workspace: Item that cannot be sold on the Flea', (
    tester,
  ) async {
    final selection = _FakeSelection()
      ..show(
        'item-x',
        _item(),
        _decision(
          fleaEligible: false,
          traderGross: 9400,
          traderName: 'Therapist',
          traderPerSlot: 4700,
        ),
      );
    await _mountPrices(tester, selection);

    expect(
      find.descendant(
        of: find.byKey(const Key('prices-flea')),
        matching: find.text("Can't be sold on the Flea"),
      ),
      findsOneWidget,
    );
    expect(find.text('24 h average'), findsNothing);
    expect(find.byKey(const Key('freshness-tag')), findsNothing);
    expect(find.text('Therapist'), findsOneWidget);
    expect(find.text('₽9400'), findsOneWidget);
    expect(find.text('₽4700'), findsOneWidget);
    // Only the trader has a per-slot value.
    expect(find.byKey(const Key('prices-per-slot-flea')), findsNothing);
    expect(find.text('Price unavailable'), findsNothing);
  });

  testWidgets('scanner-workspace: Missing prices', (tester) async {
    final selection = _FakeSelection()..show('item-x', _item(), _decision());
    await _mountPrices(tester, selection);

    // Flea, Trader, and each per-slot value.
    expect(find.text('Price unavailable'), findsNWidgets(4));
    expect(find.text('Unavailable'), findsNothing);
    expect(find.byKey(const Key('freshness-tag')), findsNothing);
  });

  testWidgets('scanner-workspace: Accepted scan', (tester) async {
    final ports = ScanFakePorts();
    final h = await _scannerWithItem(
      tester,
      const Size(1660, 870),
      ports: ports,
    );
    await tester.runAsync(
      () => publishTargetedScan(
        h.services.scanner,
        ports,
        text: 'Alternative component',
      ),
    );
    await tester.pumpAndSettle();

    final evidence = _section('Scan evidence');
    expect(
      find.descendant(
        of: evidence,
        matching: find.text('Alternative component'),
      ),
      findsOneWidget,
    );
    final rect = tester.getRect(evidence);
    expect(
      rect.top,
      greaterThanOrEqualTo(tester.getRect(_section('Why')).bottom),
    );
    expect(
      rect.top,
      greaterThanOrEqualTo(tester.getRect(_section('Prices')).bottom),
    );
  });

  testWidgets('scanner-workspace: No scan yet', (tester) async {
    await _scannerWithItem(tester, const Size(1660, 870));

    expect(
      find.descendant(
        of: _section('Scan evidence'),
        matching: find.text('No scan published yet'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _section('Why'),
        matching: find.byKey(const Key('why-summary')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _section('Prices'),
        matching: find.byKey(const Key('prices-flea')),
      ),
      findsOneWidget,
    );
  });
}
