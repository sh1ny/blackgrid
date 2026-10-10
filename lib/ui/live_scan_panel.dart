import 'package:flutter/material.dart';

import '../application/scan_coordinator.dart';
import '../data/scan_timing_log.dart';
import 'theme.dart';

/// The live scan switch with the pipeline status, any stop warning, the last
/// save error and the timing log status.
///
/// It listens to [scanner] and [timingLog] and holds no state of its own, so
/// the switch always shows the session's intent.
class LiveScanPanel extends StatelessWidget {
  /// Creates the panel over [scanner] and [timingLog].
  const LiveScanPanel({
    super.key,
    required this.scanner,
    required this.timingLog,
  });

  /// The coordinator the switch drives.
  final ScanCoordinator scanner;

  /// The timing log whose status is shown.
  final ScanTimingLog timingLog;

  @override
  Widget build(BuildContext context) {
    final errorStyle = TextStyle(color: Theme.of(context).colorScheme.error);
    return ListenableBuilder(
      listenable: Listenable.merge([scanner, timingLog.status]),
      builder: (context, _) {
        final status = scanner.status;
        final error = scanner.error;
        final warning = status.stopWarning;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'LIVE SCAN',
                    style: TextStyle(
                      color: GridColors.gold,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Switch(
                  key: const Key('live-scan-switch'),
                  value: scanner.switchOn,
                  onChanged: scanner.setLiveScan,
                ),
              ],
            ),
            Text(_statusText(status), key: const Key('live-scan-status')),
            if (warning != null)
              Text(warning, key: const Key('live-scan-warning')),
            if (error != null)
              Text(error, key: const Key('live-scan-error'), style: errorStyle),
            if (timingLog.status.value case ScanTimingUnavailable(:final error))
              Text(
                'Timing log unavailable: $error',
                key: const Key('live-scan-log-status'),
                style: errorStyle,
              ),
          ],
        );
      },
    );
  }

  static String _statusText(LiveScanStatus status) => switch (status.state) {
    LiveScanState.off => 'Live scan is off',
    LiveScanState.starting => 'Live scan is starting…',
    LiveScanState.ready => 'Live scan is ready',
    LiveScanState.stopping => 'Live scan is stopping…',
    LiveScanState.unavailable =>
      'Live scan unavailable: ${status.reason ?? 'unknown reason'}',
  };
}
