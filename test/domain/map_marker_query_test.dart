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
