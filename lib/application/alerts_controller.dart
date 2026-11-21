import 'dart:async';
import 'dart:collection';

import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:flutter/foundation.dart';

import '../domain/alert_rules.dart';
import '../domain/alerts.dart';
import '../domain/catalog.dart';
import '../domain/local_progress.dart';
import '../domain/progress_facts.dart';
import '../domain/raid_timers.dart';
import '../domain/raid_lifecycle.dart';
import '../domain/settings.dart';
import 'audio_port.dart';
import 'raid_timers_controller.dart';

/// What [AlertsController] reads from and writes to the settings.
///
/// `SettingsController` is the real source.
abstract interface class AlertSettingsSource implements Listenable {
  /// The alert preferences.
  AlertSettings get alerts;

  /// The timer settings, which set the run-through length.
  RaidTimerSettings get raidTimers;

  /// The scav cooldown starts in effect, including starts not yet saved.
  Map<GameMode, DateTime> get effectiveScavCooldownStarts;

  /// Saves [sound] for [kind].
  ///
  /// Returns a message when the sound is refused or the save fails, and `null`
  /// when it was saved.
  Future<String?> setAlertSound(AlertKind kind, AlertSound sound);
}

/// Creates a one-shot timer; [Timer.new] is the real one.
typedef AlertTimerFactory = Timer Function(Duration, void Function());

/// The longest an alert may wait before it starts playing.
const alertMaxWait = Duration(seconds: 15);

/// How many alerts may wait behind the one playing.
const alertMaxWaiting = 8;

/// How long Dart waits for a `speak` call before it stops it.
const speakBackstop = Duration(seconds: 30);

/// How long Dart waits for a `playFile` call before it stops it.
const playFileBackstop = Duration(seconds: 125);

/// The line the voice preview speaks.
const voicePreviewLine = 'This is how your alerts will sound.';

/// How many transition identities are remembered as fired.
const _maxFiredTransitions = 256;

/// How many run-through raids and scav starts are remembered as seen.
const _maxSeenDeadlines = 16;

/// One alert waiting for, or taking, its turn to play.
final class _QueuedAlert {
  const _QueuedAlert({
    required this.kind,
    required this.firedAt,
    required this.forced,
  });

  /// The alert, or `null` for the voice preview.
  final AlertKind? kind;

  /// The clock reading when it fired.
  final DateTime firedAt;

  /// Whether it plays whatever the alert's switch says (a test or preview).
  final bool forced;
}

/// A moment a timer alert fires when the clock passes it.
final class _Deadline {
  const _Deadline(this.kind, this.key, this.at);

  /// The alert it fires.
  final AlertKind kind;

  /// What makes it one-shot: the raid, or the mode and cooldown start.
  final Object key;

  /// When it falls due.
  final DateTime at;
}

/// Decides when alerts fire and plays them one at a time.
///
/// Reads the raid lifecycle, settings, catalog and progress; speaks through an
/// [AudioPort]. Every fired alert joins one FIFO queue: one plays at a time,
/// at most [alertMaxWaiting] wait, and one that waited more than
/// [alertMaxWait] is dropped when its turn comes. A failed play never stops
/// the queue; the failure is kept in [lastFailure] until a later alert plays.
class AlertsController extends ChangeNotifier {
  /// Starts listening to the sources.
  ///
  /// [clock] supplies the current time and [timerFactory] creates the
  /// one-shot timers, so tests can drive both. [questObjectives] returns the
  /// quest objectives the Map shows for a settings map ID, or `null` when no
  /// map pack is loaded. Subscribes to [lifecycle]'s transitions here, so a
  /// controller built before the log reader binds sees the replay.
  AlertsController({
    required this._lifecycle,
    required this._settings,
    required this._catalog,
    required this._progress,
    required this._audio,
    required this._clock,
    required this._questObjectives,
    this._timerFactory = Timer.new,
  }) {
    _subscription = _lifecycle.transitions.listen(_onTransition);
    _lifecycle.addListener(_onLifecycleBatch);
    for (final source in _sources) {
      source.addListener(_onSourceChanged);
    }
    _plan();
  }

