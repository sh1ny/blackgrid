import 'package:flutter/material.dart';

import '../application/scan_coordinator.dart';
import '../domain/settings.dart';
import '../data/scan_frame_recorder.dart';

/// The plain-language lines that describe live scan, shared by the Settings
/// page and the work screens.
abstract final class LiveScanLines {
  /// The hotkey line: the state the pipeline published, or the saved binding
  /// while no hotkey is registered.
  static String hotkeyText(ScanCoordinator scanner) {
    final saved = scanner.settings.settings.scanHotkey;
    return switch (scanner.hotkeyState) {
      ScanHotkeyRegistered(:final key) => '${key.label} scans at the cursor',
      ScanHotkeyUnavailable(:final key, :final reason) =>
        '${key.label} unavailable: $reason (mouse scans still work)',
      ScanHotkeyDisabled() => 'Scan hotkey off',
      ScanHotkeyInactive() when saved == ScanHotkey.off => 'Scan hotkey off',
      ScanHotkeyInactive() => '${saved.label} is used while live scan is on',
    };
  }

  /// The live scan status line for [status].
  static String statusText(LiveScanStatus status) => switch (status.state) {
    LiveScanState.off => 'Live scan is off',
    LiveScanState.starting => 'Live scan is starting…',
    LiveScanState.ready => 'Live scan is ready',
    LiveScanState.stopping => 'Live scan is stopping…',
    LiveScanState.unavailable =>
      'Live scan unavailable: ${status.reason ?? 'unknown reason'}',
  };

  /// The recording status line for [status], or `null` before any session
  /// ran.
  static String? recordingText(ScanRecordingStatus status) {
    final folder = status.folder;
    final counts = '${status.written} written, ${status.dropped} dropped';
    final where = folder == null ? '' : ' — $folder';
    final stopped = switch (status.stopReason) {
      ScanRecordingCapReached() =>
        'Recording stopped: cap of ${ScanFrameRecorder.maxHandOffs} reached',
      ScanRecordingStartFailed(:final error) ||
      ScanRecordingWriteFailed(:final error) => 'Recording stopped: $error',
      null => null,
    };
    if (stopped != null) return '$stopped. $counts$where';
    return folder == null ? null : '$counts$where';
  }
}

/// Shows a recording stop reason after configuration has been closed.
class RecordingStopNote extends StatelessWidget {
  /// Creates a note bound to [scanner]'s recording status.
  const RecordingStopNote({super.key, required this.scanner});

  /// The source of recording stop information.
  final ScanCoordinator scanner;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<ScanRecordingStatus>(
    valueListenable: scanner.recordingStatus,
    builder: (context, status, _) {
      final text = switch (status.stopReason) {
        ScanRecordingCapReached() => 'Recording stopped: scan limit reached.',
        ScanRecordingStartFailed(:final error) ||
        ScanRecordingWriteFailed(:final error) => 'Recording stopped: $error',
        null => null,
      };
      return text == null
          ? const SizedBox.shrink()
          : Text(text, key: const Key('recording-stop-note'));
    },
  );
}
