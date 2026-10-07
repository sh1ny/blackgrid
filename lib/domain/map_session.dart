import 'catalog.dart';
import 'raid_panel_text_parser.dart';
import 'screenshot_filename.dart';

/// Input availability is separate from retained, timestamped evidence.
enum MapInputStatus {
  disabled,
  missing,
  empty,
  reading,
  watching,
  unavailable,
  error,
}

class SessionLogState {
  const SessionLogState({
    this.status = MapInputStatus.disabled,
    this.sessionId,
    this.incarnation = 0,
    this.detectedMapId,
    this.detectedMode = GameMode.unknown,
    this.message,
  });
  final MapInputStatus status;
  final String? sessionId;
  final int incarnation;
  final String? detectedMapId;
  final GameMode detectedMode;
  final String? message;
}

class MapPlayerSample {
  const MapPlayerSample({
    required this.metadata,
    required this.path,
    required this.modifiedAt,
    required this.observedAt,
    required this.assumedAssociation,
    required this.sessionEpoch,
  });
  final ScreenshotFilenameSample metadata;
  final String path;
  final DateTime modifiedAt;
  final DateTime observedAt;
  final bool assumedAssociation;
  final int sessionEpoch;
  Duration ageAt(DateTime now) => now.difference(modifiedAt);
}

class MapSessionState {
  MapSessionState({
    required this.effectiveMapId,
    required this.effectiveMode,
    required this.followGameLogs,
    this.detectedMapId,
    this.detectedMode = GameMode.unknown,
    this.sessionEpoch = 0,
    this.sessionId,
    this.logStatus = MapInputStatus.disabled,
    this.logDirectory = '',
    this.logDirectoryDetected = false,
    this.screenshotDirectory = '',
    this.screenshotDirectoryDetected = false,
    this.screenshotStatus = MapInputStatus.disabled,
    this.logMessage,
    this.screenshotMessage,
    this.playerSample,
    this.raidEvidence,
    Set<String> raidHighlightIds = const {},
    this.mapDisagreement = false,
    this.readingLatest = false,
    this.assumedAssociation = false,
    this.savedScreenshotPath,
    this.savedScreenshotModifiedAt,
    this.processingScreenshot = false,
    this.pendingScreenshotPath,
  }) : raidHighlightIds = Set.unmodifiable(raidHighlightIds);
  final String effectiveMapId;
  final GameMode effectiveMode;
  final bool followGameLogs;
  final String? detectedMapId;
  final GameMode detectedMode;
  final int sessionEpoch;
  final String? sessionId;
  final MapInputStatus logStatus;

  /// Effective input folders: configured, or auto-detected when unset.
  final String logDirectory;
  final bool logDirectoryDetected;
  final String screenshotDirectory;
  final bool screenshotDirectoryDetected;
  final MapInputStatus screenshotStatus;
  final String? logMessage;
  final String? screenshotMessage;
  final MapPlayerSample? playerSample;
  final RaidPanelEvidence? raidEvidence;
  final Set<String> raidHighlightIds;
  final bool mapDisagreement;
  final bool readingLatest;
  final bool assumedAssociation;
  final String? savedScreenshotPath;
  final DateTime? savedScreenshotModifiedAt;
  final bool processingScreenshot;
  final String? pendingScreenshotPath;
}