  final RaidTimerLifecycleSource _lifecycle;
  final AlertSettingsSource _settings;
  final RaidTimerCatalogSource _catalog;
  final RaidTimerProgressSource _progress;
  final AudioPort _audio;
  final DateTime Function() _clock;
  final Iterable<QuestObjectiveRef>? Function(String mapId) _questObjectives;
  final AlertTimerFactory _timerFactory;
  late final StreamSubscription<RaidTransition> _subscription;
  bool _disposed = false;

  final Set<(AlertKind, LogRecordId)> _firedTransitions = {};
  final Set<Object> _seenRunThroughs = {};
  final Set<Object> _seenScavStarts = {};
  Map<(AlertKind, Object), DateTime> _armed = {};
  Timer? _deadlineTimer;
  LogRecordId? _queueId;
  bool _questPlayed = false;
  LogRecordId? _questPlayedQueueId;
  bool _questWaiting = false;
  String? _questMapId;
  bool _failedPending = false;

  /// Counts lifecycle batches: the lifecycle notifies once per batch, before
  /// it publishes the batch's transitions.
  int _lifecycleBatch = 0;

  /// The batch whose transitions released the failed tasks reminder.
  int? _failedReleasedBatch;
  final Queue<_QueuedAlert> _waiting = Queue();
  bool _playing = false;
  Completer<AudioResult>? _pendingPlayback;

  final Map<AlertKind, ({String path, String message})> _fileProblems = {};
  String? _lastFailure;
  String? _missingVoice;

  /// The saved voice that last spoke, evidence newer than [_voices] that it
  /// is installed.
  String? _spokenVoice;
  List<AudioVoice> _voices = const [];
  bool _voicesUnavailable = false;
  bool _voicesRead = false;

  List<Listenable> get _sources => [_lifecycle, _settings, _catalog, _progress];

  /// The installed voices, empty when the list is unavailable.
  ///
  /// The Alerts section lists "Windows default" first, then these.
  List<AudioVoice> get voices => _voices;

  /// Whether the voice list could not be read or is empty.
  bool get voicesUnavailable => _voicesUnavailable;

  /// The last playback failure in plain words, or `null`.
  ///
  /// Cleared when a later alert plays successfully.
  String? get lastFailure => _lastFailure;

  /// The problem under [kind]'s row, or `null`.
  ///
  /// Set when [kind]'s sound file could not be played and its line was spoken
  /// instead; cleared when that file next plays, or when the sound changes.
  String? rowProblem(AlertKind kind) {
    final problem = _fileProblems[kind];
    if (problem == null) return null;
    return switch (_settings.alerts.itemFor(kind).sound) {
      FileSound(:final path) when path == problem.path => problem.message,
      _ => null,
    };
  }

  /// What the voice row says about the saved voice, or `null`.
  ///
  /// Set when the saved voice is not installed: a speak call failed with
  /// voice missing, or the voice list was read and lacks it and the voice has
  /// not spoken since.
  String? get voiceNote {
    final saved = _settings.alerts.voice;
    if (saved == null) return null;
    final missing =
        _missingVoice == saved ||
        (_voicesRead &&
            !_voicesUnavailable &&
            _spokenVoice != saved &&
            !_voices.any((voice) => voice.id == saved));
    return missing
        ? 'The saved voice is not installed. '
              'Spoken alerts use the Windows default voice.'
        : null;
  }

  /// What the Alerts section says about the air filter reminders, or `null`.
  ///
  /// Set while an air filter alert is on and the local progress, or the
  /// station it needs, is unavailable.
  String? get airFilterNote {
    final alerts = _settings.alerts;
    final on =
        alerts.itemFor(AlertKind.airFilterOn).on ||
        alerts.itemFor(AlertKind.airFilterOff).on;
    if (!on || _airFilter() != AirFilterStatus.unavailable) return null;
    return 'The air filter reminders wait for local progress.';
  }

  /// What the Alerts section says about the quest items reminder, or `null`.
  ///
  /// Set while the alert is on and the last queued map could not be checked
  /// for want of map, quest or progress data.
  String? get questItemsNote =>
      _questWaiting && _settings.alerts.itemFor(AlertKind.questItems).on
      ? 'The quest items reminder waits for map, quest or progress data.'
      : null;

