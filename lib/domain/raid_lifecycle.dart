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

/// Where the player is in the matchmaking and raid cycle.
///
/// Whether a client restart interrupted the current raid is a flag on
/// [Raid.interrupted], not a phase.
enum RaidPhase {
  /// Nothing has been read yet.
  unknown,

  /// The player is in the menus.
  inMenus,

  /// The player entered the matchmaking queue.
  inQueue,

  /// Matchmaking found a raid.
  matchFound,

  /// The game is starting the raid, or rejoining one.
  raidStarting,

  /// The raid is under way.
  inRaid,

  /// The raid ended; the player has not reached the menus yet.
  raidEnded,
}

/// How the player came to enter a raid.
enum RaidEntry {
  /// Through the matchmaking queue.
  queue,

  /// A rejoin right after the previous raid ended, in the same session.
  transit,

  /// A rejoin that follows a client restart, a queue or an unknown history.
  reconnect,

  /// The raid started with no queue and no rejoin in the log.
  noQueue,
}

/// Why a raid ended.
enum RaidEndCause {
  /// The backend reported the raid result.
  raidExit,

  /// The player was back in the menus (profile selected) first.
  menus,

  /// The client restarted and the player queued for a new raid.
  clientRestart,
}

/// One raid as the log tells it.
final class Raid {
  /// Creates a raid record.
  const Raid({
    required this.mapId,
    required this.mode,
    required this.queueTime,
    required this.startTime,
    required this.startId,
    required this.entry,
    this.endTime,
    this.endCause,
    this.interrupted = false,
  });

  /// The settings map ID, or `null` when the map is unknown.
  final String? mapId;

  /// The last session mode logged before the raid, or `null` if none.
  final GameMode? mode;

  /// When the queue was entered; `null` unless [entry] is [RaidEntry.queue].
  final DateTime? queueTime;

  /// When the raid started.
  ///
  /// A raid entered by a rejoin starts at the rejoin record (see [startId]).
  final DateTime startTime;

  /// The record that started the raid.
  ///
  /// This is the raid-started record, except for raids entered by a rejoin
  /// (transit or reconnect), which carry the raid-rejoined record.
  final LogRecordId startId;

  /// How the player entered the raid.
  final RaidEntry entry;

  /// When the raid ended, or `null` while it is current.
  final DateTime? endTime;

  /// Why the raid ended, or `null` while it is current.
  final RaidEndCause? endCause;

  /// Whether a client restart interrupted the raid and it has not resumed.
  final bool interrupted;

  /// Whether the raid has not ended.
  bool get isCurrent => endTime == null;

  /// Returns a copy ended at [time] for [cause].
  Raid ended(DateTime time, RaidEndCause cause) => Raid(
    mapId: mapId,
    mode: mode,
    queueTime: queueTime,
    startTime: startTime,
    startId: startId,
    entry: entry,
    endTime: time,
    endCause: cause,
    interrupted: interrupted,
  );

  /// Returns a copy with [interrupted] set to [value].
  Raid withInterrupted({required bool value}) => Raid(
    mapId: mapId,
    mode: mode,
    queueTime: queueTime,
    startTime: startTime,
    startId: startId,
    entry: entry,
    endTime: endTime,
    endCause: endCause,
    interrupted: value,
  );
}

/// A lifecycle change the reducer publishes exactly once.
sealed class RaidTransition {
  const RaidTransition(this.id, this.time);

  /// The record that caused the transition.
  final LogRecordId id;

  /// The log time of that record, or of the profile selection that ended a
  /// raid by client restart.
  final DateTime time;
}

/// A raid started.
final class RaidStartedTransition extends RaidTransition {
  /// Creates the transition for [raid].
  const RaidStartedTransition(super.id, super.time, this.raid);

  /// The raid that started.
  final Raid raid;
}

/// A raid ended.
final class RaidEndedTransition extends RaidTransition {
  /// Creates the transition for [raid], which carries its end time and cause.
  const RaidEndedTransition(super.id, super.time, this.raid);

  /// The raid that ended.
  final Raid raid;

