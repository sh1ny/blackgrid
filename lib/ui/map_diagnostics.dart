import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/catalog.dart';
import '../domain/map_session.dart';
import '../domain/raid_lifecycle.dart';
import '../domain/raid_panel_text_parser.dart';
import 'labels.dart';

/// The map input status lines: log, screenshot and raid-panel state, the
/// saved evidence source and its age.
///
/// It lives in the collapsed Diagnostics section of Settings, so nothing here
/// is mounted, and no timer runs, until the section is expanded. The age
/// timer ticks only while a saved-screenshot age is shown and is cancelled
/// when the widget leaves the tree.
class MapDiagnostics extends StatefulWidget {
  /// Creates the status lines for [services].
  const MapDiagnostics({super.key, required this.services});

  /// The services whose map session, raid lifecycle and settings are shown.
  final AppServices services;

  @override
  State<MapDiagnostics> createState() => _MapDiagnosticsState();
}

class _MapDiagnosticsState extends State<MapDiagnostics> {
  Timer? _ageTimer;

  @override
  void initState() {
    super.initState();
    widget.services.mapSession.addListener(_syncAgeTimer);
    _syncAgeTimer();
  }

  @override
  void didUpdateWidget(MapDiagnostics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services.mapSession != widget.services.mapSession) {
      oldWidget.services.mapSession.removeListener(_syncAgeTimer);
      widget.services.mapSession.addListener(_syncAgeTimer);
      _syncAgeTimer();
    }
  }

  /// Ticks only while a saved-screenshot age is displayed.
  void _syncAgeTimer() {
    final hasAge =
        widget.services.mapSession.state.savedScreenshotModifiedAt != null;
    if (hasAge && _ageTimer == null) {
      _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!hasAge && _ageTimer != null) {
      _ageTimer!.cancel();
      _ageTimer = null;
    }
  }

  @override
  void dispose() {
    widget.services.mapSession.removeListener(_syncAgeTimer);
    _ageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.services.mapSession,
      widget.services.raidLifecycle,
      widget.services.settings,
    ]),
    builder: (context, _) {
      final services = widget.services;
      final state = services.mapSession.state;
      final sample = state.playerSample;
      final savedModifiedAt = state.savedScreenshotModifiedAt;
      final age = savedModifiedAt == null
          ? null
          : DateTime.now().toUtc().difference(savedModifiedAt.toUtc());
      final pending =
          state.processingScreenshot || state.pendingScreenshotPath != null;
      final panelAuthoritative =
          state.raidEvidence?.state == RaidPanelState.recognized ||
          state.raidEvidence?.state == RaidPanelState.empty;
      final inputUnavailable = const {
        MapInputStatus.disabled,
        MapInputStatus.missing,
        MapInputStatus.empty,
        MapInputStatus.error,
        MapInputStatus.unavailable,
      }.contains(state.screenshotStatus);
      final retainedEvidence =
          pending || inputUnavailable || !panelAuthoritative;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${state.followGameLogs ? (state.detectedMapId == null ? 'Follow logs (manual fallback)' : 'Detected map') : 'Manual map'} · ${mapLabel(state.effectiveMapId)}',
          ),
          Text(
            'Manual preference: ${mapLabel(services.settings.settings.selectedMap)}',
          ),
          Text(
            'Mode: ${modeLabel(state.effectiveMode)} · ${state.detectedMode == GameMode.unknown ? 'manual fallback' : 'detected from logs'}',
          ),
          Text(
            'Detected map: ${state.detectedMapId == null ? 'unavailable' : mapLabel(state.detectedMapId!)}',
          ),
          Text(
            'Logs: ${mapInputStatusLabel(state.logStatus)}${_folder(state.logDirectory, state.logDirectoryDetected)}',
          ),
          if (state.logMessage != null) Text(state.logMessage!),
          Text(_raidLine(services.raidLifecycle.state)),
          if (state.raidLogsMessage != null)
            Text('Raid logs: ${state.raidLogsMessage}'),
          Text(
            'Screenshots: ${mapInputStatusLabel(state.screenshotStatus)}${_folder(state.screenshotDirectory, state.screenshotDirectoryDetected)}',
          ),
          if (state.screenshotMessage != null) Text(state.screenshotMessage!),
          if (pending) ...[
            const Text(
              'Processing saved screenshot; retained highlights are not validated by the pending file.',
            ),
            if (state.pendingScreenshotPath != null)
              Text('Pending source: ${state.pendingScreenshotPath}'),
          ],
          if (state.savedScreenshotPath != null) ...[
            Text('Saved evidence source: ${state.savedScreenshotPath}'),
            if (savedModifiedAt != null)
              Text(
                'File modified: ${localTimeLabel(savedModifiedAt, now: DateTime.now())}',
              ),
            if (age != null)
              Text(
                age.isNegative
                    ? 'Saved file timestamp is in the future; freshness is uncertain.'
                    : 'Saved evidence age: ${age.inSeconds}s · not live tracking',
              ),
            Text(
              state.assumedAssociation
                  ? 'Assumed saved evidence for the selected map; not confirmed raid association.'
                  : 'Associated with detected saved-log session.',
            ),
          ],
          if (sample == null)
            const Text('No sampled player position')
          else ...[
            Text(
              'Filename sample: ${localTimeLabel(sample.metadata.savedAt, now: DateTime.now())}',
            ),
            Text(
              'X ${sample.metadata.position.x} · Z ${sample.metadata.position.z} · height ${sample.metadata.position.height ?? 'unknown'}',
            ),
          ],
          if (state.raidEvidence != null) ...[
            Text(
              '${pending || inputUnavailable ? 'Previous raid panel' : 'Raid panel'}: ${raidPanelStateLabel(state.raidEvidence!.state)}',
            ),
            if (state.raidEvidence!.message != null)
              Text(state.raidEvidence!.message!),
            if (retainedEvidence)
              Text(
                state.raidHighlightIds.isEmpty
                    ? 'No raid highlights from the latest completed panel read.'
                    : '${state.raidHighlightIds.length} previous raid highlights retained; the latest screenshot has not confirmed them.',
              ),
            if (!retainedEvidence)
              Text(
                '${state.raidHighlightIds.length} matched exits from the completed panel evidence.',
              ),
          ],
        ],
      );
    },
  );
}

/// The "Raid:" line: the phase in plain words, the map while a raid is being
/// entered, under way or just ended, and a note after a cancelled queue.
String _raidLine(RaidLifecycleState state) {
  final label = raidPhaseLabel(state.phase);
  final mapId = switch (state.phase) {
    RaidPhase.raidStarting => state.pendingMapId ?? state.currentRaid?.mapId,
    RaidPhase.inRaid || RaidPhase.raidEnded => state.raid?.mapId,
    RaidPhase.unknown ||
    RaidPhase.inMenus ||
    RaidPhase.inQueue ||
    RaidPhase.matchFound => null,
  };
  final onMap = mapId == null ? '' : ' on ${mapLabel(mapId)}';
  final cancelled = state.phase == RaidPhase.inMenus && state.lastQueueAborted
      ? ' (matching cancelled)'
      : '';
  return 'Raid: $label$onMap$cancelled';
}

String _folder(String path, bool detected) =>
    path.isEmpty ? '' : ' · $path${detected ? ' (auto-detected)' : ''}';
