import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:test/test.dart';

import 'support/wire.dart';

ProgressCatalog _parseTraders(Map<String, dynamic> traders) =>
    parseProgressCatalog(
      {
        'tasks': {'task-a': taskWire('task-a')},
      },
      {
        'station-a': stationWire('station-a'),
      },
      {'trader-a', 'trader-b'},
      null,
      null,
      rawTraders: traders,
      traderDictionary: {
        'prapor-name': 'Prapor',
        'fence-name': 'Fence',
      },
    );

Map<String, dynamic> _trader(
  String id,
  String name,
  String normalizedName,
  Object? levels,
) => {
  'id': id,
  'name': name,
  'normalizedName': normalizedName,
  'levels': levels,
};

void main() {
  test('keeps trader levels in ascending order', () {
    final catalog = _parseTraders({
      'trader-a': _trader('trader-a', 'prapor-name', 'prapor', [
        {'level': 4},
        {'level': 1},
        {'level': 3},
        {'level': 2},
      ]),
      'trader-b': _trader('trader-b', 'fence-name', 'fence', [
        {'level': 3},
        {'level': 1},
        {'level': 2},
      ]),
    });

    final traders = {for (final trader in catalog.traders!) trader.id: trader};
    expect(traders.keys, unorderedEquals(['trader-a', 'trader-b']));
    expect(traders['trader-a']!.name, 'Prapor');
    expect(traders['trader-a']!.normalizedName, 'prapor');
    expect(traders['trader-a']!.levels, [1, 2, 3, 4]);
    expect(traders['trader-b']!.name, 'Fence');
    expect(traders['trader-b']!.normalizedName, 'fence');
    expect(traders['trader-b']!.levels, [1, 2, 3]);
    expect(catalog.tasks.single.id, 'task-a');
    expect(catalog.stations.single.id, 'station-a');
  });

  test('missing or non-positive levels become unknown', () {
    final malformed = <String, Map<String, dynamic>>{
      'missing': <String, dynamic>{},
      'null': {'levels': null},
      'not a list': {'levels': '1'},
      'non-object row': {'levels': [1]},
      'missing number': {
        'levels': [<String, Object?>{}],
      },
      'malformed row beside valid level': {
        'levels': [
          {'level': 1},
          {'level': 2.5},
        ],
      },
      'zero': {
        'levels': [
          {'level': 0},
        ],
      },
      'negative': {
        'levels': [
          {'level': -1},
        ],
      },
      'fractional': {
        'levels': [
          {'level': 1.5},
        ],
      },
      'non-number': {
        'levels': [
          {'level': '2'},
        ],
      },
    };
    for (final entry in malformed.entries) {
      final badTrader = <String, dynamic>{
        'id': 'trader-a',
        'name': 'prapor-name',
        'normalizedName': 'prapor',
        ...entry.value,
      };
      final catalog = _parseTraders({
        'trader-a': badTrader,
        'trader-b': _trader('trader-b', 'fence-name', 'fence', [
          {'level': 2},
          {'level': 1},
        ]),
      });
      final traders = {for (final trader in catalog.traders!) trader.id: trader};
      expect(traders['trader-a']!.levels, isNull, reason: entry.key);
      expect(traders['trader-b']!.levels, [1, 2], reason: entry.key);
      expect(catalog.tasks.single.id, 'task-a', reason: entry.key);
      expect(catalog.stations.single.id, 'station-a', reason: entry.key);
    }
  });

  test('duplicate level numbers become unknown', () {
    final catalog = _parseTraders({
      'trader-a': _trader('trader-a', 'prapor-name', 'prapor', [
        {'level': 1},
        {'level': 2},
        {'level': 2},
      ]),
      'trader-b': _trader('trader-b', 'fence-name', 'fence', [
        {'level': 1},
        {'level': 2},
        {'level': 3},
      ]),
    });
    final traders = {for (final trader in catalog.traders!) trader.id: trader};
    expect(traders['trader-a']!.levels, isNull);
    expect(traders['trader-b']!.levels, [1, 2, 3]);
    expect(catalog.tasks.single.id, 'task-a');
    expect(catalog.stations.single.id, 'station-a');
  });
}
