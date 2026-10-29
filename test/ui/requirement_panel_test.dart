import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/selection_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/ui/evidence_panels.dart';
import 'package:blackgrid/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A selection that serves a fixed decision, so the panel is driven without a
/// database, catalog download or decision engine.
class _FakeSelection with ChangeNotifier implements SelectionController {
  @override
  String? selectedId;
  List<NeedReason>? reasons;

  @override
  ItemDecision? get decision => reasons == null
      ? null
      : ItemDecision(
          recommendation: Recommendation.keep,
          reasons: reasons!,
          warnings: const [],
        );

  @override
  CatalogSnapshot? get inspectionCatalog => null;

  /// Inspects [id], whose requirement evidence is [next].
  void inspect(String id, List<NeedReason> next) {
    selectedId = id;
    reasons = next;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeServices implements AppServices {
  _FakeServices(this.selection);

  @override
  final SelectionController selection;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

NeedReason _need(
  RequirementKind kind,
  NeedState state,
  String name, {
  int? stationLevel,
}) => NeedReason(
  requirement: ItemRequirement(
    kind: kind,
    sourceId: name,
    sourceName: name,
    id: name,
    itemIds: const ['item'],
    progressIds: const [],
    count: 2,
    gate: RequirementGate(),
    stationLevel: stationLevel,
  ),
  state: state,
  message: '$name: detail of $name',
  detail: 'detail of $name',
  remaining: 2,
);

NeedReason _task(NeedState state, String name) =>
    _need(RequirementKind.task, state, name);

NeedReason _craft(String name) =>
    _need(RequirementKind.craft, NeedState.irrelevant, name);

NeedReason _barter(String name) =>
    _need(RequirementKind.barter, NeedState.irrelevant, name);

Future<_FakeSelection> _pump(
  WidgetTester tester,
  List<NeedReason> reasons,
) async {
  tester.view.physicalSize = const Size(700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final selection = _FakeSelection()..inspect('item-a', reasons);
  addTearDown(selection.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: blackgridTheme(),
      home: Scaffold(
        body: RequirementPanel(services: _FakeServices(selection)),
      ),
    ),
  );
  return selection;
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('obligations by state, then a collapsed Optional uses header', (
    tester,
  ) async {
    await _pump(tester, [
      _task(NeedState.satisfied, 'Done task'),
      _craft('Craft A'),
      _need(
        RequirementKind.hideout,
        NeedState.actionable,
        'Stash',
        stationLevel: 2,
      ),
      _craft('Craft B'),
      _craft('Craft C'),
    ]);

    expect(find.text('Optional uses (3)'), findsOneWidget);
    expect(find.text('Craft A'), findsNothing);
    expect(find.text('Craft B'), findsNothing);
    expect(find.text('Craft C'), findsNothing);
    final hideout = _top(tester, 'Stash level 2');
    final task = _top(tester, 'Done task');
    final header = _top(tester, 'Optional uses (3)');
    expect(hideout, lessThan(task));
    expect(task, lessThan(header));
  });

  testWidgets('tapping Optional uses lists its rows', (tester) async {
    await _pump(tester, [
      _craft('Craft A'),
      _craft('Craft B'),
      _craft('Craft C'),
    ]);

    await tester.tap(find.text('Optional uses (3)'));
    await tester.pump();

    final header = _top(tester, 'Optional uses (3)');
    final a = _top(tester, 'Craft A');
    final b = _top(tester, 'Craft B');
    final c = _top(tester, 'Craft C');
    expect(header, lessThan(a));
    expect(a, lessThan(b));
    expect(b, lessThan(c));
  });

  testWidgets('only optional uses shows only the collapsed header', (
    tester,
  ) async {
    await _pump(tester, [_barter('Barter A'), _barter('Barter B')]);

    expect(find.text('Optional uses (2)'), findsOneWidget);
    expect(find.text('Barter A'), findsNothing);
    expect(find.text('Barter B'), findsNothing);
  });

  testWidgets('a newly inspected item starts with Optional uses collapsed', (
    tester,
  ) async {
    final selection = await _pump(tester, [
      _craft('Craft A'),
      _craft('Craft B'),
      _craft('Craft C'),
    ]);
    await tester.tap(find.text('Optional uses (3)'));
    await tester.pump();
    expect(find.text('Craft A'), findsOneWidget);

    selection.inspect('item-b', [_craft('Craft D'), _craft('Craft E')]);
    await tester.pump();

    expect(find.text('Optional uses (2)'), findsOneWidget);
    expect(find.text('Craft D'), findsNothing);

    selection.inspect('item-a', [
      _craft('Craft A'),
      _craft('Craft B'),
      _craft('Craft C'),
    ]);
    await tester.pump();

    expect(find.text('Optional uses (3)'), findsOneWidget);
    expect(find.text('Craft A'), findsNothing);
  });

  testWidgets('no Optional uses header without craft or barter rows', (
    tester,
  ) async {
    await _pump(tester, [
      _task(NeedState.actionable, 'Task A'),
      _task(NeedState.future, 'Task B'),
    ]);

    expect(find.text('Task A'), findsOneWidget);
    expect(find.textContaining('Optional uses'), findsNothing);
  });
}
