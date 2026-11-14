import 'dart:convert';

import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:test/test.dart';

ProgressCatalog _catalog() => ProgressCatalog(
  tasks: [
    CatalogTask(
      id: 'bear',
      name: 'Bear task',
      normalizedName: 'bear_task',
      traderId: 'trader',
      minPlayerLevel: 15,
      faction: TaskFaction.bear,
      rawFaction: 'BEAR',
      kappaRequired: true,
      lightkeeperRequired: false,
      restartable: true,
      mapId: 'map',
      requiredPrestigeId: 'prestige',
      gameModes: ['pve', 'regular'],
      prerequisites: [
        TaskPrerequisite(
          taskId: 'usec',
          statuses: [
            TaskStatus.complete,
            TaskStatus.failed,
            TaskStatus.unknown,
          ],
          rawStatuses: ['complete', 'failed', 'expired'],
        ),
      ],
      traderRequirements: [
        TraderRequirement(
          traderId: 'trader',
          type: TraderRequirementType.level,
          rawType: 'level',
          comparison: Comparison.atLeast,
          rawComparison: '>=',
          value: 2,
        ),
      ],
      failConditions: [
        FailCondition(
          id: 'condition',
          type: ObjectiveType.extract,
          rawType: 'extract',
        ),
      ],
      alternatives: [
        TaskAlternative(
          taskId: 'usec',
          statuses: [TaskStatus.complete],
          rawStatuses: ['complete'],
        ),
      ],
      objectives: [
        TaskObjective(
          id: 'shared',
          type: ObjectiveType.giveItem,
          rawType: 'giveItem',
          optional: false,
          count: 3,
          description: 'Deliver items',
          mapIds: ['map'],
          facts: ItemFacts(itemIds: ['item-a', 'item-b'], foundInRaid: true),
        ),
        TaskObjective(
          id: 'quest-item',
          type: ObjectiveType.findQuestItem,
          facts: QuestItemFacts(questItemId: 'qi-1'),
        ),
        TaskObjective(
          id: 'status',
          type: ObjectiveType.taskStatus,
          facts: TaskStatusFacts(
            taskId: 'usec',
            statuses: [TaskStatus.active, TaskStatus.unknown],
            rawStatuses: ['active', 'expired'],
          ),
        ),
        TaskObjective(
          id: 'level',
          type: ObjectiveType.traderLevel,
          facts: TraderLevelFacts(traderId: 'trader', level: 3),
        ),
        TaskObjective(
          id: 'standing',
          type: ObjectiveType.traderStanding,
          facts: TraderStandingFacts(
            traderId: 'trader',
            comparison: Comparison.atLeast,
            rawComparison: '>=',
            value: 0.5,
          ),
        ),
        TaskObjective(
          id: 'skill',
          type: ObjectiveType.skill,
          facts: SkillFacts(skillId: 'HideoutManagement', level: 5),
        ),
        TaskObjective(
          id: 'visit',
          type: ObjectiveType.visit,
          facts: const NoFacts(),
        ),
        TaskObjective(
          id: 'new',
          type: ObjectiveType.unknown,
          rawType: 'photograph',
          count: 2,
          description: 'Photograph a place',
        ),
      ],
    ),
    CatalogTask(
      id: 'usec',
      name: 'Usec task',
      faction: TaskFaction.usec,
      objectives: [TaskObjective(id: 'shared', type: ObjectiveType.visit)],
    ),
  ],
  stations: [
    HideoutStation(
      id: 'library',
      name: 'Library',
      normalizedName: 'library',
      levels: [
        StationLevel(
          id: 'library-1',
          level: 1,
          constructionTime: 120.5,
          stationRequirements: [
            StationRequirement(stationId: 'rest', level: 3),
          ],
          traderRequirements: [
            TraderRequirement(
              traderId: 'trader',
              type: TraderRequirementType.reputation,
              comparison: Comparison.greaterThan,
              rawComparison: '>',
              value: 0.2,
            ),
          ],
          skillRequirements: [
            SkillRequirement(skillId: 'HideoutManagement', level: 5),
          ],
        ),
      ],
    ),
  ],
);

