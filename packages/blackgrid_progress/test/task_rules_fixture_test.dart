import 'dart:convert';
import 'dart:io';

import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:test/test.dart';

const _root = 'test/fixtures/tarkov_dev';
const _level = '59c9392986f7742f6923add2';
const _complete = '5a68663e86f774501078f78a';
const _failed = '59c93e8e86f7742a406989c4';
const _active = '597a160786f77477531d39d2';
const _alternative = '597a0f5686f774273b74f676';
const _faction = '639136df4b15ca31f76bc31f';
const _edition = '666314b4d7f171c4c20226c3';
const _global = '64f5deac39e45b527a7c4232';
const _dialogue = '657315ddab5a49b71f098853';
const _delay = '63966fbeea19ac7ed845db2e';
const _prestige = '6761ff17cdc36bd66102e9d0';
const _reputation = '66d9cbb67b491f9d5304f6e6';

ProgressCatalog _load(String mode) {
  final source = jsonDecode(
    File('$_root/${mode}_tasks.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final traders = (jsonDecode(
    File('$_root/traders.json').readAsStringSync(),
  ) as List<dynamic>).cast<String>().toSet();
  return parseProgressCatalog(
    source['data'],
    <String, dynamic>{},
    traders,
    null,
    null,
  );
}

TaskAvailability _answer(
  ProgressCatalog catalog,
  ProgressMode mode,
  String id,
  PlayerProgress progress,
) => evaluateTasks(catalog, mode, progress).singleWhere((r) => r.taskId == id);

