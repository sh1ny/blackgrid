import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_services.dart';
import '../application/scan_coordinator.dart';
import '../domain/catalog.dart';
import 'brand_lockup.dart';
import 'answer_strip.dart';
import 'import_dialog.dart';
import 'labels.dart';
import 'map_inspector.dart';
import 'map_screen.dart';
import 'raid_timer_strip.dart';
import 'scanner_inspector.dart';
import 'scanner_screen.dart';
import 'settings/commit_field.dart';
import 'settings/settings_page.dart';
import 'settings/settings_section.dart';
import 'stats_dialog.dart';
import 'top_item_search.dart';
import 'ember/theme_access.dart';
import 'ember/ember_tokens.dart';

class BlackgridShell extends StatefulWidget {
  const BlackgridShell({super.key, required this.services});
  final AppServices services;
  @override
  State<BlackgridShell> createState() => _BlackgridShellState();
}

/// What the shell remembers while the Settings page is open.
///
/// The page is a view state of the shell, not a route: the areas and the
/// inspector stay mounted underneath, so closing it shows them as they were.
class _SettingsView {
  const _SettingsView({required this.backArea, this.section, this.request = 0});

  /// The area the page was opened from, which Back returns to.
  final int backArea;

  /// The section the latest link asked for, or `null` for none.
  final SettingsSection? section;

  /// The number of the latest request, which rises with every link.
  final int request;

  /// The same view retargeted at [section] under a higher request number.
  _SettingsView retarget(SettingsSection section) =>
      _SettingsView(backArea: backArea, section: section, request: request + 1);
}

class _BlackgridShellState extends State<BlackgridShell> {
  int selected = 0;
  bool inspectorOpen = false;
  bool inspectorVisible = false;
  bool inspectorEverOpened = false;
  bool _wasOverlay = false;
  bool _inspectorInitialized = false;
  final inspectorScope = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  final query = TextEditingController();
  final searchFocus = FocusNode();
  final inspectorFocus = FocusNode();

  /// The shell's own focus node, which takes focus back when Settings closes.
  final _rootFocus = FocusNode();

  /// Commits the page's pending text edits before it closes.
  final _settingsFlush = SettingsFlushController();

  /// The open Settings page, or `null` while it is closed.
  _SettingsView? _settings;

