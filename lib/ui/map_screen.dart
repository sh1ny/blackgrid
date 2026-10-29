import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/catalog.dart';
import '../domain/map_coordinates.dart';
import '../domain/map_session.dart';
import '../domain/marker_categories.dart';
import '../domain/raid_panel_text_parser.dart';
import '../domain/settings.dart';
import 'item_decision_card.dart';
import 'manual_controls.dart';
import 'map_workspace.dart';
import 'marker_preferences.dart';
import 'pin_editor.dart';
import 'theme.dart';

class _MapInputStatus extends StatefulWidget {
  const _MapInputStatus({super.key, required this.services});
  final AppServices services;
  @override
  State<_MapInputStatus> createState() => _MapInputStatusState();
}

class _MapInputStatusState extends State<_MapInputStatus> {
  Timer? _ageTimer;
  @override
  void initState() {
    super.initState();
    widget.services.mapSession.addListener(_syncAgeTimer);
    _syncAgeTimer();
  }

  @override
  void didUpdateWidget(_MapInputStatus oldWidget) {
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
            'Logs: ${state.logStatus.name}${_folder(state.logDirectory, state.logDirectoryDetected)}',
          ),
          if (state.logMessage != null) Text(state.logMessage!),
          Text(
            'Screenshots: ${state.screenshotStatus.name}${_folder(state.screenshotDirectory, state.screenshotDirectoryDetected)}',
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
                'File modified: ${savedModifiedAt.toUtc().toIso8601String()}',
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
              'Filename sample: ${sample.metadata.savedAt.toUtc().toIso8601String()}',
            ),
            Text(
              'X ${sample.metadata.position.x} · Z ${sample.metadata.position.z} · height ${sample.metadata.position.height ?? 'unknown'}',
            ),
          ],
          if (state.raidEvidence != null) ...[
            Text(
              '${pending || inputUnavailable ? 'Previous raid panel' : 'Raid panel'}: ${state.raidEvidence!.state.name}',
            ),
            if (state.raidEvidence!.message != null)
              Text(state.raidEvidence!.message!),
            if (retainedEvidence)
              Text(
                state.raidHighlightIds.isEmpty
                    ? 'No raid highlights authorized by the latest completed panel evidence.'
                    : '${state.raidHighlightIds.length} previous raid highlights retained; the latest screenshot has not confirmed them.',
              ),
            if (!retainedEvidence)
              Text(
                '${state.raidHighlightIds.length} matched exits from the completed panel evidence.',
              ),
          ],
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Follow logs'),
            subtitle: const Text(
              'Map selection only; configured logs continue to be monitored.',
            ),
            value: state.followGameLogs,
            onChanged: services.settings.busy
                ? null
                : (value) =>
                      services.settings.setMapInputs(followGameLogs: value),
          ),
          OutlinedButton.icon(
            onPressed: state.readingLatest || state.screenshotDirectory.isEmpty
                ? null
                : services.mapSession.readLatest,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(
              state.readingLatest ? 'Reading latest…' : 'Read Latest',
            ),
          ),
        ],
      );
    },
  );
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  AppServices get services => widget.services;

  /// Whether Map saved-file inputs is expanded. It lives above the
  /// [LayoutBuilder] so it survives layout changes and tab switches, and it
  /// is deliberately not persisted: every launch starts collapsed.
  bool _inputsExpanded = false;

  Future<void> _showPins(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ListenableBuilder(
      listenable: Listenable.merge([services.settings, services.maps]),
      builder: (context, _) {
        final map =
            services.maps.selectedMapId ??
            services.settings.settings.selectedMap;
        final records = services.settings.pins
            .where((p) => p.mapId == map)
            .toList();
        return SizedBox(
          height: 450,
          child: Column(
            children: [
              if (services.settings.busy) const LinearProgressIndicator(),
              if (services.settings.error != null)
                Text(
                  services.settings.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Expanded(
                child: records.isEmpty
                    ? const Center(child: Text('No saved pins for this map'))
                    : ListView.builder(
                        itemCount: records.length,
                        itemBuilder: (context, index) {
                          final pin = records[index];
                          return ListTile(
                            title: Text(pin.label),
                            subtitle: Text(
                              'X ${pin.x} • Y ${pin.y}\n${pin.frame} • revision ${pin.frameRevision}',
                            ),
                            onTap: services.settings.busy
                                ? null
                                : () => showPinEditor(
                                    context,
                                    services,
                                    pin: pin,
                                  ),
                            trailing: IconButton(
                              tooltip: 'Remove pin ${pin.label}',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: services.settings.busy
                                  ? null
                                  : () async {
                                      final remove = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text(
                                            'Remove pin record?',
                                          ),
                                          content: Text(
                                            '${pin.label} • ${mapLabel(pin.mapId)}',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Remove'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (remove == true) {
                                        await services.settings.removePin(pin);
                                      }
                                    },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([services.settings, services.maps]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final map =
            services.maps.selectedMapId ??
            services.settings.settings.selectedMap;
        final categories = markerPreferenceKeys(
          services.maps.applicableCategories,
        );
        final pins = services.settings.pins
            .where((p) => p.mapId == map)
            .toList();
        final workspace = GridPanel(
          title: mapLabel(map).toUpperCase(),
          icon: Icons.map_outlined,
          subtitle:
              'Native local artwork • durable pins • offline map capability',
          trailing: OutlinedButton.icon(
            onPressed: services.settings.busy
                ? null
                : () => showPinEditor(
                    context,
                    services,
                    coordinates: MapPinCoordinates(
                      mapId: map,
                      point: ArtworkPoint(.5, .5),
                      frame: map == 'thelab'
                          ? MapCoordinateFrame.labsNativeNormalized
                          : MapCoordinateFrame.legacyNormalized,
                    ),
                  ),
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('Add pin'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(height: 1),
              const SizedBox(height: 10),
              Expanded(child: MapWorkspace(services: services)),
              if (services.settings.error != null)
                Text(
                  services.settings.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              TextButton.icon(
                icon: const Icon(Icons.location_on_outlined),
                label: Text('${pins.length} saved pin records'),
                onPressed: () => _showPins(context),
              ),
            ],
          ),
        );
        final rail = ListView(
          key: const PageStorageKey('map-rail-scroll'),
          children: [
            SizedBox(
              height: 145 * scale,
              child: GridPanel(
                title: 'Active map',
                icon: Icons.map_outlined,
                child: DropdownButtonFormField<String>(
                  // Shows the displayed map, including a log-detected one.
                  key: ValueKey(map),
                  initialValue: map,
                  isExpanded: true,
                  items: supportedMaps
                      .map(
                        (id) => DropdownMenuItem(
                          value: id,
                          child: Text(mapLabel(id)),
                        ),
                      )
                      .toList(),
                  onChanged: services.settings.busy
                      ? null
                      : (id) {
                          if (id != null) services.settings.setMap(id);
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300 * scale,
              child: ItemDecisionCard(services: services, compact: true),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 430 * scale,
              child: GridPanel(
                title: 'Marker preferences',
                icon: Icons.filter_alt_outlined,
                subtitle: 'Shared drawing and selection visibility',
                child: ListView(
                  children: [
                    TextFormField(
                      key: const ValueKey('marker-search'),
                      initialValue: services.maps.search,
                      decoration: const InputDecoration(
                        labelText: 'Search map markers',
                        hintText: 'door, tunnel',
                        helperText: 'Comma-separated OR terms dim nonmatches; dimmed markers remain selectable.',
                      ),
                      onChanged: services.maps.setSearch,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: services.maps.questName,
                      decoration: const InputDecoration(
                        labelText: 'Quest name contains',
                      ),
                      onChanged: (value) =>
                          services.maps.setQuestFilters(name: value),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: services.maps.questTrader,
                      decoration: const InputDecoration(
                        labelText: 'Quest trader',
                        helperText: 'Exact trader name, or all',
                      ),
                      onChanged: (value) =>
                          services.maps.setQuestFilters(trader: value),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final action in [
                          (label: 'Show all', value: true),
                          (label: 'Hide all', value: false),
                        ])
                          TextButton(
                            onPressed: services.settings.busy
                                ? null
                                : () => services.settings.save(
                                    services.settings.settings.copyWith(
                                      markerFilters: {
                                        ...services
                                            .settings
                                            .settings
                                            .markerFilters,
                                        for (final key in categories)
                                          key: action.value,
                                      },
                                    ),
                                  ),
                            child: Text(action.label),
                          ),
                      ],
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Save marker filters'),
                      value: services.settings.settings.saveMarkerFilters,
                      onChanged: services.settings.busy
                          ? null
                          : (value) => services.settings.save(
                              services.settings.settings.copyWith(
                                saveMarkerFilters: value,
                              ),
                            ),
                    ),
                    MarkerPreferencesGrid(
                      services: services,
                      keys: categories,
                      scale: scale,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 650 * scale,
              child: GridPanel(
                title: 'Manual item search',
                icon: Icons.search,
                child: ManualControls(
                  services: services,
                  storageKey: 'map-results',
                ),
              ),
            ),
            const SizedBox(height: 12),
            CollapsibleGridPanel(
              title: 'Map saved-file inputs',
              icon: Icons.folder_open_outlined,
              expanded: _inputsExpanded,
              onExpandedChanged: (value) =>
                  setState(() => _inputsExpanded = value),
              toggleKey: const Key('map-inputs-toggle'),
              child: _MapInputStatus(
                key: const Key('map-input-status'),
                services: services,
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 1100) {
          return ListView(
            key: const PageStorageKey('map-compact-scroll'),
            children: [
              SizedBox(height: 650 * scale, child: workspace),
              const SizedBox(height: 14),
              SizedBox(height: 800 * scale, child: rail),
            ],
          );
        }
        return SingleChildScrollView(
          child: SizedBox(
            height: math.max(constraints.maxHeight, 620 * scale),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 70, child: workspace),
                const SizedBox(width: 14),
                Expanded(flex: 30, child: rail),
              ],
            ),
          ),
        );
      },
    ),
  );
}

String _folder(String path, bool detected) =>
    path.isEmpty ? '' : ' · $path${detected ? ' (auto-detected)' : ''}';
