import 'catalog.dart';
import 'progress.dart';
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

  /// Whether Tracker progress for the active mode was available.
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
/// marks complete, rounded to whole seconds and floored at zero. [progress]
/// counts only when its mode is [activeMode]; it counts however old it is.
///
/// Returns `null` when [inputs] has no Fence levels.
ScavCooldownLength? scavCooldownLength(
  ScavCooldownInputs inputs,
  double reputation,
  ProgressSnapshot? progress,
  GameMode activeMode,
) {
  final levels = inputs.fenceLevels;
  if (levels.isEmpty) return null;
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
      if (usable.modules[key]?.complete == true) bonus += value;
    }
  }
  final factor = 1 + bonus;
  final seconds = (inputs.baseSeconds * level.modifier * factor).round();
  return ScavCooldownLength(
    seconds: seconds < 0 ? 0 : seconds,
    baseSeconds: inputs.baseSeconds,
    fenceModifier: level.modifier,
    hideoutFactor: factor,
    hasProgress: usable != null,
  );
}

const _noProgress = 'No Tracker progress for this mode: no hideout bonuses';

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
  required ProgressSnapshot? progress,
}) {
  if (!settings.enabled) return RaidTimersView.empty;
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
    if (current == null) {
      value = noValue;
    } else {
      final left = settings.runThroughSeconds - seconds(current.startTime, now);
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
      settings: settings,
      activeMode: activeMode,
      starts: cooldownStarts,
      inputs: inputs,
      progress: progress,
    );
    entries.add(entry.$1);
    moving = moving || entry.$2;
  }
  return RaidTimersView(entries: entries, moving: moving);
}

(RaidTimerEntry, bool) _scavEntry({
  required DateTime now,
  required RaidTimerSettings settings,
  required GameMode activeMode,
  required Map<GameMode, DateTime> starts,
  required ScavCooldownInputs? inputs,
  required ProgressSnapshot? progress,
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
  final length = inputs == null
      ? null
      : scavCooldownLength(
          inputs,
          settings.fenceReputationFor(activeMode),
          progress,
          activeMode,
        );
  if (length == null) return (unknown('No item data for this mode'), false);
  final tooltip = length.hasProgress
      ? length.inputsText
      : '${length.inputsText}\n$_noProgress';
  final start = starts[activeMode];
  final remainingMs = start == null
      ? 0
      : start
            .add(Duration(seconds: length.seconds))
            .difference(now)
            .inMilliseconds;
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