  /// Why it ended.
  RaidEndCause get cause => raid.endCause!;
}

/// A queue ended without a raid.
final class MatchingAbortedTransition extends RaidTransition {
  /// Creates the transition.
  const MatchingAbortedTransition(super.id, super.time);
}

const _keep = Object();

/// The immutable state [reduce] folds log events into.
final class RaidLifecycleState {
  /// Creates a state; the fields beyond [phase] and [raid] are reducer
  /// bookkeeping.
  const RaidLifecycleState({
    required this.phase,
    this.raid,
    this.lastQueueAborted = false,
    this.currentFolder,
    this.transitPossible = false,
    this.sessionMode,
    this.guardTime,
    this.queueEnteredTime,
    this.pendingMapId,
    this.pendingEntry,
    this.pendingStart,
    this.restartProfile,
  });

  /// The state before any event: phase unknown, no raid.
  static const initial = RaidLifecycleState(phase: RaidPhase.unknown);

  /// The current phase.
  final RaidPhase phase;

  /// The current raid, or the last one once it has ended.
  final Raid? raid;

  /// Whether the last queue ended without a raid.
  final bool lastQueueAborted;

  /// The session folder being read, or `null` before the first folder.
  final String? currentFolder;

  /// Whether a rejoin now would be a transit.
  final bool transitPossible;

  /// The last session mode logged, remembered for the next raid.
  final GameMode? sessionMode;

  /// The queue or rejoin time; a raid exit or profile selection logged
  /// before it ends nothing.
  final DateTime? guardTime;

  /// When the queue for the raid being set up was entered.
  final DateTime? queueEnteredTime;

  /// The map of the raid being set up (last scene or rejoin location).
  final String? pendingMapId;

  /// The entry of the raid being set up, or `null` if no queue or rejoin.
  final RaidEntry? pendingEntry;

  /// The rejoin record of the raid being set up, when a rejoin entered it.
  final ({LogRecordId id, DateTime time})? pendingStart;

  /// The first profile selection after a restart interrupted the raid.
  final ({LogRecordId id, DateTime time})? restartProfile;

  /// The raid that has not ended, or `null`.
  Raid? get currentRaid => switch (raid) {
    final Raid r when r.isCurrent => r,
    _ => null,
  };

  /// Returns a copy; pass `null` to clear a nullable field.
  RaidLifecycleState copyWith({
    RaidPhase? phase,
    Object? raid = _keep,
    bool? lastQueueAborted,
    Object? currentFolder = _keep,
    bool? transitPossible,
    Object? sessionMode = _keep,
    Object? guardTime = _keep,
    Object? queueEnteredTime = _keep,
    Object? pendingMapId = _keep,
    Object? pendingEntry = _keep,
    Object? pendingStart = _keep,
    Object? restartProfile = _keep,
  }) => RaidLifecycleState(
    phase: phase ?? this.phase,
    raid: identical(raid, _keep) ? this.raid : raid as Raid?,
    lastQueueAborted: lastQueueAborted ?? this.lastQueueAborted,
    currentFolder: identical(currentFolder, _keep)
        ? this.currentFolder
        : currentFolder as String?,
    transitPossible: transitPossible ?? this.transitPossible,
    sessionMode: identical(sessionMode, _keep)
        ? this.sessionMode
        : sessionMode as GameMode?,
    guardTime: identical(guardTime, _keep)
        ? this.guardTime
        : guardTime as DateTime?,
    queueEnteredTime: identical(queueEnteredTime, _keep)
        ? this.queueEnteredTime
        : queueEnteredTime as DateTime?,
    pendingMapId: identical(pendingMapId, _keep)
        ? this.pendingMapId
        : pendingMapId as String?,
    pendingEntry: identical(pendingEntry, _keep)
        ? this.pendingEntry
        : pendingEntry as RaidEntry?,
    pendingStart: identical(pendingStart, _keep)
        ? this.pendingStart
        : pendingStart as ({LogRecordId id, DateTime time})?,
    restartProfile: identical(restartProfile, _keep)
        ? this.restartProfile
        : restartProfile as ({LogRecordId id, DateTime time})?,
  );
}

