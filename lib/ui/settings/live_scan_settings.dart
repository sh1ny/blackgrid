import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/scan_coordinator.dart';
import '../../data/scan_frame_recorder.dart';
import '../../data/scan_timing_log.dart';
import '../../domain/settings.dart';
import '../ember/ember_tokens.dart';
import '../ember/theme_access.dart';
import '../live_scan_text.dart';
import 'settings_row.dart';

/// The rows of the Settings page's Live scan section: live scan on or off, the
/// scan key, record scan frames, and the status and error lines under them.
///
/// It listens to [scanner] and [timingLog] and holds no state of its own, so
/// the switches always show the session's intent. Recording stays available
/// only while live scan is ready (ADR-0015).
class LiveScanSettings extends StatelessWidget {
  /// Creates the rows over [scanner] and [timingLog].
  const LiveScanSettings({
    super.key,
    required this.scanner,
    required this.timingLog,
  });

  /// The coordinator the switches drive.
  final ScanCoordinator scanner;

  /// The timing log whose status is shown.
  final ScanTimingLog timingLog;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    final line = EmberType.label.copyWith(color: ember.inkTertiary);
    final errorLine = EmberType.label.copyWith(color: ember.errInk);
    Widget note(String text, Key key, {bool error = false}) => Padding(
      padding: const EdgeInsets.only(bottom: EmberSpace.sm),
      child: Text(text, key: key, style: error ? errorLine : line),
    );
    return ListenableBuilder(
      listenable: Listenable.merge([
        scanner,
        scanner.settings,
        timingLog.status,
        scanner.recordingStatus,
      ]),
      builder: (context, _) {
        final status = scanner.status;
        final recording = scanner.recordingStatus.value;
        final recordingText = LiveScanLines.recordingText(recording);
        final recordingFailed =
            recording.stopReason is ScanRecordingStartFailed ||
            recording.stopReason is ScanRecordingWriteFailed;
        final canPickKey =
            (status.state == LiveScanState.off ||
                status.state == LiveScanState.ready) &&
            !scanner.hotkeyRebinding;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsRow.toggle(
              key: const Key('live-scan-switch'),
              name: 'Live scan',
              explanation: 'Read the item under the cursor while you play.',
              value: scanner.switchOn,
              onChanged: (on) => unawaited(scanner.setLiveScan(on)),
            ),
            note(
              LiveScanLines.statusText(status),
              const Key('live-scan-status'),
            ),
            SettingsRow(
              name: 'Scan key',
              explanation: 'The key that scans at the cursor.',
              trailing: SizedBox(
                width: 120,
                child: DropdownButton<ScanHotkey>(
                  key: const Key('scan-hotkey-picker'),
                  isExpanded: true,
                  // The binding still in force: a refused rebind leaves it.
                  value: scanner.settings.settings.scanHotkey,
                  items: [
                    for (final key in ScanHotkey.values)
                      DropdownMenuItem(value: key, child: Text(key.label)),
                  ],
                  onChanged: canPickKey
                      ? (key) {
                          if (key != null) unawaited(scanner.setHotkey(key));
                        }
                      : null,
                ),
              ),
            ),
            note(
              LiveScanLines.hotkeyText(scanner),
              const Key('scan-hotkey-status'),
            ),
            if (scanner.hotkeyError case final hotkeyError?)
              note(hotkeyError, const Key('scan-hotkey-error'), error: true),
            SettingsRow.toggle(
              key: const Key('record-frames-switch'),
              name: 'Record scan frames',
              explanation: 'Save the frames of each scan to a folder.',
              // A starting session shows on and can be switched off; only a
              // stopping one refuses the switch.
              value:
                  recording.state == ScanRecordingState.on ||
                  recording.state == ScanRecordingState.starting,
              enabled:
                  status.state == LiveScanState.ready &&
                  recording.state != ScanRecordingState.stopping,
              onChanged: (on) => unawaited(scanner.setRecording(on)),
            ),
            if (recordingText != null)
              note(
                recordingText,
                const Key('record-frames-status'),
                error: recordingFailed,
              ),
            if (status.stopWarning case final warning?)
              note(warning, const Key('live-scan-warning')),
            if (scanner.error case final error?)
              note(error, const Key('live-scan-error'), error: true),
            if (timingLog.status.value case ScanTimingUnavailable(:final error))
              note(
                'Timing log unavailable: $error',
                const Key('live-scan-log-status'),
                error: true,
              ),
          ],
        );
      },
    );
  }
}
