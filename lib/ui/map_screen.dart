import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/settings.dart';
import 'item_decision_card.dart';
import 'manual_controls.dart';
import 'pin_editor.dart';
import 'theme.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key, required this.services});
  final AppServices services;
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
          subtitle: 'Durable pin workspace • native artwork is outside M1',
          trailing: OutlinedButton.icon(
            onPressed: () => showPinEditor(context, services),
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('Add pin'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: GridColors.inset,
                  border: Border.all(color: GridColors.quietBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.layers_outlined,
                      size: 36,
                      color: GridColors.gold,
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Map identities, marker preferences and supported pin frames are available as data. No unqualified map artwork, player location or game listener is rendered.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${pins.length} saved pin records',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: pins.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 70,
                              color: GridColors.muted,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Your map records start here',
                              style: TextStyle(fontSize: 22),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Add a pin with explicit normalized coordinates. No map-position claim is made.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: GridColors.muted),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        key: const PageStorageKey('map-pin-scroll'),
                        itemCount: pins.length,
                        itemBuilder: (context, index) {
                          final pin = pins[index];
                          return Card(
                            color: GridColors.inset,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                              side: const BorderSide(
                                color: GridColors.quietBorder,
                              ),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.location_on_outlined,
                                color: GridColors.gold,
                              ),
                              title: Text(pin.label),
                              subtitle: Text(
                                'X ${pin.x} • Y ${pin.y}\n${pin.frame} • revision ${pin.frameRevision}',
                              ),
                              onTap: () =>
                                  showPinEditor(context, services, pin: pin),
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
                            ),
                          );
                        },
                      ),
              ),
              if (services.settings.error != null)
                Text(
                  services.settings.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const Divider(height: 24),
              const Text(
                'Pin frames are retained, not geometry-qualified • no capture or game interaction',
                style: TextStyle(color: GridColors.muted, fontSize: 12),
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
                subtitle: 'Saved preferences • no native markers rendered',
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
                                  false,
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
