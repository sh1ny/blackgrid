import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_services.dart';
import '../application/scan_coordinator.dart';
import '../domain/catalog.dart';
import 'app_logo.dart';
import 'answer_strip.dart';
import 'evidence_panels.dart';
import 'item_decision_card.dart';
import 'import_dialog.dart';
import 'labels.dart';
import 'map_inspector.dart';
import 'map_screen.dart';
import 'raid_timer_strip.dart';
import 'scanner_screen.dart';
import 'settings_dialog.dart';
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
  bool inspectionExpanded = false;
  bool requirementsExpanded = false;
  bool sourcesExpanded = false;
  late RequirementExpansion requirementExpansion;
  final query = TextEditingController();
  final searchFocus = FocusNode();
  final inspectorFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    requirementExpansion = RequirementExpansion(widget.services.selection);
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
  void didUpdateWidget(BlackgridShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services.selection != widget.services.selection) {
      requirementExpansion.dispose();
      requirementExpansion = RequirementExpansion(widget.services.selection);
    }
  }

  @override
  void dispose() {
    query.dispose();
    searchFocus.dispose();
    inspectorFocus.dispose();
    inspectorScope.dispose();
    requirementExpansion.dispose();
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

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.keyK, control: true): _SearchIntent(),
      SingleActivator(LogicalKeyboardKey.escape): _CloseInspectorIntent(),
    },
    child: Actions(
      actions: {
        _CloseInspectorIntent: CallbackAction<_CloseInspectorIntent>(
          onInvoke: (_) {
            if (inspectorOpen && inspectorScope.hasFocus) {
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
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .55,
                  ),
                  child: SingleChildScrollView(
                    child: AnswerStrip(services: widget.services),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
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
                                inspectorOpen && !overlay
                                    ? panelWidth + 28
                                    : 14,
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
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted &&
                                      !inspectorOpen &&
                                      inspectorVisible) {
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
                                    child: ListView(
                                      children: [
                                        if (selected == 1) ...[
                                          SizedBox(
                                            height:
                                                230 *
                                                MediaQuery.textScalerOf(context)
                                                    .scale(1),
                                            child: inspectorOpen
                                                ? HistoryPanel(
                                                    services: widget.services,
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                          if (inspectorOpen) ...[
                                            ExpansionTile(
                                              initiallyExpanded:
                                                  inspectionExpanded,
                                              onExpansionChanged: (value) =>
                                                  inspectionExpanded = value,
                                              title: const Text(
                                                'Inspection details',
                                              ),
                                              children: [
                                                ItemDecisionCard(
                                                  services: widget.services,
                                                  compact: true,
                                                  showCorrectionOffer: false,
                                                  fitContent: true,
                                                ),
                                              ],
                                            ),
                                            ExpansionTile(
                                              initiallyExpanded:
                                                  requirementsExpanded,
                                              onExpansionChanged: (value) =>
                                                  requirementsExpanded = value,
                                              title: const Text('Requirements'),
                                              children: [
                                                RequirementPanel(
                                                  services: widget.services,
                                                  fitContent: true,
                                                  expansion:
                                                      requirementExpansion,
                                                ),
                                              ],
                                            ),
                                            ExpansionTile(
                                              initiallyExpanded:
                                                  sourcesExpanded,
                                              onExpansionChanged: (value) =>
                                                  sourcesExpanded = value,
                                              title: const Text('Sources'),
                                              children: [
                                                SourcePanel(
                                                  services: widget.services,
                                                  fitContent: true,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ] else if (inspectorOpen)
                                          Padding(
                                            padding: const EdgeInsets.all(
                                              EmberSpace.md,
                                            ),
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
                              onTap: () => showSettings(
                                context,
                                widget.services,
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
                              onTap: () => showSettings(
                                context,
                                widget.services,
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

  List<Widget> _headerItems({required bool compact}) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final search = SizedBox(
      width: compact ? 150 : null,
      height: 39 * scale,
      child: TopItemSearch(
        services: widget.services,
        controller: query,
        focusNode: searchFocus,
      ),
    );
    final items = <Widget>[
      const AppLogo(),
      if (!compact)
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BLACKGRID'),
            Text('TRACK. PLAN. SURVIVE.', style: TextStyle(fontSize: 8)),
          ],
        ),
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
        onPressed: () => _setInspectorOpen(!inspectorOpen),
        icon: const Icon(Icons.vertical_split_outlined),
      ),
      _headerAction(
        'Settings',
        Icons.settings_outlined,
        compact,
        () => showSettings(context, widget.services),
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
      onTap: () => setState(() => selected = index),
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
