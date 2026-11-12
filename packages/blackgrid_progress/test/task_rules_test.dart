import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:test/test.dart';

import 'support/task_rules.dart';

void main() {
  test('one result per task in catalog order', () {
    final catalog = testCatalog([testTask('c'), testTask('a'), testTask('b')]);
    final results = evaluateTasks(
      catalog,
      ProgressMode.regular,
      PlayerProgress(),
      table: testEditionTable,
    );
    expect(results.map((result) => result.taskId), ['c', 'a', 'b']);
    expect(
      results.map((result) => result.status),
      everyElement(AvailabilityStatus.available),
    );
  });

  test('progress for a task outside the catalog is ignored', () {
    final catalog = testCatalog([testTask('a')]);
    final empty = evaluateTasks(
      catalog,
      ProgressMode.regular,
      PlayerProgress(),
      table: testEditionTable,
    );
    final extra = evaluateTasks(
      catalog,
      ProgressMode.regular,
      PlayerProgress(taskStates: {'gone-1': TaskProgressState.finished}),
      table: testEditionTable,
    );
    expect(extra, empty);
  });

  test('a new snapshot does not change earlier results', () {
    final catalog = testCatalog([testTask('a', minPlayerLevel: 10)]);
    final earlier = evaluateTasks(
      catalog,
      ProgressMode.regular,
      PlayerProgress(level: 4),
      table: testEditionTable,
    );
    final saved = earlier.single;
    final later = evaluateTasks(
      catalog,
      ProgressMode.regular,
      PlayerProgress(level: 10),
      table: testEditionTable,
    );
    expect(saved.status, AvailabilityStatus.locked);
    expect(saved.checked, [LevelTooLow(required: 10, actual: 4)]);
    expect(later.single.status, AvailabilityStatus.available);
    expect(earlier.single, same(saved));
    expect(
      saved,
      evaluateTasks(
        catalog,
        ProgressMode.regular,
        PlayerProgress(level: 4),
        table: testEditionTable,
      ).single,
    );
    expect(
      saved.hashCode,
      evaluateTasks(
        catalog,
        ProgressMode.regular,
        PlayerProgress(level: 4),
        table: testEditionTable,
      ).single.hashCode,
    );
    expect(saved == later.single, isFalse);
  });

  test('finished task is done without gate reasons', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        minPlayerLevel: 20,
        otherRequirements: null,
        delayMin: null,
      ),
      progress: PlayerProgress(
        level: 1,
        taskStates: {'a': TaskProgressState.finished},
      ),
    );
    expect(result.status, AvailabilityStatus.done);
    expect(result.started, isFalse);
    expect(result.checked, [const Finished()]);
    expect(result.unchecked, isEmpty);
  });

  test('failed restartable task is evaluated as not started', () {
    final task = testTask('a', restartable: true, minPlayerLevel: 10);
    final passed = evaluateTestTask(
      task,
      progress: PlayerProgress(
        level: 10,
        taskStates: {'a': TaskProgressState.failed},
      ),
    );
    expect(passed.status, AvailabilityStatus.available);
    expect(passed.started, isFalse);
    expect(passed.checked, isEmpty);
    final locked = evaluateTestTask(
      task,
      progress: PlayerProgress(
        level: 1,
        taskStates: {'a': TaskProgressState.failed},
      ),
    );
    expect(locked.status, AvailabilityStatus.locked);
    expect(locked.checked, [LevelTooLow(required: 10, actual: 1)]);
  });

  test('failed task with unknown restartability is done', () {
    for (final restartable in <bool?>[null, false]) {
      final result = evaluateTestTask(
        testTask('a', restartable: restartable),
        progress: PlayerProgress(taskStates: {'a': TaskProgressState.failed}),
      );
      expect(result.status, AvailabilityStatus.done);
      expect(result.started, isFalse);
      expect(result.checked, [const Failed()]);
      expect(result.unchecked, isEmpty);
    }
  });

  test('started task overrides failed and unchecked gates', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        minPlayerLevel: 15,
        faction: TaskFaction.usec,
        otherRequirements: null,
        delayMin: null,
      ),
      progress: PlayerProgress(
        level: 1,
        faction: PlayerFaction.bear,
        taskStates: {'a': TaskProgressState.started},
      ),
    );
    expect(result.status, AvailabilityStatus.available);
    expect(result.started, isTrue);
    expect(result.checked, isEmpty);
    expect(result.unchecked, isEmpty);
  });

  test('locked result lists every failing gate', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        minPlayerLevel: 15,
        traderRequirements: [loyalty('prapor', Comparison.atLeast, 2)],
      ),
      progress: PlayerProgress(level: 10, traderLoyalty: {'prapor': 1}),
    );
    expect(result.status, AvailabilityStatus.locked);
    expect(
      result.checked,
      unorderedEquals([
        LevelTooLow(required: 15, actual: 10),
        LoyaltyTooLow(
          traderId: 'prapor',
          comparison: Comparison.atLeast,
          required: 2,
          actual: 1,
        ),
      ]),
    );
    expect(result.unchecked, isEmpty);
  });

  test('failing gate locks and unchecked gates are still listed', () {
    final result = evaluateTestTask(
      testTask(
        'a',
        minPlayerLevel: 15,
        otherRequirements: [
          const GlobalVariableRequirement(id: 'g', variableId: 'v'),
        ],
      ),
      progress: PlayerProgress(level: 10),
    );
    expect(result.status, AvailabilityStatus.locked);
    expect(result.checked, [LevelTooLow(required: 15, actual: 10)]);
    expect(result.unchecked, [GlobalVariable(variableId: 'v')]);
  });

  test('progress maps and result collections are immutable snapshots', () {
    final states = {'a': TaskProgressState.started};
    final levels = {'trader': 2};
    final progress = PlayerProgress(taskStates: states, traderLoyalty: levels);
    states['a'] = TaskProgressState.finished;
    levels['trader'] = 1;
    expect(progress.taskStates['a'], TaskProgressState.started);
    expect(progress.traderLoyalty['trader'], 2);
    expect(
      () => progress.taskStates['b'] = TaskProgressState.failed,
      throwsUnsupportedError,
    );
    expect(() => progress.traderLoyalty['trader'] = 3, throwsUnsupportedError);

    final modes = ['regular'];
    final traders = ['one'];
    final checked = <CheckedReason>[WrongGameMode(allowed: modes)];
    final unchecked = <UncheckedReason>[TraderDialogue(traderIds: traders)];
    final result = TaskAvailability(
      taskId: 'a',
      status: AvailabilityStatus.locked,
      checked: checked,
      unchecked: unchecked,
    );
    checked.clear();
    unchecked.clear();
    modes.add('pve');
    traders.add('two');
    expect((result.checked.single as WrongGameMode).allowed, ['regular']);
    expect((result.unchecked.single as TraderDialogue).traderIds, ['one']);
    expect(result.checked, hasLength(1));
    expect(result.unchecked, hasLength(1));
    expect(() => result.checked.clear(), throwsUnsupportedError);
    expect(() => result.unchecked.clear(), throwsUnsupportedError);
    expect(
      () => (result.checked.single as WrongGameMode).allowed.add('pve'),
      throwsUnsupportedError,
    );
    expect(
      () => (result.unchecked.single as TraderDialogue).traderIds!.add('two'),
      throwsUnsupportedError,
    );
  });

  test('result equality and hash include nested reason values', () {
    TaskAvailability make(List<String> modes, Set<TaskStatus> needed) =>
        TaskAvailability(
          taskId: 'a',
          status: AvailabilityStatus.locked,
          checked: [
            WrongGameMode(allowed: modes),
            PrerequisiteNotMet(taskId: 'p', needed: needed),
          ],
          unchecked: [
            TraderDialogue(traderIds: ['one', 'two']),
          ],
        );
    final first = make(
      ['regular', 'pve'],
      {TaskStatus.complete, TaskStatus.failed},
    );
    final equal = make(
      ['regular', 'pve'],
      {TaskStatus.failed, TaskStatus.complete},
    );
    final different = make(
      ['regular'],
      {TaskStatus.complete, TaskStatus.failed},
    );
    expect(first == equal, isTrue);
    expect(first.hashCode, equal.hashCode);
    expect(first == different, isFalse);
    final needed = (first.checked.last as PrerequisiteNotMet).needed;
    expect(() => needed.add(TaskStatus.active), throwsUnsupportedError);
  });
}
