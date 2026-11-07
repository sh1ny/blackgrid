import 'dart:collection';

import 'package:blackgrid/domain/map_marker_query.dart';
import 'package:test/test.dart';

void main() {
  test('owner budgets shared searchable facts without copying their text', () {
    var reserved = 0;
    final owner = MapMarkerMetadataOwner(
      reserveMaterialized: (bytes) => reserved += bytes,
      releaseMaterialized: (bytes) => reserved -= bytes,
    );
    final shared = 'shared-${'x' * 4096}-task';
    final metadata = [
      for (var index = 0; index < 24; index++)
        MapMarkerMetadata(
          name: 'Marker $index',
          type: 'QuestItems',
          category: 'questItems',
          details: {'task': shared},
          source: const {},
          owner: owner,
        ),
    ];

    expect(owner.retainedMaterializedBytes, reserved);
    expect(owner.retainedMaterializedBytes, lessThan(shared.length * 24));
    expect(metadata.every((item) => item.matchesSearch(['x' * 128])), isTrue);
    expect(owner.retainedMaterializedBytes, lessThan(shared.length * 24));
    final afterMatching = owner.retainedMaterializedBytes;
    expect(metadata.every((item) => item.matchesSearch(['x' * 128])), isTrue);
    expect(owner.retainedMaterializedBytes, afterMatching);
  });

  test('shared fact scratch measurement visits each container once', () {
    final leaf = 'deep-${'z' * 4096}-needle';
    final nested = _CountingMap({'value': leaf, 'number': 271828});
    final shared = _CountingList([nested, true, 'final scalar']);
    var reserved = 0;
    final owner = MapMarkerMetadataOwner(
      reserveMaterialized: (bytes) => reserved += bytes,
      releaseMaterialized: (bytes) => reserved -= bytes,
    );

    MapMarkerMetadata makeMarker(int index) => MapMarkerMetadata(
      name: 'Marker $index',
      type: 'Switches',
      category: 'switches',
      details: {
        'shared': shared,
        'unique': 'individual-$index',
        'position': 'excluded-position',
      },
      source: const {},
      owner: owner,
    );

    final first = makeMarker(0);
    final mapVisits = nested.visits;
    final listVisits = shared.visits;
    expect(mapVisits, greaterThan(0));
    expect(listVisits, greaterThan(0));
    final others = [for (var i = 1; i < 24; i++) makeMarker(i)];
    expect(nested.visits, mapVisits);
    expect(shared.visits, listVisits);
    expect(owner.retainedMaterializedBytes, reserved);
    expect(reserved, greaterThanOrEqualTo(128 + leaf.length * 12));

    for (final marker in [first, ...others]) {
      expect(marker.matchesSearch(['deep-', 'not present']), isTrue);
      expect(marker.matchesSearch(['271828']), isTrue);
      expect(marker.matchesSearch(['true final scalar']), isTrue);
      expect(marker.matchesSearch(['excluded-position']), isFalse);
    }
    expect(others.last.matchesSearch(['individual-23']), isTrue);
    expect(first.matchesSearch(['individual-23']), isFalse);

    var limitedReserved = 0;
    final limitedOwner = MapMarkerMetadataOwner(
      reserveMaterialized: (bytes) {
        if (limitedReserved + bytes > 4096) {
          throw StateError('scratch budget exceeded');
        }
        limitedReserved += bytes;
      },
      releaseMaterialized: (bytes) => limitedReserved -= bytes,
    );
    expect(
      () => MapMarkerMetadata(
        name: 'Limited',
        type: 'Switches',
        category: 'switches',
        details: {'shared': shared},
        source: const {},
        owner: limitedOwner,
      ),
      throwsStateError,
    );
    expect(limitedOwner.retainedMaterializedBytes, limitedReserved);
  });

  test('shared query traversal is bounded across marker contexts', () {
    final inner = _CountingMap({
      'first': 'Bridge',
      'position': 'hidden-geometry',
      'last': 'Omega',
    });
    final shared = _CountingList([
      '',
      'Alpha',
      inner,
      <Object?>[],
      <String, Object?>{},
      271828,
      true,
      for (var i = 0; i < 24; i++) 'fact-$i',
    ]);
    var reserved = 0;
    final owner = MapMarkerMetadataOwner(
      reserveMaterialized: (bytes) => reserved += bytes,
      releaseMaterialized: (bytes) => reserved -= bytes,
    );
    final markers = [
      for (var i = 0; i < 24; i++)
        MapMarkerMetadata(
          name: 'Marker $i',
          type: 'Kind',
          category: 'prefix$i',
          details: {'shared': shared, 'end': 'Tail', 'position': 'hidden-root'},
          source: const {'name': '  Origin  ', 'other': 'hidden-source'},
          owner: owner,
        ),
    ];

    void bounded(String query, List<bool> expected) {
      final listBefore = shared.visits;
      final mapBefore = inner.visits;
      expect([
        for (final marker in markers) marker.matchesSearch([query]),
      ], expected);
      expect(shared.visits - listBefore, lessThanOrEqualTo(shared.length));
      expect(inner.visits - mapBefore, lessThanOrEqualTo(1));
      expect(owner.retainedMaterializedBytes, reserved);
    }

    final all = List<bool>.filled(markers.length, true);
    final none = List<bool>.filled(markers.length, false);
    bounded('not-present', none);
    final afterAbsent = reserved;
    bounded('not-present', none);
    expect(reserved, afterAbsent);
    bounded('alpha bridge omega 271828 true fact-0', all);
    bounded('tail origin', all);
    bounded('hidden-geometry', none);
    bounded('hidden-root', none);
    bounded('hidden-source', none);
    bounded('marker 2 kind prefix2  alpha', [
      for (var i = 0; i < markers.length; i++) i == 2,
    ]);
    bounded('not-present', none);
    expect(reserved, afterAbsent);
  });

  test('admitted shared query workspace survives plan replacement', () {
    var reserved = 0;
    var ceiling = 1 << 30;
    final owner = MapMarkerMetadataOwner(
      reserveMaterialized: (bytes) {
        if (reserved + bytes > ceiling) throw StateError('budget exceeded');
        reserved += bytes;
      },
      releaseMaterialized: (bytes) => reserved -= bytes,
    );
    final shared = _CountingMap({
      for (var i = 0; i < 40; i++) 'item-$i': ['value-$i', 'suffix'],
    });
    final markers = [
      for (var i = 0; i < 24; i++)
        MapMarkerMetadata(
          name: 'Marker $i',
          type: 'Kind',
          category: 'Category',
          details: {'shared': shared},
          source: const {'name': 'Origin'},
          owner: owner,
        ),
    ];
    final baseline = reserved;
    // This admits two overlapping small term plans, but not a graph-sized
    // query cache. Replacements must reuse generation-owned summary slots.
    ceiling = baseline + 1024;
    for (final query in ['absent', 'value-39', 'suffix origin', 'absent']) {
      for (final marker in markers) {
        expect(marker.matchesSearch([query]), query != 'absent');
      }
      expect(reserved, lessThanOrEqualTo(ceiling));
      expect(owner.retainedMaterializedBytes, reserved);
    }
    final finalPlan = reserved;
    for (final marker in markers) {
      expect(marker.matchesSearch(['absent']), isFalse);
    }
    expect(reserved, finalPlan);
  });

  test('search scratch is admitted before a large scalar is searched', () {
    var reserved = 0;
    const budget = 52000;
    final owner = MapMarkerMetadataOwner(
      reserveMaterialized: (bytes) {
        if (reserved + bytes > budget) {
          throw StateError('materialized budget exceeded');
        }
        reserved += bytes;
      },
      releaseMaterialized: (bytes) => reserved -= bytes,
    );

    final metadata = MapMarkerMetadata(
      name: 'Marker',
      type: 'QuestItems',
      category: 'questItems',
      details: {'task': 'y' * 4096},
      source: const {},
      owner: owner,
    );
    final retainedBeforeSearch = owner.retainedMaterializedBytes;
    expect(retainedBeforeSearch, greaterThanOrEqualTo(128 + 4096 * 12));
    expect(metadata.matchesSearch(['absent']), isFalse);
    expect(
      owner.retainedMaterializedBytes - retainedBeforeSearch,
      lessThan(1024),
    );
    expect(metadata.matchesSearch(['marker']), isTrue);
  });

  test('an identical uppercase query reuses its admitted plan', () {
    var reserved = 0;
    final owner = MapMarkerMetadataOwner(
      reserveMaterialized: (bytes) {
        if (reserved + bytes > 1280) throw StateError('query limit exceeded');
        reserved += bytes;
      },
      releaseMaterialized: (bytes) => reserved -= bytes,
    );
    final metadata = MapMarkerMetadata(
      name: 'Marker',
      type: 'Switches',
      category: 'switches',
      details: const {},
      source: const {},
      owner: owner,
    );
    expect(metadata.matchesSearch(['MARKER']), isTrue);
    final afterFirst = reserved;
    expect(metadata.matchesSearch(['MARKER']), isTrue);
    expect(reserved, afterFirst);
  });

  test(
    'variable quest metadata is admitted before constructing collections',
    () {
      var reserved = 0;
      final owner = MapMarkerMetadataOwner(
        reserveMaterialized: (bytes) {
          if (reserved + bytes > 2048) {
            throw StateError('metadata limit exceeded');
          }
          reserved += bytes;
        },
        releaseMaterialized: (bytes) => reserved -= bytes,
      );
      final baseline = reserved;
      expect(
        () => MapMarkerMetadata(
          name: 'Objective',
          type: 'QuestObjectives',
          category: 'questObjectives',
          details: {
            'quests': [
              for (var index = 0; index < 8; index++)
                {'name': 'A quest with a distinct name $index'},
            ],
          },
          source: const {},
          owner: owner,
        ),
        throwsStateError,
      );
      expect(reserved, baseline);
      expect(owner.retainedMaterializedBytes, baseline);
    },
  );

  test('search phrases cross scalar leaves while geometry stays excluded', () {
    final metadata = MapMarkerMetadata(
      name: 'Door',
      type: 'PmcExtracts',
      category: 'extracts',
      details: {
        'first': 'North',
        'nested': ['Tunnel'],
        'position': {'name': 'hidden-position'},
        'outline': ['hidden-outline'],
        'size': {'name': 'hidden-size'},
      },
      source: const {'name': '  North Gate  '},
    );

    expect(metadata.matchesSearch(['north tunnel']), isTrue);
    expect(metadata.matchesSearch(['north gate']), isTrue);
    expect(metadata.matchesSearch(['hidden']), isFalse);
  });

  test('comma substring OR is case-insensitive and ignores empty terms', () {
    final metadata = MapMarkerMetadata(
      name: 'Service exit',
      type: 'PmcExtracts',
      category: 'extracts',
      details: {
        'conditions': ['Open the DOOR'],
        'zone': 'North tunnel',
      },
      source: const {},
    );
    expect(metadata.matchesSearch(mapSearchTerms('bridge, door')), isTrue);
    expect(metadata.matchesSearch(mapSearchTerms(' TUNNEL , bridge ')), isTrue);
    expect(metadata.matchesSearch(mapSearchTerms('bridge, key')), isFalse);
    expect(metadata.matchesSearch(mapSearchTerms(' , ')), isTrue);
  });

  test('quest name AND exact trader applies only to quests', () {
    final quest = MapMarkerMetadata(
      name: 'Letter',
      type: 'QuestItems',
      category: 'questItems',
      details: {
        'quest': {
          'name': 'Delivery from the Past',
          'trader': {'id': 'prapor', 'name': 'Prapor'},
          'wikiLink': 'https://example.invalid/quest',
        },
      },
      source: const {},
    );
    expect(quest.matchesQuest(name: 'FROM THE', trader: 'PRAPOR'), isTrue);
    expect(quest.matchesQuest(name: 'from the', trader: 'Prap'), isFalse);
    expect(quest.matchesQuest(name: 'other', trader: 'Prapor'), isFalse);
    expect(quest.matchesQuest(name: 'delivery', trader: ' ALL '), isTrue);
    expect(quest.questLinks, ['https://example.invalid/quest']);
    final exit = MapMarkerMetadata(
      name: 'Tunnel',
      type: 'PmcExtracts',
      category: 'extracts',
      details: const {},
      source: const {},
    );
    expect(exit.matchesQuest(name: 'other', trader: 'Prapor'), isTrue);
  });

  test(
    'links retain exact source identities without name-based association',
    () {
      final exit = MapMarkerMetadata(
        name: 'Door',
        type: 'PmcExtracts',
        category: 'extracts',
        details: {
          'id': 'exit-1',
          'switches': [
            'source-switch',
            {'id': 'other-switch', 'name': 'Door'},
          ],
        },
        source: const {},
      );
      expect(exit.sourceId, 'exit-1');
      expect(exit.linkedSwitchIds, {'source-switch', 'other-switch'});
      expect(exit.linkedSwitchIds.contains('Door'), isFalse);
    },
  );
}

class _CountingMap extends MapBase<String, dynamic> {
  _CountingMap(this._values);

  final Map<String, dynamic> _values;
  int visits = 0;

  @override
  Iterable<String> get keys {
    visits++;
    return _values.keys;
  }

  @override
  dynamic operator [](Object? key) => _values[key];

  @override
  void operator []=(String key, dynamic value) =>
      throw UnsupportedError('immutable');

  @override
  void clear() => throw UnsupportedError('immutable');

  @override
  dynamic remove(Object? key) => throw UnsupportedError('immutable');
}

class _CountingList extends ListBase<Object?> {
  _CountingList(this._values);

  final List<Object?> _values;
  int visits = 0;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('immutable');

  @override
  Object? operator [](int index) {
    visits++;
    return _values[index];
  }

  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('immutable');
}
