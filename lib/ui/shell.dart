import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_services.dart';
import '../application/scan_coordinator.dart';
import 'import_dialog.dart';
import 'map_screen.dart';
import 'scanner_screen.dart';
import 'settings_dialog.dart';
import 'theme.dart';

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
                decoration: const BoxDecoration(
                  color: GridColors.inset,
                  border: Border(bottom: BorderSide(color: GridColors.border)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width:
                          constraints.maxWidth <
                              1100 * MediaQuery.textScalerOf(context).scale(1)
                          ? 1100 * MediaQuery.textScalerOf(context).scale(1)
                          : constraints.maxWidth,
                      child: Row(
                        children: [
                          const SizedBox(width: 20),
                          const Icon(
                            Icons.hub_outlined,
                            color: GridColors.gold,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width:
                                260 * MediaQuery.textScalerOf(context).scale(1),
                            child: const Column(
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
                                    color: GridColors.muted,
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
                                hintText: 'Search real items or canonical IDs…',
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
                decoration: const BoxDecoration(
                  color: GridColors.inset,
                  border: Border(top: BorderSide(color: GridColors.border)),
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
                          const Icon(
                            Icons.touch_app_outlined,
                            size: 14,
                            color: GridColors.gold,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'MANUAL INSPECTION',
                            style: TextStyle(
                              color: GridColors.gold,
                              fontSize: 11,
                              letterSpacing: .8,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Text(
                            'Live mode: ${modeLabel(widget.services.catalog.mode)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 22),
                          Text(
                            'Catalog ${widget.services.catalog.status.name}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 22),
                          Text(
                            'Progress ${widget.services.progress.status.name}',
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
      LiveScanState.off => ('Live scan off • no capture', GridColors.muted),
      LiveScanState.starting => ('Live scan starting', GridColors.muted),
      LiveScanState.ready => (
        'Live scan on • captures on click',
        GridColors.gold,
      ),
      LiveScanState.stopping => ('Live scan stopping', GridColors.muted),
      LiveScanState.unavailable => ('Live scan unavailable', GridColors.muted),
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
              ? const Color(0xff191c10)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: selected == index ? GridColors.gold : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected == index ? GridColors.gold : GridColors.text,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected == index ? GridColors.gold : GridColors.text,
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
