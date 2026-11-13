import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/decision_engine.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/progress.dart';
import 'package:blackgrid/domain/raid_timers.dart';
import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';

CatalogClient _client(
  Map<String, dynamic> wire, {
  List<http.Request>? requests,
  String? failedPath,
}) => CatalogClient(
  client: MockClient((request) async {
    requests?.add(request);
    final path = request.url.pathSegments.last;
    if (path == failedPath) return http.Response('', 500);
    return http.Response(jsonEncode(wire[path]), 200);
  }),
  clock: () => fixtureNow,
);

Map<String, dynamic> _task(Map<String, dynamic> wire) =>
    wire['tasks']['data']['tasks']['task-a'] as Map<String, dynamic>;

ProgressCatalog _progressCatalog(CatalogSnapshot snapshot) {
  final block = snapshot.progressCatalog;
  expect(
    block,
    isNotNull,
    reason: 'The refresh must attach the progress catalog',
  );
  return block!;
}

Map<String, Object?> _legacyProjection(CatalogSnapshot snapshot) => {
  'requirements': snapshot.requirements.map((r) => r.toJson()).toList(),
  'requirementIndex': snapshot.requirementIndex.map(
    (id, requirements) =>
        MapEntry(id, requirements.map((r) => r.toJson()).toList()),
  ),
  'scavCooldown': snapshot.scavCooldown?.toJson(),
};

Map<String, Object?> _advice(ItemDecision decision) => {
  'recommendation': decision.recommendation,
  'reasons': [
    for (final reason in decision.reasons)
      {
        'requirement': reason.requirement.toJson(),
        'state': reason.state,
        'message': reason.message,
        'detail': reason.detail,
        'remaining': reason.remaining,
      },
  ],
  'warnings': decision.warnings,
  'fleaGross': decision.fleaGross,
  'traderGross': decision.traderGross,
  'traderId': decision.traderId,
  'traderName': decision.traderName,
  'fleaPerSlot': decision.fleaPerSlot,
  'traderPerSlot': decision.traderPerSlot,
  'firNeed': decision.firNeed,
  'nonFirNeed': decision.nonFirNeed,
  'unknownFirNeed': decision.unknownFirNeed,
  'fleaEligible': decision.fleaEligible,
  'openInputs': decision.openInputs,
};

