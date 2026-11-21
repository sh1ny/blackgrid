import 'dart:async';

import 'package:blackgrid/application/alerts_controller.dart';
import 'package:blackgrid/application/audio_port.dart';
import 'package:blackgrid/application/raid_timers_controller.dart';
import 'package:blackgrid/domain/alert_rules.dart';
import 'package:blackgrid/domain/alerts.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/progress_facts.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';

import 'fake_audio_port.dart';

/// The session folder the fake lifecycle's record identities name.
const alertsFolder = 'log_2026.11.21_12-00-00_1.3.0.0.48484';

/// The test day's local time at [h]:[m]:[s].
DateTime alertsAt(int h, [int m = 0, int s = 0]) =>
    DateTime(2026, 11, 21, h, m, s);

/// A lifecycle source that folds events with the real reducer and publishes
/// like `RaidLifecycleController`: state first, then each transition.
class FakeAlertLifecycle extends ChangeNotifier
    implements RaidTimerLifecycleSource {
  RaidLifecycleState _state = RaidLifecycleState.initial;
  final _out = StreamController<RaidTransition>.broadcast(sync: true);
  int _offset = 0;

  @override
  RaidLifecycleState get state => _state;

  @override
  Stream<RaidTransition> get transitions => _out.stream;

  /// A fresh record identity.
  LogRecordId nextId() =>
      LogRecordId(alertsFolder, LogFile.application, _offset++);

  /// Folds one event, notifies, then publishes its transitions.
  void feed(GameLogEvent event) => feedBatch([event]);

  /// Folds [events] as one batch: one notify, then every transition.
  void feedBatch(List<GameLogEvent> events) {
    final published = <RaidTransition>[];
    for (final event in events) {
      final (next, transitions) = reduce(_state, event);
      _state = next;
      published.addAll(transitions);
    }
    notifyListeners();
    published.forEach(_out.add);
  }

  /// Publishes [transition] with no state change.
  void emit(RaidTransition transition) => _out.add(transition);

  /// Replaces the state, notifying listeners.
  void setState(RaidLifecycleState state) {
    _state = state;
    notifyListeners();
  }

  void profile(DateTime t) => feed(ProfileSelected(nextId(), t));
  void queue(DateTime t) => feed(QueueEntered(nextId(), t));
  void scene(DateTime t, String? map) => feed(SceneLoaded(nextId(), t, map));

  /// Matchmaking completes and the client joins the raid's server.
  void matchFound(DateTime t) {
    matchingCompleted(t);
    serverJoined(t);
  }

  void matchingCompleted(DateTime t) => feed(MatchFound(nextId(), t));
  void serverJoined(DateTime t) => feed(ServerJoined(nextId(), t));
  void matchingCancelled(DateTime t) => feed(MatchingAborted(nextId(), t));
  void rejoin(DateTime t) =>
      feed(RaidRejoined(nextId(), t, 'MatchWait', 'bigmap', 'customs'));
  void raidStarting(DateTime t) => feed(RaidStarting(nextId(), t));
  void raidStarted(DateTime t) => feed(RaidStarted(nextId(), t));
  void raidExit(DateTime t) => feed(RaidExit(nextId(), t));
  void taskFailed(DateTime t, String task) =>
      feed(TaskFailed(nextId(), t, task));

  /// A raid entered from the queue and started at [start].
  ///
  /// A PMC raid by default: its countdown is dated a minute before [start],
  /// long enough to make it a PMC countdown and too old to speak. A [scav]
  /// raid logs no countdown.
  void startRaid(DateTime start, {GameMode? mode, bool scav = false}) {
    if (mode != null) feed(SessionModeChanged(nextId(), start, mode));
    profile(start);
    queue(start);
    if (!scav) raidStarting(start.subtract(const Duration(minutes: 1)));
    raidStarted(start);
  }

  /// The game client restarts mid-raid and the player queues again.
  void restartClient(DateTime profileTime, DateTime queueTime) {
    feed(const SessionFolderChanged('next'));
    profile(profileTime);
    queue(queueTime);
  }

  @override
  void dispose() {
    unawaited(_out.close());
    super.dispose();
  }
}

/// A settings source the test edits directly.
class FakeAlertSettings extends ChangeNotifier implements AlertSettingsSource {
  FakeAlertSettings({AlertSettings? alerts, RaidTimerSettings? timers})
    : _alerts = alerts ?? AlertSettings(),
      _timers = timers ?? RaidTimerSettings();

  AlertSettings _alerts;
  RaidTimerSettings _timers;

  /// The cooldown start of each mode.
  final starts = <GameMode, DateTime>{};

  /// What [setAlertSound] answers; `null` accepts the sound.
  String? soundMessage;

  /// The calls [setAlertSound] received.
  final soundCalls = <(AlertKind, AlertSound)>[];

  @override
  AlertSettings get alerts => _alerts;

  @override
  RaidTimerSettings get raidTimers => _timers;

  @override
  Map<GameMode, DateTime> get effectiveScavCooldownStarts =>
      Map.unmodifiable(starts);

