import '../application/catalog_controller.dart';
import '../application/progress_controller.dart';
import '../application/scan_coordinator.dart';
import '../domain/inspection_context.dart';
import '../domain/map_session.dart';
import '../domain/raid_panel_text_parser.dart';
import '../domain/settings.dart';

// Plain-English wording for the states and reasons the UI shows.
//
// Each label function is an exhaustive `switch` expression with no default,
// so adding an enum value fails analysis until it has wording.

/// Reads as "Item data: <label>".
String catalogStatusLabel(CatalogStatus status) => switch (status) {
  CatalogStatus.missing => 'not downloaded yet',
  CatalogStatus.loading => 'downloading',
  CatalogStatus.current => 'up to date',
  CatalogStatus.stale => 'out of date',
  CatalogStatus.failed => 'download failed',
};

/// Reads as "Progress: <label>".
String progressStatusLabel(ProgressStatus status) => switch (status) {
  ProgressStatus.missing => 'not connected',
  ProgressStatus.loading => 'refreshing',
  ProgressStatus.current => 'up to date',
  ProgressStatus.stale => 'out of date',
  ProgressStatus.failed => 'refresh failed',
  ProgressStatus.cooldown => 'refresh cooling down',
};

/// Reads as "Logs: <label>" or "Screenshots: <label>".
String mapInputStatusLabel(MapInputStatus status) => switch (status) {
  MapInputStatus.disabled => 'turned off',
  MapInputStatus.missing => 'folder not found',
  MapInputStatus.empty => 'no files yet',
  MapInputStatus.reading => 'reading files',
  MapInputStatus.watching => 'watching folder',
  MapInputStatus.unavailable => 'cannot be read',
  MapInputStatus.error => 'something went wrong',
};

/// Describes how well the raid panel text was read.
String raidPanelStateLabel(RaidPanelState state) => switch (state) {
  RaidPanelState.missing => 'no raid panel found',
  RaidPanelState.unreadable => 'could not be read',
  RaidPanelState.partial => 'partly read',
  RaidPanelState.recognized => 'read',
  RaidPanelState.empty => 'nothing to read',
  RaidPanelState.ambiguous => 'unclear',
  RaidPanelState.unavailable => 'reader not available',
  RaidPanelState.error => 'reading failed',
};

/// Explains why a scan did not produce an item.
String scanRejectReasonLabel(ScanRejectReason reason) => switch (reason) {
  ScanRejectReason.noMarker => 'no item name found on screen',
  ScanRejectReason.matcherFailed => 'item matching failed',
  ScanRejectReason.emptyCatalog => 'no item data to match against',
  ScanRejectReason.titleTooShort => 'item name was too short',
  ScanRejectReason.uiChrome => 'only game menu text was found',
  ScanRejectReason.belowSimilarity =>
    'name did not match any item closely enough',
  ScanRejectReason.ambiguous => 'name matched several items equally well',
  ScanRejectReason.catalogModeMismatch =>
    'item is not in the selected game mode',
  ScanRejectReason.catalogUnavailable => 'item data is not available',
};

/// Explains why a scan or live scan could not deliver.
String scanFailureCodeLabel(ScanFailureCode code) => switch (code) {
  ScanFailureCode.targetGone => 'the game window is gone',
  ScanFailureCode.targetNotForeground => 'the game window was not in front',
  ScanFailureCode.targetMinimised => 'the game window is minimised',
  ScanFailureCode.wrongTarget => 'the window is not the game',
  ScanFailureCode.roiOutsideClient =>
    'the scan area is outside the game window',
  ScanFailureCode.captureTooLarge => 'the captured area is too large',
  ScanFailureCode.targetChanged => 'the game window changed during capture',
  ScanFailureCode.blankCapture => 'the capture was blank',
  ScanFailureCode.frameBudgetExceeded ||
  ScanFailureCode.captureFailed ||
  ScanFailureCode.captureBusy ||
  ScanFailureCode.captureTimeout ||
  ScanFailureCode.captureClosed ||
  ScanFailureCode.captureUnavailable ||
  ScanFailureCode.shutdownIncomplete => 'screen capture error',
  ScanFailureCode.alreadyStarted => 'live scan is already running',
  ScanFailureCode.triggerUnavailable =>
    'the mouse trigger could not be installed',
  ScanFailureCode.stopTimedOut => 'the mouse trigger did not stop in time',
  ScanFailureCode.visionTimeout => 'reading the item took too long',
  ScanFailureCode.visionSuperseded ||
  ScanFailureCode.visionInvalidated => 'a newer scan replaced this one',
  ScanFailureCode.visionClosed ||
  ScanFailureCode.visionUnavailable ||
  ScanFailureCode.visionInvalidInput ||
  ScanFailureCode.visionInvalidTemplate ||
  ScanFailureCode.visionJobFailed ||
  ScanFailureCode.visionFailed ||
  ScanFailureCode.visionRuntimeUnavailable ||
  ScanFailureCode.visionStartFailed => 'item reader error',
  ScanFailureCode.markerTemplateUnavailable ||
  ScanFailureCode.markerTemplateInvalid => 'item marker file problem',
};

/// Names the scan pass a result came from.
String scanPassLabel(ScanPass pass) => switch (pass) {
  ScanPass.targeted => 'Targeted',
  ScanPass.fallback => 'Wider scan',
};

/// Reads as "Found in raid: <label>".
String firLabel(FirState state) => switch (state) {
  FirState.unknown => 'unknown',
  FirState.yes => 'yes',
  FirState.no => 'no',
};

/// Names where an item activity entry came from.
String activitySourceLabel(ActivitySource source) => switch (source) {
  ActivitySource.manual => 'Manual',
  ActivitySource.scan => 'Scan',
  ActivitySource.importedScan => 'Imported scan',
  ActivitySource.importedManual => 'Imported manual',
};

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats [time] in the local time zone relative to [now].
///
/// Returns `HH:mm` when [time] falls on the same local day as [now],
/// `d MMM HH:mm` (for example `3 Oct 14:32`) for any other day, and
/// `unknown` when [time] is `null`.
String localTimeLabel(DateTime? time, {required DateTime now}) {
  if (time == null) return 'unknown';
  final local = time.toLocal();
  final today = now.toLocal();
  final clock =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  return sameDay ? clock : '${local.day} ${_months[local.month - 1]} $clock';
}
