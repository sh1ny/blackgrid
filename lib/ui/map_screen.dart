import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/settings.dart';
import 'item_decision_card.dart';
import 'manual_controls.dart';
import 'map_workspace.dart';
import 'pin_editor.dart';
import 'theme.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key, required this.services});
  final AppServices services;

  Future<void> _showPins(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final map = services.settings.settings.selectedMap;
        final records = services.settings.pins
            .where((p) => p.mapId == map)
            .toList();
        return SizedBox(
          height: 450,
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
                      onTap: () => showPinEditor(context, services, pin: pin),
                      trailing: IconButton(
                        tooltip: 'Remove pin ${pin.label}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final remove = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Remove pin record?'),
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
                                  onPressed: () => Navigator.pop(context, true),
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
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.settings,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final map = services.settings.settings.selectedMap;
        final pins = services.settings.pins
            .where((p) => p.mapId == map)
            .toList();
        final workspace = GridPanel(
          title: mapLabel(map).toUpperCase(),
          icon: Icons.map_outlined,
          subtitle:
              'Native local artwork • durable pins • offline map capability',
          trailing: OutlinedButton.icon(
            onPressed: () => showPinEditor(context, services),
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
              child: Row(
                children: [
                  Expanded(
                    child: GridPanel(
                      title: 'Latest accepted scan',
                      icon: Icons.center_focus_weak,
                      child: Text(
                        services.scans.status,
                        style: const TextStyle(color: GridColors.muted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GridPanel(
                      title: 'Active map',
                      icon: Icons.map_outlined,
                      child: DropdownButtonFormField<String>(
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
                        onChanged: (id) {
                          if (id != null) services.settings.setMap(id);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300 * scale,
              child: ItemDecisionCard(services: services, compact: true),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 285 * scale,
              child: GridPanel(
                title: 'Marker preferences',
                icon: Icons.filter_alt_outlined,
                subtitle: 'Shared drawing and selection visibility',
                child: ListView(
                  children: [
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Save marker filters'),
                      value: services.settings.settings.saveMarkerFilters,
                      onChanged: (value) => services.settings.save(
                        services.settings.settings.copyWith(
                          saveMarkerFilters: value,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: markerCategories
                          .map(
                            (key) => FilterChip(
                              label: Text(key),
                              selected:
                                  services
                                      .settings
                                      .settings
                                      .markerFilters[key] ??
                                  true,
                              onSelected: (value) =>
                                  services.settings.setMarker(key, value),
                            ),
                          )
                          .toList(),
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
