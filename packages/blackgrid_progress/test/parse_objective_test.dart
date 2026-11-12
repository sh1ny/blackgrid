import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:test/test.dart';

import 'support/wire.dart';

void main() {
  test('giveItem keeps count, found in raid and items', () {
    final catalog = parseWire(
      tasks: [
        taskWire('task-a', {
          'objectives': [
            {
              'id': 'give',
              'type': 'giveItem',
              'count': 3,
              'optional': true,
              'items': ['item-a', 'item-b'],
              'foundInRaid': true,
              'maps': ['map-a', 'map-b'],
            },
          ],
        }),
      ],
    );
    final objective = catalog.tasks.single.objectives.single;
    expect(objective.id, 'give');
    expect(objective.type, ObjectiveType.giveItem);
    expect(objective.count, 3);
    expect(objective.optional, isTrue);
    expect(objective.mapIds, ['map-a', 'map-b']);
    final facts = objective.facts as ItemFacts;
    expect(facts.itemIds, ['item-a', 'item-b']);
    expect(facts.foundInRaid, isTrue);
  });

  test('item-bearing types use their designated wire fields', () {
    final objectives = <Map<String, dynamic>>[
      for (final type in ['findItem', 'giveItem', 'plantItem', 'sellItem'])
        {
          'id': type,
          'type': type,
          'items': ['item-$type'],
          'foundInRaid': false,
        },
      {
        'id': 'build',
        'type': 'buildWeapon',
        'item': 'weapon',
        'foundInRaid': true,
      },
      {
        'id': 'use',
        'type': 'useItem',
        'useAny': ['use-a', 'use-b'],
        'foundInRaid': true,
      },
      {
        'id': 'mark',
        'type': 'mark',
        'markerItem': 'marker',
        'foundInRaid': true,
      },
    ];
    final parsed = parseWire(
      tasks: [
        taskWire('task-a', {'objectives': objectives}),
      ],
    ).tasks.single.objectives;
    expect(parsed.map((o) => o.id), objectives.map((o) => o['id']));
    for (var i = 0; i < 4; i++) {
      final facts = parsed[i].facts as ItemFacts;
      expect(facts.itemIds, ['item-${objectives[i]['type']}']);
      expect(facts.foundInRaid, isFalse);
      expect(parsed[i].type.name, objectives[i]['type']);
    }
    for (final (index, ids) in [
      (4, ['weapon']),
      (5, ['use-a', 'use-b']),
      (6, ['marker']),
    ]) {
      final facts = parsed[index].facts as ItemFacts;
      expect(facts.itemIds, ids);
      expect(facts.foundInRaid, isNull);
    }
    expect(parsed[4].type, ObjectiveType.buildWeapon);
    expect(parsed[5].type, ObjectiveType.useItem);
    expect(parsed[6].type, ObjectiveType.mark);
  });

  test('unrecognized type keeps raw type string', () {
    final objective = parseWire(
      tasks: [
        taskWire('task-a', {
          'objectives': [
            {
              'id': 'photo',
              'type': 'photograph',
              'count': 2,
              'optional': false,
              'maps': ['map-x'],
              'description': 'photo-desc',
              'items': ['stray'],
            },
          ],
        }),
      ],
      taskDictionary: {'photo-desc': 'Take a photograph'},
    ).tasks.single.objectives.single;
    expect(objective.id, 'photo');
    expect(objective.type, ObjectiveType.unknown);
    expect(objective.rawType, 'photograph');
    expect(objective.count, 2);
    expect(objective.optional, isFalse);
    expect(objective.mapIds, ['map-x']);
    expect(objective.description, 'Take a photograph');
    expect(objective.facts, isA<NoFacts>());
  });

  test('quest item objectives carry the quest item ID', () {
    final objectives = <Map<String, dynamic>>[
      for (final type in [
        'findQuestItem',
        'giveQuestItem',
        'plantQuestItem',
      ]) ...[
        {'id': '$type-string', 'type': type, 'questItem': 'quest-string'},
        {
          'id': '$type-object',
          'type': type,
          'questItem': {'id': 'quest-object'},
        },
      ],
    ];
    final parsed = parseWire(
      tasks: [
        taskWire('task-a', {'objectives': objectives}),
      ],
    ).tasks.single.objectives;
    expect(parsed, hasLength(6));
    for (var i = 0; i < parsed.length; i++) {
      expect(parsed[i].type.name, objectives[i]['type']);
      expect(
        (parsed[i].facts as QuestItemFacts).questItemId,
        i.isEven ? 'quest-string' : 'quest-object',
      );
    }
  });

  test('useItem without useAny has unknown items', () {
    final objective = parseWire(
      tasks: [
        taskWire('task-a', {
          'objectives': [
            {'id': 'use', 'type': 'useItem'},
          ],
        }),
      ],
    ).tasks.single.objectives.single;
    final facts = objective.facts as ItemFacts;
    expect(facts.itemIds, isNull);
    expect(facts.foundInRaid, isNull);
  });

  test('traderStanding carries trader, comparison and value', () {
    final objective = parseWire(
      tasks: [
        taskWire('task-a', {
          'objectives': [
            {
              'id': 'standing',
              'type': 'traderStanding',
              'trader': 'display-only',
              'compareMethod': '>=',
              'value': 5,
            },
          ],
        }),
      ],
    ).tasks.single.objectives.single;
    expect(objective.type, ObjectiveType.traderStanding);
    final facts = objective.facts as TraderStandingFacts;
    expect(facts.traderId, 'display-only');
    expect(facts.comparison, Comparison.atLeast);
    expect(facts.rawComparison, '>=');
    expect(facts.value, 5);
  });

  test('target objectives retain statuses, trader level and skill', () {
    final objectives = parseWire(
      tasks: [
        taskWire('task-a', {
          'objectives': [
            {
              'id': 'status',
              'type': 'taskStatus',
              'task': 'task-b',
              'status': ['complete', 'active', 'expired', 'failed'],
            },
            {
              'id': 'loyalty',
              'type': 'traderLevel',
              'trader': 'display-only',
              'level': 3,
            },
            {'id': 'skill', 'type': 'skill', 'skill': 'Attention', 'level': 8},
          ],
        }),
        taskWire('task-b'),
      ],
    ).tasksById['task-a']!.objectives;
    final status = objectives[0].facts as TaskStatusFacts;
    expect(status.taskId, 'task-b');
    expect(status.statuses, [
      TaskStatus.complete,
      TaskStatus.active,
      TaskStatus.unknown,
      TaskStatus.failed,
    ]);
    expect(status.rawStatuses, ['complete', 'active', 'expired', 'failed']);
    final trader = objectives[1].facts as TraderLevelFacts;
    expect(trader.traderId, 'display-only');
    expect(trader.level, 3);
    final skill = objectives[2].facts as SkillFacts;
    expect(skill.skillId, 'Attention');
    expect(skill.level, 8);
  });

  test('missing target fact is unknown; other types carry no facts', () {
    final objectives = parseWire(
      tasks: [
        taskWire('task-a', {
          'objectives': [
            {
              'id': 'standing',
              'type': 'traderStanding',
              'trader': 'trader-a',
              'compareMethod': '>=',
            },
            {
              'id': 'visit',
              'type': 'visit',
              'items': ['stray'],
            },
            {
              'id': 'bad-standing',
              'type': 'traderStanding',
              'trader': 7,
              'compareMethod': '~',
              'value': 'five',
            },
            {'id': 'bad-status', 'type': 'taskStatus', 'task': 7, 'status': 7},
            {
              'id': 'bad-level',
              'type': 'traderLevel',
              'trader': 7,
              'level': 'three',
            },
            {'id': 'bad-skill', 'type': 'skill', 'skill': 7, 'level': 'eight'},
          ],
        }),
      ],
    ).tasks.single.objectives;
    expect((objectives[0].facts as TraderStandingFacts).value, isNull);
    expect(objectives[1].facts, isA<NoFacts>());
    final standing = objectives[2].facts as TraderStandingFacts;
    expect(standing.traderId, isNull);
    expect(standing.comparison, Comparison.unknown);
    expect(standing.rawComparison, '~');
    expect(standing.value, isNull);
    final status = objectives[3].facts as TaskStatusFacts;
    expect(status.taskId, isNull);
    expect(status.statuses, isNull);
    expect(status.rawStatuses, isNull);
    final trader = objectives[4].facts as TraderLevelFacts;
    expect(trader.traderId, isNull);
    expect(trader.level, isNull);
    final skill = objectives[5].facts as SkillFacts;
    expect(skill.skillId, isNull);
    expect(skill.level, isNull);
  });

  test('unresolved taskStatus objective target is an identity error', () {
    expect(
      () => parseWire(
        tasks: [
          taskWire('task-a', {
            'objectives': [
              {
                'id': 'status',
                'type': 'taskStatus',
                'task': 'missing',
                'status': ['complete'],
              },
            ],
          }),
        ],
      ),
      throwsFormatException,
    );
  });

  test('objective ID under two tasks is marked shared on both', () {
    final catalog = parseWire(
      tasks: [
        taskWire('bear', {
          'factionName': 'BEAR',
          'objectives': [
            {'id': 'shared', 'type': 'visit'},
            {'id': 'only-bear', 'type': 'visit'},
          ],
        }),
        taskWire('usec', {
          'factionName': 'USEC',
          'objectives': [
            {'id': 'shared', 'type': 'visit'},
          ],
        }),
      ],
    );
    expect(catalog.sharedObjectiveIds, {'shared'});
    expect(catalog.tasksById['bear']!.objectives.first.isShared, isTrue);
    expect(catalog.tasksById['usec']!.objectives.single.isShared, isTrue);
    expect(catalog.tasksById['bear']!.objectives.last.isShared, isFalse);
  });

  test('repeated objective ID within a task is an identity error', () {
    expect(
      () => parseWire(
        tasks: [
          taskWire('task-a', {
            'objectives': [
              {'id': 'duplicate', 'type': 'visit'},
              {'id': 'duplicate', 'type': 'visit'},
            ],
          }),
        ],
      ),
      throwsFormatException,
    );
  });

  test('objective description comes from the dictionary', () {
    final catalog = parseWire(
      tasks: [
        taskWire('task-a', {
          'objectives': [
            {'id': 'translated', 'type': 'visit', 'description': 'desc-key'},
            {'id': 'missing', 'type': 'visit', 'description': 'unknown-key'},
            {'id': 'wrong', 'type': 'visit', 'description': 42},
            {'id': 'empty', 'type': 'visit', 'description': 'empty-key'},
          ],
        }),
      ],
      taskDictionary: {
        'desc-key': 'Locate the Emercom station on Ground Zero',
        'empty-key': '',
      },
    );
    final objectives = catalog.tasks.single.objectives;
    expect(
      objectives[0].description,
      'Locate the Emercom station on Ground Zero',
    );
    expect(objectives[1].description, isNull);
    expect(objectives[2].description, isNull);
    expect(objectives[3].description, isNull);
    final withoutDictionary = parseWire(
      tasks: [
        taskWire('task-a', {
          'objectives': [
            {'id': 'unknown', 'type': 'visit', 'description': 'desc-key'},
          ],
        }),
      ],
    );
    expect(
      withoutDictionary.tasks.single.objectives.single.description,
      isNull,
    );
  });
}
