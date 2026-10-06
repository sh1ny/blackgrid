import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/decision.dart';
import 'theme.dart';

String recommendationLabel(Recommendation value) => switch (value) {
  Recommendation.keep => 'Keep',
  Recommendation.keepForLater => 'Keep for later',
  Recommendation.check => 'Check / May Need',
  Recommendation.flea => 'Flea',
  Recommendation.trader => 'Trader',
  Recommendation.priceUnavailable => 'Price unavailable',
};

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
    listenable: services.selection,
    builder: (context, _) {
      final selection = services.selection;
      final item = selection.item;
      final decision = selection.decision;
      return GridPanel(
        title: selection.isHistory
            ? 'History inspection'
            : 'Current manual inspection',
        icon: Icons.center_focus_strong,
        subtitle: selection.isHistory
            ? 'Stored ${modeLabel(selection.inspectionMode)} context • live mode unchanged'
            : 'Shared item decision • not an accepted scan',
        trailing: selection.isHistory
            ? IconButton(
                tooltip: 'Close history inspection',
                onPressed: selection.closeHistory,
                icon: const Icon(Icons.close),
              )
            : null,
        child: item == null || decision == null
            ? ListView(
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
                        ? 'Opening stored-mode catalog…'
                        : selection.selectedId == null
                        ? 'Find an item to inspect'
                        : 'Identity retained • catalog unavailable',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    selection.error ?? 'Search real item identities, then select one. Requirements, gross values and uncertainty appear here.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final detail = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
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
                                  'Flea • gross RUB',
                                  rub(decision.fleaGross),
                                  'Per slot: ${rub(decision.fleaPerSlot)}',
                                ),
                                _value(
                                  decision.traderName ?? 'Trader • unavailable',
                                  rub(decision.traderGross),
                                  'Per slot: ${rub(decision.traderPerSlot)}',
                                ),
                                _value(
                                  'Requirement remainder',
                                  'FIR ${decision.firNeed ?? 'Unknown'}',
                                  'Non-FIR ${decision.nonFirNeed ?? 'Unknown'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Mode: ${modeLabel(selection.inspectionMode)} • FIR: ${selection.fir.name} • Values are gross, not profit.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        );
                        if (compact || constraints.maxWidth < 560) {
                          return detail;
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 185,
                              height: 220,
                              margin: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: GridColors.inset,
                                border: Border.all(
                                  color: GridColors.quietBorder,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.inventory_2_outlined,
                                    size: 68,
                                    color: GridColors.gold,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    item.shortName ?? item.normalizedName,
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
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Identity only • no artwork',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: GridColors.muted,
                                    ),
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
