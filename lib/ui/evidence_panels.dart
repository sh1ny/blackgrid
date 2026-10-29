import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../application/app_services.dart';
import '../application/catalog_controller.dart';
import '../application/progress_controller.dart';
import '../domain/catalog.dart';
import '../domain/decision.dart';
import 'item_icon.dart';
import 'labels.dart';
import 'requirement_rows.dart';
import 'theme.dart';

/// The evidence line for the newest items source update in [snapshot].
///
/// The time is display evidence only and never affects catalog authority.
String itemsSourceUpdateLabel(CatalogSnapshot snapshot) =>
    'Items source update: '
    '${snapshot.sourceTimestamps['items']?.toUtc().toIso8601String() ?? 'unknown'}';

/// The requirements and uses of the inspected item.
///
/// Task and hideout rows come first. Craft and barter rows follow under an
/// `Optional uses` header that starts collapsed for every newly inspected item.
class RequirementPanel extends StatefulWidget {
  /// Creates the panel over [services]' selection.
  const RequirementPanel({super.key, required this.services});

  /// The services whose current selection the panel shows.
  final AppServices services;

  @override
  State<RequirementPanel> createState() => _RequirementPanelState();
}

class _RequirementPanelState extends State<RequirementPanel> {
  bool _optionalOpen = false;

  /// The item [_optionalOpen] was set for.
  String? _openFor;

  @override
  void initState() {
    super.initState();
    _openFor = widget.services.selection.selectedId;
    widget.services.selection.addListener(_selectionChanged);
  }

  @override
  void didUpdateWidget(RequirementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services.selection != widget.services.selection) {
      oldWidget.services.selection.removeListener(_selectionChanged);
      widget.services.selection.addListener(_selectionChanged);
      _selectionChanged();
    }
  }

  @override
  void dispose() {
    widget.services.selection.removeListener(_selectionChanged);
    super.dispose();
  }

  /// Collapses the group as soon as a different item is inspected, so that
  /// returning to an earlier item never reopens it.
  void _selectionChanged() {
    final id = widget.services.selection.selectedId;
    if (id == _openFor) return;
    _openFor = id;
    _optionalOpen = false;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.services.selection,
    builder: (context, _) {
      final selection = widget.services.selection;
      final reasons = selection.decision?.reasons;
      final open = _optionalOpen;
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
                  'No catalog requirement references. Tracker progress may still be unknown.',
                ),
              )
            : _rows(context, reasons, open),
      );
    },
  );

  Widget _rows(BuildContext context, List<NeedReason> reasons, bool open) {
    final selection = widget.services.selection;
    final catalog = selection.inspectionCatalog;
    final arranged = arrangeRequirementRows(reasons);
    final obligations = arranged.obligations;
    final optional = arranged.optionalUses;
    final hasHeader = optional.isNotEmpty;
    final shownOptional = open ? optional.length : 0;
    return ListView.builder(
      key: const PageStorageKey('requirement-scroll'),
      itemCount: obligations.length + (hasHeader ? 1 : 0) + shownOptional,
      itemBuilder: (context, index) {
        if (index < obligations.length) {
          return _RequirementRow(requirementRow(obligations[index], catalog));
        }
        if (index == obligations.length) {
          return _OptionalHeader(
            count: optional.length,
            open: open,
            onTap: () => setState(() => _optionalOpen = !open),
          );
        }
        final need = optional[index - obligations.length - 1];
        return _RequirementRow(requirementRow(need, catalog));
      },
    );
  }
}

class _OptionalHeader extends StatelessWidget {
  const _OptionalHeader({
    required this.count,
    required this.open,
    required this.onTap,
  });

  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
            const SizedBox(width: 6),
            Text(
              'Optional uses ($count)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow(this.row);

  final RequirementRowView row;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final facts = [?row.needs, ?row.remaining].join(' • ');
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
          Text(row.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            '${row.kindTag} • ${row.stateLabel}',
            style: const TextStyle(color: GridColors.gold),
          ),
          if (row.sourceLine case final line?) Text(line, style: small),
          if (facts.isNotEmpty) Text(facts, style: small),
          if (row.reason case final reason?) Text(reason, style: small),
          if (row.foundInRaidLine case final fir?) Text(fir, style: small),
        ],
      ),
    );
  }
}