void main() {
  final catalogs = {
    ProgressMode.regular: _load('regular'),
    ProgressMode.pve: _load('pve'),
  };

  test('repeated evaluation over the excerpt is equal', () {
    for (final MapEntry(key: mode, value: catalog) in catalogs.entries) {
      final progress = PlayerProgress(
        level: 10,
        faction: PlayerFaction.bear,
        edition: 'standard',
        traderLoyalty: {
          for (final task in catalog.tasks)
            if (task.traderId != null) task.traderId!: 1,
        },
      );
      final first = evaluateTasks(catalog, mode, progress);
      final second = evaluateTasks(catalog, mode, progress);
      expect(second, first);
      expect(second.map((r) => r.hashCode), first.map((r) => r.hashCode));
      expect(first.map((r) => r.taskId), catalog.tasks.map((t) => t.id));
    }
  });

  test('every gate kind is hit by an excerpt task', () {
    for (final MapEntry(key: mode, value: catalog) in catalogs.entries) {
      TaskAvailability answer(
        String id,
        PlayerProgress progress, {
        ProgressMode? evaluatedMode,
      }) => _answer(catalog, evaluatedMode ?? mode, id, progress);
      final levelTask = catalog.tasksById[_level]!;
      expect(
        answer(_level, PlayerProgress(level: 1)).checked,
        contains(LevelTooLow(required: levelTask.minPlayerLevel!, actual: 1)),
      );
      final loyalty = levelTask.traderRequirements!.firstWhere(
        (r) => r.type == TraderRequirementType.level,
      );
      expect(
        answer(
          _level,
          PlayerProgress(traderLoyalty: {loyalty.traderId: 1}),
        ).checked,
        contains(
          LoyaltyTooLow(
            traderId: loyalty.traderId,
            comparison: loyalty.comparison,
            required: loyalty.value!,
            actual: 1,
          ),
        ),
      );

      final complete = catalog.tasksById[_complete]!.prerequisites!.first;
      expect(
        answer(_complete, PlayerProgress()).checked,
        contains(
          PrerequisiteNotMet(
            taskId: complete.taskId,
            needed: {TaskStatus.complete},
          ),
        ),
      );
      final failed = catalog.tasksById[_failed]!.prerequisites!.first;
      expect(
        answer(
          _failed,
          PlayerProgress(
            taskStates: {failed.taskId: TaskProgressState.finished},
          ),
        ).checked,
        contains(
          PrerequisiteNotMet(
            taskId: failed.taskId,
            needed: {TaskStatus.failed},
          ),
        ),
      );
      final active = catalog.tasksById[_active]!.prerequisites!.first;
      expect(
        answer(_active, PlayerProgress()).checked,
        contains(
          PrerequisiteNotMet(
            taskId: active.taskId,
            needed: {TaskStatus.active},
          ),
        ),
      );
      expect(
        answer(
          _active,
          PlayerProgress(
            taskStates: {active.taskId: TaskProgressState.finished},
          ),
        ).unchecked,
        contains(ActivePrerequisiteFinished(taskId: active.taskId)),
      );
      final alternative = catalog.tasksById[_alternative]!.alternatives!.first;
      expect(
        answer(
          _alternative,
          PlayerProgress(
            taskStates: {alternative.taskId: TaskProgressState.finished},
          ),
        ).checked,
        contains(AlternativeTaken(taskId: alternative.taskId)),
      );

      final faction = catalog.tasksById[_faction]!.faction;
      expect(
        answer(
          _faction,
          PlayerProgress(
            faction: faction == TaskFaction.bear
                ? PlayerFaction.usec
                : PlayerFaction.bear,
          ),
        ).checked,
        contains(WrongFaction(required: faction)),
      );
      final restricted = mode == ProgressMode.regular
          ? _prestige
          : '6834287b7559f4e6d50bc0fa';
      expect(
        answer(
          restricted,
          PlayerProgress(),
          evaluatedMode: mode == ProgressMode.regular
              ? ProgressMode.pve
              : ProgressMode.regular,
        ).checked,
        contains(
          WrongGameMode(allowed: catalog.tasksById[restricted]!.gameModes!),
        ),
      );
      expect(
        answer(_edition, PlayerProgress(edition: 'standard')).checked,
        contains(const EditionNotPermitted(edition: 'standard')),
      );
      final global = catalog.tasksById[_global]!.otherRequirements!
          .whereType<GlobalVariableRequirement>()
          .first;
      expect(
        answer(_global, PlayerProgress()).unchecked,
        contains(GlobalVariable(variableId: global.variableId)),
      );
      final dialogue = catalog.tasksById[_dialogue]!.otherRequirements!
          .whereType<DialogueRequirement>()
          .first;
      expect(
        answer(_dialogue, PlayerProgress()).unchecked,
        contains(TraderDialogue(traderIds: dialogue.traderIds)),
      );
      final delay = catalog.tasksById[_delay]!;
      expect(
        answer(_delay, PlayerProgress()).unchecked,
        contains(
          AvailabilityDelay(
            minSeconds: delay.availableDelaySecondsMin,
            maxSeconds: delay.availableDelaySecondsMax,
          ),
        ),
      );
      final reputation = catalog.tasksById[_reputation]!.traderRequirements!
          .firstWhere((r) => r.type == TraderRequirementType.reputation);
      expect(
        answer(_reputation, PlayerProgress()).unchecked,
        contains(ReputationRequirement(traderId: reputation.traderId)),
      );
    }
    final regular = catalogs[ProgressMode.regular]!;
    expect(
      _answer(
        regular,
        ProgressMode.regular,
        _prestige,
        PlayerProgress(),
      ).unchecked,
      contains(
        PrestigeRequired(
          prestigeId: regular.tasksById[_prestige]!.requiredPrestigeId!,
        ),
      ),
    );
  });

  test('excerpt manifest records source URLs and fetch date', () {
    final source = File('$_root/SOURCE.md').readAsStringSync();
    expect(source, contains('Fetch date: 2026-11-12'));
    expect(source, contains('https://json.tarkov.dev/regular/tasks'));
    expect(source, contains('https://json.tarkov.dev/pve/tasks'));
    expect(source, contains('## Selection by gate'));
    for (final mode in ['regular', 'pve']) {
      expect(
        File('$_root/${mode}_tasks.json').lengthSync(),
        lessThanOrEqualTo(200000),
      );
    }
    for (final entry in editionTable.entries.entries) {
      expect(regularTaskIds(catalogs), contains(entry.key));
    }
  });
}

Set<String> regularTaskIds(Map<ProgressMode, ProgressCatalog> catalogs) =>
    catalogs[ProgressMode.regular]!.tasksById.keys.toSet();
