import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/live_map_data_controller.dart';
import '../application/app_version.dart' as app_version;
import '../domain/catalog.dart';
import '../domain/raid_timers.dart';
import '../domain/settings.dart';
import 'labels.dart';
import 'live_map_status.dart';
import 'live_scan_panel.dart';
import 'panels.dart';
import 'ember/theme_access.dart';
import 'settings/commit_field.dart';
import 'settings/raid_timer_input.dart';
import 'settings/settings_diagnostics_body.dart';
import 'settings/settings_section.dart';

/// Opens Settings and optionally brings one section into view and focus.
Future<void> showSettings(
  BuildContext context,
  AppServices services, {
  SettingsSection? section,
}) => showDialog<void>(
  context: context,
  builder: (context) => SettingsDialog(services: services, section: section),
);

/// Existing Settings dialog, optionally opened at [section].
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.services,
    this.version = app_version.appVersion,
    this.section,
  });
  final AppServices services;
  final String version;

  /// The section focused once after the dialog opens.
  final SettingsSection? section;
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final token = TextEditingController();
  final _sectionKeys = {
    for (final section in SettingsSection.values) section: GlobalKey(),
  };
  final _sectionFocus = {
    for (final section in SettingsSection.values) section: FocusNode(),
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.section == null) return;
      final section = widget.section!;
      final target = _sectionKeys[section]!.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target, alignment: 0.05);
        _sectionFocus[section]!.requestFocus();
      }
    });
  }

  late final gameLogs = TextEditingController(
    text: widget.services.settings.settings.gameLogDirectory,
  );
  late final screenshots = TextEditingController(
    text: widget.services.settings.settings.screenshotDirectory,
  );
  bool busy = false;
  String? message;

  /// Whether Diagnostics is expanded. It is dialog state, so each opening of
  /// Settings starts collapsed.
  bool _diagnosticsExpanded = false;
  @override
  void dispose() {
    for (final focus in _sectionFocus.values) {
      focus.dispose();
    }
    token.clear();
    token.dispose();
    gameLogs.dispose();
    screenshots.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() work, String success) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work();
      if (!mounted) return;
      token.clear();
      setState(() => message = widget.services.progress.error ?? success);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Tracker token operation failed. Nothing was stored as plain text.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// The "Raid timers" section: the on/off switch, the three show checkboxes,
  /// the run-through length and the active mode's Fence reputation.
  ///
  /// The two text fields save on the keyboard's done action and when they lose
  /// focus; a value outside its range is refused with a message and the saved
  /// value stays.
  List<Widget> _raidTimerSection(BuildContext context) {
    final services = widget.services;
    final timers = services.settings.raidTimers;
    final mode = services.catalog.mode;
    final idle = !services.settings.busy;
    void save(RaidTimerSettings next) =>
        unawaited(services.settings.setRaidTimers(next));
    CheckboxListTile show(
      String title,
      bool value,
      RaidTimerSettings Function(bool) change,
    ) => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Text(title),
      value: value,
      onChanged: idle ? (v) => save(change(v ?? false)) : null,
    );
    return [
      Text('Raid timers', style: Theme.of(context).textTheme.titleMedium),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show raid timers'),
        subtitle: const Text(
          'A strip under the header with the time in raid, the run-through countdown and the scav cooldown. It is computed from the game logs and never touches the game.',
        ),
        value: timers.enabled,
        onChanged: idle ? (v) => save(timers.copyWith(enabled: v)) : null,
      ),
      show(
        'Time in raid',
        timers.showTimeInRaid,
        (v) => timers.copyWith(showTimeInRaid: v),
      ),
      show(
        'Run-through',
        timers.showRunThrough,
        (v) => timers.copyWith(showRunThrough: v),
      ),
      show(
        'Scav cooldown',
        timers.showScavCooldown,
        (v) => timers.copyWith(showScavCooldown: v),
      ),
      const SizedBox(height: 12),
      CommitField(
        label: 'Run-through length (m:ss)',
        helper: 'From 1:00 to 30:00.',
        value: formatTimerSeconds(timers.runThroughSeconds),
        onCommit: (text) async {
          final seconds = parseRunThrough(text);
          if (seconds == null) return runThroughMessage;
          final saved = await services.settings.setRaidTimers(
            services.settings.raidTimers.copyWith(runThroughSeconds: seconds),
          );
          return saved ? null : notSavedMessage;
        },
      ),
      const SizedBox(height: 12),
      CommitField(
        label: 'Fence reputation',
        helper: mode == GameMode.unknown
            ? null
            : 'For ${modeLabel(mode)}, with two decimals. Used for the scav cooldown.',
        value: timers.fenceReputationFor(mode).toStringAsFixed(2),
        enabled: mode != GameMode.unknown,
        onCommit: (text) async {
          final value = parseReputation(text);
          if (value == null) return reputationMessage;
          final saved = await services.settings.setFenceReputation(mode, value);
          return saved ? null : notSavedMessage;
        },
      ),
      if (mode == GameMode.unknown)
        Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Choose a game mode first.',
            style: TextStyle(color: context.ember.inkSecondary),
          ),
        ),
      const Divider(height: 28),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.services.settings,
      widget.services.catalog,
      widget.services.progress,
      widget.services.mapData,
    ]),
    builder: (context, _) {
      final services = widget.services;
      final known = services.catalog.mode != GameMode.unknown;
      return AlertDialog(
        title: const Text('Settings'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SegmentedButton<ThemeChoice>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeChoice.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(value: ThemeChoice.dark, label: Text('Dark')),
                    ButtonSegment(
                      value: ThemeChoice.light,
                      label: Text('Light'),
                    ),
                  ],
                  selected: {services.settings.settings.themeMode},
                  onSelectionChanged: (choice) {
                    final next = choice.single;
                    if (next == services.settings.settings.themeMode) return;
                    unawaited(services.settings.setThemeChoice(next));
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'System follows the Windows light or dark setting.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                Text(
                  'Version ${widget.version}',
                  style: TextStyle(color: context.ember.inkSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  'The game mode below is used when the game logs do not say which mode you are playing. Blackgrid only reads saved files and never interacts with the game.',
                  style: TextStyle(color: context.ember.inkSecondary),
                ),
                const SizedBox(height: 18),
                Focus(
                  key: _sectionKeys[SettingsSection.general],
                  focusNode: _sectionFocus[SettingsSection.general],
                  child: DropdownButtonFormField<GameMode>(
                    key: ValueKey(services.catalog.mode),
                    initialValue: services.catalog.mode,
                    decoration: const InputDecoration(labelText: 'Game mode'),
                    items: GameMode.values
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(modeLabel(m)),
                          ),
                        )
                        .toList(),
                    onChanged: busy || services.settings.busy
                        ? null
                        : (m) {
                            if (m != null) services.setMode(m);
                          },
                  ),
                ),
                const SizedBox(height: 14),
                Focus(
                  key: _sectionKeys[SettingsSection.itemData],
                  focusNode: _sectionFocus[SettingsSection.itemData],
                  child: Column(
                    key: const Key('settings-item-data'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: known && !services.catalog.loading
                            ? services.catalog.refresh
                            : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh item data'),
                      ),
                      Text(
                        'Item data: ${catalogStatusLabel(services.catalog.status)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Map data',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                LiveMapStatus(
                  mode: services.mapData.state.mode,
                  dataMode: services.mapData.state.dataMode,
                  source: services.mapData.state.source,
                  checkedAt: services.mapData.state.checkedAt,
                  failure: services.mapData.state.failure,
                  refreshing: services.mapData.state.refreshing,
                  onRefresh:
                      services.mapData.state.refreshing ||
                          services.mapData.state.mode == GameMode.unknown ||
                          services.mapData.state.source ==
                              LiveMapDataSource.unavailable
                      ? null
                      : services.mapData.refresh,
                ),
                const Divider(height: 28),
                Text(
                  'Map files',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: gameLogs,
                  enabled: !services.settings.busy,
                  decoration: const InputDecoration(
                    labelText: 'Game log folder',
                    helperText: "Leave empty to find the game's Logs folder automatically. Logs are watched even when Follow logs is off.",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: screenshots,
                  enabled: !services.settings.busy,
                  decoration: const InputDecoration(
                    labelText: 'Screenshot folder',
                    helperText: r'Leave empty to use Documents\Escape from Tarkov\Screenshots.',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: services.settings.busy
                      ? null
                      : () => services.settings.setMapInputs(
                          gameLogDirectory: gameLogs.text.trim(),
                          screenshotDirectory: screenshots.text.trim(),
                        ),
                  child: Text(
                    services.settings.busy
                        ? 'Saving map files…'
                        : 'Save map files',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Follow logs'),
                  subtitle: const Text(
                    'Use the map found in the game logs when there is one. Choosing a map yourself turns this off; the logs are still watched.',
                  ),
                  value: services.settings.settings.followGameLogs,
                  onChanged: services.settings.busy
                      ? null
                      : (value) => services.settings.setMapInputs(
                          followGameLogs: value,
                        ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Save marker filters'),
                  subtitle: const Text(
                    'Keep which marker types are shown the next time Blackgrid starts.',
                  ),
                  value: services.settings.settings.saveMarkerFilters,
                  onChanged: services.settings.busy
                      ? null
                      : (value) => services.settings.save(
                          services.settings.settings.copyWith(
                            saveMarkerFilters: value,
                          ),
                        ),
                ),
                const Divider(height: 28),
                ..._raidTimerSection(context),
                Focus(
                  key: _sectionKeys[SettingsSection.liveScan],
                  focusNode: _sectionFocus[SettingsSection.liveScan],
                  child: Column(
                    key: const Key('settings-live-scan'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LiveScanPanel(
                        scanner: services.scanner,
                        timingLog: services.scanTimingLog,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 28),
                Focus(
                  key: _sectionKeys[SettingsSection.tracker],
                  focusNode: _sectionFocus[SettingsSection.tracker],
                  child: Column(
                    key: const Key('settings-tracker'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use Tracker progress'),
                        subtitle: const Text(
                          'Blackgrid only reads your progress. Your token needs the GP permission.',
                        ),
                        value: services.settings.settings.trackerEnabled,
                        onChanged: busy
                            ? null
                            : (value) async {
                                final success = await services.settings.save(
                                  services.settings.settings.copyWith(
                                    trackerEnabled: value,
                                  ),
                                );
                                if (success && !value) {
                                  await services.progress.setMode(
                                    services.catalog.mode,
                                  );
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tracker token: ${services.progress.hasCredential ? 'saved for ${modeLabel(services.progress.mode)}' : 'not saved'}',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: token,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Tracker token (current game mode)',
                          helperText: 'Starts with PVP_, PVE_ or SZN_. It is never imported or kept in the database.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: busy || !known
                                ? null
                                : () => action(
                                    () => services.progress.saveCredential(
                                      token.text.trim(),
                                    ),
                                    'Tracker token saved',
                                  ),
                            child: const Text('Save token'),
                          ),
                          OutlinedButton(
                            onPressed:
                                busy ||
                                    !known ||
                                    !services.progress.hasCredential
                                ? null
                                : () => action(
                                    services.progress.removeCredential,
                                    'Token removed',
                                  ),
                            child: const Text('Remove token'),
                          ),
                          OutlinedButton(
                            onPressed:
                                busy ||
                                    !services.progress.hasCredential ||
                                    !services.settings.settings.trackerEnabled
                                ? null
                                : () => action(
                                    services.progress.refresh,
                                    'Progress refreshed',
                                  ),
                            child: const Text('Refresh progress'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message ??
                            services.progress.error ??
                            'Progress: ${progressStatusLabel(services.progress.status)}',
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your Tracker token is stored encrypted for your Windows account. Your progress is kept only while Blackgrid is open, so refresh it after a restart.',
                        style: TextStyle(color: context.ember.inkSecondary),
                      ),
                    ],
                  ),
                ),
                if (services.settings.error != null)
                  Text(
                    services.settings.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (services.settings.loadNotice != null)
                  Text(
                    services.settings.loadNotice!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 18),
                CollapsibleGridPanel(
                  title: 'Diagnostics',
                  icon: Icons.folder_open_outlined,
                  expanded: _diagnosticsExpanded,
                  onExpandedChanged: (value) =>
                      setState(() => _diagnosticsExpanded = value),
                  toggleKey: const Key('settings-diagnostics-toggle'),
                  child: SettingsDiagnosticsBody(services: services),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