Map<String, dynamic> _jsonCopy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

void main() {
  test('catalog stored without traders loads with traders unknown', () {
    final original = _catalog();
    final stored = _jsonCopy(original.toJson())..remove('traders');
    final restored = ProgressCatalog.fromJson(stored);

    expect(restored.traders, isNull);
    expect(restored.toJson()['formatVersion'], 1);
    expect(restored.toJson()['tasks'], stored['tasks']);
    expect(restored.toJson()['stations'], stored['stations']);
    expect(restored.tasksById['bear']!.name, 'Bear task');
    expect(restored.stationsById['library']!.levels.single.level, 1);
  });

  test('traders round trip at format version 1', () {
    final original = _catalog();
    final catalog = ProgressCatalog(
      tasks: original.tasks,
      stations: original.stations,
      traders: [
        CatalogTraderLevels(
          id: 'fence',
          name: 'Fence',
          normalizedName: 'fence',
          levels: [1, 2, 3],
        ),
        CatalogTraderLevels(
          id: 'unknown',
          name: 'Unknown levels',
          normalizedName: 'unknown',
          levels: null,
        ),
      ],
    );
    final stored = _jsonCopy(catalog.toJson());
    expect(stored['formatVersion'], 1);

    final restored = ProgressCatalog.fromJson(stored);
    expect(restored.traders, hasLength(2));
    final fence = restored.traders!.first;
    expect(fence.id, 'fence');
    expect(fence.name, 'Fence');
    expect(fence.normalizedName, 'fence');
    expect(fence.levels, [1, 2, 3]);
    expect(restored.traders!.last.id, 'unknown');
    expect(restored.traders!.last.levels, isNull);
    expect(restored.toJson(), stored);
  });

  test('catalog stored without other requirements and delays loads them as unknown', () {
    final json = _jsonCopy(_catalog().toJson());
    for (final task in json['tasks'] as List<dynamic>) {
      (task as Map<String, dynamic>)
        ..remove('otherRequirements')
        ..remove('availableDelaySecondsMin')
        ..remove('availableDelaySecondsMax');
    }
    final catalog = ProgressCatalog.fromJson(json);
    expect(catalog.toJson()['formatVersion'], 1);
    for (final task in catalog.tasks) {
      expect(task.otherRequirements, isNull);
      expect(task.availableDelaySecondsMin, isNull);
      expect(task.availableDelaySecondsMax, isNull);
    }
  });

  test('dialogue requirement and delay round-trip', () {
    final catalog = ProgressCatalog(
      tasks: [
        CatalogTask(
          id: 'dialogue',
          name: 'Dialogue',
          otherRequirements: [
            DialogueRequirement(id: 'gate', traderIds: ['trader']),
          ],
          availableDelaySecondsMin: 1800,
          availableDelaySecondsMax: 2100,
        ),
      ],
      stations: [],
    );
    final decoded = ProgressCatalog.fromJson(_jsonCopy(catalog.toJson()));
    final task = decoded.tasks.single;
    final gate = task.otherRequirements!.single as DialogueRequirement;
    expect(gate.id, 'gate');
    expect(gate.traderIds, ['trader']);
    expect(task.availableDelaySecondsMin, 1800);
    expect(task.availableDelaySecondsMax, 2100);
    expect(decoded.toJson(), catalog.toJson());
  });

  group('progress catalog stored model', () {
    test(
      'retains independently asserted task, objective and station facts',
      () {
        final catalog = _catalog();
        final task = catalog.tasksById['bear']!;
        expect(task.name, 'Bear task');
        expect(task.normalizedName, 'bear_task');
        expect(task.traderId, 'trader');
        expect(task.minPlayerLevel, 15);
        expect(task.faction, TaskFaction.bear);
        expect(task.rawFaction, 'BEAR');
        expect(task.kappaRequired, isTrue);
        expect(task.lightkeeperRequired, isFalse);
        expect(task.restartable, isTrue);
        expect(task.mapId, 'map');
        expect(task.requiredPrestigeId, 'prestige');
        expect(task.gameModes, ['pve', 'regular']);
        expect(task.prerequisites!.single.taskId, 'usec');
        expect(task.prerequisites!.single.statuses, [
          TaskStatus.complete,
          TaskStatus.failed,
          TaskStatus.unknown,
        ]);
        expect(task.prerequisites!.single.rawStatuses, [
          'complete',
          'failed',
          'expired',
        ]);
        expect(task.alternatives!.single.taskId, 'usec');
        expect(task.alternatives!.single.statuses, [TaskStatus.complete]);
        expect(task.failConditions!.single.id, 'condition');
        expect(task.failConditions!.single.type, ObjectiveType.extract);
        final gate = task.traderRequirements!.single;
        expect(gate.traderId, 'trader');
        expect(gate.type, TraderRequirementType.level);
        expect(gate.comparison, Comparison.atLeast);
        expect(gate.value, 2);
        final objective = task.objectives.first;
        expect(objective.id, 'shared');
        expect(objective.type, ObjectiveType.giveItem);
        expect(objective.optional, isFalse);
        expect(objective.count, 3);
        expect(objective.description, 'Deliver items');
        expect(objective.mapIds, ['map']);
        final item = objective.facts as ItemFacts;
        expect(item.itemIds, ['item-a', 'item-b']);
        expect(item.foundInRaid, isTrue);
        expect(
          (task.objectives[1].facts as QuestItemFacts).questItemId,
          'qi-1',
        );
        final status = task.objectives[2].facts as TaskStatusFacts;
        expect(status.taskId, 'usec');
        expect(status.statuses, [TaskStatus.active, TaskStatus.unknown]);
        expect(status.rawStatuses, ['active', 'expired']);
        final level = task.objectives[3].facts as TraderLevelFacts;
        expect(level.traderId, 'trader');
        expect(level.level, 3);
        final standing = task.objectives[4].facts as TraderStandingFacts;
        expect(standing.traderId, 'trader');
        expect(standing.comparison, Comparison.atLeast);
        expect(standing.rawComparison, '>=');
        expect(standing.value, 0.5);
        final skill = task.objectives[5].facts as SkillFacts;
        expect(skill.skillId, 'HideoutManagement');
        expect(skill.level, 5);
        expect(task.objectives[6].facts, isA<NoFacts>());
        expect(task.objectives[7].type, ObjectiveType.unknown);
        expect(task.objectives[7].rawType, 'photograph');
        final station = catalog.stationsById['library']!;
        expect(station.name, 'Library');
        expect(station.normalizedName, 'library');
        final stationLevel = station.levels.single;
        expect(stationLevel.id, 'library-1');
        expect(stationLevel.level, 1);
        expect(stationLevel.constructionTime, 120.5);
        expect(stationLevel.stationRequirements!.single.stationId, 'rest');
        expect(stationLevel.stationRequirements!.single.level, 3);
        expect(
          stationLevel.traderRequirements!.single.type,
          TraderRequirementType.reputation,
        );
        expect(
          stationLevel.traderRequirements!.single.comparison,
          Comparison.greaterThan,
        );
        expect(
          stationLevel.skillRequirements!.single.skillId,
          'HideoutManagement',
        );
        expect(stationLevel.skillRequirements!.single.level, 5);
      },
    );

    test(
      'stores named enums and every facts subtype and restores the full JSON',
      () {
        final catalog = _catalog();
        final json = _jsonCopy(catalog.toJson());
        expect(json['formatVersion'], 1);
        final tasks = json['tasks'] as List<dynamic>;
        final task = tasks.first as Map<String, dynamic>;
        expect(task['id'], 'bear');
        expect(task['faction'], 'bear');
        final prerequisites = task['prerequisites'] as List<dynamic>;
        expect((prerequisites.single as Map<String, dynamic>)['statuses'], [
          'complete',
          'failed',
          'unknown',
        ]);
        final objectives = task['objectives'] as List<dynamic>;
        final item = objectives[0] as Map<String, dynamic>;
        expect(item['type'], 'giveItem');
        expect(item['count'], 3);
        expect(item['facts'], containsPair('kind', 'item'));
        expect(item['facts'], containsPair('itemIds', ['item-a', 'item-b']));
        expect(item['facts'], containsPair('foundInRaid', true));
        final factExpectations = <Map<String, Object>>[
          {'kind': 'questItem', 'questItemId': 'qi-1'},
          {
            'kind': 'taskStatus',
            'taskId': 'usec',
            'statuses': ['active', 'unknown'],
            'rawStatuses': ['active', 'expired'],
          },
          {'kind': 'traderLevel', 'traderId': 'trader', 'level': 3},
          {
            'kind': 'traderStanding',
            'traderId': 'trader',
            'comparison': 'atLeast',
            'rawComparison': '>=',
            'value': 0.5,
          },
          {'kind': 'skill', 'skillId': 'HideoutManagement', 'level': 5},
          {'kind': 'none'},
        ];
        for (var i = 0; i < factExpectations.length; i++) {
          final facts = (objectives[i + 1] as Map<String, dynamic>)['facts'];
          for (final entry in factExpectations[i].entries) {
            expect(facts, containsPair(entry.key, entry.value));
          }
        }
        final decoded = ProgressCatalog.fromJson(json);
        expect(_jsonCopy(decoded.toJson()), json);
        expect(
          decoded.tasksById['bear']!.objectives[1].facts,
          isA<QuestItemFacts>(),
        );
        expect(
          decoded.tasksById['bear']!.objectives[2].facts,
          isA<TaskStatusFacts>(),
        );
        expect(
          decoded.tasksById['bear']!.objectives[3].facts,
          isA<TraderLevelFacts>(),
        );
        expect(
          decoded.tasksById['bear']!.objectives[4].facts,
          isA<TraderStandingFacts>(),
        );
        expect(
          decoded.tasksById['bear']!.objectives[5].facts,
          isA<SkillFacts>(),
        );
        expect(decoded.tasksById['bear']!.objectives[6].facts, isA<NoFacts>());
      },
    );

    test('preserves unknown enums with their raw source strings', () {
      final task = CatalogTask(
        id: 'unknown',
        name: 'Unknown',
        faction: TaskFaction.unknown,
        rawFaction: 'Marauder',
        prerequisites: [
          TaskPrerequisite(
            taskId: 'x',
            statuses: [TaskStatus.unknown],
            rawStatuses: ['expired'],
          ),
        ],
        alternatives: [
          TaskAlternative(
            taskId: 'x',
            statuses: [TaskStatus.unknown],
            rawStatuses: ['expired'],
          ),
        ],
        failConditions: [
          FailCondition(
            id: 'f',
            type: ObjectiveType.unknown,
            rawType: 'newCondition',
          ),
        ],
        traderRequirements: [
          TraderRequirement(
            traderId: 't',
            type: TraderRequirementType.unknown,
            rawType: 'newGate',
            comparison: Comparison.unknown,
            rawComparison: '~',
          ),
        ],
        objectives: [
          TaskObjective(
            id: 'o',
            type: ObjectiveType.unknown,
            rawType: 'photograph',
            facts: TraderStandingFacts(
              comparison: Comparison.unknown,
              rawComparison: '~',
            ),
          ),
        ],
      );
      final decoded = CatalogTask.fromJson(_jsonCopy(task.toJson()));
      expect(decoded.faction, TaskFaction.unknown);
      expect(decoded.rawFaction, 'Marauder');
      expect(decoded.prerequisites!.single.statuses, [TaskStatus.unknown]);
      expect(decoded.prerequisites!.single.rawStatuses, ['expired']);
      expect(decoded.alternatives!.single.rawStatuses, ['expired']);
      expect(decoded.failConditions!.single.type, ObjectiveType.unknown);
      expect(decoded.failConditions!.single.rawType, 'newCondition');
      expect(
        decoded.traderRequirements!.single.type,
        TraderRequirementType.unknown,
      );
      expect(decoded.traderRequirements!.single.rawType, 'newGate');
      expect(decoded.traderRequirements!.single.comparison, Comparison.unknown);
      expect(decoded.traderRequirements!.single.rawComparison, '~');
      expect(decoded.objectives.single.type, ObjectiveType.unknown);
      expect(decoded.objectives.single.rawType, 'photograph');
      final facts = decoded.objectives.single.facts as TraderStandingFacts;
      expect(facts.comparison, Comparison.unknown);
      expect(facts.rawComparison, '~');
    });

    test('distinguishes absent and empty nullable lists after storage', () {
      final unknown = CatalogTask(id: 'null', name: 'Null');
      final empty = CatalogTask(
        id: 'empty',
        name: 'Empty',
        gameModes: [],
        prerequisites: [],
        traderRequirements: [],
        failConditions: [],
        alternatives: [],
      );
      final a = CatalogTask.fromJson(_jsonCopy(unknown.toJson()));
      final b = CatalogTask.fromJson(_jsonCopy(empty.toJson()));
      expect(a.gameModes, isNull);
      expect(a.prerequisites, isNull);
      expect(a.traderRequirements, isNull);
      expect(a.failConditions, isNull);
      expect(a.alternatives, isNull);
      expect(b.gameModes, isEmpty);
      expect(b.prerequisites, isEmpty);
      expect(b.traderRequirements, isEmpty);
      expect(b.failConditions, isEmpty);
      expect(b.alternatives, isEmpty);
      final unknownLevel = StationLevel.fromJson(
        _jsonCopy(StationLevel(id: 'a', level: 1).toJson()),
      );
      final emptyLevel = StationLevel.fromJson(
        _jsonCopy(
          StationLevel(
            id: 'b',
            level: 1,
            stationRequirements: [],
            traderRequirements: [],
            skillRequirements: [],
          ).toJson(),
        ),
      );
      expect(unknownLevel.stationRequirements, isNull);
      expect(unknownLevel.traderRequirements, isNull);
      expect(unknownLevel.skillRequirements, isNull);
      expect(emptyLevel.stationRequirements, isEmpty);
      expect(emptyLevel.traderRequirements, isEmpty);
      expect(emptyLevel.skillRequirements, isEmpty);
      final nullPrereq = TaskPrerequisite.fromJson(
        _jsonCopy(TaskPrerequisite(taskId: 'x').toJson()),
      );
      final emptyPrereq = TaskPrerequisite.fromJson(
        _jsonCopy(
          TaskPrerequisite(taskId: 'x', statuses: [], rawStatuses: []).toJson(),
        ),
      );
      expect(nullPrereq.statuses, isNull);
      expect(nullPrereq.rawStatuses, isNull);
      expect(emptyPrereq.statuses, isEmpty);
      expect(emptyPrereq.rawStatuses, isEmpty);
      final nullAlternative = TaskAlternative.fromJson(
        _jsonCopy(TaskAlternative(taskId: 'x').toJson()),
      );
      final emptyAlternative = TaskAlternative.fromJson(
        _jsonCopy(
          TaskAlternative(taskId: 'x', statuses: [], rawStatuses: []).toJson(),
        ),
      );
      expect(nullAlternative.statuses, isNull);
      expect(nullAlternative.rawStatuses, isNull);
      expect(emptyAlternative.statuses, isEmpty);
      expect(emptyAlternative.rawStatuses, isEmpty);
      final nullObjective = TaskObjective.fromJson(
        _jsonCopy(TaskObjective(id: 'x', facts: ItemFacts()).toJson()),
      );
      final emptyObjective = TaskObjective.fromJson(
        _jsonCopy(
          TaskObjective(
            id: 'x',
            mapIds: [],
            facts: ItemFacts(itemIds: []),
          ).toJson(),
        ),
      );
      expect(nullObjective.mapIds, isNull);
      expect(emptyObjective.mapIds, isEmpty);
      expect((nullObjective.facts as ItemFacts).itemIds, isNull);
      expect((emptyObjective.facts as ItemFacts).itemIds, isEmpty);
      final nullStatus = ObjectiveFacts.fromJson(
        _jsonCopy(TaskStatusFacts().toJson()),
      ) as TaskStatusFacts;
      final emptyStatus = ObjectiveFacts.fromJson(
        _jsonCopy(TaskStatusFacts(statuses: [], rawStatuses: []).toJson()),
      ) as TaskStatusFacts;
      expect(nullStatus.statuses, isNull);
      expect(nullStatus.rawStatuses, isNull);
      expect(emptyStatus.statuses, isEmpty);
      expect(emptyStatus.rawStatuses, isEmpty);
    });

    test(
      'rebuilds shared objective flags and indexes without storing them',
      () {
        final catalog = _catalog();
        expect(catalog.tasksById.keys, unorderedEquals(['bear', 'usec']));
        expect(catalog.stationsById.keys, unorderedEquals(['library']));
        expect(catalog.sharedObjectiveIds, {'shared'});
        expect(catalog.tasksById['bear']!.objectives.first.isShared, isTrue);
        expect(catalog.tasksById['usec']!.objectives.single.isShared, isTrue);
        expect(catalog.tasksById['bear']!.objectives[1].isShared, isFalse);
        final json = _jsonCopy(catalog.toJson());
        expect(json, isNot(contains('tasksById')));
        expect(json, isNot(contains('stationsById')));
        expect(json, isNot(contains('sharedObjectiveIds')));
        for (final task in json['tasks'] as List<dynamic>) {
          for (final objective
              in (task as Map<String, dynamic>)['objectives']
                  as List<dynamic>) {
            expect(objective, isNot(contains('isShared')));
          }
        }
        final restored = ProgressCatalog.fromJson(json);
        expect(restored.sharedObjectiveIds, {'shared'});
        expect(restored.tasksById['bear']!.objectives.first.isShared, isTrue);
        expect(restored.tasksById['usec']!.objectives.single.isShared, isTrue);
        expect(restored.tasksById['bear']!.objectives[1].isShared, isFalse);
        expect(restored.stationsById['library']!.id, 'library');
      },
    );

    test('rejects unsupported and wrong-typed stored format versions', () {
      final json = _catalog().toJson();
      for (final value in <Object?>[null, 0, 2, 1.0, '1', true, []]) {
        expect(
          () => ProgressCatalog.fromJson({...json, 'formatVersion': value}),
          throwsA(isA<FormatException>()),
          reason: 'version $value',
        );
      }
    });

    test('rejects wrong-typed nested stored fields with FormatException', () {
      final mutations = <void Function(Map<String, dynamic>)>[
        (j) => j['tasks'] = 'not a list',
        (j) => j['stations'] = [7],
        (j) =>
            ((j['tasks'] as List<dynamic>).first
                    as Map<String, dynamic>)['name'] =
                7,
        (j) =>
            ((j['tasks'] as List<dynamic>).first
                    as Map<String, dynamic>)['kappaRequired'] =
                'yes',
        (j) =>
            ((j['tasks'] as List<dynamic>).first
                as Map<String, dynamic>)['gameModes'] = [
              7,
            ],
        (j) =>
            ((((j['tasks'] as List<dynamic>).first
                            as Map<String, dynamic>)['prerequisites']
                        as List<dynamic>)
                    .first
                as Map<String, dynamic>)['statuses'] = [
              7,
            ],
        (j) =>
            ((((j['tasks'] as List<dynamic>).first
                                as Map<String, dynamic>)['alternatives']
                            as List<dynamic>)
                        .first
                    as Map<String, dynamic>)['taskId'] =
                false,
        (j) =>
            ((((j['tasks'] as List<dynamic>).first
                                as Map<String, dynamic>)['failConditions']
                            as List<dynamic>)
                        .first
                    as Map<String, dynamic>)['type'] =
                3,
        (j) =>
            ((((j['tasks'] as List<dynamic>).first
                                as Map<String, dynamic>)['traderRequirements']
                            as List<dynamic>)
                        .first
                    as Map<String, dynamic>)['value'] =
                'two',
        (j) =>
            (((((j['tasks'] as List<dynamic>).first
                                as Map<String, dynamic>)['objectives']
                            as List<dynamic>)
                        .first
                    as Map<String, dynamic>)['facts']
                as Map<String, dynamic>)['itemIds'] = [
              false,
            ],
        (j) =>
            ((((j['stations'] as List<dynamic>).first
                                as Map<String, dynamic>)['levels']
                            as List<dynamic>)
                        .first
                    as Map<String, dynamic>)['level'] =
                '1',
        (j) {
          final station =
              (j['stations'] as List<dynamic>).first as Map<String, dynamic>;
          final level =
              (station['levels'] as List<dynamic>).first
                  as Map<String, dynamic>;
          final requirement =
              (level['stationRequirements'] as List<dynamic>).first
                  as Map<String, dynamic>;
          requirement['level'] = '3';
        },
        (j) {
          final station =
              (j['stations'] as List<dynamic>).first as Map<String, dynamic>;
          final level =
              (station['levels'] as List<dynamic>).first
                  as Map<String, dynamic>;
          final requirement =
              (level['skillRequirements'] as List<dynamic>).first
                  as Map<String, dynamic>;
          requirement['level'] = false;
        },
      ];
      for (var i = 0; i < mutations.length; i++) {
        final json = _jsonCopy(_catalog().toJson());
        mutations[i](json);
        expect(
          () => ProgressCatalog.fromJson(json),
          throwsA(isA<FormatException>()),
          reason: 'malformed nested field $i',
        );
      }
    });

    test('copies inputs and exposes unmodifiable collections and indexes', () {
      final modes = ['pve'];
      final statuses = [TaskStatus.complete];
      final rawStatuses = ['complete'];
      final alternativeStatuses = [TaskStatus.failed];
      final alternativeRaw = ['failed'];
      final itemIds = ['item'];
      final maps = ['map'];
      final factStatuses = [TaskStatus.active];
      final factRaw = ['active'];
      final prerequisites = [
        TaskPrerequisite(
          taskId: 'b',
          statuses: statuses,
          rawStatuses: rawStatuses,
        ),
      ];
      final alternatives = [
        TaskAlternative(
          taskId: 'b',
          statuses: alternativeStatuses,
          rawStatuses: alternativeRaw,
        ),
      ];
      final failConditions = [FailCondition(id: 'f')];
      final traders = [TraderRequirement(traderId: 't')];
      final objectives = [
        TaskObjective(
          id: 'o',
          mapIds: maps,
          facts: ItemFacts(itemIds: itemIds),
        ),
        TaskObjective(
          id: 's',
          facts: TaskStatusFacts(statuses: factStatuses, rawStatuses: factRaw),
        ),
      ];
      final stationRequirements = [StationRequirement(stationId: 'rest')];
      final levelTraders = [TraderRequirement(traderId: 't')];
      final skills = [SkillRequirement(skillId: 's')];
      final levels = [
        StationLevel(
          id: 'l',
          level: 1,
          stationRequirements: stationRequirements,
          traderRequirements: levelTraders,
          skillRequirements: skills,
        ),
      ];
      final tasks = [
        CatalogTask(
          id: 'a',
          name: 'A',
          gameModes: modes,
          prerequisites: prerequisites,
          alternatives: alternatives,
          failConditions: failConditions,
          traderRequirements: traders,
          objectives: objectives,
        ),
      ];
      final stations = [HideoutStation(id: 'h', name: 'H', levels: levels)];
      final catalog = ProgressCatalog(tasks: tasks, stations: stations);
      modes.clear();
      statuses.clear();
      rawStatuses.clear();
      alternativeStatuses.clear();
      alternativeRaw.clear();
      itemIds.clear();
      maps.clear();
      factStatuses.clear();
      factRaw.clear();
      prerequisites.clear();
      alternatives.clear();
      failConditions.clear();
      traders.clear();
      objectives.clear();
      stationRequirements.clear();
      levelTraders.clear();
      skills.clear();
      levels.clear();
      tasks.clear();
      stations.clear();
      final task = catalog.tasks.single;
      final prerequisite = task.prerequisites!.single;
      final alternative = task.alternatives!.single;
      final item = task.objectives.first.facts as ItemFacts;
      final fact = task.objectives[1].facts as TaskStatusFacts;
      final level = catalog.stations.single.levels.single;
      expect(task.gameModes, ['pve']);
      expect(prerequisite.statuses, [TaskStatus.complete]);
      expect(prerequisite.rawStatuses, ['complete']);
      expect(alternative.statuses, [TaskStatus.failed]);
      expect(alternative.rawStatuses, ['failed']);
      expect(task.failConditions, hasLength(1));
      expect(task.traderRequirements, hasLength(1));
      expect(task.objectives.first.mapIds, ['map']);
      expect(item.itemIds, ['item']);
      expect(fact.statuses, [TaskStatus.active]);
      expect(fact.rawStatuses, ['active']);
      expect(level.stationRequirements, hasLength(1));
      expect(level.traderRequirements, hasLength(1));
      expect(level.skillRequirements, hasLength(1));
      expect(() => catalog.tasks.clear(), throwsUnsupportedError);
      expect(() => catalog.stations.clear(), throwsUnsupportedError);
      expect(() => catalog.tasksById.clear(), throwsUnsupportedError);
      expect(() => catalog.stationsById.clear(), throwsUnsupportedError);
      expect(() => catalog.sharedObjectiveIds.add('x'), throwsUnsupportedError);
      expect(() => task.gameModes!.clear(), throwsUnsupportedError);
      expect(() => task.prerequisites!.clear(), throwsUnsupportedError);
      expect(() => task.alternatives!.clear(), throwsUnsupportedError);
      expect(() => task.failConditions!.clear(), throwsUnsupportedError);
      expect(() => task.traderRequirements!.clear(), throwsUnsupportedError);
      expect(() => task.objectives.clear(), throwsUnsupportedError);
      expect(() => prerequisite.statuses!.clear(), throwsUnsupportedError);
      expect(() => prerequisite.rawStatuses!.clear(), throwsUnsupportedError);
      expect(() => alternative.statuses!.clear(), throwsUnsupportedError);
      expect(() => alternative.rawStatuses!.clear(), throwsUnsupportedError);
      expect(
        () => task.objectives.first.mapIds!.clear(),
        throwsUnsupportedError,
      );
      expect(() => item.itemIds!.clear(), throwsUnsupportedError);
      expect(() => fact.statuses!.clear(), throwsUnsupportedError);
      expect(() => fact.rawStatuses!.clear(), throwsUnsupportedError);
      expect(
        () => catalog.stations.single.levels.clear(),
        throwsUnsupportedError,
      );
      expect(() => level.stationRequirements!.clear(), throwsUnsupportedError);
      expect(() => level.traderRequirements!.clear(), throwsUnsupportedError);
      expect(() => level.skillRequirements!.clear(), throwsUnsupportedError);
    });
    test('rejects malformed facts discriminators and subtype fields', () {
      for (final json in <Map<String, dynamic>>[
        {},
        {'kind': 7},
        {'kind': 'futureFacts'},
        {'kind': 'item', 'foundInRaid': 'yes'},
        {'kind': 'questItem', 'questItemId': 7},
        {'kind': 'taskStatus', 'taskId': false},
        {
          'kind': 'taskStatus',
          'rawStatuses': [7],
        },
        {'kind': 'traderLevel', 'level': 1.5},
        {'kind': 'traderStanding', 'comparison': 7},
        {'kind': 'traderStanding', 'value': 'five'},
        {'kind': 'skill', 'skillId': 7},
        {'kind': 'skill', 'level': 'five'},
      ]) {
        expect(
          () => ObjectiveFacts.fromJson(json),
          throwsA(isA<FormatException>()),
          reason: '$json',
        );
      }
    });
  });
}
