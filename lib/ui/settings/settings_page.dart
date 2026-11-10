import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/app_version.dart' as app_version;
import '../../application/live_map_data_controller.dart';
import '../../domain/catalog.dart';
import '../../domain/raid_timers.dart';
import '../../domain/settings.dart';
import '../ember/ember_tokens.dart';
import '../ember/theme_access.dart';
import '../labels.dart';
import '../panels.dart';
import 'commit_field.dart';
import 'live_scan_settings.dart';
import 'raid_timer_input.dart';
import 'settings_diagnostics_body.dart';
import 'settings_row.dart';
import 'settings_section.dart';

/// The Settings page: a sidebar of sections beside one scrolling column of
/// rows.
///
/// Every setting saves as it is changed, with no Save button; only the Tracker
/// token saves on its own button. Text fields save on Enter, and when they lose
/// focus. A section that a link names is scrolled into view and its title takes
/// keyboard focus. The page keeps only view state: which sections are expanded
/// and what the player has typed. Saved settings belong to
/// [AppServices.settings].
class SettingsPage extends StatefulWidget {
  /// Creates the page over [services].
  ///
  /// [backLabel] names the area Back returns to, and [onBack] closes the page.
  /// While [section] is not `null`, the page scrolls to that section and
  /// focuses its title on mount and whenever [request] or [section] changes, so
  /// asking again for the same section with a higher [request] scrolls again.
  /// Without a section, the page title takes focus on mount. [flush] commits
  /// pending text edits for a caller that is about to unmount the page.
  const SettingsPage({
    super.key,
    required this.services,
    required this.backLabel,
    required this.onBack,
    required this.flush,
    this.section,
    this.request = 0,
    this.version = app_version.appVersion,
  });

  /// The services the sections read and change.
  final AppServices services;

  /// The label of the Back button, such as "Back to Map".
  final String backLabel;

  /// Called when the Back button is pressed.
  final VoidCallback onBack;

  /// The controller that commits every pending text edit on the page.
  final SettingsFlushController flush;

  /// The section to scroll into view and focus, or `null` for none.
  final SettingsSection? section;

  /// The number of the latest request for [section].
  final int request;

  /// The app version shown in General.
  final String version;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _tokenText = TextEditingController();
  final _titleKeys = {
    for (final section in SettingsSection.values) section: GlobalKey(),
  };
  final _titleFocus = {
    for (final section in SettingsSection.values) section: FocusNode(),
  };
  final _pageTitleFocus = FocusNode();

  /// Whether Diagnostics is expanded. It is page state, so each mount starts
  /// collapsed.
  bool _diagnosticsExpanded = false;

  /// Whether a token action is running.
  bool _tokenBusy = false;

