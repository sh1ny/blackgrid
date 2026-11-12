import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

const _folder = 'f1';
const _nextFolder = 'f2';
const _taskId = '5936d90786f7742b1420ba5b';
const _modeId = LogRecordId(_folder, LogFile.application, 1);
const _taskRecordId = LogRecordId(_folder, LogFile.pushNotifications, 42);
final _modeTime = DateTime(2026, 10, 28, 19, 30);
final _taskTime = DateTime(2026, 10, 28, 19, 31);

RaidLifecycleState _after(Iterable<GameLogEvent> events) {
  var state = RaidLifecycleState.initial;
  for (final event in events) {
    state = reduce(state, event).$1;
  }
  return state;
}

void main() {
  test('late task uses the mode preceding its log time', () {
    final ten = DateTime(2026, 10, 28, 10);
    DateTime at(int minute, [int second = 0]) =>
        ten.add(Duration(minutes: minute, seconds: second));
    LogRecordId modeId(int offset) =>
        LogRecordId(_folder, LogFile.application, offset);

    final early = _after([
      const SessionFolderChanged(_folder),
      SessionModeChanged(modeId(10), at(0), GameMode.pvp),
    ]);
    var state = early;
    for (final event in [
      SessionModeChanged(modeId(20), at(2), GameMode.pve),
      SessionModeChanged(modeId(30), at(3), GameMode.unknown),
      SessionModeChanged(modeId(50), at(4), GameMode.pvp),
      SessionModeChanged(modeId(40), at(4), GameMode.pve),
      SessionModeChanged(modeId(70), at(5), GameMode.unknown),
      SessionModeChanged(modeId(60), at(5), GameMode.pve),
      SessionModeChanged(modeId(90), at(6), GameMode.pve),
      SessionModeChanged(modeId(80), at(6), GameMode.unknown),
      SessionModeChanged(modeId(15), at(1, 30), GameMode.seasonal),
    ]) {
      state = reduce(state, event).$1;
    }

    void expectMode(
      RaidLifecycleState state,
      DateTime time,
      GameMode? mode, {
      String folder = _folder,
    }) {
      final id = LogRecordId(folder, LogFile.pushNotifications, 42);
      final events = <(RecordedGameLogEvent, ProgressTaskStatus)>[
        (TaskStarted(id, time, _taskId), ProgressTaskStatus.started),
        (TaskFailed(id, time, _taskId), ProgressTaskStatus.failed),
        (TaskFinished(id, time, _taskId), ProgressTaskStatus.finished),
      ];
      for (final (event, status) in events) {
        final (next, published) = reduce(state, event);
        final task = published.single as TaskTransition;
        expect(task.status, status);
        expect(task.mode, mode);
        expect(next, same(state));
      }
    }

    expectMode(state, ten.subtract(const Duration(milliseconds: 1)), null);
    expectMode(state, at(1), GameMode.pvp);
    expectMode(state, at(1, 30), GameMode.seasonal);
    expectMode(state, at(2), GameMode.pve);
    expectMode(state, at(3), null);
    expectMode(state, at(3, 30), null);
    expectMode(state, at(4), GameMode.pvp);
    expectMode(state, at(5), null);
    expectMode(state, at(6), GameMode.pve);
    expectMode(state.copyWith(phase: RaidPhase.inMenus), at(1), GameMode.pvp);
    expectMode(early, at(4), GameMode.pvp);

    final (nextFolder, _) = reduce(
      state,
      const SessionFolderChanged(_nextFolder),
    );
    expect(nextFolder.sessionMode, GameMode.seasonal);
    expect(nextFolder.folderMode, isNull);
    expectMode(nextFolder, at(4), null, folder: _nextFolder);
    final (reset, _) = reduce(state, const LogInputReset());
    expectMode(reset, at(4), null);
    expectMode(state, at(1), GameMode.pvp);
  });

  test(
    'task finished in the menus publishes one transition with folder mode',
    () {
      final state = _after([
        const SessionFolderChanged(_folder),
        SessionModeChanged(_modeId, _modeTime, GameMode.pvp),
        ProfileSelected(_modeId, _modeTime),
      ]);
      expect(state.phase, RaidPhase.inMenus);
      expect(state.folderMode, GameMode.pvp);

      final (next, published) = reduce(
        state,
        TaskFinished(_taskRecordId, _taskTime, _taskId),
      );

      final task = published.single as TaskTransition;
      expect(task.id, _taskRecordId);
      expect(task.time, _taskTime);
      expect(task.taskId, _taskId);
      expect(task.status, ProgressTaskStatus.finished);
      expect(task.mode, GameMode.pvp);
      expect(next.phase, RaidPhase.inMenus);
      expect(next.raid, same(state.raid));
    },
  );

  test('task before any mode has no mode', () {
    final state = _after([const SessionFolderChanged(_folder)]);
    final (next, published) = reduce(
      state,
      TaskFailed(_taskRecordId, _taskTime, _taskId),
    );

    final task = published.single as TaskTransition;
    expect(task.id, _taskRecordId);
    expect(task.time, _taskTime);
    expect(task.taskId, _taskId);
    expect(task.status, ProgressTaskStatus.failed);
    expect(task.mode, isNull);
    expect(next.folderMode, isNull);
    expect(next.phase, state.phase);
    expect(next.raid, same(state.raid));
  });

  test('folder change clears the task mode', () {
    final before = _after([
      const SessionFolderChanged(_folder),
      SessionModeChanged(_modeId, _modeTime, GameMode.pvp),
    ]);
    expect(before.folderMode, GameMode.pvp);

    final (state, folderTransitions) = reduce(
      before,
      const SessionFolderChanged(_nextFolder),
    );
    expect(folderTransitions, isEmpty);
    expect(state.folderMode, isNull);
    expect(state.sessionMode, GameMode.pvp);

    final (_, fleaTransitions) = reduce(
      state,
      FleaSale(
        const LogRecordId(_nextFolder, LogFile.pushNotifications, 1),
        _taskTime,
        'item-a',
        1,
        100,
      ),
    );
    expect((fleaTransitions.single as FleaSoldTransition).mode, GameMode.pvp);

    const taskId = LogRecordId(_nextFolder, LogFile.pushNotifications, 42);
    final (next, published) = reduce(
      state,
      TaskStarted(taskId, _taskTime, _taskId),
    );
    final task = published.single as TaskTransition;
    expect(task.id, taskId);
    expect(task.time, _taskTime);
    expect(task.taskId, _taskId);
    expect(task.status, ProgressTaskStatus.started);
    expect(task.mode, isNull);
    expect(next.phase, state.phase);
    expect(next.raid, same(state.raid));
  });

  test('unrecognised session mode gives no task mode', () {
    final state = _after([
      const SessionFolderChanged(_folder),
      SessionModeChanged(_modeId, _modeTime, GameMode.pvp),
      SessionModeChanged(_modeId, _modeTime, GameMode.unknown),
    ]);
    expect(state.folderMode, isNull);

    final (_, published) = reduce(
      state,
      TaskFinished(_taskRecordId, _taskTime, _taskId),
    );
    final task = published.single as TaskTransition;
    expect(task.status, ProgressTaskStatus.finished);
    expect(task.mode, isNull);
  });

  test('input reset clears the task mode', () {
    final before = _after([
      const SessionFolderChanged(_folder),
      SessionModeChanged(_modeId, _modeTime, GameMode.pve),
    ]);
    expect(before.folderMode, GameMode.pve);

    final (state, resetTransitions) = reduce(before, const LogInputReset());
    expect(resetTransitions, isEmpty);
    expect(state.folderMode, isNull);
    final (_, published) = reduce(
      state,
      TaskStarted(_taskRecordId, _taskTime, _taskId),
    );
    expect((published.single as TaskTransition).mode, isNull);
  });

  test('all task statuses leave an active raid unchanged', () {
    final state = _after([
      const SessionFolderChanged(_folder),
      SessionModeChanged(_modeId, _modeTime, GameMode.pve),
      RaidStarted(_modeId, _modeTime),
    ]);
    expect(state.phase, RaidPhase.inRaid);
    expect(state.currentRaid, isNotNull);

    final events = <(RecordedGameLogEvent, ProgressTaskStatus)>[
      (
        TaskStarted(_taskRecordId, _taskTime, _taskId),
        ProgressTaskStatus.started,
      ),
      (
        TaskFailed(_taskRecordId, _taskTime, _taskId),
        ProgressTaskStatus.failed,
      ),
      (
        TaskFinished(_taskRecordId, _taskTime, _taskId),
        ProgressTaskStatus.finished,
      ),
    ];
    for (final (event, status) in events) {
      final (next, published) = reduce(state, event);
      final task = published.single as TaskTransition;
      expect(task.id, event.id);
      expect(task.time, event.time);
      expect(task.taskId, _taskId);
      expect(task.status, status);
      expect(task.mode, GameMode.pve);
      expect(next.phase, state.phase);
      expect(next.raid, same(state.raid));
      expect(next.currentRaid, same(state.currentRaid));
    }
  });
}
