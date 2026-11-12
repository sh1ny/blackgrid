import 'catalog.dart';
import 'local_progress.dart';
import 'raid_lifecycle.dart';

/// Maps a task observation to a durable log event, or `null` if its mode or identity is invalid.
ProgressEvent? taskLogEvent({
  required TaskTransition transition,
  required String cycleId,
  required String deviceId,
}) {
  final mode = transition.mode;
  if (mode == null || mode == GameMode.unknown) return null;

  final id = transition.id;
  final eventId = 'log1|$cycleId|${id.folder}|pushNotifications|${id.offset}';
  try {
    ProgressEventCodec.validateIdentity(eventId);
    ProgressEventCodec.validateIdentity(cycleId);
    ProgressEventCodec.validateIdentity(deviceId);
    ProgressEventCodec.validateIdentity(transition.taskId);
  } on FormatException {
    return null;
  }
  return ProgressEvent(
    eventId: eventId,
    deviceId: deviceId,
    occurredAtMs: transition.time.millisecondsSinceEpoch,
    scope: ProgressScope(mode: mode, cycleId: cycleId),
    source: ProgressSource.log,
    target: ProgressTarget(
      kind: ProgressEntityKind.task,
      id: transition.taskId,
      field: ProgressField.state,
    ),
    value: ProgressTaskState(transition.status),
  );
}