  /// Plays [kind]'s sound with the current voice, speed and volume, whether
  /// the alert is on or off.
  ///
  /// Waits in the same queue as every alert.
  void test(AlertKind kind) =>
      _enqueue(_QueuedAlert(kind: kind, firedAt: _clock(), forced: true));

  /// Speaks a sample line with the current voice, speed and volume.
  ///
  /// Waits in the same queue as every alert.
  void previewVoice() =>
      _enqueue(_QueuedAlert(kind: null, firedAt: _clock(), forced: true));

  /// Reads the installed voices again.
  ///
  /// A failed read or an empty list leaves [voices] empty and sets
  /// [voicesUnavailable].
  Future<void> refreshVoices() async {
    List<AudioVoice> read;
    try {
      read = await _audio.voices();
    } on Object {
      read = const [];
    }
    if (_disposed) return;
    _voices = List.unmodifiable(read);
    if (read.any((voice) => voice.id == _missingVoice)) _missingVoice = null;
    _spokenVoice = null;
    _voicesUnavailable = read.isEmpty;
    _voicesRead = true;
    notifyListeners();
  }

  /// Opens the Windows speech settings, where more voices can be added.
  Future<void> openVoiceSettings() async {
    try {
      await _audio.openVoiceSettings();
    } on Object {
      // Nothing to show: the player can open Windows settings by hand.
    }
  }

  /// Lets the player choose a sound file for [kind] in the Windows dialog.
  ///
  /// Returns `null` when the file was saved or the player cancelled, and a
  /// message when the settings refused the file or the dialog failed; the
  /// previous sound is kept either way.
  Future<String?> pickSoundFile(AlertKind kind) async {
    final String? path;
    try {
      path = await _audio.pickSoundFile();
    } on Object {
      return 'The file dialog could not be opened.';
    }
    if (path == null || _disposed) return null;
    return _settings.setAlertSound(kind, FileSound(path));
  }

  // ---- Firing -----------------------------------------------------------

  void _onTransition(RaidTransition transition) {
    if (_disposed) return;
    switch (transition) {
      case MatchFoundTransition():
        _guardRule(
          AlertKind.matchFound,
          () => _fireFromLog(AlertKind.matchFound, transition),
        );
      case RaidStartingTransition():
        _guardRule(
          AlertKind.raidStarting,
          () => _fireFromLog(AlertKind.raidStarting, transition),
        );
      case QueueEnteredTransition():
        _queueId = transition.id;
        _guardRule(AlertKind.airFilterOn, () {
          if (_airFilter() != AirFilterStatus.built) return;
          _fireFromLog(AlertKind.airFilterOn, transition);
        });
      case RaidEndedTransition(:final cause):
        if (cause == RaidEndCause.clientRestart) return;
        _guardRule(AlertKind.airFilterOff, () {
          if (_airFilter() != AirFilterStatus.built) return;
          _fireFromLog(AlertKind.airFilterOff, transition);
        });
      case MapKnownTransition(:final mapId):
        _guardRule(AlertKind.questItems, () => _questItems(transition, mapId));
      case TaskTransition(status: ProgressTaskStatus.failed, :final taskId):
        _guardRule(
          AlertKind.failedTasks,
          () => _taskFailed(transition, taskId),
        );
      case RaidStartedTransition(:final raid)
          when raid.entry == RaidEntry.queue && raid.raidStartingTime == null:
        // No countdown was logged for this queued raid: the raid starting line
        // plays when the raid starts instead.
        _guardRule(
          AlertKind.raidStarting,
          () => _fireFromLog(AlertKind.raidStarting, transition),
        );
      case TaskTransition() ||
          RaidStartedTransition() ||
          MatchingAbortedTransition() ||
          FleaSoldTransition():
        break;
    }
  }

  /// The progress catalog of the active mode, or `null` while it is missing.
  ProgressCatalog? get _progressCatalog {
    final mode = _catalog.mode;
    final snapshot = _catalog.snapshot;
    if (mode == GameMode.unknown || snapshot?.mode != mode) return null;
    return snapshot?.progressCatalog;
  }

  /// The local progress of the active mode, or `null` while it is missing.
  ProgressFacts? get _facts =>
      _progress.mode == _catalog.mode ? _progress.facts : null;

