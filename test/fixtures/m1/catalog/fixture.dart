import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/catalog_normalizer.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/progress.dart';

final fixtureNow = DateTime.utc(2026, 10, 6);
Map<String, dynamic> wireFixture() => Map<String, dynamic>.from(
  jsonDecode(
    File('test/fixtures/m1/catalog/six_datasets.json').readAsStringSync(),
  ) as Map,
);
// Minimized shape observed at /{regular,pve,pvp-season}/tasks: three
// separately gated tasks reuse item and non-item objective IDs. Public dataset
// envelopes provide data/translations, but no source update timestamp.
Map<String, dynamic> sharedObjectiveWireFixture() {
  final j = wireFixture();
  for (final key in catalogDatasets) {
    (j[key] as Map).remove('updated');
    j[key]['translations'] = <String>[];
  }
  final item = j['items']['data']['items']['item-a'] as Map;
  item['lastScan'] = item.remove('lastScanISO');
  final template = j['tasks']['data']['tasks']['task-a'] as Map;
  j['tasks']['data']['tasks'] = {
    for (final owner in ['task-a', 'task-b', 'task-c'])
      owner: {
        ...template,
        'id': owner,
        'normalizedName': 'synthetic-$owner',
        'minPlayerLevel': owner == 'task-a' ? 1 : 2,
        'objectives': [
          {'id': 'shared-find-quest', 'type': 'findQuestItem', 'count': 1},
          {
            'id': 'shared-find-item',
            'type': 'findItem',
            'items': ['item-a'],
            'count': 1,
            'foundInRaid': true,
            'optional': false,
          },
          {'id': 'shared-give-quest', 'type': 'giveQuestItem', 'count': 1},
          {'id': 'shared-visit', 'type': 'visit', 'optional': false},
        ],
      },
  };
  return j;
}

Map<String, dynamic> progressWire() => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/m1/progress/progress.json').readAsStringSync())
      as Map,
);
CatalogSnapshot fixtureCatalog({
  GameMode mode = GameMode.pvp,
  Map<String, dynamic>? wire,
}) {
  final j = wire ?? wireFixture();
  return normalizeCatalog(
    CatalogWireCandidate(
      mode: mode,
      observedAt: fixtureNow,
      datasets: {for (final key in catalogDatasets) key: jsonEncode(j[key])},
      localization: {
        for (final key in catalogTranslations) key: jsonEncode(j['${key}_en']),
      },
    ),
  );
}

CatalogItem saleItem({
  bool? noFlea = false,
  int? minimum = 0,
  num? price = 400,
  DateTime? quoteAt,
  num? width = 2,
  num? height = 2,
  Iterable<CashOffer>? offers,
}) => CatalogItem(
  id: 'item-a',
  name: 'Synthetic component',
  normalizedName: 'synthetic-component',
  width: width,
  height: height,
  noFlea: noFlea,
  minLevelForFlea: minimum,
  fleaPrice: price,
  quoteAt: quoteAt ?? fixtureNow,
  sellOffers:
      offers ??
      const [CashOffer(traderId: 'trader-a', currency: 'RUB', price: 120)],
);
CatalogSnapshot decisionCatalog({
  CatalogItem? item,
  Iterable<ItemRequirement> requirements = const [],
  DateTime? observedAt,
  Map<String, DateTime?>? times,
}) => CatalogSnapshot(
  mode: GameMode.pvp,
  revision: 'synthetic-revision',
  observedAt: observedAt ?? fixtureNow,
  items: {'item-a': item ?? saleItem()},
  traders: const {
    'trader-a': CatalogTrader(id: 'trader-a', name: 'Synthetic Alpha'),
    'trader-b': CatalogTrader(id: 'trader-b', name: 'Synthetic Beta'),
    'trader-unnamed': CatalogTrader(id: 'trader-unnamed'),
  },
  requirements: requirements,
  sourceTimestamps:
      times ?? {for (final key in catalogDatasets) key: fixtureNow},
);
ProgressSnapshot decisionProgress({
  Map<String, EntityProgress> tasks = const {},
  Map<String, EntityProgress> objectives = const {},
  Map<String, EntityProgress> modules = const {},
  Map<String, EntityProgress> parts = const {},
  DateTime? observedAt,
  int? playerLevel = 30,
  int? edition = 1,
  String? faction = 'USEC',
  GameMode mode = GameMode.pvp,
}) => ProgressSnapshot(
  mode: mode,
  credentialSession: 1,
  owner: 'synthetic-owner',
  observedAt: observedAt ?? fixtureNow,
  playerLevel: playerLevel,
  gameEdition: edition,
  faction: faction,
  tasks: tasks,
  objectives: objectives,
  modules: modules,
  parts: parts,
);
ItemRequirement taskNeed({
  num? count = 3,
  bool? fir = true,
  RequirementGate? gate,
  Iterable<String> items = const ['item-a'],
  Iterable<String> ids = const ['objective-a'],
  bool optional = false,
}) => ItemRequirement(
  kind: RequirementKind.task,
  sourceId: 'task-a',
  sourceName: 'Synthetic task',
  id: 'objective-a',
  itemIds: items,
  progressIds: ids,
  count: count,
  foundInRaid: fir,
  gate:
      gate ??
      RequirementGate(
        minPlayerLevel: 1,
        faction: 'Any',
        editions: const [],
        taskStatuses: const {},
        stations: const {},
      ),
  optional: optional,
);
