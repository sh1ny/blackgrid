import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:test/test.dart';

import 'support/wire.dart';

void main() {
  test('keeps Kappa, Lightkeeper, faction and level', () {
    final task = parseWire(
      tasks: [
        taskWire('task-a', {
          'name': 'task.name',
          'normalizedName': 'the-task',
          'trader': 'trader-b',
          'minPlayerLevel': 15,
          'factionName': 'USEC',
          'kappaRequired': true,
          'lightkeeperRequired': false,
          'restartable': true,
          'map': 'map-a',
          'requiredPrestige': 'prestige-a',
          'gameMode': ['pve', 'regular'],
        }),
      ],
      taskDictionary: {'task.name': 'The Task'},
    ).tasks.single;

    expect(task.id, 'task-a');
    expect(task.name, 'The Task');
    expect(task.normalizedName, 'the-task');
    expect(task.traderId, 'trader-b');
    expect(task.minPlayerLevel, 15);
    expect(task.faction, TaskFaction.usec);
    expect(task.rawFaction, 'USEC');
    expect(task.kappaRequired, isTrue);
    expect(task.lightkeeperRequired, isFalse);
    expect(task.restartable, isTrue);
    expect(task.mapId, 'map-a');
    expect(task.requiredPrestigeId, 'prestige-a');
    expect(task.gameModes, ['pve', 'regular']);
  });

  test('absent or odd new facts are unknown', () {
    final absent = taskWire('absent')
      ..remove('minPlayerLevel')
      ..remove('factionName')
      ..remove('taskRequirements')
      ..remove('traderRequirements')
      ..remove('failConditions');
    final odd = taskWire('odd', {
      'minPlayerLevel': 'ten',
      'factionName': 'Marauder',
      'kappaRequired': 'yes',
      'lightkeeperRequired': 0,
      'restartable': 'no',
      'map': 10,
      'requiredPrestige': false,
      'gameMode': 'pve',
    });
    final catalog = parseWire(tasks: [absent, odd]);
    final missing = catalog.tasksById['absent']!;
    final malformed = catalog.tasksById['odd']!;
    expect(missing.minPlayerLevel, isNull);
    expect(missing.faction, TaskFaction.unknown);
    expect(missing.kappaRequired, isNull);
    expect(missing.lightkeeperRequired, isNull);
    expect(missing.restartable, isNull);
    expect(missing.mapId, isNull);
    expect(missing.requiredPrestigeId, isNull);
    expect(missing.gameModes, isNull);
    expect(missing.prerequisites, isNull);
    expect(missing.traderRequirements, isNull);
    expect(missing.failConditions, isNull);
    expect(missing.alternatives, isNull);
    expect(malformed.minPlayerLevel, isNull);
    expect(malformed.faction, TaskFaction.unknown);
    expect(malformed.rawFaction, 'Marauder');
    expect(malformed.kappaRequired, isNull);
    expect(malformed.lightkeeperRequired, isNull);
    expect(malformed.restartable, isNull);
    expect(malformed.mapId, isNull);
    expect(malformed.requiredPrestigeId, isNull);
    expect(malformed.gameModes, isNull);
  });

  test('absent failConditions means alternatives unknown', () {
    final task = taskWire('task-a')..remove('failConditions');
    final parsed = parseWire(tasks: [task]).tasks.single;
    expect(parsed.failConditions, isNull);
    expect(parsed.alternatives, isNull);
  });

  test('empty taskRequirements means no prerequisites', () {
    final task = parseWire(tasks: [taskWire('task-a')]).tasks.single;
    expect(task.prerequisites, isEmpty);
    expect(task.traderRequirements, isEmpty);
    expect(task.failConditions, isEmpty);
    expect(task.alternatives, isEmpty);
  });

  test('keeps must-be-failed prerequisite statuses in order', () {
    final catalog = parseWire(
      tasks: [
        taskWire('a', {
          'taskRequirements': [
            {
              'task': 'b',
              'status': ['complete', 'failed'],
            },
            {
              'task': 'c',
              'status': ['failed'],
            },
          ],
        }),
        taskWire('b'),
        taskWire('c'),
      ],
    );
    final requirements = catalog.tasksById['a']!.prerequisites!;
    expect(requirements.map((r) => r.taskId), ['b', 'c']);
    expect(requirements[0].statuses, [TaskStatus.complete, TaskStatus.failed]);
    expect(requirements[0].rawStatuses, ['complete', 'failed']);
    expect(requirements[1].statuses, [TaskStatus.failed]);
    expect(requirements[1].rawStatuses, ['failed']);
  });

  test('unknown prerequisite status is kept as unknown', () {
    final catalog = parseWire(
      tasks: [
        taskWire('a', {
          'taskRequirements': [
            {
              'task': 'b',
              'status': ['active', 'expired', 'failed'],
            },
          ],
        }),
        taskWire('b'),
      ],
    );
    final requirement = catalog.tasksById['a']!.prerequisites!.single;
    expect(requirement.taskId, 'b');
    expect(requirement.statuses, [
      TaskStatus.active,
      TaskStatus.unknown,
      TaskStatus.failed,
    ]);
    expect(requirement.rawStatuses, ['active', 'expired', 'failed']);
  });

  test('taskStatus fail condition becomes an alternative', () {
    final catalog = parseWire(
      tasks: [
        taskWire('a', {
          'failConditions': [
            {
              'id': 'condition-a',
              'type': 'taskStatus',
              'task': 'b',
              'status': ['complete', 'expired', 'failed'],
            },
          ],
        }),
        taskWire('b'),
      ],
    );
    final task = catalog.tasksById['a']!;
    expect(task.failConditions!.single.id, 'condition-a');
    expect(task.failConditions!.single.type, ObjectiveType.taskStatus);
    expect(task.failConditions!.single.rawType, 'taskStatus');
    final alternative = task.alternatives!.single;
    expect(alternative.taskId, 'b');
    expect(alternative.statuses, [
      TaskStatus.complete,
      TaskStatus.unknown,
      TaskStatus.failed,
    ]);
    expect(alternative.rawStatuses, ['complete', 'expired', 'failed']);
  });

  test('other fail conditions are kept but are not alternatives', () {
    final task = parseWire(
      tasks: [
        taskWire('a', {
          'failConditions': [
            {'id': 'extract-condition', 'type': 'extract'},
            {'id': 'future-condition', 'type': 'futureCondition'},
          ],
        }),
      ],
    ).tasks.single;
    expect(task.alternatives, isEmpty);
    expect(task.failConditions!.map((c) => c.id), [
      'extract-condition',
      'future-condition',
    ]);
    expect(task.failConditions![0].type, ObjectiveType.extract);
    expect(task.failConditions![0].rawType, 'extract');
    expect(task.failConditions![1].type, ObjectiveType.unknown);
    expect(task.failConditions![1].rawType, 'futureCondition');
  });

  test('keeps trader level requirement with comparison', () {
    final task = parseWire(
      tasks: [
        taskWire('a', {
          'traderRequirements': [
            {
              'trader': 'trader-a',
              'requirementType': 'level',
              'compareMethod': '>=',
              'value': 2,
            },
            {
              'trader': 'trader-b',
              'requirementType': 'reputation',
              'compareMethod': '>',
              'value': 0.2,
            },
            {
              'trader': 'trader-a',
              'requirementType': 'reputation',
              'compareMethod': '<=',
              'value': 0.3,
            },
            {
              'trader': 'trader-a',
              'requirementType': 'level',
              'compareMethod': '<',
              'value': 4,
            },
            {
              'trader': 'trader-a',
              'requirementType': 'level',
              'compareMethod': '=',
              'value': 3,
            },
          ],
        }),
      ],
    ).tasks.single;
    final requirements = task.traderRequirements!;
    expect(requirements.map((r) => r.comparison), [
      Comparison.atLeast,
      Comparison.greaterThan,
      Comparison.atMost,
      Comparison.lessThan,
      Comparison.equal,
    ]);
    expect(requirements.map((r) => r.rawComparison), [
      '>=',
      '>',
      '<=',
      '<',
      '=',
    ]);
    expect(requirements.map((r) => r.value), [2, 0.2, 0.3, 4, 3]);
    expect(requirements[0].traderId, 'trader-a');
    expect(requirements[0].type, TraderRequirementType.level);
    expect(requirements[0].rawType, 'level');
    expect(requirements[1].traderId, 'trader-b');
    expect(requirements[1].type, TraderRequirementType.reputation);
    expect(requirements[1].rawType, 'reputation');
  });

  test('unknown comparison is kept as unknown', () {
    final task = parseWire(
      tasks: [
        taskWire('a', {
          'traderRequirements': [
            {
              'trader': 'trader-a',
              'requirementType': 'future',
              'compareMethod': '~',
              'value': 'two',
            },
            {
              'trader': 'trader-b',
              'requirementType': 1,
              'compareMethod': false,
            },
          ],
        }),
      ],
    ).tasks.single;
    final requirements = task.traderRequirements!;
    expect(requirements[0].traderId, 'trader-a');
    expect(requirements[0].type, TraderRequirementType.unknown);
    expect(requirements[0].rawType, 'future');
    expect(requirements[0].comparison, Comparison.unknown);
    expect(requirements[0].rawComparison, '~');
    expect(requirements[0].value, isNull);
    expect(requirements[1].type, TraderRequirementType.unknown);
    expect(requirements[1].rawType, isNull);
    expect(requirements[1].comparison, Comparison.unknown);
    expect(requirements[1].rawComparison, isNull);
    expect(requirements[1].value, isNull);
  });

  test('unknown map ID is kept, not resolved', () {
    final task = parseWire(
      tasks: [
        taskWire('a', {
          'map': 'unknown-map',
          'requiredPrestige': 'unknown-prestige',
          'objectives': [
            {
              'id': 'standing',
              'type': 'traderStanding',
              'trader': 'unknown-trader',
              'compareMethod': '>=',
              'value': 5,
            },
          ],
        }),
      ],
    ).tasks.single;
    expect(task.mapId, 'unknown-map');
    expect(task.requiredPrestigeId, 'unknown-prestige');
    final facts = task.objectives.single.facts as TraderStandingFacts;
    expect(facts.traderId, 'unknown-trader');
  });

  test('task names fall back from dictionary to normalized name to ID', () {
    final tasks = [
      taskWire('translated', {
        'name': 'translated-key',
        'normalizedName': 'translated-normalized',
      }),
      taskWire('missing-dictionary', {
        'name': 'missing-key',
        'normalizedName': 'fallback-name',
      }),
      taskWire('empty-translation', {
        'name': 'empty-key',
        'normalizedName': 'other-name',
      }),
      taskWire('missing-normalized', {
        'name': 'missing-key',
        'normalizedName': null,
      }),
      taskWire('empty-normalized', {
        'name': 'missing-key',
        'normalizedName': '',
      }),
    ];
    final catalog = parseWire(
      tasks: tasks,
      taskDictionary: {'translated-key': 'Translated name', 'empty-key': ''},
    );
    expect(catalog.tasksById['translated']!.name, 'Translated name');
    expect(
      catalog.tasksById['translated']!.normalizedName,
      'translated-normalized',
    );
    expect(catalog.tasksById['missing-dictionary']!.name, 'fallback-name');
    expect(catalog.tasksById['empty-translation']!.name, 'other-name');
    expect(catalog.tasksById['missing-normalized']!.name, 'missing-normalized');
    expect(catalog.tasksById['empty-normalized']!.name, 'empty-normalized');
    final noDictionary = parseWire(tasks: [taskWire('without-dictionary')]);
    expect(noDictionary.tasks.single.name, 'normalized-without-dictionary');
  });

  test(
    'unresolved required task and trader references are identity errors',
    () {
      final invalidTasks = <Map<String, dynamic>>[
        taskWire('a', {'trader': 'missing-trader'}),
        taskWire('a', {
          'taskRequirements': [
            {
              'task': 'missing-task',
              'status': ['complete'],
            },
          ],
        }),
        taskWire('a', {
          'failConditions': [
            {
              'id': 'alternative',
              'type': 'taskStatus',
              'task': 'missing-task',
              'status': ['complete'],
            },
          ],
        }),
        taskWire('a', {
          'objectives': [
            {
              'id': 'target',
              'type': 'taskStatus',
              'task': 'missing-task',
              'status': ['complete'],
            },
          ],
        }),
        taskWire('a', {
          'traderRequirements': [
            {
              'trader': 'missing-trader',
              'requirementType': 'level',
              'compareMethod': '>=',
              'value': 2,
            },
          ],
        }),
      ];
      for (final task in invalidTasks) {
        expect(
          () => parseWire(tasks: [task]),
          throwsFormatException,
          reason: '$task',
        );
      }
    },
  );

  test(
    'missing or wrong-typed taskStatus objective target remains unknown',
    () {
      final task = parseWire(
        tasks: [
          taskWire('a', {
            'objectives': [
              {'id': 'missing', 'type': 'taskStatus'},
              {'id': 'odd', 'type': 'taskStatus', 'task': 7},
            ],
          }),
        ],
      ).tasks.single;
      expect((task.objectives[0].facts as TaskStatusFacts).taskId, isNull);
      expect((task.objectives[1].facts as TaskStatusFacts).taskId, isNull);
    },
  );

  test('missing or invalid task, objective and station identities reject', () {
    for (final invalidId in [null, 7, '', '  ']) {
      final task = taskWire('a', {'id': invalidId});
      expect(
        () => parseProgressCatalog(
          {
            'tasks': {'a': task},
          },
          <String, dynamic>{},
          {'trader-a'},
          null,
          null,
        ),
        throwsFormatException,
        reason: 'task id: $invalidId',
      );
      final station = stationWire('station-a', {'id': invalidId});
      expect(
        () => parseProgressCatalog(
          {'tasks': <String, dynamic>{}},
          {'station-a': station},
          {'trader-a'},
          null,
          null,
        ),
        throwsFormatException,
        reason: 'station id: $invalidId',
      );
      final objectiveTask = taskWire('a', {
        'objectives': [
          {'id': invalidId, 'type': 'visit'},
        ],
      });
      expect(
        () => parseWire(tasks: [objectiveTask]),
        throwsFormatException,
        reason: 'objective id: $invalidId',
      );
    }
  });

  test(
    'duplicate task and station identities reject even under different keys',
    () {
      expect(
        () => parseProgressCatalog(
          {
            'tasks': {'a': taskWire('same'), 'b': taskWire('same')},
          },
          <String, dynamic>{},
          {'trader-a'},
          null,
          null,
        ),
        throwsFormatException,
      );
      expect(
        () => parseProgressCatalog(
          {'tasks': <String, dynamic>{}},
          {'a': stationWire('same'), 'b': stationWire('same')},
          {'trader-a'},
          null,
          null,
        ),
        throwsFormatException,
      );
    },
  );

  test('omitted identity fields reject', () {
    final task = taskWire('a')..remove('id');
    final station = stationWire('s')..remove('id');
    final objective = <String, dynamic>{'type': 'visit'};
    final level = levelWire('level-a', 1)..remove('id');
    expect(
      () => parseProgressCatalog(
        {
          'tasks': {'a': task},
        },
        <String, dynamic>{},
        {'trader-a'},
        null,
        null,
      ),
      throwsFormatException,
    );
    expect(
      () => parseProgressCatalog(
        {'tasks': <String, dynamic>{}},
        {'s': station},
        {'trader-a'},
        null,
        null,
      ),
      throwsFormatException,
    );
    expect(
      () => parseWire(
        tasks: [
          taskWire('a', {
            'objectives': [objective],
          }),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => parseWire(
        stations: [
          stationWire('s', {
            'levels': [level],
          }),
        ],
      ),
      throwsFormatException,
    );
  });

  test('unresolved station requirement is an identity error', () {
    expect(
      () => parseWire(
        stations: [
          stationWire('s', {
            'levels': [
              levelWire('level-a', 1, {
                'stationLevelRequirements': [
                  {'station': 'missing-station', 'level': 1},
                ],
              }),
            ],
          }),
        ],
      ),
      throwsFormatException,
    );
  });
}
