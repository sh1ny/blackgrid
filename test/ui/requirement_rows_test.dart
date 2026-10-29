import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/ui/requirement_rows.dart';

const _productId = '5a0000000000000000000001';
const _traderId = '5a0000000000000000000002';
const _taskId = '5a0000000000000000000003';

CatalogItem _item(String id, String name) =>
    CatalogItem(id: id, name: name, normalizedName: name.toLowerCase());

CatalogSnapshot _catalog({
  Map<String, CatalogItem>? items,
  Map<String, CatalogTrader>? traders,
}) => CatalogSnapshot(
  mode: GameMode.pve,
  revision: 'r1',
  observedAt: DateTime.utc(2026),
  items:
      items ??
      {
        _productId: _item(_productId, 'Gunpowder "Kite"'),
        'ak': _item('ak', 'AK-74N'),
      },
  traders:
      traders ??
      {_traderId: const CatalogTrader(id: _traderId, name: 'Prapor')},
  requirements: const [],
);

ItemRequirement _req(
  RequirementKind kind, {
  String sourceName = 'Source',
  num? count,
  bool? foundInRaid,
  bool optional = false,
  int? stationLevel,
  String? stationName,
  String? productItemId,
  num? productCount,
  String? traderId,
  int? traderLevel,
  String? unlockTaskId,
  String? unlockTaskName,
  bool? tool,
}) => ItemRequirement(
  kind: kind,
  sourceId: 'src',
  sourceName: sourceName,
  id: 'req',
  itemIds: const ['item'],
  progressIds: const [],
  count: count,
  foundInRaid: foundInRaid,
  gate: RequirementGate(),
  optional: optional,
  stationLevel: stationLevel,
  stationName: stationName,
  productItemId: productItemId,
  productCount: productCount,
  traderId: traderId,
  traderLevel: traderLevel,
  unlockTaskId: unlockTaskId,
  unlockTaskName: unlockTaskName,
  tool: tool,
);

NeedReason _reason(
  ItemRequirement requirement,
  NeedState state, {
  String detail = 'some detail',
  num? remaining,
}) => NeedReason(
  requirement: requirement,
  state: state,
  message: '${requirement.sourceName}: $detail',
  detail: detail,
  remaining: remaining,
);

RequirementRowView _row(
  ItemRequirement requirement,
  NeedState state, {
  String detail = 'some detail',
  num? remaining,
  CatalogSnapshot? catalog,
}) => requirementRow(
  _reason(requirement, state, detail: detail, remaining: remaining),
  catalog ?? _catalog(),
);

ItemRequirement _craft({
  num? count,
  bool? tool,
  int? level = 2,
  num? productCount = 2,
  String productItemId = _productId,
}) => _req(
  RequirementKind.craft,
  sourceName: 'Gunpowder "Kite"',
  count: count,
  optional: true,
  stationName: 'Workbench',
  stationLevel: level,
  productItemId: productItemId,
  productCount: productCount,
  tool: tool,
);

ItemRequirement _barter({int? level = 3, String? task = 'Gunsmith - Part 4'}) =>
    _req(
      RequirementKind.barter,
      sourceName: 'AK-74N',
      optional: true,
      productItemId: 'ak',
      productCount: 1,
      traderId: _traderId,
      traderLevel: level,
      unlockTaskId: task == null ? null : _taskId,
      unlockTaskName: task,
    );

String _allText(RequirementRowView v) => [
  v.title,
  v.kindTag,
  v.stateLabel,
  v.sourceLine,
  v.needs,
  v.remaining,
  v.foundInRaidLine,
  v.reason,
].whereType<String>().join('\n');