/// The result of one [reduce] step: the next state and what it published.
typedef RaidReduction = (RaidLifecycleState, List<RaidTransition>);

/// Folds one [event] into [state].
///
/// Pure. Returns the next state and the transitions the event published, each
/// published once. Events must arrive in log-time order; a raid exit or
/// profile selection logged before the current queue or rejoin time ends
/// nothing, and the first ending of a raid wins. A new folder's first profile
/// selection is the exception that does not end an interrupted raid: it waits
/// for the next queue, which ends the raid by client restart.
///
/// A raid entered by a rejoin (transit or reconnect) is published with the
/// raid-rejoined record's identity and time, not the raid-started record's.
RaidReduction reduce(
  RaidLifecycleState state,
  GameLogEvent event,
) => switch (event) {
  LogInputReset() => (RaidLifecycleState.initial, const []),
  final SessionFolderChanged e => _folderChanged(state, e),
  final SessionModeChanged e => (state.copyWith(sessionMode: e.mode), const []),
  final ProfileSelected e => _profileSelected(state, e),
  final QueueEntered e => _queueEntered(state, e),
  final SceneLoaded e => _sceneLoaded(state, e),
  MatchFound() => (state.copyWith(phase: RaidPhase.matchFound), const []),
  RaidStarting() => (state.copyWith(phase: RaidPhase.raidStarting), const []),
  final RaidStarted e => _raidStarted(state, e),
  final MatchingAborted e => _matchingAborted(state, e),
  final RaidRejoined e => _raidRejoined(state, e),
  final RaidExit e => _raidExit(state, e),
  FleaSale() ||
  TaskStarted() ||
  TaskFailed() ||
  TaskFinished() => (state, const []),
};

bool _isLoading(RaidPhase phase) => switch (phase) {
  RaidPhase.inQueue || RaidPhase.matchFound || RaidPhase.raidStarting => true,
  RaidPhase.unknown ||
  RaidPhase.inMenus ||
  RaidPhase.inRaid ||
  RaidPhase.raidEnded => false,
};

bool _beforeGuard(RaidLifecycleState state, DateTime time) =>
    state.guardTime != null && time.isBefore(state.guardTime!);

RaidReduction _folderChanged(RaidLifecycleState state, SessionFolderChanged e) {
  final raid = state.currentRaid;
  return (
    state.copyWith(
      currentFolder: e.folder,
      transitPossible: false,
      restartProfile: null,
      raid: raid == null ? state.raid : raid.withInterrupted(value: true),
    ),
    const [],
  );
}

RaidReduction _endRaid(
  RaidLifecycleState state,
  Raid raid,
  LogRecordId id,
  DateTime time,
  RaidEndCause cause, {
  required RaidPhase phase,
  required bool transitPossible,
}) {
  final ended = raid.ended(time, cause);
  return (
    state.copyWith(
      phase: phase,
      raid: ended,
      transitPossible: transitPossible,
      restartProfile: null,
      pendingEntry: null,
      pendingMapId: null,
      pendingStart: null,
    ),
    [RaidEndedTransition(id, time, ended)],
  );
}

RaidReduction _abortQueue(
  RaidLifecycleState state,
  LogRecordId id,
  DateTime time,
) => (
  state.copyWith(
    phase: RaidPhase.inMenus,
    lastQueueAborted: true,
    transitPossible: false,
    pendingEntry: null,
    pendingMapId: null,
    pendingStart: null,
  ),
  [MatchingAbortedTransition(id, time)],
);

RaidReduction _profileSelected(RaidLifecycleState state, ProfileSelected e) {
  if (_beforeGuard(state, e.time)) return (state, const []);
  final raid = state.currentRaid;
  if (raid != null && raid.interrupted) {
    // First profile selection of the new folder: back in the menus, but the
    // raid may still be rejoined, so it does not end yet.
    return (
      state.copyWith(
        phase: RaidPhase.inMenus,
        restartProfile: state.restartProfile ?? (id: e.id, time: e.time),
      ),
      const [],
    );
  }
  if (raid != null) {
    return _endRaid(
      state,
      raid,
      e.id,
      e.time,
      RaidEndCause.menus,
      phase: RaidPhase.inMenus,
      transitPossible: true,
    );
  }
  if (_isLoading(state.phase)) return _abortQueue(state, e.id, e.time);
  return (state.copyWith(phase: RaidPhase.inMenus), const []);
}