void main() {
  test(
    'passes raw traders to the progress catalog without another request',
    () async {
      final wire = progressCatalogWireFixture();
      final traders = wire['traders']['data'] as Map<String, dynamic>;
      final prapor = traders['trader-a'] as Map<String, dynamic>;
      prapor['normalizedName'] = 'prapor';
      prapor['levels'] = [
        {'level': 4},
        {'level': 2},
        {'level': 1},
        {'level': 3},
      ];
      final fence = traders['trader-fence'] as Map<String, dynamic>;
      fence['name'] = 'fence-name';
      fence['levels'] = [
        {'level': 3},
        {'level': 1},
        {'level': 2},
      ];
      (wire['traders_en']['data'] as Map<String, dynamic>)['fence-name'] =
          'Fence';

      final requests = <http.Request>[];
      final snapshot = await _client(
        wire,
        requests: requests,
      ).fetch(GameMode.pve);
      const paths = {
        'items',
        'traders',
        'tasks',
        'hideout',
        'crafts',
        'barters',
        'items_en',
        'traders_en',
        'tasks_en',
        'hideout_en',
      };
      expect(requests, hasLength(paths.length));
      expect(requests.map((request) => request.url.path).toSet(), {
        for (final path in paths) '/pve/$path',
      });
      expect(requests.every((request) => request.method == 'GET'), isTrue);

      final progress = _progressCatalog(snapshot);
      final retained = {
        for (final trader in progress.traders!) trader.id: trader,
      };
      expect(retained.keys, unorderedEquals(traders.keys));
      expect(retained['trader-a']!.name, 'Synthetic Alpha');
      expect(retained['trader-a']!.normalizedName, 'prapor');
      expect(retained['trader-a']!.levels, [1, 2, 3, 4]);
      expect(retained['trader-fence']!.name, 'Fence');
      expect(retained['trader-fence']!.normalizedName, 'fence');
      expect(retained['trader-fence']!.levels, [1, 2, 3]);
      expect(retained['trader-b']!.levels, isNull);
    },
  );

  test(
    "refresh builds the mode's task catalog from the existing datasets",
    () async {
      const paths = {
        'items',
        'traders',
        'tasks',
        'hideout',
        'crafts',
        'barters',
        'items_en',
        'traders_en',
        'tasks_en',
        'hideout_en',
      };
      for (final (mode, route) in [
        (GameMode.pvp, 'regular'),
        (GameMode.pve, 'pve'),
        (GameMode.seasonal, 'pvp-season'),
      ]) {
        final wire = progressCatalogWireFixture();
        final requests = <http.Request>[];
        final snapshot = await _client(wire, requests: requests).fetch(mode);
        expect(snapshot.mode, mode);
        expect(requests, hasLength(paths.length));
        expect(requests.map((r) => r.url.path).toSet(), {
          for (final path in paths) '/$route/$path',
        });
        for (final request in requests) {
          expect(request.method, 'GET');
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'json.tarkov.dev');
          expect(request.followRedirects, isFalse);
        }
        final progress = _progressCatalog(snapshot);
        expect(progress.tasks, hasLength(snapshot.datasetCounts['tasks']!));
        expect(
          progress.stations,
          hasLength(snapshot.datasetCounts['hideout']!),
        );
        expect(progress.tasks, hasLength(1));
        expect(progress.stations, hasLength(1));
        expect(progress.tasks.single.id, 'task-a');
        expect(progress.stations.single.id, 'station-a');
      }
    },
  );

  test('values the item parse rejects still reject the refresh', () async {
    final invalid = <(String, void Function(Map<String, dynamic>))>[
      ('minPlayerLevel', (task) => task['minPlayerLevel'] = 'ten'),
      ('factionName', (task) => task['factionName'] = 42),
      (
        'prerequisite statuses not a list',
        (task) {
          task['taskRequirements'] = [
            {'task': 'task-a', 'status': 'complete'},
          ];
        },
      ),
      (
        'prerequisite status not a string',
        (task) {
          task['taskRequirements'] = [
            {
              'task': 'task-a',
              'status': [42],
            },
          ];
        },
      ),
      (
        'objective missing type',
        (task) {
          (task['objectives'] as List).first.remove('type');
        },
      ),
      for (final type in ['findItem', 'giveItem', 'plantItem', 'buildWeapon'])
        for (final field in ['count', 'foundInRaid', 'optional', 'items'])
          (
            '$type $field',
            (task) {
              final objective = <String, dynamic>{
                'id': 'invalid-objective',
                'type': type,
                if (type == 'buildWeapon')
                  'item': 'item-a'
                else
                  'items': ['item-a'],
                'count': 1,
                'foundInRaid': true,
                'optional': false,
              };
              final key = field == 'items' && type == 'buildWeapon'
                  ? 'item'
                  : field;
              objective[key] = switch (field) {
                'count' => 'one',
                'foundInRaid' || 'optional' => 'yes',
                _ => 42,
              };
              task['objectives'] = [objective];
            },
          ),
    ];
    for (final (label, mutate) in invalid) {
      final wire = progressCatalogWireFixture();
      mutate(_task(wire));
      await expectLater(
        _client(wire).fetch(GameMode.pve),
        throwsA(
          isA<CatalogException>().having(
            (e) => e.kind,
            'kind',
            CatalogFailure.invalid,
          ),
        ),
        reason: label,
      );
    }
  });

  test(
    'valid level, faction and found-in-raid pass into the task catalog',
    () async {
      final wire = progressCatalogWireFixture();
      _task(wire)
        ..['minPlayerLevel'] = 10
        ..['factionName'] = 'Any';
      final snapshot = await _client(wire).fetch(GameMode.pve);
      final task = _progressCatalog(snapshot).tasksById['task-a']!;
      final objective = task.objectives.singleWhere((o) => o.id == 'give-a');
      expect(task.minPlayerLevel, 10);
      expect(task.faction, TaskFaction.any);
      expect(objective.type, ObjectiveType.giveItem);
      expect(objective.facts, isA<ItemFacts>());
      expect((objective.facts as ItemFacts).foundInRaid, isTrue);
    },
  );

  test('unresolved prerequisite rejects the refresh as invalid', () async {
    for (final alternative in [false, true]) {
      final wire = progressCatalogWireFixture();
      final task = _task(wire);
      if (alternative) {
        task['failConditions'] = [
          {
            'id': 'fail-a',
            'type': 'taskStatus',
            'task': 'missing-task',
            'status': ['complete'],
          },
        ];
      } else {
        task['taskRequirements'] = [
          {
            'task': 'missing-task',
            'status': ['complete'],
          },
        ];
      }
      await expectLater(
        _client(wire).fetch(GameMode.pve),
        throwsA(
          isA<CatalogException>().having(
            (e) => e.kind,
            'kind',
            CatalogFailure.invalid,
          ),
        ),
        reason: alternative ? 'alternative' : 'prerequisite',
      );
    }
  });

  test('missing tasks dictionary falls back and is reported', () async {
    final snapshot = await _client(
      progressCatalogWireFixture(),
      failedPath: 'tasks_en',
    ).fetch(GameMode.pve);
    expect(snapshot.localizationErrors, contains('tasks'));
    final task = _progressCatalog(snapshot).tasksById['task-a']!;
    expect(task.name, 'synthetic-task');
    expect(
      task.objectives.singleWhere((o) => o.id == 'find-a').description,
      isNull,
    );
  });

  test('item requirements, index and scav inputs are identical with and without the block', () {
    final withBlock = fixtureCatalog(wire: progressCatalogWireFixture());
    _progressCatalog(withBlock);
    final captured = jsonDecode(
      File('test/fixtures/m1/catalog/item_projection_without_progress.json')
          .readAsStringSync(),
    );
    expect(_legacyProjection(withBlock), captured);
    expect(withBlock.requirements, isNotEmpty);
    expect(withBlock.requirementIndex, isNotEmpty);
    expect(withBlock.scavCooldown, isNotNull);

    final withoutJson = Map<String, dynamic>.from(withBlock.toJson())
      ..remove('progressCatalog');
    final withoutBlock = CatalogSnapshot.fromJson(withoutJson);
    expect(withoutBlock.toJson().containsKey('progressCatalog'), isFalse);
    expect(_legacyProjection(withoutBlock), captured);
    expect(withoutBlock.toJson(), withoutJson);

    final progress = decisionProgress(
      tasks: const {
        'task-a': EntityProgress(
          complete: false,
          failed: false,
          invalid: false,
        ),
      },
      objectives: const {
        'find-a': EntityProgress(complete: false, count: 1, invalid: false),
      },
      modules: const {'station-a-1': EntityProgress(complete: true)},
    );
    const engine = DecisionEngine();
    for (final id in withBlock.items.keys) {
      for (final fir in FirState.values) {
        ItemDecision evaluate(CatalogSnapshot catalog) => engine.evaluate(
          catalog.items[id]!,
          InspectionContext(
            mode: GameMode.pvp,
            now: fixtureNow,
            catalog: catalog,
            progress: progress,
            fir: fir,
          ),
        );
        expect(_advice(evaluate(withBlock)), _advice(evaluate(withoutBlock)));
      }
    }
    final withTimer = scavCooldownLength(
      withBlock.scavCooldown!,
      0,
      progress,
      GameMode.pvp,
    )!;
    final withoutTimer = scavCooldownLength(
      withoutBlock.scavCooldown!,
      0,
      progress,
      GameMode.pvp,
    )!;
    expect(withTimer.seconds, 1275);
    expect(withTimer.seconds, withoutTimer.seconds);
    expect(withTimer.inputsText, withoutTimer.inputsText);
    expect(withTimer.hasProgress, withoutTimer.hasProgress);
  });
  test(
    'malformed newly retained skill rows do not block item refreshes',
    () async {
      final wire = progressCatalogWireFixture();
      final level =
          (wire['hideout']['data']['station-a']['levels'] as List).first as Map;
      level['skillRequirements'] = [
        {'skill': 'Attention', 'level': 8},
      ];
      final baseline = fixtureCatalog(wire: wire);
      level['skillRequirements'] = [42];
      final snapshot = await _client(wire).fetch(GameMode.pve);
      final skill = snapshot
          .progressCatalog!
          .stations
          .single
          .levels
          .single
          .skillRequirements!
          .single;
      expect(skill.skillId, isNull);
      expect(skill.level, isNull);
      expect(
        snapshot.items['item-a']!.toJson(),
        baseline.items['item-a']!.toJson(),
      );
      expect(
        snapshot.requirements.map((requirement) => requirement.toJson()),
        baseline.requirements.map((requirement) => requirement.toJson()),
      );
      expect(snapshot.scavCooldown!.toJson(), baseline.scavCooldown!.toJson());
    },
  );
  test(
    'malformed newly retained fail conditions do not block item refreshes',
    () async {
      for (final conditions in <List<Object?>>[
        [42],
        [
          {'type': 'extract'},
        ],
        [
          {'id': 'condition', 'type': 'taskStatus'},
        ],
      ]) {
        final wire = progressCatalogWireFixture();
        final baseline = fixtureCatalog(wire: wire);
        _task(wire)['failConditions'] = conditions;
        final snapshot = await _client(wire).fetch(GameMode.pve);
        final task = snapshot.progressCatalog!.tasks.single;
        expect(task.failConditions, isNull);
        expect(task.alternatives, isNull);
        expect(
          snapshot.items['item-a']!.toJson(),
          baseline.items['item-a']!.toJson(),
        );
        expect(
          snapshot.requirements.map((requirement) => requirement.toJson()),
          baseline.requirements.map((requirement) => requirement.toJson()),
        );
      }
    },
  );
}
