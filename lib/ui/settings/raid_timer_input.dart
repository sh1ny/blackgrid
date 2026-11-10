import '../../domain/settings.dart';

/// Shown when a run-through length is not `m:ss` or is out of range.
const runThroughMessage =
    'The run-through length must be between 1:00 and 30:00.';

/// Shown when a Fence reputation is not a number or is out of range.
const reputationMessage =
    'The Fence reputation must be between −7.00 and 6.00.';

/// Shown when a valid edit was not saved: another save was in flight, or the
/// save failed (the settings error then says more).
const notSavedMessage = 'Not saved. Try again.';

final _minutesSeconds = RegExp(r'^(\d{1,2}):([0-5]\d)$');

/// Reads `m:ss` as seconds, or `null` when [text] is not `m:ss` or is outside
/// the allowed run-through range.
int? parseRunThrough(String text) {
  final match = _minutesSeconds.firstMatch(text.trim());
  if (match == null) return null;
  final seconds = int.parse(match[1]!) * 60 + int.parse(match[2]!);
  return seconds >= RaidTimerSettings.minRunThroughSeconds &&
          seconds <= RaidTimerSettings.maxRunThroughSeconds
      ? seconds
      : null;
}

/// Reads a Fence reputation, accepting a comma as the decimal mark, or `null`
/// when [text] is not a number in the allowed range.
double? parseReputation(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null ||
      !(value >= RaidTimerSettings.minFenceReputation &&
          value <= RaidTimerSettings.maxFenceReputation)) {
    return null;
  }
  return value;
}
