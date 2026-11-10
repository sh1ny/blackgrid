import 'package:flutter/material.dart';

import '../application/accepted_scan.dart';
import '../application/app_services.dart';
import '../application/scan_correction.dart';
import '../application/selection_controller.dart';
import '../domain/roubles.dart';
import '../domain/verdict_reason.dart';
import 'correction_offer_block.dart';
import 'freshness_tag.dart';
import 'item_icon.dart';
import 'labels.dart';
import 'panels.dart';
import 'ember/theme_access.dart';
import 'verdict_plate.dart';

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
    this.showCorrectionOffer = true,
    this.fitContent = false,
  });
  final AppServices services;
  final bool compact;

  /// Sizes the content within an enclosing scrolling inspector.
  final bool fitContent;

  /// Whether the card presents the shared correction controls.
  final bool showCorrectionOffer;
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
      final offer = showCorrectionOffer ? selection.correctionOffer : null;
      final offerBlock = offer == null
          ? null
          : CorrectionOfferBlock(selection: selection, offer: offer);
      return GridPanel(
        fitContent: fitContent,
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
            ? 'Corrected from a scan • '
                  '${_correctionAge(selection, correction)} ago • '
                  'chosen by hand'
            : 'Chosen by hand',
        trailing: _trailing(selection, backToLatest ? latest : null),
        child: item == null || decision == null
            ? offerBlock != null
                  ? ListView(
                      shrinkWrap: fitContent,
                      physics: fitContent
                          ? const NeverScrollableScrollPhysics()
                          : null,
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
                      shrinkWrap: fitContent,
                      physics: fitContent
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      children: [
                        const SizedBox(height: 28),
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 72,
                          color: context.ember.inkSecondary,
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
                physics: fitContent
                    ? const NeverScrollableScrollPhysics()
                    : null,
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
                                    color: context.ember.accentText,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: name),
                                ],
                              )
                            else
                              name,
                            const SizedBox(height: 5),
                            const SizedBox(height: 14),
                            VerdictPlate(decision: decision),
                            const SizedBox(height: 8),
                            Text(
                              verdictReason(decision),
                              key: const Key('verdict-reason'),
                            ),
                            const SizedBox(height: 14),
                            Column(
                              key: const Key('price-row'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _value(
                                      context,
                                      'Flea price',
                                      rub(decision.fleaGross),
                                      'Per slot: ${rub(decision.fleaPerSlot)}',
                                    ),
                                    _value(
                                      context,
                                      decision.traderName ??
                                          'Trader unavailable',
                                      rub(decision.traderGross),
                                      'Per slot: ${rub(decision.traderPerSlot)}',
                                    ),
                                    _value(
                                      context,
                                      'Still needed',
                                      'Found in raid: ${decision.firNeed ?? 'Unknown'}',
                                      'Not found in raid: ${decision.nonFirNeed ?? 'Unknown'}',
                                    ),
                                  ],
                                ),
                                if (decision.fleaEligible != false) ...[
                                  const SizedBox(height: 8),
                                  FreshnessTag(
                                    quoteAt: item.quoteAt,
                                    now: selection.clock(),
                                    fleaEligible: decision.fleaEligible,
                                  ),
                                ],
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
                                color: context.ember.raised,
                                border: Border.all(
                                  color: context.ember.hairline,
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
                                    color: context.ember.accentText,
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
                            style: TextStyle(color: context.ember.warnInk),
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

  Widget _value(
    BuildContext context,
    String title,
    String value,
    String detail,
  ) => Container(
    width: 180,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.ember.raised,
      border: Border.all(color: context.ember.hairline),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: context.ember.inkSecondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          style: TextStyle(color: context.ember.inkSecondary, fontSize: 12),
        ),
      ],
    ),
  );
}
