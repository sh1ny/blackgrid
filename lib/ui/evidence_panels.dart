import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/catalog_controller.dart';
import '../domain/catalog.dart';
import '../domain/settings.dart';
import 'item_icon.dart';
import 'theme.dart';

/// The evidence line for the newest items source update in [snapshot].
///
/// The time is display evidence only and never affects catalog authority.
String itemsSourceUpdateLabel(CatalogSnapshot snapshot) =>
    'Items source update: '
    '${snapshot.sourceTimestamps['items']?.toUtc().toIso8601String() ?? 'unknown'}';

class RequirementPanel extends StatelessWidget {
  const RequirementPanel({super.key, required this.services});
  final AppServices services;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.selection,
    builder: (context, _) {
      final reasons = services.selection.decision?.reasons;
      return GridPanel(
        title: 'Requirements & uses',
        icon: Icons.fact_check_outlined,
        subtitle: 'Confirmed needs and unresolved gates remain distinct',
        child: reasons == null
            ? const Center(
                child: Text('Inspect an item to see its requirement evidence.'),
              )
            : reasons.isEmpty
            ? const Center(
                child: Text(
                  'No catalog requirement references. Progress authority may still be unknown.',
                ),
              )
            : ListView.builder(
                key: const PageStorageKey('requirement-scroll'),
                itemCount: reasons.length,
                itemBuilder: (context, index) {
                  final reason = reasons[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 7),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GridColors.inset,
                      border: Border.all(color: GridColors.quietBorder),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reason.requirement.sourceName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${reason.state.name} • ${reason.requirement.kind.name} • remaining ${reason.remaining ?? 'Unknown'}',
                          style: const TextStyle(color: GridColors.gold),
                        ),
                        Text(
                          reason.message,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          'FIR requirement: ${reason.requirement.foundInRaid == null
                              ? 'Unknown'
                              : reason.requirement.foundInRaid!
                              ? 'Yes'
                              : 'No'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
      );
    },
  );
}

class SourcePanel extends StatelessWidget {
  const SourcePanel({super.key, required this.services});
  final AppServices services;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.catalog,
      services.progress,
      services.selection,
    ]),
    builder: (context, _) {
      final selection = services.selection;
      final snapshot = selection.inspectionCatalog;
      final inspectionMode = selection.inspectionMode;
      final usesLive =
          !selection.isHistory || inspectionMode == services.catalog.mode;
      final catalogStatus = usesLive
          ? services.catalog.status
          : selection.loadingHistory
          ? CatalogStatus.loading
          : snapshot == null
          ? CatalogStatus.missing
          : CatalogStatus.stale;
      final progress = services.progress;
      final quote = services.selection.item?.quoteAt;
      return GridPanel(
        title: 'Source authority',
        icon: Icons.description_outlined,
        subtitle: 'Catalog age is measured from download',
        child: ListView(
          children: [
            Text(
              'Catalog: ${catalogStatus.name} • ${modeLabel(inspectionMode)}',
            ),
            const SizedBox(height: 10),
            Text(
              snapshot == null
                  ? 'No complete six-dataset snapshot.'
                  : 'Source: ${snapshot.source}',
            ),
            if (snapshot != null) ...[
              Text(
                'Observed: ${snapshot.observedAt.toUtc().toIso8601String()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                itemsSourceUpdateLabel(snapshot),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              ...snapshot.datasetCounts.entries.map(
                (e) => Text(
                  '${e.key}: ${e.value} records',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              ...snapshot.localizationErrors.map(
                (e) => Text(e, style: const TextStyle(color: GridColors.gold)),
              ),
            ],
            const Divider(height: 24),
            Text(
              'Flea quote: ${quote?.toUtc().toIso8601String() ?? 'Unknown source time'}',
            ),
            const Text(
              'Initial freshness limits: catalog 24h, flea quote 1h, session progress 15m.',
              style: TextStyle(color: GridColors.muted, fontSize: 12),
            ),
            const Divider(height: 24),
            Text(
              'Tracker: ${progress.status.name} • ${modeLabel(progress.mode)}',
            ),
            Text(
              progress.snapshot == null
                  ? 'No authorized current-session progress. Missing entities stay unknown.'
                  : 'Observed: ${progress.snapshot!.observedAt.toUtc().toIso8601String()} • session-only',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (progress.cooldownUntil != null)
              Text(
                'Cooldown until ${progress.cooldownUntil!.toUtc().toIso8601String()}',
              ),
            if (progress.error != null)
              Text(
                progress.error!,
                style: const TextStyle(color: GridColors.gold),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed:
                  progress.hasCredential &&
                      services.settings.settings.trackerEnabled
                  ? progress.refresh
                  : null,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Refresh read-only progress'),
            ),
          ],
        ),
      );
    },
  );
}

String _sourceLabel(ActivitySource source) => switch (source) {
  ActivitySource.scan => 'Scan',
  _ => source.name,
};

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key, required this.services});
  final AppServices services;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      services.history,
      services.catalog,
      services.selection,
    ]),
    builder: (context, _) => GridPanel(
      title: 'Recent item activity',
      icon: Icons.history,
      subtitle: 'Item activity • manual picks and accepted scans',
      child: services.history.rows.isEmpty
          ? Center(
              child: Text(
                services.history.error ?? 'No durable item activity yet.',
              ),
            )
          : ListView.builder(
              key: const PageStorageKey('history-scroll'),
              itemCount: services.history.rows.length,
              itemBuilder: (context, index) {
                final row = services.history.rows[index];
                // Only the current catalog may name an item or supply its
                // icon; a row from another mode gets neither.
                final item = services.catalog.mode == row.mode
                    ? services.catalog.snapshot?.items[row.itemId]
                    : null;
                final name = item?.name;
                final selected = services.selection.historyRow?.key == row.key;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: GridColors.inset,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: selected
                            ? GridColors.gold
                            : GridColors.quietBorder,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: item == null
                          ? const Icon(
                              Icons.inventory_2_outlined,
                              color: GridColors.muted,
                            )
                          : ItemIcon(
                              key: ValueKey(item.id),
                              cache: services.itemIcons,
                              itemId: item.id,
                              iconLink: item.iconLink,
                              size: 24,
                              color: GridColors.muted,
                            ),
                      title: Text(name ?? row.itemId),
                      subtitle: Text(
                        '${modeLabel(row.mode)} • ${_sourceLabel(row.source)}\n${row.observedAt.toUtc().toIso8601String()}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      onTap: () => services.selection.openHistory(row),
                    ),
                  ),
                );
              },
            ),
    ),
  );
}
