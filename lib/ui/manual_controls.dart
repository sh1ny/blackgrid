import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/catalog_controller.dart';
import '../domain/catalog.dart';
import '../domain/inspection_context.dart';
import 'labels.dart';
import 'theme.dart';

class ManualControls extends StatelessWidget {
  const ManualControls({
    super.key,
    required this.services,
    required this.storageKey,
  });
  final AppServices services;
  final String storageKey;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.catalog,
      services.progress,
      services.selection,
      services.settings,
    ]),
    builder: (context, _) {
      final results = services.selection.results;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<GameMode>(
            key: ValueKey('$storageKey-${services.catalog.mode.name}'),
            initialValue: services.catalog.mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Live game mode'),
            items: GameMode.values
                .map(
                  (m) => DropdownMenuItem(value: m, child: Text(modeLabel(m))),
                )
                .toList(),
            onChanged: services.settings.busy
                ? null
                : (m) {
                    if (m != null) services.setMode(m);
                  },
          ),
          const SizedBox(height: 12),
          const Text(
            'MANUAL INSPECTION',
            style: TextStyle(
              color: GridColors.gold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Picking an item here does not scan.',
            style: TextStyle(color: GridColors.muted),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed:
                services.catalog.mode == GameMode.unknown ||
                    services.catalog.loading
                ? null
                : services.catalog.refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(
              services.catalog.loading
                  ? 'Refreshing item data…'
                  : 'Refresh item data',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Item data: ${catalogStatusLabel(services.catalog.status)}',
            key: Key('$storageKey-catalog-status'),
          ),
          Text(
            'Tracker: ${progressStatusLabel(services.progress.status)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (services.catalog.error != null)
            Text(
              services.catalog.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (services.settings.error != null)
            Text(
              services.settings.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const Divider(height: 24),
          const Text('Found in raid • this item only'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: FirState.values
                .map(
                  (f) => ChoiceChip(
                    label: Text(switch (f) {
                      FirState.unknown => 'Unknown',
                      FirState.yes => 'Yes',
                      FirState.no => 'No',
                    }),
                    selected: services.selection.fir == f,
                    onSelected: services.selection.item == null
                        ? null
                        : (_) => services.selection.setFir(f),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Text(
            services.selection.query.isEmpty
                ? 'Type an item name.'
                : '${results.length} matching items',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: services.catalog.snapshot == null
                ? Center(
                    child: Text(
                      services.catalog.mode == GameMode.unknown
                          ? 'Choose a game mode to get item data.'
                          : services.catalog.status == CatalogStatus.loading
                          ? 'Loading item data…'
                          : 'No item data yet. Refresh to download item data.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    key: PageStorageKey(storageKey),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final item = results[index];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        selected:
                            !services.selection.isHistory &&
                            services.selection.selectedId == item.id,
                        selectedColor: GridColors.gold,
                        title: Text(item.name),
                        subtitle: item.shortName == null
                            ? null
                            : Text(item.shortName!),
                        onTap: () => services.selection.selectManual(item),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}
