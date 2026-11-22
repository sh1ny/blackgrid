import 'package:flutter/material.dart';

import '../../application/screenshot_cleanup_controller.dart';
import '../../application/settings_controller.dart';
import 'raid_timer_input.dart';
import 'settings_row.dart';

/// The opt-in raid screenshot cleanup switch and its latest result.
class ScreenshotCleanupSettings extends StatefulWidget {
  /// Creates the row over saved [settings] and the optional live [cleanup].
  const ScreenshotCleanupSettings({
    super.key,
    required this.settings,
    this.cleanup,
  });

  /// The owner of the saved cleanup setting.
  final SettingsController settings;

  /// The owner of the last cleanup result, when wired by the app.
  final ScreenshotCleanupController? cleanup;

  @override
  State<ScreenshotCleanupSettings> createState() =>
      _ScreenshotCleanupSettingsState();
}

class _ScreenshotCleanupSettingsState extends State<ScreenshotCleanupSettings> {
  String? _saveError;

  Future<void> _save(bool enabled) async {
    final saved = await widget.settings.setCleanUpRaidScreenshots(enabled);
    if (mounted) setState(() => _saveError = saved ? null : notSavedMessage);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.settings, ?widget.cleanup]),
    builder: (context, _) {
      final result = widget.cleanup?.lastResult;
      final lines = [?_saveError, if (result != null) _resultLine(result)];
      return SettingsRow.toggle(
        name: "Delete a raid's screenshots after it ends",
        explanation:
            'Moves only that raid’s game screenshots to the Recycle Bin.',
        value: widget.settings.settings.cleanUpRaidScreenshots,
        enabled: !widget.settings.busy,
        onChanged: _save,
        message: lines.isEmpty ? null : lines.join('\n'),
      );
    },
  );
}

String _resultLine(ScreenshotCleanupResult result) {
  final lines = <String>[];
  if (result.folderUnreadable) {
    lines.add('The screenshot folder could not be read.');
  } else if (result.noScreenshots) {
    lines.add('The last raid had no screenshots to move.');
  } else {
    lines.add(
      'Moved ${result.moved} ${_screenshots(result.moved)} from the last raid to the Recycle Bin.',
    );
    if (result.notMoved > 0) {
      lines.add(
        '${result.notMoved} could not be moved and are still in the folder.',
      );
    }
    if (result.unconfirmed > 0) {
      lines.add('${result.unconfirmed} could not be confirmed as moved.');
    }
  }
  if (result.unavailable) {
    lines.add(
      'Cleanup is unavailable for this run. Restart Blackgrid to try again.',
    );
  }
  if (result.skippedRaids > 0) {
    lines.add(
      result.skippedRaids == 1
          ? 'A raid was skipped because too many cleanups were waiting.'
          : '${result.skippedRaids} raids were skipped because too many cleanups were waiting.',
    );
  }
  return lines.join(' ');
}

String _screenshots(int count) => count == 1 ? 'screenshot' : 'screenshots';