  @override
  void initState() {
    super.initState();
    query.text = widget.services.selection.query;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_inspectorInitialized) {
      _inspectorInitialized = true;
      inspectorOpen = MediaQuery.sizeOf(context).width > 1080;
      inspectorVisible = inspectorOpen;
      inspectorEverOpened = inspectorOpen;
      _wasOverlay = !inspectorOpen;
    }
  }

  @override
  void dispose() {
    query.dispose();
    searchFocus.dispose();
    inspectorFocus.dispose();
    _rootFocus.dispose();
    inspectorScope.dispose();
    super.dispose();
  }

  void _setInspectorOpen(bool open) {
    setState(() {
      inspectorOpen = open;
      if (open) {
        inspectorVisible = true;
        inspectorEverOpened = true;
      }
    });
    if (open && MediaQuery.sizeOf(context).width <= 1080) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && inspectorOpen) inspectorScope.requestFocus();
      });
    } else if (!open) {
      inspectorFocus.requestFocus();
    }
  }

  /// Opens the Settings page in place of the answer strip and the main column.
  ///
  /// With a [section], the page scrolls to it and focuses its title. While the
  /// page is already open, a section only retargets it and Back keeps the
  /// area the page was first opened from; no section changes nothing.
  void _openSettings({SettingsSection? section}) {
    final open = _settings;
    if (open != null) {
      if (section != null) setState(() => _settings = open.retarget(section));
      return;
    }
    setState(() {
      _settings = _SettingsView(
        backArea: selected,
        section: section,
        request: section == null ? 0 : 1,
      );
    });
  }

  /// Closes the Settings page, the one path every close goes through.
  ///
  /// Pending text edits start their commit first. The page unmounts in the
  /// same frame, which a field survives because it ignores a result that
  /// arrives after it is gone. [area] shows that area instead of the one the
  /// page was opened from.
  void _closeSettings({int? area}) {
    final open = _settings;
    if (open == null) return;
    unawaited(_settingsFlush.flush());
    setState(() {
      selected = area ?? open.backArea;
      _settings = null;
    });
    // Focus moves once the page is gone, so leaving its field is not a second
    // commit of the same text.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _settings == null) _rootFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return _shell(context, settings);
  }

  Widget _shell(BuildContext context, _SettingsView? settings) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.keyK, control: true): _SearchIntent(),
      SingleActivator(LogicalKeyboardKey.escape): _CloseInspectorIntent(),
    },
    child: Actions(
      actions: {
        _CloseInspectorIntent: CallbackAction<_CloseInspectorIntent>(
          onInvoke: (_) {
            if (_settings != null) {
              _closeSettings();
            } else if (inspectorOpen && inspectorScope.hasFocus) {
              _setInspectorOpen(false);
            }
            return null;
          },
        ),
        _SearchIntent: CallbackAction<_SearchIntent>(
          onInvoke: (_) {
            searchFocus.requestFocus();
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < 1300 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.2;
                    return Container(
                      key: const Key('shell-top-bar'),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.ember.canvas,
                        border: Border(
                          bottom: BorderSide(color: context.ember.hairline),
                        ),
                      ),
                      child: compact
                          ? Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: _headerItems(compact: true),
                            )
                          : Row(children: _headerItems(compact: false)),
                    );
                  },
                ),
                Offstage(
                  offstage: settings != null,
                  child: ExcludeFocus(
                    excluding: settings != null,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .55,
                      ),
                      child: SingleChildScrollView(
                        child: AnswerStrip(services: widget.services),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Offstage(
                          offstage: settings != null,
                          child: ExcludeFocus(
                            excluding: settings != null,
                            child: _main(),
                          ),
                        ),
                      ),
                      if (settings != null)
                        Positioned.fill(
                          child: SettingsPage(
                            services: widget.services,
                            backLabel:
                                'Back to ${_areaName(settings.backArea)}',
                            onBack: _closeSettings,
                            flush: _settingsFlush,
                            section: settings.section,
                            request: settings.request,
                          ),
                        ),
                    ],
                  ),
                ),
                ListenableBuilder(
                  listenable: widget.services.scanner,
                  builder: (context, _) => widget.services.scanner.error == null
                      ? const SizedBox.shrink()
                      : Text(
                          widget.services.scanner.error!,
                          key: const Key('status-live-scan-error'),
                        ),
                ),
                Container(
                  key: const Key('shell-status-bar'),
                  width: double.infinity,
                  height: 28 * MediaQuery.textScalerOf(context).scale(1),
                  decoration: BoxDecoration(
                    color: context.ember.canvas,
                    border: Border(
                      top: BorderSide(color: context.ember.hairline),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          widget.services.catalog,
                          widget.services.progress,
                          widget.services.scanner,
                          widget.services.mapSession,
                        ]),
                        builder: (context, _) => Row(
                          children: [
                            PopupMenuButton<GameMode>(
                              key: const Key('status-game-mode'),
                              tooltip:
                                  widget
                                          .services
                                          .mapSession
                                          .state
                                          .detectedMode ==
                                      GameMode.unknown
                                  ? 'Choose game mode'
                                  : 'The game log currently determines the active mode',
                              onSelected: widget.services.setMode,
                              itemBuilder: (context) => [
                                for (final mode in GameMode.values)
                                  PopupMenuItem(
                                    value: mode,
                                    child: Text(modeLabel(mode)),
                                  ),
                              ],
                              child: Text(
                                'Game mode ${modeLabel(widget.services.catalog.mode)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 22),
                            InkWell(
                              key: const Key('status-item-data'),
                              onTap: () => _openSettings(
                                section: SettingsSection.itemData,
                              ),
                              child: Text(
                                'Item data ${catalogStatusLabel(widget.services.catalog.status)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 22),
                            InkWell(
                              key: const Key('status-tracker'),
                              onTap: () => _openSettings(
                                section: SettingsSection.tracker,
                              ),
                              child: Text(
                                'Tracker ${progressStatusLabel(widget.services.progress.status)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 22),
                            ListenableBuilder(
                              listenable: widget.services.scanner,
                              builder: (context, _) => InkWell(
                                key: const Key('status-live-scan'),
                                onTap: () =>
                                    widget.services.scanner.setLiveScan(
                                      !widget.services.scanner.switchOn,
                                    ),
                                child: _liveScanFooter(
                                  widget.services.scanner.status.state,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// The Map and Scanner areas with the inspector, which stay mounted while
  /// Settings is open.
  Widget _main() => LayoutBuilder(
    builder: (context, constraints) {
      final overlay = MediaQuery.sizeOf(context).width <= 1080;
      if (overlay != _wasOverlay) {
        _wasOverlay = overlay;
        if (overlay && inspectorOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && inspectorOpen && _wasOverlay) {
              inspectorScope.requestFocus();
            }
          });
        }
      }
      final panelWidth = 352.0.clamp(0.0, constraints.maxWidth);
      return Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                14,
                inspectorOpen && !overlay ? panelWidth + 28 : 14,
                14,
              ),
              child: IndexedStack(
                index: selected,
                children: [
                  MapScreen(
                    key: const PageStorageKey('map'),
                    services: widget.services,
                  ),
                  ScannerScreen(
                    key: const PageStorageKey('scanner'),
                    services: widget.services,
                  ),
                ],
              ),
            ),
          ),
          if (inspectorOpen && overlay)
            Positioned.fill(
              child: GestureDetector(
                key: const Key('inspector-scrim'),
                onTap: () => _setInspectorOpen(false),
                child: ColoredBox(color: context.ember.scrim),
              ),
            ),
          if (inspectorEverOpened)
            AnimatedPositioned(
              top: 14,
              bottom: 14,
              right: inspectorOpen ? 14 : -panelWidth,
              width: panelWidth,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : EmberMotion.panel,
              curve: EmberMotion.panelEase,
              onEnd: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !inspectorOpen && inspectorVisible) {
                    setState(() => inspectorVisible = false);
                  }
                });
              },
              child: Offstage(
                offstage: !inspectorVisible,
                child: FocusScope(
                  node: inspectorScope,
                  canRequestFocus: inspectorOpen,
                  descendantsAreFocusable: inspectorOpen,
                  descendantsAreTraversable: inspectorOpen,
                  child: SizedBox(
                    key: const Key('shell-inspector'),
                    child: selected == 1
                        ? (inspectorOpen
                              ? ScannerInspector(services: widget.services)
                              : const SizedBox.shrink())
                        : ListView(
                            children: [
                              if (inspectorOpen)
                                Padding(
                                  padding: const EdgeInsets.all(EmberSpace.md),
                                  child: MapInspector(
                                    services: widget.services,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  String _areaName(int area) => area == 0 ? 'Map' : 'Scanner';

  List<Widget> _headerItems({required bool compact}) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final search = SizedBox(
      width: compact ? 150 : null,
      height: 39 * scale,
      child: TopItemSearch(
        services: widget.services,
        controller: query,
        focusNode: searchFocus,
        onPicked: _closeSettings,
      ),
    );
    final items = <Widget>[
      BrandLockup.topBar(compact: compact),
      _nav(0, Icons.map_outlined, 'Map'),
      _nav(1, Icons.center_focus_weak, 'Scanner'),
      if (compact) search else Expanded(child: search),
      RaidTimerStrip(controller: widget.services.raidTimers),
      IconButton(
        key: const Key('inspector-toggle'),
        focusNode: inspectorFocus,
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        tooltip: inspectorOpen ? 'Close inspector' : 'Open inspector',
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        // The inspector is hidden while Settings is open.
        onPressed: _settings != null
            ? null
            : () => _setInspectorOpen(!inspectorOpen),
        icon: const Icon(Icons.vertical_split_outlined),
      ),
      _headerAction(
        'Settings',
        Icons.settings_outlined,
        compact,
        _openSettings,
      ),
      _headerAction(
        'Stats',
        Icons.bar_chart,
        compact,
        () => showStats(context, widget.services.localStats),
      ),
      _headerAction(
        'Import',
        Icons.file_open_outlined,
        compact,
        () => showLegacyImport(context, widget.services),
      ),
    ];
    if (compact) return items;
    return [
      for (final (index, item) in items.indexed) ...[
        if (index > 0) const SizedBox(width: 8),
        item,
      ],
    ];
  }

  Widget _liveScanFooter(LiveScanState state) {
    final scanner = widget.services.scanner;
    final text = switch (state) {
      LiveScanState.off => 'Live scan off · no capture',
      LiveScanState.starting => 'Live scan starting',
      LiveScanState.ready => switch (scanner.hotkeyState) {
        ScanHotkeyRegistered(:final key) =>
          'Live scan on · ${key.label} or click',
        ScanHotkeyUnavailable(:final reason) =>
          'Live scan on · click ($reason)',
        _ => 'Live scan on · click',
      },
      LiveScanState.stopping => 'Live scan stopping',
      LiveScanState.unavailable =>
        'Live scan unavailable · ${scanner.status.reason ?? "reason unknown"}',
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const Key('live-scan-state-dot'),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: state == LiveScanState.ready
                ? context.ember.accentText
                : context.ember.inkTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(color: context.ember.inkSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _headerAction(
    String label,
    IconData icon,
    bool compact,
    VoidCallback onPressed,
  ) => compact
      ? IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon))
      : Tooltip(
          message: label,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
        );

  Widget _nav(int index, IconData icon, String label) => Semantics(
    selected: selected == index,
    child: InkWell(
      key: Key(index == 0 ? 'nav-map' : 'nav-scanner'),
      onTap: () {
        if (_settings != null) {
          _closeSettings(area: index);
        } else {
          setState(() => selected = index);
        }
      },
      child: Container(
        height: 36 * MediaQuery.textScalerOf(context).scale(1),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected == index
              ? context.ember.accentSoft
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: selected == index
                  ? context.ember.accentText
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected == index
                  ? context.ember.accentText
                  : context.ember.ink,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected == index
                    ? context.ember.accentText
                    : context.ember.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _CloseInspectorIntent extends Intent {
  const _CloseInspectorIntent();
}
