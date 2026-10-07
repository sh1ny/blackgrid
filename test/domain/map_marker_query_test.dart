import 'package:blackgrid/domain/map_marker_query.dart';
import 'package:test/test.dart';

void main() {
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
