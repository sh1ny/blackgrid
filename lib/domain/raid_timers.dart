import 'dart:math' as math;

import 'catalog.dart';
import 'progress_facts.dart';
import 'raid_lifecycle.dart';
import 'settings.dart';

/// Which timer a [RaidTimerEntry] shows.
enum RaidTimerKind {
  /// Time in the current raid, or the last raid's time once it ended.
  inRaid,

  /// The run-through countdown.
  runThrough,

  /// The active mode's scav cooldown.
  scav,
}

/// One labelled value in the timer strip.
class RaidTimerEntry {
  /// Creates an entry.
  const RaidTimerEntry({
    required this.kind,
    required this.label,
    required this.value,
    this.tooltip,
  });

  /// Which timer this is.
  final RaidTimerKind kind;

  /// The label: "In raid", "Last raid", "Run-through" or "Scav".
  final String label;

  /// The value: a duration, `done`, `ready`, `unknown` or [noValue].
  final String value;

  /// The explanation shown on hover, or `null` when there is none.
  final String? tooltip;

  /// The strip text, for example `In raid 12:34`.
  String get text => '$label $value';
}

/// What the strip shows at one clock reading.
class RaidTimersView {
  /// Creates a view.
  const RaidTimersView({required this.entries, required this.moving});

  /// The view with nothing to show.
  static const empty = RaidTimersView(entries: [], moving: false);

  /// The entries to show, in strip order; empty when the timers are off.
  final List<RaidTimerEntry> entries;

  /// Whether any shown value changes as the clock moves, so a periodic
  /// update is needed.
  final bool moving;
}

/// The value shown where a timer has nothing to count: a dash.
const noValue = '—';

