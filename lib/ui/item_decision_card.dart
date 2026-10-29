import 'package:flutter/material.dart';

import '../application/accepted_scan.dart';
import '../application/app_services.dart';
import '../application/scan_correction.dart';
import '../application/selection_controller.dart';
import '../domain/catalog.dart';
import '../domain/decision.dart';
import '../domain/title_matching.dart' show normaliseTitle;
import 'item_icon.dart';
import 'labels.dart';
import 'theme.dart';

String recommendationLabel(Recommendation value) => switch (value) {
  Recommendation.keep => 'Keep',
  Recommendation.keepForLater => 'Keep for later',
  Recommendation.check => 'Check / May Need',
  Recommendation.flea => 'Flea',
  Recommendation.trader => 'Trader',
  Recommendation.priceUnavailable => 'Price unavailable',
};

/// A short age such as `0 s`, `42 s`, `5 min` or `3 h`, for the card.
String scanAgeLabel(Duration age) {
  if (age.inMinutes < 1) return '${age.inSeconds} s';
  if (age.inHours < 1) return '${age.inMinutes} min';
  return '${age.inHours} h';
}

class ItemDecisionCard extends StatelessWidget {
  const ItemDecisionCard({
    super.key,
    required this.services,
    this.compact = false,
  });
  final AppServices services;
  final bool compact;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([services.selection, services.scans]),
    builder: (context, _) {
      final selection = services.selection;
      final latest = services.scans.latest;
      final backToLatest =
          latest != null && selection.scan?.reportId != latest.reportId;
      final item = selection.item;
      final decision = selection.decision;
      final scan = selection.scan;
      final correction = selection.isHistory ? null : selection.correction;
      final offer = selection.correctionOffer;
      final offerBlock = offer == null
          ? null
          : _CorrectionOfferBlock(selection: selection, offer: offer);
      return GridPanel(
        title: selection.isHistory
            ? 'History inspection'
            : scan != null
            ? 'Accepted scan'
            : correction != null
            ? 'Corrected scan'
            : 'Picked item',
        icon: Icons.center_focus_strong,
        subtitle: selection.isHistory
            ? 'Saved from ${modeLabel(selection.inspectionMode)} • game mode unchanged'
            : scan != null
            ? 'Scanned ${_scanAge(selection, scan)} ago'
            : correction != null
            ? 'Corrected from scan #${correction.reportId} • '
                  '${_correctionAge(selection, correction)} ago • '
                  'chosen by hand'
            : 'Chosen by hand',
        trailing: _trailing(selection, backToLatest ? latest : null),
        child: item == null || decision == null
            ? offerBlock != null
                  ? ListView(
                      children: [
                        // The offer replaces only the find-an-item hint; a
                        // loading or unresolved selection still says so.
                        if (selection.loadingHistory ||
                            selection.selectedId != null) ...[
                          Text(
                            selection.loadingHistory
                                ? 'Opening saved item data…'
                                : 'Item data unavailable',
                            key: const Key('correction-offer-status'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                        ],
                        offerBlock,
                        if (selection.error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            selection.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    )
                  : ListView(
                      children: [
                        const SizedBox(height: 28),
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 72,
                          color: GridColors.muted,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          selection.loadingHistory
                              ? 'Opening saved item data…'
                              : selection.selectedId == null
                              ? selection.scanRetired
                                    ? 'Last scan was in an earlier mode or session; scan again'
                                    : 'Find an item'
                              : 'Item data unavailable',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          selection.error ?? 'Search for an item and pick it. What you still need and its prices appear here.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (offerBlock != null) ...[
                      offerBlock,
                      const SizedBox(height: 12),
                    ],
                    const Divider(height: 1),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final inline = compact || constraints.maxWidth < 560;
                        final name = Text(
                          item.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        );
                        final detail = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (inline)
                              Row(
                                key: const Key('item-title-row'),
                                children: [
                                  ItemIcon(
                                    key: ValueKey(item.id),
                                    cache: services.itemIcons,
                                    itemId: item.id,
                                    iconLink: item.iconLink,
                                    size: 30,
                                    color: GridColors.gold,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: name),
                                ],
                              )
                            else
                              name,
                            const SizedBox(height: 5),
                            SelectableText(
                              item.id,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: GridColors.inset,
                                border: Border.all(color: GridColors.gold),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                recommendationLabel(decision.recommendation),
                                key: const Key('recommendation'),
                                style: const TextStyle(
                                  color: GridColors.gold,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _value(
                                  'Flea price',
                                  rub(decision.fleaGross),
                                  'Per slot: ${rub(decision.fleaPerSlot)}',
                                ),
                                _value(
                                  decision.traderName ?? 'Trader unavailable',
                                  rub(decision.traderGross),
                                  'Per slot: ${rub(decision.traderPerSlot)}',
                                ),
                                _value(
                                  'Still needed',
                                  'Found in raid: ${decision.firNeed ?? 'Unknown'}',
                                  'Not found in raid: ${decision.nonFirNeed ?? 'Unknown'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${modeLabel(selection.inspectionMode)} · Found in raid: ${firLabel(selection.fir)} · Prices before fees',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        );
                        if (inline) {
                          return detail;
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 185,
                              constraints: const BoxConstraints(minHeight: 220),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              margin: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: GridColors.inset,
                                border: Border.all(
                                  color: GridColors.quietBorder,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ItemIcon(
                                    key: ValueKey(item.id),
                                    cache: services.itemIcons,
                                    itemId: item.id,
                                    iconLink: item.iconLink,
                                    size: 68,
                                    color: GridColors.gold,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    item.shortName ?? item.name,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.slots == null
                                        ? 'Dimensions unavailable'
                                        : '${item.width} × ${item.height} • ${item.slots} slots',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(child: detail),
                          ],
                        );
                      },
                    ),
                    if (selection.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        selection.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (decision.warnings.isNotEmpty) ...[
                      const Divider(height: 24),
                      ...decision.warnings.map(
                        (warning) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            '• $warning',
                            style: const TextStyle(color: GridColors.gold),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      );
    },
  );

  /// The history close button and the return-to-latest-scan action, if any.
  Widget? _trailing(SelectionController selection, AcceptedScan? latest) {
    final close = selection.isHistory
        ? IconButton(
            tooltip: 'Close history inspection',
            onPressed: selection.closeHistory,
            icon: const Icon(Icons.close),
          )
        : null;
    if (latest == null) return close;
    final name =
        services.catalog.snapshot?.items[latest.itemId]?.name ?? latest.itemId;
    final back = Tooltip(
      message: 'Back to latest scan: $name',
      child: TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () {
          // Read at tap time: the latest scan may have moved or cleared.
          final current = services.scans.latest;
          if (current != null) selection.showScan(current);
        },
        icon: const Icon(Icons.undo, size: 18),
        // Bounded so a wide font cannot starve the title and subtitle.
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: const Text(
            'Back to latest scan',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
    if (close == null) return back;
    return Row(mainAxisSize: MainAxisSize.min, children: [back, close]);
  }

  String _scanAge(SelectionController selection, AcceptedScan scan) =>
      scanAgeLabel(selection.clock().toUtc().difference(scan.acceptedAt));

  String _correctionAge(
    SelectionController selection,
    ScanCorrection correction,
  ) => scanAgeLabel(
    selection.clock().toUtc().difference(correction.correctedAt),
  );

  Widget _value(String title, String value, String detail) => Container(
    width: 180,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: GridColors.inset,
      border: Border.all(color: GridColors.quietBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: GridColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          style: const TextStyle(color: GridColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

/// The bounded offer block: the scan's candidates, a search field and results.
///
/// It owns the search field's controller and keeps its text equal to the
/// offer's query whenever the selection notifies, so every mounted card shows
/// the same text.
class _CorrectionOfferBlock extends StatefulWidget {
  const _CorrectionOfferBlock({required this.selection, required this.offer});

  final SelectionController selection;
  final ScanCorrectionOffer offer;

  @override
  State<_CorrectionOfferBlock> createState() => _CorrectionOfferBlockState();
}

class _CorrectionOfferBlockState extends State<_CorrectionOfferBlock> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.offer.query,
  );

  @override
  void didUpdateWidget(_CorrectionOfferBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = widget.offer.query;
    if (_controller.text == query) return;
    final cursor = _controller.selection.baseOffset;
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(
        offset: cursor < 0 ? query.length : cursor.clamp(0, query.length),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.selection;
    final offer = widget.offer;
    final candidates = selection.correctionCandidates;
    final results = selection.correctionResults;
    final shared = _sharedDisplayNames([
      for (final c in candidates) c.item,
      ...results,
    ]);
    final theme = Theme.of(context);
    return Container(
      key: const Key('correction-offer'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GridColors.inset,
        border: Border.all(color: GridColors.gold),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Scan #${offer.reportId} not accepted — pick the item',
                  style: const TextStyle(
                    color: GridColors.gold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                key: const Key('correction-dismiss'),
                onPressed: selection.dismissCorrection,
                child: const Text('Dismiss'),
              ),
            ],
          ),
          Text('Read: ${offer.ocrText}', style: theme.textTheme.bodySmall),
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in candidates)
                  OutlinedButton(
                    key: Key('correction-candidate-${c.item.id}'),
                    onPressed: () =>
                        selection.selectCorrection(offer.reportId, c.item.id),
                    child: Text(
                      '${_rowLabel(c.item, shared)} • '
                      '${c.score.toStringAsFixed(2)}',
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            key: const Key('correction-query'),
            controller: _controller,
            onChanged: selection.setCorrectionQuery,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Search items',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 4),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'No items match',
                key: const Key('correction-no-match'),
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            for (final item in results)
              InkWell(
                key: Key('correction-result-${item.id}'),
                onTap: () =>
                    selection.selectCorrection(offer.reportId, item.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(_rowLabel(item, shared)),
                ),
              ),
        ],
      ),
    );
  }
}

/// The display names that two or more different [items] share.
///
/// An item listed twice, as a candidate and as a search result, counts once.
Set<String> _sharedDisplayNames(Iterable<CatalogItem> items) {
  final idsByName = <String, Set<String>>{};
  for (final item in items) {
    (idsByName[normaliseTitle(item.name)] ??= <String>{}).add(item.id);
  }
  return {
    for (final MapEntry(:key, :value) in idsByName.entries)
      if (value.length > 1) key,
  };
}

/// The row text for [item]: its name, followed by its flea status and the
/// last 6 characters of its ID when another listed row shares its display
/// name (a member of [shared]).
///
/// An unknown flea status reads `flea unknown`, never `flea`.
String _rowLabel(CatalogItem item, Set<String> shared) {
  if (!shared.contains(normaliseTitle(item.name))) return item.name;
  final status = switch (item.noFlea) {
    false => 'flea',
    true => 'no flea',
    null => 'flea unknown',
  };
  final id = item.id;
  final suffix = id.length > 6 ? id.substring(id.length - 6) : id;
  return '${item.name} · $status · $suffix';
}