  AirFilterStatus _airFilter() =>
      airFilterStatus(catalog: _progressCatalog, facts: _facts);

  QuestItemsCheck _questCheck(String? mapId) => questItemsCheck(
    mapId: mapId,
    objectives: mapId == null ? null : _questObjectives(mapId),
    catalog: _progressCatalog,
    facts: _facts,
  );

  /// The quest items rule: at most once per queue, on the map-known
  /// transition.
  void _questItems(MapKnownTransition transition, String? mapId) {
    if (!isFreshLogTime(transition.time, _clock())) return;
    if (!_settings.alerts.itemFor(AlertKind.questItems).on) {
      // Remembered while off, so a redelivery after the switch goes on plays
      // nothing.
      _remember(_firedTransitions, (
        AlertKind.questItems,
        transition.id,
      ), _maxFiredTransitions);
      return;
    }
    if (_questPlayed && _questPlayedQueueId == _queueId) return;
    _questMapId = mapId;
    switch (_questCheck(mapId)) {
      case QuestItemsFire():
        _questWaiting = false;
        if (_fireFromLog(AlertKind.questItems, transition)) {
          _questPlayed = true;
          _questPlayedQueueId = _queueId;
        }
      case QuestItemsQuiet():
        _questWaiting = false;
      case QuestItemsUnavailable():
        _questWaiting = true;
    }
    notifyListeners();
  }

  /// Sets the failed-task flag for a fresh failure of a restartable task.
  void _taskFailed(TaskTransition transition, String taskId) {
    if (!isFreshLogTime(transition.time, _clock())) return;
    final key = (AlertKind.failedTasks, transition.id);
    if (_firedTransitions.contains(key)) return;
    // Remembered even while the alert is off, so a redelivered failure never
    // plays after the switch goes on.
    _remember(_firedTransitions, key, _maxFiredTransitions);
    if (!_settings.alerts.itemFor(AlertKind.failedTasks).on) return;
    if (!isRestartable(_progressCatalog, taskId)) return;
    // A failure read in the same batch as one that already released the
    // reminder is covered by it: one reminder for the failures of a raid.
    if (_failedReleasedBatch == _lifecycleBatch) return;
    _failedPending = true;
    _releaseFailedTasks();
  }

  /// Fires the failed tasks reminder once the player is in the menus with no
  /// raid current.
  ///
  /// Checked on each lifecycle change and when a failure arrives, because the
  /// lifecycle notifies before it publishes a batch's transitions.
  void _releaseFailedTasks() {
    if (!_failedPending) return;
    final state = _lifecycle.state;
    if (state.phase != RaidPhase.inMenus || state.currentRaid != null) return;
    _failedPending = false;
    _failedReleasedBatch = _lifecycleBatch;
    _fire(AlertKind.failedTasks);
  }

  /// Runs a rule, naming [kind] in [lastFailure] when it throws, so one
  /// broken rule never stops the others.
  void _guardRule(AlertKind kind, void Function() rule) {
    try {
      rule();
    } on Object {
      _failed('The "${kind.line}" alert could not be decided.');
    }
  }

  void _onLifecycleBatch() => _lifecycleBatch++;

  void _onSourceChanged() {
    if (_disposed) return;
    _releaseFailedTasks();
    _plan();
    if (_questWaiting && _questCheck(_questMapId) is! QuestItemsUnavailable) {
      _questWaiting = false;
    }
    notifyListeners();
  }

  // ---- Timer alerts -----------------------------------------------------

  /// The deadlines the current inputs give, with the same arithmetic as the
  /// timer strip.
  List<_Deadline> _deadlines() {
    final deadlines = <_Deadline>[];
    final raid = _lifecycle.state.currentRaid;
    // Only a PMC raid that was not a reconnect has a run-through to warn about.
    if (raid != null &&
        raid.side == RaidSide.pmc &&
        raid.entry != RaidEntry.reconnect) {
      deadlines.add(
        _Deadline(
          AlertKind.runThroughOver,
          raid.startId,
          raid.startTime.add(
            Duration(seconds: _settings.raidTimers.runThroughSeconds),
          ),
        ),
      );
    }
    final mode = _catalog.mode;
    final snapshot = _catalog.snapshot;
    final inputs = snapshot != null && snapshot.mode == mode
        ? snapshot.scavCooldown
        : null;
    final start = _settings.effectiveScavCooldownStarts[mode];
    if (mode != GameMode.unknown && inputs != null && start != null) {
      final ProgressFacts? facts = _progress.mode == mode
          ? _progress.facts
          : null;
      final length = scavCooldownLength(
        inputs,
        _settings.raidTimers.fenceReputationFor(mode),
        facts,
        mode,
      );
      if (length != null) {
        deadlines.add(
          _Deadline(AlertKind.scavReady, (
            mode,
            start,
          ), start.add(Duration(seconds: length.seconds))),
        );
      }
    }
    return deadlines;
  }