/// Formats [seconds] as `m:ss` under an hour and `h:mm:ss` from an hour.
String formatTimerSeconds(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// Whether [raid] ends a scav cooldown start: its mode is PvE, or its guessed
/// side is scav.
///
/// Says nothing about an unknown mode; a caller records no start for a raid
/// whose [Raid.mode] is `null` or [GameMode.unknown].
bool countsAsScavRaid(Raid raid) =>
    raid.mode == GameMode.pve ||
    switch (raid.side) {
      RaidSide.scav => true,
      RaidSide.pmc || RaidSide.unknown => false,
    };

/// A computed scav cooldown length and the inputs behind it.
class ScavCooldownLength {
  /// Creates a length.
  const ScavCooldownLength({
    required this.seconds,
    required this.baseSeconds,
    required this.fenceModifier,
    required this.hideoutFactor,
    required this.hasProgress,
  });

  /// The cooldown in whole seconds, never below zero.
  final int seconds;

  /// The base cooldown from item data.
  final double baseSeconds;

  /// The Fence level's multiplier.
  final double fenceModifier;

  /// One plus the sum of the built hideout bonuses.
  final double hideoutFactor;

  /// Whether local progress for the active mode was available.
  final bool hasProgress;

  /// The inputs as text, for example `Base 25:00 × Fence 0.80 × hideout 0.65`.
  String get inputsText =>
      'Base ${formatTimerSeconds(baseSeconds.round())}'
      ' × Fence ${fenceModifier.toStringAsFixed(2)}'
      ' × hideout ${hideoutFactor.toStringAsFixed(2)}';
}

/// Works out the scav cooldown for [activeMode].
///
/// The length is the base times the modifier of the Fence level with the
/// highest minimum at or below [reputation] (the lowest level when below all),
/// times one plus the sum of the bonuses of the hideout levels [progress]
/// records as built, rounded to whole seconds and floored at zero. A bonus key
/// is `<stationId>-<level>`, split at its last dash; a level is built when the
/// station's recorded level is at least that level, and a key whose suffix is
/// not a positive integer gives no bonus. [progress] counts only when its mode
/// is [activeMode].
///
/// Returns `null` when [inputs] has no Fence levels, or when the base or the
/// length is not finite or exceeds one day, so item data with absurd values
/// shows as unknown instead of overflowing.
ScavCooldownLength? scavCooldownLength(
  ScavCooldownInputs inputs,
  double reputation,
  ProgressFacts? progress,
  GameMode activeMode,
) {
  final levels = inputs.fenceLevels;
  if (levels.isEmpty || !_countable(inputs.baseSeconds)) return null;
  final level = levels.lastWhere(
    (l) => l.minimumReputation <= reputation,
    orElse: () => levels.first,
  );
  final usable = progress != null && progress.mode == activeMode
      ? progress
      : null;
  var bonus = 0.0;
  if (usable != null) {
    for (final MapEntry(:key, :value) in inputs.bonuses.entries) {
      if (_built(usable, key)) bonus += value;
    }
  }
  final factor = 1 + bonus;
  final raw = inputs.baseSeconds * level.modifier * factor;
  if (!_countable(raw)) return null;
  final seconds = raw.round();
  return ScavCooldownLength(
    seconds: seconds < 0 ? 0 : seconds,
    baseSeconds: inputs.baseSeconds,
    fenceModifier: level.modifier,
    hideoutFactor: factor,
    hasProgress: usable != null,
  );
}

bool _built(ProgressFacts progress, String key) {
  final dash = key.lastIndexOf('-');
  if (dash <= 0) return false;
  final level = int.tryParse(key.substring(dash + 1));
  if (level == null || level < 1) return false;
  return progress.stationLevel(key.substring(0, dash)) >= level;
}

/// The longest scav cooldown the timer counts, one day; real ones are minutes.
const _maxCooldownSeconds = 24 * 60 * 60;

bool _countable(double seconds) =>
    seconds.isFinite && seconds <= _maxCooldownSeconds;

/// When the run-through and the scav cooldown end, from the log times and the
/// settings.
///
/// The timer strip shows these and the timer alerts fire on them, so both
/// agree on every moment.
class RaidTimerDeadlines {
  /// Creates deadlines.
  const RaidTimerDeadlines({
    required this.runThroughEnd,
    required this.scavLength,
    required this.scavReady,
  });

  /// When the current raid's run-through ends, or `null` when no raid is
  /// current.
  final DateTime? runThroughEnd;

  /// The active mode's scav cooldown length, or `null` when the mode is
  /// unknown or the length cannot be computed (see [scavCooldownLength]).
  final ScavCooldownLength? scavLength;

  /// When the active mode's scav cooldown ends, or `null` when [scavLength] is
  /// `null` or the mode has no cooldown start.
  final DateTime? scavReady;
}

/// Works out when the run-through and the active mode's scav cooldown end.
///
/// Pure, and independent of the clock. The run-through ends
/// [RaidTimerSettings.runThroughSeconds] after the current raid's log start.
/// The scav cooldown ends its [scavCooldownLength] after [activeMode]'s entry
/// in [cooldownStarts], which holds each mode's start (including starts not
/// yet saved). [inputs] must belong to [activeMode]; [progress] counts only
/// when its mode is [activeMode].
RaidTimerDeadlines raidTimerDeadlines({
  required RaidLifecycleState lifecycle,
  required RaidTimerSettings settings,
  required GameMode activeMode,
  required Map<GameMode, DateTime> cooldownStarts,
  required ScavCooldownInputs? inputs,
  required ProgressFacts? progress,
}) {
  final raid = lifecycle.currentRaid;
  final length = activeMode == GameMode.unknown || inputs == null
      ? null
      : scavCooldownLength(
          inputs,
          settings.fenceReputationFor(activeMode),
          progress,
          activeMode,
        );
  final start = cooldownStarts[activeMode];
  return RaidTimerDeadlines(
    runThroughEnd: raid?.startTime.add(
      Duration(seconds: settings.runThroughSeconds),
    ),
    scavLength: length,
    scavReady: length == null || start == null
        ? null
        : start.add(Duration(seconds: length.seconds)),
  );
}

const _noProgress = 'Progress unavailable: no hideout bonuses';

/// Projects the timers at [now] from the log times and the settings.
///
/// Pure: every value comes from [now] and the arguments, never from earlier
/// calls. [cooldownStarts] holds each mode's scav cooldown start (including
/// starts not yet saved). [inputs] and [progress] must belong to
/// [activeMode]; [progress] is also checked here. A negative time in raid
/// (the clock behind the log) shows as `0:00`.
///
/// With the timers off the view has no entries. A timer with nothing to count
/// shows [noValue]: time in raid with no raid known, and the run-through
/// whenever no raid is current.
RaidTimersView raidTimersView({
  required DateTime now,
  required RaidLifecycleState lifecycle,
  required RaidTimerSettings settings,
  required GameMode activeMode,
  required Map<GameMode, DateTime> cooldownStarts,
  required ScavCooldownInputs? inputs,
  required ProgressFacts? progress,
}) {
  if (!settings.enabled) return RaidTimersView.empty;
  final deadlines = raidTimerDeadlines(
    lifecycle: lifecycle,
    settings: settings,
    activeMode: activeMode,
    cooldownStarts: cooldownStarts,
    inputs: inputs,
    progress: progress,
  );
  final entries = <RaidTimerEntry>[];
  var moving = false;

  final current = lifecycle.currentRaid;
  final lastRaid = lifecycle.raid;
  int seconds(DateTime from, DateTime to) {
    final s = to.difference(from).inSeconds;
    return s < 0 ? 0 : s;
  }

  if (settings.showTimeInRaid) {
    entries.add(switch ((current, lastRaid)) {
      (final Raid raid, _) => RaidTimerEntry(
        kind: RaidTimerKind.inRaid,
        label: 'In raid',
        value: formatTimerSeconds(seconds(raid.startTime, now)),
      ),
      (_, Raid(endTime: final DateTime end, :final startTime)) =>
        RaidTimerEntry(
          kind: RaidTimerKind.inRaid,
          label: 'Last raid',
          value: formatTimerSeconds(seconds(startTime, end)),
        ),
      _ => const RaidTimerEntry(
        kind: RaidTimerKind.inRaid,
        label: 'In raid',
        value: noValue,
      ),
    });
    moving = current != null;
  }

  if (settings.showRunThrough) {
    final String value;
    final end = deadlines.runThroughEnd;
    if (end == null) {
      value = noValue;
    } else {
      // Whole seconds left, rounded up; a raid that starts after now shows
      // the full length.
      final micros = end.difference(now).inMicroseconds;
      final left = math.min(
        settings.runThroughSeconds,
        (micros / Duration.microsecondsPerSecond).ceil(),
      );
      final done = left <= 0;
      value = done ? 'done' : formatTimerSeconds(left);
      moving = moving || !done;
    }
    entries.add(
      RaidTimerEntry(
        kind: RaidTimerKind.runThrough,
        label: 'Run-through',
        value: value,
      ),
    );
  }

  if (settings.showScavCooldown) {
    final entry = _scavEntry(
      now: now,
      activeMode: activeMode,
      deadlines: deadlines,
    );
    entries.add(entry.$1);
    moving = moving || entry.$2;
  }
  return RaidTimersView(entries: entries, moving: moving);
}

(RaidTimerEntry, bool) _scavEntry({
  required DateTime now,
  required GameMode activeMode,
  required RaidTimerDeadlines deadlines,
}) {
  RaidTimerEntry unknown(String reason) => (RaidTimerEntry(
    kind: RaidTimerKind.scav,
    label: 'Scav',
    value: 'unknown',
    tooltip: reason,
  ));
  if (activeMode == GameMode.unknown) {
    return (unknown('Choose a mode'), false);
  }
  final length = deadlines.scavLength;
  if (length == null) return (unknown('No item data for this mode'), false);
  final tooltip = length.hasProgress
      ? length.inputsText
      : '${length.inputsText}\n$_noProgress';
  final ready = deadlines.scavReady;
  final remainingMs = ready == null ? 0 : ready.difference(now).inMilliseconds;
  final counting = remainingMs > 0;
  return (
    RaidTimerEntry(
      kind: RaidTimerKind.scav,
      label: 'Scav',
      value: counting
          ? formatTimerSeconds((remainingMs / 1000).ceil())
          : 'ready',
      tooltip: tooltip,
    ),
    counting,
  );
}
