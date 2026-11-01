import 'catalog.dart';

/// The three EFT log files the raid lifecycle reads from a session folder.
enum LogFile {
  /// The `application` log; carries game-start, scene and session lines.
  application,

  /// The `backend` log; carries matchmaking and raid-settings lines.
  backend,

  /// The `push-notifications` log; carries multi-line notification records.
  pushNotifications,
}

/// Identity of one log record: the session folder, the file and the byte
/// offset of the record's header line.
final class LogRecordId {
  /// Creates the identity of the record at [offset] of [file] in [folder].
  const LogRecordId(this.folder, this.file, this.offset);

  /// Name of the session folder, for example `log_2026.10.28_19-40-00_1.2.5.0.48146`.
  final String folder;

  /// Which log file of the folder holds the record.
  final LogFile file;

  /// Absolute byte offset of the record's header line.
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is LogRecordId &&
      other.folder == folder &&
      other.file == file &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(folder, file, offset);

  @override
  String toString() => 'LogRecordId($folder, ${file.name}, $offset)';
}

final _logTime = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\.(\d{3})\|',
);

/// Parses the `YYYY-MM-DD HH:MM:SS.mmm|` prefix of a log header line.
///
/// Returns the instant as a local [DateTime], or `null` when [line] has no
/// such prefix or the prefix is not a real calendar time.
DateTime? parseLogTime(String line) {
  final match = _logTime.firstMatch(line);
  if (match == null) return null;
  final [year, month, day, hour, minute, second, millisecond] = [
    for (var i = 1; i <= 7; ++i) int.parse(match[i]!),
  ];
  final time = DateTime(year, month, day, hour, minute, second, millisecond);
  if (time.year != year ||
      time.month != month ||
      time.day != day ||
      time.hour != hour ||
      time.minute != minute ||
      time.second != second) {
    return null;
  }
  return time;
}

/// One thing the game logs said, in the form the raid reducer consumes.
sealed class GameLogEvent {
  const GameLogEvent();
}

/// A [GameLogEvent] read from one log record.
sealed class RecordedGameLogEvent extends GameLogEvent {
  const RecordedGameLogEvent(this.id, this.time);

  /// The record the event was read from.
  final LogRecordId id;

  /// The record's log time, in local time.
  final DateTime time;
}

/// The application log named the session mode.
final class SessionModeChanged extends RecordedGameLogEvent {
  /// Creates the event for [mode].
  const SessionModeChanged(super.id, super.time, this.mode);

  /// The mode; `PvpSeason` is [GameMode.seasonal].
  final GameMode mode;
}

/// The player's profile was selected for a session.
final class ProfileSelected extends RecordedGameLogEvent {
  /// Creates the event.
  const ProfileSelected(super.id, super.time);
}

/// The player entered the matchmaking queue.
final class QueueEntered extends RecordedGameLogEvent {
  /// Creates the event.
  const QueueEntered(super.id, super.time);
}

/// A map scene preset started loading.
final class SceneLoaded extends RecordedGameLogEvent {
  /// Creates the event for the scene mapped to [mapId].
  const SceneLoaded(super.id, super.time, this.mapId);

  /// The settings map ID, or `null` when the scene is not a supported map.
  final String? mapId;
}

/// Matchmaking found a raid.
final class MatchFound extends RecordedGameLogEvent {
  /// Creates the event.
  const MatchFound(super.id, super.time);
}

/// The game began starting the raid.
final class RaidStarting extends RecordedGameLogEvent {
  /// Creates the event.
  const RaidStarting(super.id, super.time);
}

/// The raid started.
final class RaidStarted extends RecordedGameLogEvent {
  /// Creates the event.
  const RaidStarted(super.id, super.time);
}

/// Matchmaking was cancelled before a raid started.
final class MatchingAborted extends RecordedGameLogEvent {
  /// Creates the event.
  const MatchingAborted(super.id, super.time);
}

/// The client reconnected into a raid in progress.
final class RaidRejoined extends RecordedGameLogEvent {
  /// Creates the event.
  const RaidRejoined(
    super.id,
    super.time,
    this.status,
    this.location,
    this.mapId,
  );

  /// The transit status text, for example `MatchWait`.
  final String status;

  /// The raw location name from the log, for example `bigmap`.
  final String location;

  /// The settings map ID of [location], or `null` when it is not a known map.
  final String? mapId;
}

/// The backend log reported the raid result (`userMatchOver`).
final class RaidExit extends RecordedGameLogEvent {
  /// Creates the event.
  const RaidExit(super.id, super.time);
}

/// A flea market sale notification.
final class FleaSale extends RecordedGameLogEvent {
  /// Creates the event.
  const FleaSale(super.id, super.time, this.itemId, this.count, this.roubles);

  /// The sold item's template ID.
  final String itemId;

  /// How many of the item sold.
  final int count;

  /// The rouble payout, or `null` when the sale paid in another currency.
  final int? roubles;
}

/// A quest was started.
final class TaskStarted extends RecordedGameLogEvent {
  /// Creates the event for [taskId].
  const TaskStarted(super.id, super.time, this.taskId);

  /// The quest's task ID.
  final String taskId;
}

/// A quest failed.
final class TaskFailed extends RecordedGameLogEvent {
  /// Creates the event for [taskId].
  const TaskFailed(super.id, super.time, this.taskId);

  /// The quest's task ID.
  final String taskId;
}

/// A quest was completed.
final class TaskFinished extends RecordedGameLogEvent {
  /// Creates the event for [taskId].
  const TaskFinished(super.id, super.time, this.taskId);

  /// The quest's task ID.
  final String taskId;
}

/// The reader moved to another session folder.
///
/// Emitted by the log reader, never by the record parsers. Later records in
/// the stream belong to [folder].
final class SessionFolderChanged extends GameLogEvent {
  /// Creates the event for [folder], whose start time is [time] when known.
  const SessionFolderChanged(this.folder, [this.time]);

  /// Name of the new session folder.
  final String folder;

  /// The start time encoded in the folder name, or `null` if unparsable.
  final DateTime? time;
}

/// The reader discarded its input position and will replay the folder.
///
/// Emitted by the log reader, never by the record parsers, when a log file was
/// replaced or rewritten. The reducer drops state derived from the old bytes.
final class LogInputReset extends GameLogEvent {
  /// Creates the event.
  const LogInputReset();
}