/// Where the item data, prices and tracker progress come from, and how old
/// each is.
///
/// The open view says what a player needs; the source URL, UTC times, the
/// freshness limits and the cooldown end time sit behind Details.
class SourcePanel extends StatelessWidget {
  /// Creates the panel over [services].
  const SourcePanel({
    super.key,
    required this.services,
    required this.detailsExpanded,
    required this.onDetailsExpandedChanged,
  });

  /// The services whose data sources the panel describes.
  final AppServices services;

  /// Whether the Details section is expanded; owned by the screen.
  final bool detailsExpanded;

  /// Called when the Details section asks to expand or collapse.
  final ValueChanged<bool> onDetailsExpandedChanged;

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
      final quote = selection.item?.quoteAt;
      final now = DateTime.now();
      final small = Theme.of(context).textTheme.bodySmall;
      final progressSnapshot = progress.snapshot;
      final cooldownUntil = progress.cooldownUntil;
      return GridPanel(
        title: 'Data sources',
        icon: Icons.description_outlined,
        subtitle: 'How old the data on screen is',
        child: ListView(
          children: [
            Text(
              snapshot == null
                  ? 'Item data: ${catalogStatusLabel(catalogStatus)}'
                  : 'Item data: ${catalogStatusLabel(catalogStatus)}'
                        ' · updated '
                        '${localTimeLabel(snapshot.observedAt, now: now)}',
            ),
            Text('Game mode: ${modeLabel(inspectionMode)}', style: small),
            if (snapshot != null)
              ...snapshot.localizationErrors.map(
                (e) => Text(
                  'Some item names could not be loaded: $e',
                  style: const TextStyle(color: GridColors.gold),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              quote == null
                  ? 'Prices: price time unknown'
                  : 'Prices: ${localTimeLabel(quote, now: now)}',
            ),
            const SizedBox(height: 10),
            Text(
              'Tracker progress: ${progressStatusLabel(progress.status)}'
              ' · ${modeLabel(progress.mode)}',
            ),
            Text(
              progressSnapshot == null
                  ? 'No tracker progress yet. Anything missing stays unknown.'
                  : 'Progress updated '
                        '${localTimeLabel(progressSnapshot.observedAt, now: now)}'
                        ' (this session only)',
              style: small,
            ),
            if (progress.status == ProgressStatus.cooldown)
              Text(
                'Progress refresh is cooling down. Try again shortly.',
                style: small,
              ),
            if (progress.error case final error?)
              Text(
                'Tracker problem: $error',
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
            const SizedBox(height: 6),
            DetailsSection(
              expanded: detailsExpanded,
              onExpandedChanged: onDetailsExpandedChanged,
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (snapshot == null)
                    Text('No complete item data download.', style: small)
                  else ...[
                    Text('Source: ${snapshot.source}', style: small),
                    Text(
                      'Item data downloaded (UTC): '
                      '${snapshot.observedAt.toUtc().toIso8601String()}',
                      style: small,
                    ),
                    Text(itemsSourceUpdateLabel(snapshot), style: small),
                    ...snapshot.datasetCounts.entries.map(
                      (e) => Text('${e.key}: ${e.value} records', style: small),
                    ),
                  ],
                  Text(
                    'Price time (UTC): '
                    '${quote?.toUtc().toIso8601String() ?? 'unknown'}',
                    style: small,
                  ),
                  if (progressSnapshot != null)
                    Text(
                      'Progress updated (UTC): '
                      '${progressSnapshot.observedAt.toUtc().toIso8601String()}',
                      style: small,
                    ),
                  if (cooldownUntil != null)
                    Text(
                      'Refresh available again at '
                      '${localTimeLabel(cooldownUntil, now: now)}',
                      style: small,
                    ),
                  Text(
                    'Data is treated as old after: item data 24h, '
                    'prices 1h, tracker progress 15m.',
                    style: small,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The items the player picked or scanned, newest first.
class HistoryPanel extends StatelessWidget {
  /// Creates the panel over [services].
  const HistoryPanel({super.key, required this.services});

  /// The services whose activity history the panel lists.
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
      subtitle: 'Items you picked or scanned',
      child: services.history.rows.isEmpty
          ? Center(child: Text(services.history.error ?? 'No items yet.'))
          : ListView.builder(
              key: const PageStorageKey('history-scroll'),
              // Rows past the edge would otherwise request their icons.
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
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
                        '${modeLabel(row.mode)} • ${activitySourceLabel(row.source)}\n${localTimeLabel(row.observedAt, now: DateTime.now())}',
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
