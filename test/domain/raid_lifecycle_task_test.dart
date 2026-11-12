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
