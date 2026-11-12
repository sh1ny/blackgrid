import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/domain/task_log_events.dart';
import 'package:test/test.dart';

const _id = LogRecordId(
  'log_2026.11.12_18-02-11_1.3.0.0.48484',
  LogFile.pushNotifications,
  12345,
);

void main() {
  test('task finished maps to log-sourced finished event with UTC time', () {
    final localTime = DateTime(2026, 11, 12, 18, 40, 0, 125);
    final event = taskLogEvent(
      transition: TaskTransition(
        _id,
        localTime,
        '5936d90786f7742b1420ba5b',
        ProgressTaskStatus.finished,
        GameMode.pvp,
      ),
      cycleId: 'cycle-123',
      deviceId: 'device-456',
    );
    expect(event, isNotNull);
    expect(
      event!.eventId,
      'log1|cycle-123|log_2026.11.12_18-02-11_1.3.0.0.48484|pushNotifications|12345',
    );
    expect(event.deviceId, 'device-456');
    expect(
      event.scope,
      const ProgressScope(mode: GameMode.pvp, cycleId: 'cycle-123'),
    );
    expect(event.source, ProgressSource.log);
    expect(event.occurredAtMs, localTime.toUtc().millisecondsSinceEpoch);
    expect(
      event.target,
      const ProgressTarget(
        kind: ProgressEntityKind.task,
        id: '5936d90786f7742b1420ba5b',
        field: ProgressField.state,
      ),
    );
    expect(event.value, const ProgressTaskState(ProgressTaskStatus.finished));
    expect(event.formatVersion, 1);
    expect(event.undoOf, isNull);
  });

  test('task ID is kept without catalog lookup', () {
    final event = taskLogEvent(
      transition: TaskTransition(
        _id,
        DateTime(2026, 11, 12),
        'unknown-future-task',
        ProgressTaskStatus.started,
        GameMode.pve,
      ),
      cycleId: 'cycle',
      deviceId: 'device',
    );
    expect(event, isNotNull);
    expect(event!.scope.mode, GameMode.pve);
    expect(event.target.id, 'unknown-future-task');
    expect(event.value, const ProgressTaskState(ProgressTaskStatus.started));
  });

  test('all task statuses are preserved in their events', () {
    for (final status in ProgressTaskStatus.values) {
      final event = taskLogEvent(
        transition: TaskTransition(
          _id,
          DateTime(2026),
          'task',
          status,
          GameMode.seasonal,
        ),
        cycleId: 'cycle',
        deviceId: 'device',
      );
      expect(event, isNotNull, reason: status.name);
      expect(event!.value, ProgressTaskState(status), reason: status.name);
      expect(event.scope.mode, GameMode.seasonal);
    }
  });

  test('transition without a known mode cannot produce an event', () {
    for (final mode in <GameMode?>[null, GameMode.unknown]) {
      expect(
        taskLogEvent(
          transition: TaskTransition(
            _id,
            DateTime(2026),
            'task',
            ProgressTaskStatus.started,
            mode,
          ),
          cycleId: 'cycle',
          deviceId: 'device',
        ),
        isNull,
      );
    }
  });

  test('derived event identity over the UTF-8 budget is rejected', () {
    final longId = LogRecordId('é' * 140, LogFile.pushNotifications, 1);
    expect(
      taskLogEvent(
        transition: TaskTransition(
          longId,
          DateTime(2026),
          'task',
          ProgressTaskStatus.failed,
          GameMode.pvp,
        ),
        cycleId: 'cycle',
        deviceId: 'device',
      ),
      isNull,
    );
    final valid = taskLogEvent(
      transition: TaskTransition(
        _id,
        DateTime(2026),
        'task',
        ProgressTaskStatus.failed,
        GameMode.pvp,
      ),
      cycleId: 'cycle',
      deviceId: 'device',
    );
    expect(valid, isNotNull);
    expect(valid!.value, const ProgressTaskState(ProgressTaskStatus.failed));
  });
}