  void setAlerts(AlertSettings alerts) {
    _alerts = alerts;
    notifyListeners();
  }

  void setTimers(RaidTimerSettings timers) {
    _timers = timers;
    notifyListeners();
  }

  void setStart(GameMode mode, DateTime start) {
    starts[mode] = start;
    notifyListeners();
  }

  /// Switches [kind] on or off.
  void setOn(AlertKind kind, {required bool on}) =>
      setAlerts(_alerts.withItem(kind, _alerts.itemFor(kind).copyWith(on: on)));

  /// Sets [kind]'s sound.
  void setSound(AlertKind kind, AlertSound sound) => setAlerts(
    _alerts.withItem(kind, _alerts.itemFor(kind).copyWith(sound: sound)),
  );

  @override
  Future<String?> setAlertSound(AlertKind kind, AlertSound sound) async {
    soundCalls.add((kind, sound));
    final message = soundMessage;
    if (message == null) setSound(kind, sound);
    return message;
  }
}

/// A catalog source the test edits directly.
class FakeAlertCatalog extends ChangeNotifier
    implements RaidTimerCatalogSource {
  @override
  GameMode mode = GameMode.unknown;
  @override
  CatalogSnapshot? snapshot;

  void set(GameMode newMode, CatalogSnapshot? newSnapshot) {
    mode = newMode;
    snapshot = newSnapshot;
    notifyListeners();
  }
}

/// A progress source the test edits directly.
class FakeAlertProgress extends ChangeNotifier
    implements RaidTimerProgressSource {
  @override
  GameMode mode = GameMode.unknown;
  @override
  ProgressFacts? facts;

  void set(GameMode newMode, ProgressFacts? newFacts) {
    mode = newMode;
    facts = newFacts;
    notifyListeners();
  }
}

/// Base 25:00; Fence modifier 1.0; [bonuses] are hideout bonus keys.
ScavCooldownInputs alertsScavInputs({Map<String, double> bonuses = const {}}) =>
    ScavCooldownInputs(
      baseSeconds: 1500,
      fenceLevels: const [
        FenceCooldownLevel(minimumReputation: -7, modifier: 1),
      ],
      bonuses: bonuses,
    );

/// A catalog snapshot of [mode] with scav inputs and an optional progress
/// catalog.
CatalogSnapshot alertsSnapshot(
  GameMode mode, {
  ProgressCatalog? progressCatalog,
  Map<String, double> bonuses = const {},
}) => CatalogSnapshot(
  mode: mode,
  revision: 'r',
  observedAt: alertsAt(0),
  items: const {},
  traders: const {},
  requirements: const [],
  scavCooldown: alertsScavInputs(bonuses: bonuses),
  progressCatalog: progressCatalog,
);

/// Everything a test needs, built inside [fakeAsync].
class AlertsRig {
  /// Creates a rig whose clock starts at [origin].
  AlertsRig(this.async, {required this._origin, AlertSettings? alerts})
    : settings = FakeAlertSettings(alerts: alerts);

  final FakeAsync async;
  final DateTime _origin;

  /// Extra clock movement with no timers delivered.
  Duration jump = Duration.zero;

  final lifecycle = FakeAlertLifecycle();
  final FakeAlertSettings settings;
  final catalog = FakeAlertCatalog();
  final progress = FakeAlertProgress();
  final audio = FakeAudioPort();

  /// What the quest items lookup answers, by map id.
  Iterable<QuestObjectiveRef>? Function(String mapId) objectives = (_) => null;

  late final AlertsController controller;

  /// The clock: the origin, fake elapsed time and any [jump].
  DateTime now() => _origin.add(async.elapsed + jump);

  /// Builds the controller with every fake wired in.
  AlertsRig open() {
    controller = AlertsController(
      lifecycle: lifecycle,
      settings: settings,
      catalog: catalog,
      progress: progress,
      audio: audio,
      clock: now,
      questObjectives: (mapId) => objectives(mapId),
    );
    return this;
  }

  /// Lets pending microtasks run.
  void settle() => async.flushMicrotasks();

  /// Completes the oldest waiting playback and lets the queue move on.
  void finish([AudioResult result = const AudioOk()]) {
    audio.completeNext(result);
    settle();
  }

  /// The spoken lines or file paths played so far, in order.
  ///
  /// Lets pending microtasks run first, so a queue that moves on after an
  /// automatic completion has done so.
  List<String> get played {
    settle();
    return [
      for (final call in audio.playCalls)
        (call.args['text'] ?? call.args['path'])! as String,
    ];
  }
}

/// Runs [body] in a [FakeAsync] zone with a rig starting at [origin].
void runAlerts(
  DateTime origin,
  void Function(AlertsRig rig) body, {
  AlertSettings? alerts,
}) {
  fakeAsync((async) {
    final rig = AlertsRig(async, origin: origin, alerts: alerts);
    body(rig);
    rig.controller.dispose();
    rig.lifecycle.dispose();
    async.flushTimers();
  });
}