  /// The result line of the last token action.
  String? _tokenMessage;

  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _target();
  }

  @override
  void didUpdateWidget(SettingsPage old) {
    super.didUpdateWidget(old);
    if (old.request != widget.request || old.section != widget.section) {
      _target();
    }
  }

  @override
  void dispose() {
    for (final focus in _titleFocus.values) {
      focus.dispose();
    }
    _pageTitleFocus.dispose();
    _tokenText.clear();
    _tokenText.dispose();
    super.dispose();
  }

  /// Brings the requested section into view, or focuses the page title when
  /// there is none.
  void _target() {
    final section = widget.section;
    if (section == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pageTitleFocus.requestFocus();
      });
      return;
    }
    _reveal(section);
  }

  /// Scrolls [section] into view and moves focus to its title after the next
  /// frame. Diagnostics is expanded first. A section whose title is not built
  /// leaves the page where it is.
  ///
  /// It changes view state without rebuilding, so call it from a lifecycle
  /// method or inside [setState].
  void _reveal(SettingsSection section) {
    if (section == SettingsSection.diagnostics) _diagnosticsExpanded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _titleKeys[section]!.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(target);
      _titleFocus[section]!.requestFocus();
    });
  }

  Future<void> _tokenAction(
    Future<void> Function() work,
    String success,
  ) async {
    setState(() {
      _tokenBusy = true;
      _tokenMessage = null;
    });
    try {
      await work();
      if (!mounted) return;
      _tokenText.clear();
      setState(() => _tokenMessage = _services.progress.error ?? success);
    } catch (_) {
      if (!mounted) return;
      _tokenText.clear();
      setState(
        () => _tokenMessage =
            'Tracker token operation failed. Nothing was stored as plain text.',
      );
    } finally {
      if (mounted) setState(() => _tokenBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    return SettingsFlushScope(
      controller: widget.flush,
      child: Material(
        color: ember.canvas,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sidebar(context),
            Expanded(
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    key: const Key('settings-column'),
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: EmberSpace.xl,
                        vertical: EmberSpace.xxl,
                      ),
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          _services.settings,
                          _services.catalog,
                          _services.progress,
                          _services.mapData,
                        ]),
                        builder: (context, _) => _column(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(BuildContext context) {
    final ember = context.ember;
    return Container(
      key: const Key('settings-sidebar'),
      width: EmberSize.sidebar,
      padding: const EdgeInsets.all(EmberSpace.md),
      decoration: BoxDecoration(
        color: ember.panel,
        border: Border(right: BorderSide(color: ember.hairline)),
      ),
      child: ListView(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: EmberSize.icon),
              label: Text(widget.backLabel),
            ),
          ),
          const SizedBox(height: EmberSpace.sm),
          for (final section in SettingsSection.values)
            InkWell(
              key: Key('settings-nav-${section.name}'),
              borderRadius: BorderRadius.circular(EmberRadius.s),
              onTap: () => setState(() => _reveal(section)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: EmberSpace.md,
                  vertical: EmberSpace.sm,
                ),
                child: Text(
                  section.title,
                  style: EmberType.control.copyWith(color: ember.inkSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _column(BuildContext context) {
    final ember = context.ember;
    final settings = _services.settings;
    final problem = TextStyle(
      fontFamily: EmberType.body.fontFamily,
      fontSize: EmberType.body.fontSize,
      color: ember.errInk,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          focusNode: _pageTitleFocus,
          child: Semantics(
            header: true,
            child: Text(
              'Settings',
              key: const Key('settings-page-title'),
              style: EmberType.display.copyWith(color: ember.ink),
            ),
          ),
        ),
        if (settings.loadNotice case final notice?)
          Padding(
            key: const ValueKey('settings-load-notice-row'),
            padding: const EdgeInsets.only(top: EmberSpace.md),
            child: Text(
              notice,
              key: const Key('settings-load-notice'),
              style: problem,
            ),
          ),
        if (settings.error case final error?)
          Padding(
            key: const ValueKey('settings-error-row'),
            padding: const EdgeInsets.only(top: EmberSpace.md),
            child: Text(
              error,
              key: const Key('settings-error'),
              style: problem,
            ),
          ),
        _section(context, SettingsSection.general, _general(context)),
        _section(context, SettingsSection.liveScan, [
          LiveScanSettings(
            scanner: _services.scanner,
            timingLog: _services.scanTimingLog,
          ),
        ], contentKey: const Key('settings-live-scan')),
        _section(
          context,
          SettingsSection.itemData,
          _itemAndMapData(context),
          contentKey: const Key('settings-item-data'),
        ),
        _section(
          context,
          SettingsSection.tracker,
          _tracker(context),
          contentKey: const Key('settings-tracker'),
        ),
        _section(context, SettingsSection.gameFiles, _gameFiles()),
        _section(context, SettingsSection.raidTimers, _raidTimers(context)),
        _section(context, SettingsSection.map, _map()),
        _section(context, SettingsSection.diagnostics, [
          CollapsibleGridPanel(
            title: 'Technical detail',
            icon: Icons.folder_open_outlined,
            expanded: _diagnosticsExpanded,
            onExpandedChanged: (value) =>
                setState(() => _diagnosticsExpanded = value),
            toggleKey: const Key('settings-diagnostics-toggle'),
            child: SettingsDiagnosticsBody(services: _services),
          ),
        ]),
      ],
    );
  }

  /// A titled section. Its title is the target of links and of the sidebar.
  Widget _section(
    BuildContext context,
    SettingsSection section,
    List<Widget> rows, {
    Key? contentKey,
  }) {
    final ember = context.ember;
    // A key per section keeps its fields when a notice or an error above it
    // appears or goes, which would otherwise shift every section by one.
    return Padding(
      key: ValueKey('settings-section-${section.name}'),
      padding: const EdgeInsets.only(top: EmberSpace.xxl),
      child: Column(
        key: contentKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            key: _titleKeys[section],
            focusNode: _titleFocus[section],
            child: Semantics(
              header: true,
              child: Text(
                section.title,
                key: Key('settings-title-${section.name}'),
                style: EmberType.title.copyWith(color: ember.ink),
              ),
            ),
          ),
          const SizedBox(height: EmberSpace.sm),
          ...rows,
        ],
      ),
    );
  }

  List<Widget> _general(BuildContext context) {
    final settings = _services.settings;
    final mode = _services.catalog.mode;
    return [
      SettingsRow(
        name: 'Theme',
        explanation: 'System follows the Windows light or dark setting.',
        trailing: SegmentedButton<ThemeChoice>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ThemeChoice.system, label: Text('System')),
            ButtonSegment(value: ThemeChoice.dark, label: Text('Dark')),
            ButtonSegment(value: ThemeChoice.light, label: Text('Light')),
          ],
          selected: {settings.settings.themeMode},
          onSelectionChanged: (choice) {
            final next = choice.single;
            if (next == settings.settings.themeMode) return;
            unawaited(settings.setThemeChoice(next));
          },
        ),
      ),
      SettingsRow(
        name: 'Game mode',
        explanation: 'Used when the game logs do not say which mode you play.',
        trailing: SegmentedButton<GameMode>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: [
            for (final value in [GameMode.pvp, GameMode.pve, GameMode.seasonal])
              ButtonSegment(value: value, label: Text(modeLabel(value))),
          ],
          selected: mode == GameMode.unknown ? const {} : {mode},
          onSelectionChanged: settings.busy
              ? null
              : (choice) {
                  // Pressing the chosen mode again would empty the selection.
                  if (choice.length == 1 && choice.single != mode) {
                    unawaited(_services.setMode(choice.single));
                  }
                },
        ),
      ),
      SettingsRow(
        name: 'Version',
        explanation: 'The version of Blackgrid you are running.',
        trailing: Text(
          widget.version,
          style: EmberType.body.copyWith(color: context.ember.ink),
        ),
      ),
    ];
  }

  List<Widget> _itemAndMapData(BuildContext context) {
    final catalog = _services.catalog;
    final map = _services.mapData;
    final state = map.state;
    final known = catalog.mode != GameMode.unknown;
    final mapLine = switch (state) {
      _ when state.mode == GameMode.unknown => 'Choose a game mode first.',
      LiveMapDataState(refreshing: true) => 'Refreshing map data…',
      LiveMapDataState(source: LiveMapDataSource.unavailable) =>
        'No map data is available.',
      LiveMapDataState(checkedAt: null) => 'Not checked yet.',
      LiveMapDataState(:final checkedAt?) =>
        'Checked ${checkedTimeLabel(checkedAt, now: DateTime.now())}.',
    };
    return [
      SettingsRow(
        name: 'Item data',
        explanation: _sentence(catalogStatusLabel(catalog.status)),
        trailing: OutlinedButton(
          onPressed: known && !catalog.loading ? catalog.refresh : null,
          child: const Text('Refresh item data'),
        ),
      ),
      SettingsRow(
        name: 'Map data',
        explanation: mapLine,
        message:
            state.failure != null &&
                state.source != LiveMapDataSource.unavailable
            ? 'Map data refresh failed. The map keeps the data it had.'
            : null,
        trailing: OutlinedButton(
          onPressed:
              state.refreshing ||
                  state.mode == GameMode.unknown ||
                  state.source == LiveMapDataSource.unavailable
              ? null
              : map.refresh,
          child: Text(
            state.refreshing ? 'Refreshing map data…' : 'Refresh map data',
          ),
        ),
      ),
    ];
  }

  List<Widget> _tracker(BuildContext context) {
    final services = _services;
    final settings = services.settings;
    final progress = services.progress;
    final known = services.catalog.mode != GameMode.unknown;
    final idle = !settings.busy;
    return [
      SettingsRow.toggle(
        name: 'Use Tracker progress',
        explanation: 'Blackgrid only reads your progress. Your token needs the GP permission.',
        value: settings.settings.trackerEnabled,
        enabled: idle && !_tokenBusy,
        onChanged: (value) => unawaited(() async {
          final saved = await settings.save(
            settings.settings.copyWith(trackerEnabled: value),
          );
          if (saved && !value) await progress.setMode(services.catalog.mode);
        }()),
      ),
      SettingsRow(
        name: 'Tracker token',
        explanation: progress.hasCredential
            ? 'Saved for ${modeLabel(progress.mode)}'
            : 'Not saved',
        trailing: const SizedBox.shrink(),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: EmberSpace.md),
        child: TextField(
          controller: _tokenText,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Tracker token (current game mode)',
            helperText: 'Starts with PVP_, PVE_ or SZN_. It is never imported or kept in the database.',
          ),
        ),
      ),
      Wrap(
        spacing: EmberSpace.sm,
        runSpacing: EmberSpace.sm,
        children: [
          FilledButton(
            onPressed: _tokenBusy || !known
                ? null
                : () => unawaited(
                    _tokenAction(
                      () => progress.saveCredential(_tokenText.text.trim()),
                      'Tracker token saved',
                    ),
                  ),
            child: const Text('Save token'),
          ),
          OutlinedButton(
            onPressed: _tokenBusy || !known || !progress.hasCredential
                ? null
                : () => unawaited(
                    _tokenAction(progress.removeCredential, 'Token removed'),
                  ),
            child: const Text('Remove token'),
          ),
          OutlinedButton(
            onPressed:
                _tokenBusy ||
                    !progress.hasCredential ||
                    !settings.settings.trackerEnabled
                ? null
                : () => unawaited(
                    _tokenAction(progress.refresh, 'Progress refreshed'),
                  ),
            child: const Text('Refresh progress'),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: EmberSpace.md),
        child: Text(
          _tokenMessage ??
              progress.error ??
              'Progress: ${progressStatusLabel(progress.status)}',
          style: EmberType.label.copyWith(color: context.ember.inkTertiary),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: EmberSpace.sm),
        child: Text(
          'Your Tracker token is stored encrypted for your Windows account. Your progress is kept only while Blackgrid is open, so refresh it after a restart.',
          style: EmberType.label.copyWith(color: context.ember.inkTertiary),
        ),
      ),
    ];
  }

  List<Widget> _gameFiles() {
    final settings = _services.settings;
    Future<String?> save({String? logs, String? shots}) async {
      final saved = await settings.setMapInputs(
        gameLogDirectory: logs,
        screenshotDirectory: shots,
      );
      return saved ? null : notSavedMessage;
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: EmberSpace.sm),
        child: CommitField(
          label: 'Game log folder',
          helper: "Leave empty to find the game's Logs folder automatically. Logs are watched even when Follow logs is off.",
          value: settings.settings.gameLogDirectory,
          onCommit: (text) => save(logs: text.trim()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: EmberSpace.sm),
        child: CommitField(
          label: 'Screenshot folder',
          helper:
              r'Leave empty to use Documents\Escape from Tarkov\Screenshots.',
          value: settings.settings.screenshotDirectory,
          onCommit: (text) => save(shots: text.trim()),
        ),
      ),
      SettingsRow.toggle(
        name: 'Follow logs',
        explanation: 'Use the map found in the game logs. Choosing a map yourself turns this off.',
        value: settings.settings.followGameLogs,
        enabled: !settings.busy,
        onChanged: (value) =>
            unawaited(settings.setMapInputs(followGameLogs: value)),
      ),
    ];
  }

  List<Widget> _raidTimers(BuildContext context) {
    final services = _services;
    final timers = services.settings.raidTimers;
    final mode = services.catalog.mode;
    final idle = !services.settings.busy;
    void save(RaidTimerSettings next) =>
        unawaited(services.settings.setRaidTimers(next));
    SettingsRow show(
      String name,
      String explanation,
      bool value,
      RaidTimerSettings Function(bool) change,
    ) => SettingsRow.toggle(
      name: name,
      explanation: explanation,
      value: value,
      enabled: idle,
      onChanged: (on) => save(change(on)),
    );
    return [
      show(
        'Show raid timers',
        'A strip under the header, worked out from the game logs.',
        timers.enabled,
        (on) => timers.copyWith(enabled: on),
      ),
      show(
        'Time in raid',
        'How long the raid has run.',
        timers.showTimeInRaid,
        (on) => timers.copyWith(showTimeInRaid: on),
      ),
      show(
        'Run-through',
        'The run-through countdown.',
        timers.showRunThrough,
        (on) => timers.copyWith(showRunThrough: on),
      ),
      show(
        'Scav cooldown',
        'The time until you can play a scav again.',
        timers.showScavCooldown,
        (on) => timers.copyWith(showScavCooldown: on),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: EmberSpace.sm),
        child: CommitField(
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
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: EmberSpace.sm),
        child: CommitField(
          label: 'Fence reputation',
          helper: mode == GameMode.unknown
              ? null
              : 'For ${modeLabel(mode)}, with two decimals. Used for the scav cooldown.',
          value: timers.fenceReputationFor(mode).toStringAsFixed(2),
          enabled: mode != GameMode.unknown,
          onCommit: (text) async {
            final value = parseReputation(text);
            if (value == null) return reputationMessage;
            final saved = await services.settings.setFenceReputation(
              mode,
              value,
            );
            return saved ? null : notSavedMessage;
          },
        ),
      ),
      if (mode == GameMode.unknown)
        Text(
          'Choose a game mode first.',
          style: EmberType.label.copyWith(color: context.ember.inkTertiary),
        ),
    ];
  }

  List<Widget> _map() {
    final settings = _services.settings;
    return [
      SettingsRow.toggle(
        name: 'Save marker filters',
        explanation:
            'Keep which marker types are shown the next time Blackgrid starts.',
        value: settings.settings.saveMarkerFilters,
        enabled: !settings.busy,
        onChanged: (value) => unawaited(
          settings.save(settings.settings.copyWith(saveMarkerFilters: value)),
        ),
      ),
    ];
  }
}

/// Capitalises the first letter of a status [label] that reads mid-sentence.
String _sentence(String label) =>
    label.isEmpty ? label : '${label[0].toUpperCase()}${label.substring(1)}';
