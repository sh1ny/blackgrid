import 'package:flutter/material.dart';

import '../application/scan_correction.dart';
import '../application/selection_controller.dart';
import '../domain/catalog.dart';
import '../domain/title_matching.dart' show normaliseTitle;
import 'ember/theme_access.dart';

/// Candidate and search controls for a scan awaiting manual correction.
///
/// Owns the search field controller and synchronizes it with the offer's query
/// whenever the selection notifies.
class CorrectionOfferBlock extends StatefulWidget {
  /// Creates controls bound to [selection] and its current [offer].
  const CorrectionOfferBlock({
    super.key,
    required this.selection,
    required this.offer,
  });

  /// The owner of the current query, candidates, and correction actions.
  final SelectionController selection;

  /// The scan awaiting manual correction.
  final ScanCorrectionOffer offer;

  @override
  State<CorrectionOfferBlock> createState() => _CorrectionOfferBlockState();
}

class _CorrectionOfferBlockState extends State<CorrectionOfferBlock> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.offer.query,
  );

  @override
  void didUpdateWidget(CorrectionOfferBlock oldWidget) {
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
        color: context.ember.raised,
        border: Border.all(color: context.ember.accentLine),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last scan not accepted — pick the item',
                  style: TextStyle(
                    color: context.ember.accentText,
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
                    child: Text(_rowLabel(c.item, shared)),
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