  /// Plans the timer alerts from the current inputs.
  ///
  /// A deadline fires only when it was ahead at the previous plan with the
  /// same time, and the clock has now passed it. One that is already past, or
  /// that an input change moved into the past, is marked seen and never fires.
  /// Arms one timer for the earliest deadline still ahead.
  void _plan() {
    final now = _clock();
    final due = <AlertKind>[];
    final armed = <(AlertKind, Object), DateTime>{};
    DateTime? earliest;
    for (final deadline in _deadlines()) {
      final seen = switch (deadline.kind) {
        AlertKind.runThroughOver => _seenRunThroughs,
        _ => _seenScavStarts,
      };
      if (seen.contains(deadline.key)) continue;
      final slot = (deadline.kind, deadline.key);
      if (deadline.at.isAfter(now)) {
        armed[slot] = deadline.at;
        if (earliest == null || deadline.at.isBefore(earliest)) {
          earliest = deadline.at;
        }
        continue;
      }
      if (_armed[slot] == deadline.at && _speaksNow(deadline.kind)) {
        due.add(deadline.kind);
      }
      _remember(seen, deadline.key, _maxSeenDeadlines);
    }
    _armed = armed;
    _deadlineTimer?.cancel();
    _deadlineTimer = earliest == null
        ? null
        : _timerFactory(earliest.difference(now), _onDeadlineTimer);
    due.forEach(_fire);
  }

  // The scav cooldown can end mid-raid, when the line is no use: it is then
  // dropped, not delayed.
  bool _speaksNow(AlertKind kind) =>
      kind != AlertKind.scavReady || _lifecycle.state.phase != RaidPhase.inRaid;

  void _onDeadlineTimer() {
    if (_disposed) return;
    _deadlineTimer = null;
    _plan();
  }

  /// Fires [kind] for [transition] when the transition is fresh, has not been
  /// seen for this alert before and the alert is on.
  ///
  /// Returns whether the alert fired.
  bool _fireFromLog(AlertKind kind, RaidTransition transition) {
    if (!isFreshLogTime(transition.time, _clock())) return false;
    final key = (kind, transition.id);
    if (_firedTransitions.contains(key)) return false;
    // Remembered even while the alert is off, so a redelivered transition
    // never plays after the switch goes on.
    _remember(_firedTransitions, key, _maxFiredTransitions);
    if (!_settings.alerts.itemFor(kind).on) return false;
    _fire(kind);
    return true;
  }

  /// Adds [value] to [seen], evicting the oldest past [limit].
  static void _remember<T>(Set<T> seen, T value, int limit) {
    seen.add(value);
    while (seen.length > limit) {
      seen.remove(seen.first);
    }
  }

  /// Queues [kind] when its switch is on.
  void _fire(AlertKind kind) {
    if (!_settings.alerts.itemFor(kind).on) return;
    _enqueue(_QueuedAlert(kind: kind, firedAt: _clock(), forced: false));
  }

  // ---- Queue ------------------------------------------------------------

