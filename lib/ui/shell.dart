import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_services.dart';
import '../application/scan_coordinator.dart';
import 'app_logo.dart';
import 'import_dialog.dart';
import 'labels.dart';
import 'map_screen.dart';
import 'raid_timer_strip.dart';
import 'scanner_screen.dart';
import 'settings_dialog.dart';
import 'stats_dialog.dart';
import 'ember/theme_access.dart';

class BlackgridShell extends StatefulWidget {
  const BlackgridShell({super.key, required this.services});
  final AppServices services;
  @override
  State<BlackgridShell> createState() => _BlackgridShellState();
}

class _BlackgridShellState extends State<BlackgridShell> {
  int selected = 0;
  final query = TextEditingController();
  final searchFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    query.text = widget.services.selection.query;
  }

  @override
  void dispose() {
    query.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.keyK, control: true): _SearchIntent(),
    },
    child: Actions(
      actions: {
        _SearchIntent: CallbackAction<_SearchIntent>(
          onInvoke: (_) {
            searchFocus.requestFocus();
            return null;
          },
        ),
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 66 * MediaQuery.textScalerOf(context).scale(1),
                decoration: BoxDecoration(
                  color: context.ember.canvas,
                  border: Border(
                    bottom: BorderSide(color: context.ember.hairline),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width:
                          constraints.maxWidth <
                              1220 * MediaQuery.textScalerOf(context).scale(1)
                          ? 1220 * MediaQuery.textScalerOf(context).scale(1)
                          : constraints.maxWidth,
                      child: Row(
                        children: [
                          const SizedBox(width: 20),
                          const AppLogo(),
                          const SizedBox(width: 12),
                          SizedBox(
                            width:
                                260 * MediaQuery.textScalerOf(context).scale(1),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'BLACKGRID',
                                  style: TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  'TRACK. PLAN. SURVIVE.',
                                  style: TextStyle(
                                    color: context.ember.inkSecondary,
                                    fontSize: 10,
                                    letterSpacing: 1.7,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _nav(0, Icons.map_outlined, 'Map'),
                          _nav(1, Icons.center_focus_weak, 'Scanner'),
                          const SizedBox(width: 24),
                          Expanded(
                            child: TextField(
                              controller: query,
                              focusNode: searchFocus,
                              onChanged: widget.services.selection.setQuery,
                              decoration: const InputDecoration(
                                hintText: 'Search items…',
                                prefixIcon: Icon(Icons.search, size: 20),
                                suffixText: 'Ctrl K',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                              onSubmitted: (_) {
                                if (widget
                                    .services
                                    .selection
                                    .results
                                    .isNotEmpty) {
                                  widget.services.selection.selectManual(
                                    widget.services.selection.results.first,
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 18),
                          OutlinedButton.icon(
                            onPressed: () =>
                                showSettings(context, widget.services),
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            label: const Text('Settings'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () =>
                                showStats(context, widget.services.localStats),
                            icon: const Icon(Icons.bar_chart, size: 18),
                            label: const Text('Stats'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () =>
                                showLegacyImport(context, widget.services),
                            icon: const Icon(
                              Icons.file_open_outlined,
                              size: 18,
                            ),
                            label: const Text('Import'),
                          ),
                          const SizedBox(width: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              RaidTimerStrip(controller: widget.services.raidTimers),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
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
              Container(
                height: 34 * MediaQuery.textScalerOf(context).scale(1),
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
                      ]),
                      builder: (context, _) => Row(
                        children: [
                          Icon(
                            Icons.touch_app_outlined,
                            size: 14,
                            color: context.ember.accentText,
                          ),
                          const SizedBox(width: 8),
                          const SizedBox(width: 2),
                          Text(
                            'Game mode ${modeLabel(widget.services.catalog.mode)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 22),
                          Text(
                            'Item data ${catalogStatusLabel(widget.services.catalog.status)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 22),
                          Text(
                            'Tracker ${progressStatusLabel(widget.services.progress.status)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 22),
                          ListenableBuilder(
                            listenable: widget.services.scanner,
                            builder: (context, _) => _liveScanFooter(
                              widget.services.scanner.status.state,
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
  );

  /// The footer line for the live scan [state]; only `ready` is gold.
  Widget _liveScanFooter(LiveScanState state) {
    final (text, color) = switch (state) {
      LiveScanState.off => (
        'Live scan off • no capture',
        context.ember.inkSecondary,
      ),
      LiveScanState.starting => (
        'Live scan starting',
        context.ember.inkSecondary,
      ),
      LiveScanState.ready => (
        'Live scan on • captures on click',
        context.ember.accentText,
      ),
      LiveScanState.stopping => (
        'Live scan stopping',
        context.ember.inkSecondary,
      ),
      LiveScanState.unavailable => (
        'Live scan unavailable',
        context.ember.inkSecondary,
      ),
    };
    return Text(text, style: TextStyle(color: color, fontSize: 11));
  }

  Widget _nav(int index, IconData icon, String label) => Semantics(
    selected: selected == index,
    child: InkWell(
      key: Key(index == 0 ? 'nav-map' : 'nav-scanner'),
      onTap: () => setState(() => selected = index),
      child: Container(
        height: 66 * MediaQuery.textScalerOf(context).scale(1),
        padding: const EdgeInsets.symmetric(horizontal: 20),
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