RaidReduction _raidExit(RaidLifecycleState state, RaidExit e) {
  if (_beforeGuard(state, e.time)) return (state, const []);
  final raid = state.currentRaid;
  if (raid != null) {
    return _endRaid(
      state,
      raid,
      e.id,
      e.time,
      RaidEndCause.raidExit,
      phase: RaidPhase.raidEnded,
      transitPossible: true,
    );
  }
  if (_isLoading(state.phase)) return _abortQueue(state, e.id, e.time);
  return (state, const []);
}

RaidReduction _matchingAborted(RaidLifecycleState state, MatchingAborted e) =>
    _isLoading(state.phase) && state.currentRaid == null
    ? _abortQueue(state, e.id, e.time)
    : (state, const []);

RaidReduction _queueEntered(RaidLifecycleState state, QueueEntered e) {
  var base = state;
  final transitions = <RaidTransition>[];
  final raid = state.currentRaid;
  final restart = state.restartProfile;
  if (raid != null && raid.interrupted && restart != null) {
    final (ended, published) = _endRaid(
      state,
      raid,
      restart.id,
      restart.time,
      RaidEndCause.clientRestart,
      phase: state.phase,
      transitPossible: false,
    );
    base = ended;
    transitions.addAll(published);
  }
  return (
    base.copyWith(
      phase: RaidPhase.inQueue,
      lastQueueAborted: false,
      transitPossible: false,
      guardTime: e.time,
      queueEnteredTime: e.time,
      pendingMapId: null,
      pendingEntry: RaidEntry.queue,
      pendingStart: null,
    ),
    transitions,
  );
}

RaidReduction _sceneLoaded(RaidLifecycleState state, SceneLoaded e) =>
    _isLoading(state.phase)
    ? (state.copyWith(pendingMapId: e.mapId), const [])
    : (state, const []);

RaidReduction _raidRejoined(RaidLifecycleState state, RaidRejoined e) {
  final raid = state.currentRaid;
  if (raid != null && raid.interrupted) {
    // Continue the interrupted raid; nothing new starts.
    return (
      state.copyWith(
        phase: RaidPhase.raidStarting,
        guardTime: e.time,
        restartProfile: null,
      ),
      const [],
    );
  }
  return (
    state.copyWith(
      phase: RaidPhase.raidStarting,
      guardTime: e.time,
      pendingMapId: e.mapId,
      pendingEntry: state.transitPossible
          ? RaidEntry.transit
          : RaidEntry.reconnect,
      pendingStart: (id: e.id, time: e.time),
      transitPossible: false,
    ),
    const [],
  );
}

RaidReduction _raidStarted(RaidLifecycleState state, RaidStarted e) {
  if (state.phase == RaidPhase.inRaid) return (state, const []);
  final current = state.currentRaid;
  if (current != null && current.interrupted) {
    return (
      state.copyWith(
        phase: RaidPhase.inRaid,
        raid: current.withInterrupted(value: false),
        restartProfile: null,
      ),
      const [],
    );
  }
  final entry = state.pendingEntry ?? RaidEntry.noQueue;
  final start = state.pendingStart ?? (id: e.id, time: e.time);
  final raid = Raid(
    mapId: state.pendingMapId,
    mode: state.sessionMode,
    queueTime: entry == RaidEntry.queue ? state.queueEnteredTime : null,
    startTime: start.time,
    startId: start.id,
    entry: entry,
  );
  return (
    state.copyWith(
      phase: RaidPhase.inRaid,
      raid: raid,
      transitPossible: false,
      restartProfile: null,
      pendingMapId: null,
      pendingEntry: null,
      pendingStart: null,
    ),
    [RaidStartedTransition(start.id, start.time, raid)],
  );
}