void main() {
  group('titles and source lines', () {
    test('craft row titles the product with its count and names the station '
        'level', () {
      final v = _row(_craft(count: 1), NeedState.irrelevant);
      expect(v.title, 'Gunpowder "Kite" ×2');
      expect(v.sourceLine, 'Workbench level 2');
    });

    test('barter row names the trader level and the unlocking task', () {
      final v = _row(_barter(), NeedState.irrelevant);
      expect(v.title, 'AK-74N');
      expect(v.sourceLine, 'Prapor LL3, unlocked by Gunsmith - Part 4');
    });

    test('a barter row without a trader level names the trader alone', () {
      final v = _row(_barter(level: null, task: null), NeedState.irrelevant);
      expect(v.sourceLine, 'Prapor');
    });

    test('hideout row titles the station and its level', () {
      final v = _row(
        _req(
          RequirementKind.hideout,
          sourceName: 'Defective Wall',
          stationLevel: 2,
        ),
        NeedState.actionable,
      );
      expect(v.title, 'Defective Wall level 2');
      expect(v.sourceLine, isNull);
    });

    test('task row titles the task name', () {
      final v = _row(
        _req(RequirementKind.task, sourceName: 'Delivery from the Past'),
        NeedState.actionable,
      );
      expect(v.title, 'Delivery from the Past');
      expect(v.sourceLine, isNull);
    });

    test('a trader without a name falls back to its id', () {
      final v = _row(
        _barter(level: null, task: null),
        NeedState.irrelevant,
        catalog: _catalog(
          traders: {_traderId: const CatalogTrader(id: _traderId)},
        ),
      );
      expect(v.sourceLine, _traderId);
    });

    test('a product item missing from the catalog falls back to its id', () {
      final v = _row(
        _craft(productCount: 1),
        NeedState.irrelevant,
        catalog: _catalog(items: {}),
      );
      expect(v.title, _productId);
    });

    test('a fully resolved craft row shows no 24-hex id', () {
      final v = _row(_craft(count: 1), NeedState.irrelevant);
      expect(_allText(v), isNot(matches(RegExp(r'[0-9a-f]{24}'))));
    });
  });

  group('kind tag and state label', () {
    test('unresolved hideout row reads Can\'t confirm with a Hideout tag', () {
      final v = _row(
        _req(
          RequirementKind.hideout,
          sourceName: 'Defective Wall',
          stationLevel: 2,
        ),
        NeedState.unresolved,
        detail: 'station module status unknown',
      );
      expect(v.kindTag, 'Hideout');
      expect(v.stateLabel, "Can't confirm");
      final text = _allText(v);
      expect(text, isNot(contains('unresolved')));
      expect(text, isNot(contains('hideout')));
    });

    test('actionable task row reads Needed now with a Task tag', () {
      final v = _row(
        _req(RequirementKind.task, sourceName: 'Delivery from the Past'),
        NeedState.actionable,
      );
      expect(v.kindTag, 'Task');
      expect(v.stateLabel, 'Needed now');
    });

    test('craft row reads Optional use with no raw state or kind name', () {
      final v = _row(_craft(count: 1), NeedState.irrelevant);
      expect(v.kindTag, 'Craft');
      expect(v.stateLabel, 'Optional use');
      final text = _allText(v);
      expect(text, isNot(contains('irrelevant')));
      expect(text, isNot(contains('craft')));
    });

    test('a gated-out task row reads Not for you', () {
      final v = _row(
        _req(RequirementKind.task, sourceName: 'Delivery from the Past'),
        NeedState.irrelevant,
        remaining: 0,
      );
      expect(v.stateLabel, 'Not for you');
      expect(v.remaining, isNull);
    });

    test('a non-FIR copy of a FIR obligation reads Needs found in raid with '
        'its remaining', () {
      final v = _row(
        _req(
          RequirementKind.task,
          sourceName: 'Delivery from the Past',
          count: 3,
          foundInRaid: true,
        ),
        NeedState.irrelevant,
        remaining: 2,
      );
      expect(v.stateLabel, 'Needs found in raid');
      expect(v.remaining, '2 remaining');
    });

    test('an optional task objective reads Optional objective', () {
      final v = _row(
        _req(RequirementKind.task, sourceName: 'T', optional: true),
        NeedState.irrelevant,
      );
      expect(v.stateLabel, 'Optional objective');
    });
  });

  group('quantities', () {
    test(
      'an optional use shows its fractional need without remaining or FIR',
      () {
        final v = _row(_craft(count: 1.5), NeedState.irrelevant);
        expect(v.needs, 'Needs 1.5');
        expect(v.remaining, isNull);
        expect(v.foundInRaidLine, isNull);
      },
    );

    test('a needed-now hideout row shows need, remaining and its FIR rule', () {
      final v = _row(
        _req(
          RequirementKind.hideout,
          sourceName: 'Defective Wall',
          stationLevel: 2,
          count: 2,
          foundInRaid: false,
        ),
        NeedState.actionable,
        remaining: 1.0,
      );
      expect(v.needs, 'Needs 2');
      expect(v.remaining, '1 remaining');
      expect(v.foundInRaidLine, 'Found in raid not required');
    });

    test('a required found-in-raid rule reads Found in raid required', () {
      final v = _row(
        _req(RequirementKind.task, sourceName: 'T', foundInRaid: true),
        NeedState.actionable,
      );
      expect(v.foundInRaidLine, 'Found in raid required');
    });

    test('a done row shows no remaining', () {
      final v = _row(
        _req(RequirementKind.task, sourceName: 'T', count: 1),
        NeedState.satisfied,
        remaining: 0,
      );
      expect(v.stateLabel, 'Done');
      expect(v.remaining, isNull);
    });

    test('a craft tool row says it is not used up instead of its need', () {
      final v = _row(_craft(count: 1, tool: true), NeedState.irrelevant);
      expect(v.needs, 'Tool, not used up');
      expect(_allText(v), isNot(contains('Needs 1')));
    });

    test('a row without a count shows no need', () {
      final v = _row(_craft(), NeedState.irrelevant);
      expect(v.needs, isNull);
    });
  });

  group('reason line', () {
    test('an obligation reason line drops the source name', () {
      final v = _row(
        _req(
          RequirementKind.hideout,
          sourceName: 'Defective Wall',
          stationLevel: 2,
        ),
        NeedState.unresolved,
        detail: 'station module status unknown',
      );
      expect(v.reason, 'station module status unknown');
      expect(v.reason, isNot(startsWith('Defective Wall')));
    });

    test('craft and barter rows have no reason line', () {
      const text = 'optional use, not an automatic obligation';
      for (final req in [_craft(count: 1), _barter()]) {
        final v = _row(req, NeedState.irrelevant, detail: text);
        expect(v.reason, isNull);
        expect(_allText(v), isNot(contains(text)));
      }
    });
  });

  test('a stored projection without display facts still loads; an old craft '
      'row keeps its stored source name', () {
    final v = _row(
      _req(RequirementKind.craft, sourceName: 'craft craft-a', optional: true),
      NeedState.irrelevant,
    );
    expect(v.title, 'craft craft-a');
    expect(v.kindTag, 'Craft');
    expect(v.stateLabel, 'Optional use');
    expect(v.sourceLine, isNull);
  });

  test('requirementRow works without a catalog by falling back to ids', () {
    final v = requirementRow(
      _reason(_craft(productCount: 1), NeedState.irrelevant),
      null,
    );
    expect(v.title, _productId);
  });

  test('arrangeRequirementRows orders obligations by state and keeps catalog '
      'order within a state', () {
    NeedReason r(String name, NeedState s, [RequirementKind? k]) =>
        _reason(_req(k ?? RequirementKind.task, sourceName: name), s);
    final input = [
      r('craft-1', NeedState.irrelevant, RequirementKind.craft),
      r('irrelevant', NeedState.irrelevant),
      r('done-1', NeedState.satisfied),
      r('later-1', NeedState.future),
      r('barter-1', NeedState.irrelevant, RequirementKind.barter),
      r('now-1', NeedState.actionable),
      r('unknown-1', NeedState.unresolved, RequirementKind.hideout),
      r('later-2', NeedState.future),
      r('now-2', NeedState.actionable, RequirementKind.hideout),
      r('done-2', NeedState.satisfied),
    ];
    final (:obligations, :optionalUses) = arrangeRequirementRows(input);
    expect(obligations.map((n) => n.requirement.sourceName), [
      'now-1',
      'now-2',
      'later-1',
      'later-2',
      'unknown-1',
      'done-1',
      'done-2',
      'irrelevant',
    ]);
    expect(optionalUses.map((n) => n.requirement.sourceName), [
      'craft-1',
      'barter-1',
    ]);
  });
}