  void _enqueue(_QueuedAlert alert) {
    if (_disposed || _waiting.length >= alertMaxWaiting) return;
    _waiting.add(alert);
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_playing || _disposed) return;
    _playing = true;
    try {
      while (!_disposed && _waiting.isNotEmpty) {
        final alert = _waiting.removeFirst();
        if (_clock().difference(alert.firedAt) > alertMaxWait) continue;
        final kind = alert.kind;
        if (!alert.forced &&
            kind != null &&
            !_settings.alerts.itemFor(kind).on) {
          continue;
        }
        await _play(alert);
      }
    } finally {
      _playing = false;
    }
  }

  Future<void> _play(_QueuedAlert alert) async {
    final kind = alert.kind;
    final name = kind?.line ?? 'Voice preview';
    final alerts = _settings.alerts;
    if (kind != null) {
      if (alerts.itemFor(kind).sound case FileSound(:final path)) {
        final result = await _guarded(
          () => _audio.playFile(path: path, volume: alerts.volume),
          playFileBackstop,
        );
        if (_disposed) return;
        switch (result) {
          case AudioOk():
            _fileProblems.remove(kind);
            _succeeded();
            return;
          case AudioFailure(
            code: AudioFailureCode.fileMissing ||
                AudioFailureCode.fileUnplayable,
          ):
            _fileProblems[kind] = (
              path: path,
              message:
                  'The sound file could not be played. '
                  'The alert is spoken instead.',
            );
          case AudioFailure(code: AudioFailureCode.stopped):
            return;
          case AudioFailure(code: AudioFailureCode.timeout):
            _failed('The "$name" sound file ran too long and was stopped.');
            return;
          case AudioFailure():
            _failed('The "$name" sound could not be played.');
            return;
        }
      }
    }
    await _speak(kind?.line ?? voicePreviewLine, name);
  }

  Future<void> _speak(String text, String name) async {
    final alerts = _settings.alerts;
    var voice = alerts.voice;
    var result = await _speakOnce(text, voice);
    if (_disposed) return;
    if (voice != null &&
        result is AudioFailure &&
        result.code == AudioFailureCode.voiceMissing) {
      _missingVoice = voice;
      if (_spokenVoice == voice) _spokenVoice = null;
      voice = null;
      result = await _speakOnce(text, null);
      if (_disposed) return;
    }
    switch (result) {
      case AudioOk():
        // The saved voice spoke, so it is installed again.
        if (voice != null) {
          _spokenVoice = voice;
          if (voice == _missingVoice) _missingVoice = null;
        }
        _succeeded();
      case AudioFailure(code: AudioFailureCode.stopped):
        notifyListeners();
      case AudioFailure():
        _failed('"$name" could not be spoken.');
    }
  }

  Future<AudioResult> _speakOnce(String text, String? voice) {
    final alerts = _settings.alerts;
    return _guarded(
      () => _audio.speak(
        text: text,
        voice: voice,
        speed: alerts.speed,
        volume: alerts.volume,
      ),
      speakBackstop,
    );
  }

  /// Runs [call], giving up after [limit]: stops playback and answers a
  /// timeout. A thrown error answers a speech failure.
  Future<AudioResult> _guarded(
    Future<AudioResult> Function() call,
    Duration limit,
  ) {
    final done = Completer<AudioResult>();
    _pendingPlayback = done;
    final timer = _timerFactory(limit, () {
      if (done.isCompleted) return;
      done.complete(const AudioFailure(AudioFailureCode.timeout));
      unawaited(_stopQuietly());
    });
    void finish(AudioResult result) {
      if (!done.isCompleted) done.complete(result);
    }

    call().then(
      finish,
      onError: (Object _) =>
          finish(const AudioFailure(AudioFailureCode.speechFailed)),
    );
    return done.future.whenComplete(() {
      timer.cancel();
      if (identical(_pendingPlayback, done)) _pendingPlayback = null;
    });
  }

  Future<void> _stopQuietly() async {
    try {
      await _audio.stop();
    } on Object {
      // The item is already treated as failed.
    }
  }

  void _succeeded() {
    _lastFailure = null;
    notifyListeners();
  }

  void _failed(String message) {
    _lastFailure = message;
    notifyListeners();
  }

  /// Stops playback, empties the queue and stops listening.
  ///
  /// Safe to call more than once.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _waiting.clear();
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    final pending = _pendingPlayback;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const AudioFailure(AudioFailureCode.stopped));
    }
    unawaited(_stopQuietly());
    unawaited(_subscription.cancel());
    _lifecycle.removeListener(_onLifecycleBatch);
    for (final source in _sources) {
      source.removeListener(_onSourceChanged);
    }
    super.dispose();
  }
}
