import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/data/catalog_normalizer.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/decision_engine.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/progress.dart';

import '../fixtures/m1/catalog/fixture.dart';

void main() {
  for (final field in [
    'stationLevelRequirements',
    'traderRequirements',
    'skillRequirements',
  ]) {
    for (final isNull in [false, true]) {
      test(
        'review 8 hideout $field ${isNull ? 'null' : 'absent'} stays Check',
        () {
          final wire = wireFixture();
          wire['tasks']['data']['tasks'] = <String, dynamic>{};
          final level =
              wire['hideout']['data']['station-a']['levels'][0] as Map;
          if (isNull) {
            level[field] = null;
          } else {
            level.remove(field);
          }
          final c = fixtureCatalog(wire: wire);
          final item = c.items['item-a']!;
          final decision = const DecisionEngine().evaluate(
            item,
            InspectionContext(
              mode: GameMode.pvp,
              now: fixtureNow,
              catalog: c,
              progress: decisionProgress(
                modules: const {
                  'station-a-1': EntityProgress(
                    complete: false,
                    invalid: false,
                  ),
                },
                parts: const {
                  'part-a': EntityProgress(
                    complete: false,
                    count: 0,
                    invalid: false,
                  ),
                },
              ),
              fir: FirState.yes,
            ),
          );
          expect(decision.recommendation, Recommendation.check);
          expect(
            c.requirements
                .singleWhere((r) => r.kind == RequirementKind.hideout)
                .gate
                .incomplete,
            isTrue,
          );
        },
      );
    }
  }
  test('all six live-shaped collections, dictionaries and fractional uses normalize', () {
    final c = fixtureCatalog();
    expect(c.datasetCounts, {
      'items': 2,
      'traders': 2,
      'tasks': 1,
      'hideout': 1,
      'crafts': 1,
      'barters': 1,
    });
    expect(c.items['item-a']!.name, 'Synthetic component');
    expect(
      c.requirements.where((v) => v.kind == RequirementKind.craft).single.count,
      1.5,
    );
    expect(
      c.requirements
          .where((v) => v.kind == RequirementKind.barter)
          .single
          .count,
      2.5,
    );
    expect(c.items['item-a']!.quoteAt, fixtureNow);
  });
  for (final mode in [GameMode.pvp, GameMode.pve, GameMode.seasonal]) {
    test(
      'shared live objective IDs retain every task owner in ${mode.name}',
      () {
        final c = fixtureCatalog(
          mode: mode,
          wire: sharedObjectiveWireFixture(),
        );
        final requirements = c.requirements
            .where((r) => r.kind == RequirementKind.task)
            .toList();
        expect(c.datasetCounts['tasks'], 3);
        expect(requirements.map((r) => r.sourceId), [
          'task-a',
          'task-b',
          'task-c',
        ]);
        expect(requirements.map((r) => r.id).toSet(), {'shared-find-item'});
        expect(requirements.every((r) => r.ambiguousProgressIdentity), isTrue);
        expect(
          requirements.every((r) => r.progressIds.single == 'shared-find-item'),
          isTrue,
        );
        expect(requirements.map((r) => r.gate.minPlayerLevel), [1, 2, 2]);
        expect(
          c.requirementIndex['item-a']!
              .where((r) => r.kind == RequirementKind.task)
              .map((r) => r.sourceId),
          ['task-a', 'task-b', 'task-c'],
        );
        expect(c.items['item-a']!.quoteAt, fixtureNow);
        expect(c.authoritativeAt(fixtureNow), isTrue);
        final restored = CatalogSnapshot.fromJson(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(c.toJson())) as Map),
        );
        expect(restored.toJson(), c.toJson());
        expect(
          restored.requirements
              .where((r) => r.kind == RequirementKind.task)
              .every((r) => r.ambiguousProgressIdentity),
          isTrue,
        );
      },
    );
  }
  test(
    'same-task duplicate live objective ID still rejects complete candidate',
    () {
      final j = sharedObjectiveWireFixture();
      final objectives =
          j['tasks']['data']['tasks']['task-b']['objectives'] as List;
      objectives.add(objectives.first);
      expect(() => fixtureCatalog(wire: j), throwsFormatException);
    },
  );
  test(
    'shared non-item objectives do not make unique item progress ambiguous',
    () {
      final j = sharedObjectiveWireFixture();
      for (final owner in ['task-a', 'task-b', 'task-c']) {
        j['tasks']['data']['tasks'][owner]['objectives'][1]['id'] =
            '$owner-find';
      }
      final requirements = fixtureCatalog(wire: j).requirements
          .where((r) => r.kind == RequirementKind.task);
      expect(requirements.length, 3);
      expect(requirements.every((r) => !r.ambiguousProgressIdentity), isTrue);
    },
  );
  test(
    'cross-kind progress identity collision still invalidates candidate',
    () {
      final j = wireFixture();
      j['tasks']['data']['tasks']['task-a']['objectives'][0]['id'] = 'part-a';
      expect(() => fixtureCatalog(wire: j), throwsFormatException);
    },
  );
  test('unambiguous requirements and previous payloads keep explicit false identity ambiguity', () {
    final need = fixtureCatalog().requirements.first;
    expect(need.ambiguousProgressIdentity, isFalse);
    final previous = Map<String, dynamic>.from(need.toJson())
      ..remove('ambiguousProgressIdentity');
    expect(
      ItemRequirement.fromJson(previous).ambiguousProgressIdentity,
      isFalse,
    );
  });
  test('pairing carries shared handover identity ambiguity', () {
    final j = sharedObjectiveWireFixture();
    for (final owner in ['task-a', 'task-b', 'task-c']) {
      final objectives =
          j['tasks']['data']['tasks'][owner]['objectives'] as List;
      objectives.add({
        'id': '$owner-give-item',
        'type': 'giveItem',
        'items': ['item-a'],
        'count': 1,
        'foundInRaid': true,
        'optional': false,
      });
    }
    final requirements = fixtureCatalog(wire: j).requirements
        .where((r) => r.kind == RequirementKind.task)
        .toList();
    expect(requirements.length, 3);
    for (final r in requirements) {
      expect(r.progressIds, contains('shared-find-item'));
      expect(r.completionId, '${r.sourceId}-give-item');
      expect(r.ambiguousProgressIdentity, isTrue);
    }
  });
  test('typed payload roundtrips immutable snapshots and indexes', () {
    final c = fixtureCatalog();
    final restored = CatalogSnapshot.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(c.toJson())) as Map),
    );
    expect(restored.toJson(), c.toJson());
    expect(restored.search('Component').map((v) => v.id), ['item-a', 'item-b']);
    expect(() => restored.items.clear(), throwsUnsupportedError);
    expect(
      () => restored.requirementIndex['item-a']!.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => restored.requirements.first.itemIds.clear(),
      throwsUnsupportedError,
    );
  });
  for (final query in [
    'item-a',
    'Synthetic component',
    'Component',
    'synthetic-component',
  ]) {
    test(
      'search indexes canonical identity/name/short/normalized $query',
      () => expect(fixtureCatalog().search(query).first.id, 'item-a'),
    );
  }
  test('empty tasks/crafts/barters permitted, items and traders required', () {
    final j = wireFixture();
    (j['tasks']['data'] as Map)['tasks'] = {};
    j['crafts']['data'] = [];
    j['barters']['data'] = [];
    expect(fixtureCatalog(wire: j).datasetCounts['tasks'], 0);
    for (final key in ['items', 'traders']) {
      final bad = wireFixture();
      if (key == 'items') {
        bad[key]['data']['items'] = {};
      } else {
        bad[key]['data'] = {};
      }
      expect(() => fixtureCatalog(wire: bad), throwsFormatException);
    }
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'wrong collection': (j) => j['hideout']['data'] = [],
    'missing collection': (j) => (j['crafts'] as Map).remove('data'),
    'mismatched ID': (j) =>
        j['items']['data']['items']['item-a']['id'] = 'other',
    'duplicate objective': (j) =>
        j['tasks']['data']['tasks']['task-a']['objectives'][1]['id'] = 'find-a',
    'duplicate craft': (j) =>
        (j['crafts']['data'] as List).add(j['crafts']['data'][0]),
    'unknown requirement item': (j) =>
        j['hideout']['data']['station-a']['levels'][0]['itemRequirements'][0]['item'] =
            'missing',
    'unknown trader': (j) =>
        j['items']['data']['items']['item-a']['sellToTrader'][0]['trader'] =
            'missing',
    'unknown station': (j) => j['crafts']['data'][0]['station'] = 'missing',
    'negative quantity': (j) =>
        j['barters']['data'][0]['requiredItems'][0]['count'] = -1,
    'invalid quantity': (j) =>
        j['barters']['data'][0]['requiredItems'][0]['count'] = 'NaN',
    'wrong FIR': (j) =>
        j['tasks']['data']['tasks']['task-a']['objectives'][0]['foundInRaid'] =
            'false',
  };
  for (final e in mutations.entries) {
    test('${e.key} invalidates complete candidate', () {
      final j = wireFixture();
      e.value(j);
      expect(() => fixtureCatalog(wire: j), throwsFormatException);
    });
  }
  test('missing six payload and Unknown mode are invalid', () {
    expect(
      () => normalizeCatalog(
        CatalogWireCandidate(
          mode: GameMode.pvp,
          observedAt: fixtureNow,
          datasets: const {},
        ),
      ),
      throwsFormatException,
    );
    expect(() => fixtureCatalog(mode: GameMode.unknown), throwsFormatException);
  });
  test(
    'failed localization keeps complete data and honest normalized fallback',
    () {
      final j = wireFixture();
      j['items_en'] = {'data': []};
      j['traders_en'] = {'data': []};
      final c = fixtureCatalog(wire: j);
      expect(c.localizationErrors, ['items', 'traders']);
      expect(c.items['item-a']!.name, 'synthetic-component');
      expect(c.traders['trader-a']!.name, isNull);
    },
  );
  test(
    'source/schema metadata cannot assert unsupported catalog authority',
    () {
      final c = fixtureCatalog();
      final other = CatalogSnapshot(
        mode: c.mode,
        source: 'unsupported.example',
        revision: c.revision,
        observedAt: c.observedAt,
        items: c.items,
        traders: c.traders,
        requirements: c.requirements,
        sourceTimestamps: c.sourceTimestamps,
      );
      expect(other.authoritativeAt(fixtureNow), isFalse);
      final j = Map<String, dynamic>.from(c.toJson())..['schemaVersion'] = 2;
      expect(() => CatalogSnapshot.fromJson(j), throwsFormatException);
    },
  );
  test('live wire shape without dataset timestamps is authoritative at observation', () {
    final j = wireFixture();
    for (final key in catalogDatasets) {
      expect((j[key] as Map).keys.toSet(), {'data', 'translations'});
    }
    expect(fixtureCatalog(wire: j).authoritativeAt(fixtureNow), isTrue);
  });
  test(
    'items source time is the newest per-item updated; other datasets absent',
    () {
      final c = fixtureCatalog();
      expect(c.sourceTimestamps.keys.toSet(), catalogDatasets.toSet());
      expect(c.sourceTimestamps['items'], DateTime.utc(2026, 10, 5, 23));
      for (final key in catalogDatasets.where((k) => k != 'items')) {
        expect(c.sourceTimestamps[key], isNull, reason: key);
      }
    },
  );
  test('items without updated leave every source time absent and stay authoritative', () {
    final j = wireFixture();
    for (final item in (j['items']['data']['items'] as Map).values) {
      (item as Map).remove('updated');
    }
    final c = fixtureCatalog(wire: j);
    expect(c.sourceTimestamps.values.every((v) => v == null), isTrue);
    expect(c.authoritativeAt(fixtureNow), isTrue);
  });
  test('malformed item updated fails validation', () {
    final j = wireFixture();
    j['items']['data']['items']['item-b']['updated'] = 'yesterday';
    expect(() => fixtureCatalog(wire: j), throwsFormatException);
  });
  test('dataset-level updated is ignored', () {
    final j = wireFixture();
    j['items']['updated'] = '2020-01-01T00:00:00Z';
    j['traders']['updated'] = '2020-01-01T00:00:00Z';
    final c = fixtureCatalog(wire: j);
    expect(c.sourceTimestamps['items'], DateTime.utc(2026, 10, 5, 23));
    expect(c.sourceTimestamps['traders'], isNull);
  });
  test('current catalog string edition identities survive normalization', () {
    final j = wireFixture();
    j['crafts']['data'][0]['gameEditions'] = [
      'edge_of_darkness',
      'eod_tue_edition',
    ];
    expect(
      fixtureCatalog(wire: j).requirements
          .singleWhere((r) => r.kind == RequirementKind.craft)
          .gate
          .editionIds,
      ['edge_of_darkness', 'eod_tue_edition'],
    );
  });
  const goodLink = 'https://assets.tarkov.dev/item-a-icon.webp';
  String? iconLinkAfter(Object? value) {
    final j = wireFixture();
    (j['items']['data']['items']['item-a'] as Map)['iconLink'] = value;
    return fixtureCatalog(wire: j).items['item-a']!.iconLink;
  }

  test('keeps an https assets.tarkov.dev icon link', () {
    expect(iconLinkAfter(goodLink), goodLink);
    final c = fixtureCatalog();
    expect(c.items['item-a']!.iconLink, goodLink);
    expect(c.items['item-b']!.iconLink, isNull);
    final restored = CatalogSnapshot.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(c.toJson())) as Map),
    );
    expect(restored.items['item-a']!.iconLink, goodLink);
  });
  test('drops icon links on another scheme, host, port, query or fragment', () {
    for (final link in [
      'http://assets.tarkov.dev/a.webp',
      'ftp://assets.tarkov.dev/a.webp',
      'https://evil.example/a.webp',
      'https://assets.tarkov.dev.evil.example/a.webp',
      'https://user@assets.tarkov.dev/a.webp',
      'https://assets.tarkov.dev:8443/a.webp',
      'https://assets.tarkov.dev:443/a.webp',
      'https://assets.tarkov.dev/a.webp?x=1',
      'https://assets.tarkov.dev/a.webp?',
      'https://assets.tarkov.dev/a.webp#frag',
      'https://assets.tarkov.dev/a.webp#',
      '//assets.tarkov.dev/a.webp',
      '/a.webp',
    ]) {
      expect(iconLinkAfter(link), isNull, reason: link);
    }
    final j = wireFixture();
    (j['items']['data']['items']['item-a'] as Map)['iconLink'] =
        'https://evil.example/a.webp';
    final tampered = fixtureCatalog(wire: j).toJson();
    ((tampered['items'] as Map)['item-a'] as Map)['iconLink'] =
        'https://evil.example/a.webp';
    expect(
      CatalogSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(tampered)) as Map),
      ).items['item-a']!.iconLink,
      isNull,
    );
  });
  test('treats the unknown-item-icon placeholder as no picture', () {
    expect(
      iconLinkAfter('https://assets.tarkov.dev/unknown-item-icon.jpg'),
      isNull,
    );
  });
  test('drops non-string, empty or unparseable icon links without rejecting the catalog', () {
    for (final value in [
      42,
      true,
      <String>[],
      <String, Object?>{},
      '',
      ' ',
      'http://[bad',
    ]) {
      expect(iconLinkAfter(value), isNull, reason: '$value');
    }
    final j = wireFixture();
    (j['items']['data']['items']['item-a'] as Map)['iconLink'] = 42;
    final c = fixtureCatalog(wire: j);
    expect(c.items.keys, containsAll(['item-a', 'item-b']));
    expect(c.items['item-a']!.shortName, 'Component');
  });
  test('a stored projection without iconLink keys still loads', () {
    final stored = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(fixtureCatalog().toJson())) as Map,
    );
    for (final item in (stored['items'] as Map).values) {
      (item as Map).remove('iconLink');
    }
    final restored = CatalogSnapshot.fromJson(stored);
    expect(restored.items['item-a']!.iconLink, isNull);
    expect(restored.items['item-a']!.shortName, 'Component');
    expect(restored.schemaVersion, 1);
    expect(restored.normalizerVersion, 1);
  });
  test('purchase-only cash offers are not sale offers', () {
    final j = wireFixture();
    final i = j['items']['data']['items']['item-a'] as Map;
    i['buyFromTrader'] = i.remove('sellToTrader');
    expect(fixtureCatalog(wire: j).items['item-a']!.sellOffers, isEmpty);
  });
  test('buildWeapon singular canonical item reference is normalized', () {
    final j = wireFixture();
    final objectives =
        j['tasks']['data']['tasks']['task-a']['objectives'] as List;
    objectives.add({
      'id': 'build-a',
      'type': 'buildWeapon',
      'item': 'item-a',
      'count': 1,
      'optional': false,
    });
    final r = fixtureCatalog(wire: j).requirements
        .singleWhere((r) => r.id == 'build-a');
    expect(r.itemIds, ['item-a']);
    expect(r.foundInRaid, isNull);
  });
  test('duplicate keyed JSON identity cannot silently overwrite candidate', () {
    final j = wireFixture();
    final datasets = {
      for (final key in catalogDatasets) key: jsonEncode(j[key]),
    };
    datasets['items'] = datasets['items']!.replaceFirst(
      '"id":"item-a"',
      '"id":"item-a","id":"item-a"',
    );
    expect(
      () => normalizeCatalog(
        CatalogWireCandidate(
          mode: GameMode.pvp,
          observedAt: fixtureNow,
          datasets: datasets,
        ),
      ),
      throwsFormatException,
    );
  });
  test('nonfinite required count from valid JSON syntax invalidates complete candidate', () {
    final j = wireFixture();
    final datasets = {
      for (final key in catalogDatasets) key: jsonEncode(j[key]),
    };
    datasets['barters'] = datasets['barters']!.replaceFirst(
      '"count":2.5',
      '"count":1e999',
    );
    expect(
      () => normalizeCatalog(
        CatalogWireCandidate(
          mode: GameMode.pvp,
          observedAt: fixtureNow,
          datasets: datasets,
        ),
      ),
      throwsFormatException,
    );
  });
  test('current deployed lastScan is recognized as quote time, never envelope time', () {
    final j = wireFixture();
    final item = j['items']['data']['items']['item-a'] as Map;
    item['lastScan'] = item.remove('lastScanISO');
    expect(fixtureCatalog(wire: j).items['item-a']!.quoteAt, fixtureNow);
    item.remove('lastScan');
    expect(fixtureCatalog(wire: j).items['item-a']!.quoteAt, isNull);
  });
}
