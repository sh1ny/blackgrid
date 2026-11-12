import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:test/test.dart';

import 'support/task_rules.dart';

void main() {
  test('level below minimum locks', () {
    final result = evaluateTestTask(
      testTask('a', minPlayerLevel: 20),
      progress: PlayerProgress(level: 19),
    );
    expect(result.status, AvailabilityStatus.locked);
    expect(result.checked, [LevelTooLow(required: 20, actual: 19)]);
  });

  test('unset level is unchecked above minimum 1', () {
    final result = evaluateTestTask(testTask('a', minPlayerLevel: 20));
    expect(result.status, AvailabilityStatus.available);
    expect(result.unchecked, [LevelUnset(required: 20)]);
    for (final minimum in [0, 1]) {
      expect(
        evaluateTestTask(testTask('a', minPlayerLevel: minimum)).unchecked,
        isEmpty,
      );
    }
    expect(evaluateTestTask(testTask('a', minPlayerLevel: null)).unchecked, [
      const LevelRequirementUnknown(),
    ]);
  });

  test('loyalty at the required level passes', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        traderRequirements: [loyalty('skier', Comparison.atLeast, 3)],
      ),
      progress: PlayerProgress(traderLoyalty: {'skier': 3}),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(result.checked, isEmpty);
    expect(result.unchecked, isEmpty);
  });

  test('loyalty comparisons use their exact boundaries', () {
    final cases = <(Comparison, int, bool)>[
      (Comparison.atLeast, 1, false),
      (Comparison.atLeast, 2, true),
      (Comparison.greaterThan, 2, false),
      (Comparison.greaterThan, 3, true),
      (Comparison.atMost, 2, true),
      (Comparison.atMost, 3, false),
      (Comparison.lessThan, 1, true),
      (Comparison.lessThan, 2, false),
      (Comparison.equal, 2, true),
      (Comparison.equal, 3, false),
    ];
    for (final (comparison, actual, passes) in cases) {
      final result = evaluateTestTask(
        testTask('a', traderRequirements: [loyalty('t', comparison, 2)]),
        progress: PlayerProgress(traderLoyalty: {'t': actual}),
      );
      expect(
        result.status,
        passes ? AvailabilityStatus.available : AvailabilityStatus.locked,
        reason: '$comparison with $actual',
      );
      expect(
        result.checked,
        passes
            ? isEmpty
            : [
                LoyaltyTooLow(
                  traderId: 't',
                  comparison: comparison,
                  required: 2,
                  actual: actual,
                ),
              ],
      );
    }
  });

  test('reputation requirement is always unchecked', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        traderRequirements: [
          const TraderRequirement(
            traderId: 'fence',
            type: TraderRequirementType.reputation,
            comparison: Comparison.atMost,
            value: -1,
          ),
        ],
      ),
      progress: PlayerProgress(traderLoyalty: {'fence': 4}),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(result.unchecked, [ReputationRequirement(traderId: 'fence')]);
  });

  test('unset loyalty is unchecked for at least 2', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        traderRequirements: [loyalty('mechanic', Comparison.atLeast, 2)],
      ),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(result.unchecked, [LoyaltyUnset(traderId: 'mechanic')]);
  });

  test('unset loyalty is unchecked for at most 2', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        traderRequirements: [loyalty('ragman', Comparison.atMost, 2)],
      ),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(result.unchecked, [LoyaltyUnset(traderId: 'ragman')]);
  });

  test('only universally satisfied unset loyalty comparisons pass', () {
    final cases = <(Comparison, num, bool)>[
      (Comparison.atLeast, 1, true),
      (Comparison.atLeast, 0, true),
      (Comparison.atLeast, 2, false),
      (Comparison.greaterThan, 0, true),
      (Comparison.greaterThan, 1, false),
      (Comparison.atMost, 1, false),
      (Comparison.lessThan, 2, false),
      (Comparison.equal, 1, false),
    ];
    for (final (comparison, threshold, passes) in cases) {
      final result = evaluateTestTask(
        testTask(
          'a',
          traderRequirements: [loyalty('t', comparison, threshold)],
        ),
      );
      expect(result.status, AvailabilityStatus.available);
      expect(
        result.unchecked,
        passes ? isEmpty : [LoyaltyUnset(traderId: 't')],
        reason: '$comparison $threshold',
      );
    }
  });

  test('unknown loyalty type comparison and value are unchecked', () {
    final requirements = [
      const TraderRequirement(traderId: 'type'),
      loyalty('comparison', Comparison.unknown, 2),
      loyalty('value', Comparison.atLeast, null),
    ];
    final result = evaluateTestTask(
      testTask('a', traderRequirements: requirements),
      progress: PlayerProgress(
        traderLoyalty: {'type': 2, 'comparison': 2, 'value': 2},
      ),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(
      result.unchecked,
      unorderedEquals([
        LoyaltyRequirementUnknown(traderId: 'type'),
        LoyaltyRequirementUnknown(traderId: 'comparison'),
        LoyaltyRequirementUnknown(traderId: 'value'),
      ]),
    );
  });

  test('missing completion prerequisite locks', () {
    final result = evaluateTestTask(
      testTask(
        'b',
        prerequisites: [
          TaskPrerequisite(taskId: 'a', statuses: [TaskStatus.complete]),
        ],
      ),
    );
    expect(result.status, AvailabilityStatus.locked);
    expect(result.checked, [
      PrerequisiteNotMet(taskId: 'a', needed: {TaskStatus.complete}),
    ]);
  });

  test('must-be-failed prerequisite finished locks', () {
    final result = evaluateTestTask(
      testTask(
        'b',
        prerequisites: [
          TaskPrerequisite(taskId: 'a', statuses: [TaskStatus.failed]),
        ],
      ),
      progress: PlayerProgress(taskStates: {'a': TaskProgressState.finished}),
    );
    expect(result.status, AvailabilityStatus.locked);
    expect(result.checked, [
      PrerequisiteNotMet(taskId: 'a', needed: {TaskStatus.failed}),
    ]);
  });

  test('unknown prerequisites are unchecked', () {
    final result = evaluateTestTask(testTask('b', prerequisites: null));
    expect(result.status, AvailabilityStatus.available);
    expect(result.unchecked, [const PrerequisitesUnknown()]);
  });

  test('finished active-only prerequisite is unchecked', () {
    for (final statuses in [
      [TaskStatus.active],
      [TaskStatus.active, TaskStatus.failed],
      [TaskStatus.active, TaskStatus.unknown],
    ]) {
      final result = evaluateTestTask(
        testTask(
          'b',
          prerequisites: [TaskPrerequisite(taskId: 'a', statuses: statuses)],
        ),
        progress: PlayerProgress(taskStates: {'a': TaskProgressState.finished}),
      );
      expect(result.status, AvailabilityStatus.available);
      expect(result.unchecked, [ActivePrerequisiteFinished(taskId: 'a')]);
    }
    final accepted = evaluateTestTask(
      testTask(
        'b',
        prerequisites: [
          TaskPrerequisite(
            taskId: 'a',
            statuses: [TaskStatus.active, TaskStatus.complete],
          ),
        ],
      ),
      progress: PlayerProgress(taskStates: {'a': TaskProgressState.finished}),
    );
    expect(accepted.unchecked, isEmpty);
    expect(accepted.checked, isEmpty);
  });

  test('never-taken active-only prerequisite locks', () {
    final result = evaluateTestTask(
      testTask(
        'b',
        prerequisites: [
          TaskPrerequisite(taskId: 'a', statuses: [TaskStatus.active]),
        ],
      ),
    );
    expect(result.status, AvailabilityStatus.locked);
    expect(result.checked, [
      PrerequisiteNotMet(taskId: 'a', needed: {TaskStatus.active}),
    ]);
  });

  test('known prerequisite statuses are used and unknown ones ignored', () {
    final mixed = testTask(
      'b',
      prerequisites: [
        TaskPrerequisite(
          taskId: 'a',
          statuses: [TaskStatus.unknown, TaskStatus.failed],
        ),
      ],
    );
    final missing = evaluateTestTask(mixed);
    expect(missing.checked, [
      PrerequisiteNotMet(taskId: 'a', needed: {TaskStatus.failed}),
    ]);
    expect(missing.unchecked, isEmpty);
    final met = evaluateTestTask(
      mixed,
      progress: PlayerProgress(taskStates: {'a': TaskProgressState.failed}),
    );
    expect(met.status, AvailabilityStatus.available);
    expect(met.checked, isEmpty);
    for (final statuses in <List<TaskStatus>?>[
      null,
      [],
      [TaskStatus.unknown],
    ]) {
      final result = evaluateTestTask(
        testTask(
          'b',
          prerequisites: [TaskPrerequisite(taskId: 'a', statuses: statuses)],
        ),
      );
      expect(result.status, AvailabilityStatus.available);
      expect(result.unchecked, [PrerequisiteStatusUnknown(taskId: 'a')]);
    }
  });

  test('prerequisite and alternative states map to catalog statuses', () {
    final pairs = <(TaskStatus, TaskProgressState)>[
      (TaskStatus.complete, TaskProgressState.finished),
      (TaskStatus.active, TaskProgressState.started),
      (TaskStatus.failed, TaskProgressState.failed),
    ];
    for (final (status, state) in pairs) {
      final progress = PlayerProgress(taskStates: {'a': state});
      final prerequisite = evaluateTestTask(
        testTask(
          'b',
          prerequisites: [
            TaskPrerequisite(taskId: 'a', statuses: [status]),
          ],
        ),
        progress: progress,
      );
      expect(prerequisite.status, AvailabilityStatus.available);
      expect(prerequisite.checked, isEmpty);
      expect(prerequisite.unchecked, isEmpty);
      final alternative = evaluateTestTask(
        testTask(
          'b',
          alternatives: [
            TaskAlternative(taskId: 'a', statuses: [status]),
          ],
        ),
        progress: progress,
      );
      expect(alternative.status, AvailabilityStatus.locked);
      expect(alternative.checked, [AlternativeTaken(taskId: 'a')]);
    }
  });

  test('completed alternative locks', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        alternatives: [
          TaskAlternative(taskId: 'b', statuses: [TaskStatus.complete]),
        ],
      ),
      progress: PlayerProgress(taskStates: {'b': TaskProgressState.finished}),
    );
    expect(result.status, AvailabilityStatus.locked);
    expect(result.checked, [AlternativeTaken(taskId: 'b')]);
  });

  test('started alternative accepting complete passes', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        alternatives: [
          TaskAlternative(taskId: 'b', statuses: [TaskStatus.complete]),
        ],
      ),
      progress: PlayerProgress(taskStates: {'b': TaskProgressState.started}),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(result.checked, isEmpty);
  });

  test(
    'unknown alternative statuses are ignored and unknown list is unchecked',
    () {
      final unknownList = evaluateTestTask(testTask('a', alternatives: null));
      expect(unknownList.status, AvailabilityStatus.available);
      expect(unknownList.unchecked, [const AlternativesUnknown()]);
      for (final statuses in <List<TaskStatus>?>[
        null,
        [],
        [TaskStatus.unknown],
      ]) {
        final result = evaluateTestTask(
          testTask(
            'a',
            alternatives: [TaskAlternative(taskId: 'b', statuses: statuses)],
          ),
          progress: PlayerProgress(
            taskStates: {'b': TaskProgressState.finished},
          ),
        );
        expect(result.status, AvailabilityStatus.available);
        expect(result.checked, isEmpty);
        expect(result.unchecked, isEmpty);
      }
      final mixed = evaluateTestTask(
        testTask(
          'a',
          alternatives: [
            TaskAlternative(
              taskId: 'b',
              statuses: [TaskStatus.unknown, TaskStatus.failed],
            ),
          ],
        ),
        progress: PlayerProgress(taskStates: {'b': TaskProgressState.failed}),
      );
      expect(mixed.checked, [AlternativeTaken(taskId: 'b')]);
    },
  );

  test('other faction locks', () {
    final result = evaluateTestTask(
      testTask('a', faction: TaskFaction.usec),
      progress: PlayerProgress(faction: PlayerFaction.bear),
    );
    expect(result.status, AvailabilityStatus.locked);
    expect(result.checked, [WrongFaction(required: TaskFaction.usec)]);
  });

  test('unset faction is unchecked for a faction task', () {
    final result = evaluateTestTask(testTask('a', faction: TaskFaction.bear));
    expect(result.status, AvailabilityStatus.available);
    expect(result.unchecked, [FactionUnset(required: TaskFaction.bear)]);
    final unknown = evaluateTestTask(
      testTask('a', faction: TaskFaction.unknown),
      progress: PlayerProgress(faction: PlayerFaction.bear),
    );
    expect(unknown.unchecked, [const FactionUnknown()]);
    final same = evaluateTestTask(
      testTask('a', faction: TaskFaction.bear),
      progress: PlayerProgress(faction: PlayerFaction.bear),
    );
    expect(same.checked, isEmpty);
    expect(same.unchecked, isEmpty);
  });

  test('regular-only task locks in pve', () {
    final result = evaluateTestTask(
      testTask('a', gameModes: ['regular']),
      mode: ProgressMode.pve,
    );
    expect(result.status, AvailabilityStatus.locked);
    expect(result.checked, [
      WrongGameMode(allowed: ['regular']),
    ]);
  });

  test('unrestricted task passes in every ProgressMode', () {
    for (final mode in ProgressMode.values) {
      final result = evaluateTasks(
        testCatalog([testTask('a')]),
        mode,
        PlayerProgress(),
        table: testEditionTable,
      ).single;
      expect(result.status, AvailabilityStatus.available);
      expect(result.checked, isEmpty);
    }
    expect(ProgressMode.seasonal.tarkovDevName, 'pvp-season');
    expect(
      evaluateTestTask(
        testTask('a', gameModes: ['pvp-season']),
        mode: ProgressMode.seasonal,
      ).status,
      AvailabilityStatus.available,
    );
    expect(
      evaluateTestTask(
        testTask('a', gameModes: ['regular']),
        mode: ProgressMode.seasonal,
      ).checked,
      [
        WrongGameMode(allowed: ['regular']),
      ],
    );
    expect(
      evaluateTestTask(
        testTask('a', gameModes: []),
        mode: ProgressMode.regular,
      ).status,
      AvailabilityStatus.locked,
    );
  });

  test('edition outside the allowed set locks', () {
    final result = evaluateTestTask(
      testTask('allowed'),
      progress: PlayerProgress(edition: 'standard'),
    );
    expect(result.status, AvailabilityStatus.locked);
    expect(result.checked, [EditionNotPermitted(edition: 'standard')]);
    expect(
      evaluateTestTask(
        testTask('allowed'),
        progress: PlayerProgress(edition: 'unheard'),
      ).status,
      AvailabilityStatus.available,
    );
    expect(
      evaluateTestTask(
        testTask('excluded'),
        progress: PlayerProgress(edition: 'standard'),
      ).checked,
      [EditionNotPermitted(edition: 'standard')],
    );
    expect(
      evaluateTestTask(
        testTask('excluded'),
        progress: PlayerProgress(edition: 'other'),
      ).status,
      AvailabilityStatus.available,
    );
    expect(evaluateTestTask(testTask('no-entry')).unchecked, isEmpty);
    expect(evaluateTestTask(testTask('allowed')).unchecked, [
      const EditionUnset(),
    ]);
  });

  test('unrecognised edition is unchecked', () {
    final result = evaluateTestTask(
      testTask('allowed'),
      progress: PlayerProgress(edition: 'collector-2031'),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(result.unchecked, [EditionUnrecognised(edition: 'collector-2031')]);
  });

  test('global-variable gate is unchecked and available', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        otherRequirements: [
          const GlobalVariableRequirement(id: 'g', variableId: 'v'),
        ],
      ),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(result.checked, isEmpty);
    expect(result.unchecked, [GlobalVariable(variableId: 'v')]);
  });

  test('unknown other requirements and delay are unchecked', () {
    final result = evaluateTestTask(
      testTask('a', otherRequirements: null, delayMin: null, delayMax: null),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(
      result.unchecked,
      unorderedEquals([
        const OtherRequirementsUnknown(),
        const AvailabilityDelayUnknown(),
      ]),
    );
  });

  test('dialogue unknown other type delays and prestige are unchecked', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        requiredPrestigeId: 'prestige',
        delayMin: 1800,
        delayMax: 2100,
        otherRequirements: [
          const GlobalVariableRequirement(id: 'g'),
          DialogueRequirement(id: 'd', traderIds: ['one', 'two']),
          DialogueRequirement(id: 'missing'),
          const UnknownOtherRequirement(id: 'u', rawType: 'future'),
          const UnknownOtherRequirement(id: 'v'),
        ],
      ),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(
      result.unchecked,
      unorderedEquals([
        GlobalVariable(variableId: null),
        TraderDialogue(traderIds: ['one', 'two']),
        TraderDialogue(traderIds: null),
        OtherRequirementUnknownType(rawType: 'future'),
        OtherRequirementUnknownType(rawType: null),
        AvailabilityDelay(minSeconds: 1800, maxSeconds: 2100),
        PrestigeRequired(prestigeId: 'prestige'),
      ]),
    );
    for (final bounds in <(int?, int?)>[
      (null, 0),
      (0, null),
      (null, null),
      (30, null),
      (null, 30),
    ]) {
      final unknown = evaluateTestTask(
        testTask('a', delayMin: bounds.$1, delayMax: bounds.$2),
      );
      expect(unknown.unchecked, [const AvailabilityDelayUnknown()]);
    }
    expect(evaluateTestTask(testTask('a')).unchecked, isEmpty);
  });
}
