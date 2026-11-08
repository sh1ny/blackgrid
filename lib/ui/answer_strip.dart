import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../domain/inspection_context.dart';
import '../domain/decision.dart';
import '../domain/roubles.dart';
import 'ember/ember_tokens.dart';
import '../domain/verdict_reason.dart';
import 'ember/theme_access.dart';
import 'freshness_tag.dart';
import 'item_icon.dart';
import 'item_decision_card.dart' show CorrectionOfferBlock;
import 'verdict_plate.dart';

/// The shared current inspection shown before either workspace.
///
/// Selection and Found in raid remain owned by the existing selection
/// controller. The strip grows when the reason or text scale needs more room.
class AnswerStrip extends StatelessWidget {
  /// Creates the strip using the shared application [services].
  const AnswerStrip({super.key, required this.services});

  /// The current inspection and item icon cache.
  final AppServices services;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([services.selection, services.scans]),
    builder: (context, _) {
      final selection = services.selection;
      final item = selection.item;
      final decision = selection.decision;
      final latest = services.scans.latest;
      final offer = selection.correctionOffer;
      return Container(
        key: const Key('answer-strip'),
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: context.ember.panel,
          border: Border(bottom: BorderSide(color: context.ember.hairline)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            item == null || decision == null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selection.loadingHistory
                              ? 'Opening saved item data…'
                              : selection.selectedId == null
                              ? offer == null
                                    ? selection.scanRetired
                                          ? 'Last scan was in an earlier mode or session; scan again'
                                          : 'Find an item'
                                    : 'Scan needs review'
                              : 'Item data unavailable',
                        ),
                        if (selection.selectedId == null &&
                            !selection.loadingHistory &&
                            offer == null)
                          const Text('Search with Ctrl K'),
                        if (selection.isHistory)
                          IconButton(
                            tooltip: 'Close history inspection',
                            onPressed: selection.closeHistory,
                            icon: const Icon(Icons.close),
                          ),
                        if (latest != null &&
                            selection.scan?.reportId != latest.reportId)
                          TextButton(
                            onPressed: () {
                              final current = services.scans.latest;
                              if (current != null) selection.showScan(current);
                            },
                            child: const Text('Back to latest scan'),
                          ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final fleaPrice = decision.fleaEligible != false
                          ? decision.fleaGross
                          : null;
                      final price = fleaPrice ?? decision.traderGross;
                      final parts = <Widget>[
                        ItemIcon(
                          cache: services.itemIcons,
                          itemId: item.id,
                          iconLink: item.iconLink,
                          size: 48,
                          color: context.ember.accentText,
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: EmberType.title),
                              if (!selection.isHistory &&
                                  selection.scan != null)
                                const Text('Accepted scan')
                              else if (!selection.isHistory &&
                                  selection.correction != null)
                                const Text('Corrected scan'),
                              if (selection.isHistory)
                                const Text(
                                  'Current advice for history inspection',
                                ),
                            ],
                          ),
                        ),
                        AnswerVerdict(
                          decision: decision,
                          maxWidth: constraints.maxWidth < 1300
                              ? 460
                              : (constraints.maxWidth - 60).clamp(
                                  1,
                                  double.infinity,
                                ),
                        ),
                        FirControls(services: services),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              price == null
                                  ? 'Price unavailable'
                                  : '${fleaPrice != null ? "Flea" : "Trader"} ${rub(price)}',
                              key: const Key('answer-price'),
                            ),
                            if (fleaPrice != null)
                              FreshnessTag(
                                quoteAt: item.quoteAt,
                                now: selection.clock(),
                                fleaEligible: decision.fleaEligible,
                              )
                            else
                              const Text('price time unknown'),
                          ],
                        ),
                        if (selection.isHistory)
                          IconButton(
                            tooltip: 'Close history inspection',
                            onPressed: selection.closeHistory,
                            icon: const Icon(Icons.close),
                          ),
                        if (latest != null &&
                            selection.scan?.reportId != latest.reportId)
                          TextButton(
                            onPressed: () {
                              final current = services.scans.latest;
                              if (current != null) selection.showScan(current);
                            },
                            child: const Text('Back to latest scan'),
                          ),
                      ];
                      if (constraints.maxWidth >= 1300 &&
                          MediaQuery.textScalerOf(context).scale(1) <= 1.2) {
                        return Row(
                          children: [
                            parts[0],
                            const SizedBox(width: 12),
                            parts[1],
                            const SizedBox(width: 12),
                            Expanded(child: parts[2]),
                            const SizedBox(width: 12),
                            parts[3],
                            const SizedBox(width: 12),
                            parts[4],
                            for (final part in parts.skip(5)) ...[
                              const SizedBox(width: 12),
                              part,
                            ],
                          ],
                        );
                      }
                      return Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: parts,
                      );
                    },
                  ),
            if (selection.error != null)
              Text(
                selection.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (offer != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * .18).clamp(
                    64,
                    130,
                  ),
                ),
                child: SingleChildScrollView(
                  child: CorrectionOfferBlock(
                    selection: selection,
                    offer: offer,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Per-item Found in raid selector shared with manual inspection.
class FirControls extends StatelessWidget {
  /// Creates a selector bound to [services]' selection controller.
  const FirControls({super.key, required this.services});

  /// The owner of the current item's FIR state.
  final AppServices services;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text('Found in raid'),
      for (final fir in FirState.values)
        ChoiceChip(
          label: Text(switch (fir) {
            FirState.unknown => 'Unknown',
            FirState.yes => 'Yes',
            FirState.no => 'No',
          }),
          selected: services.selection.fir == fir,
          onSelected: services.selection.item == null
              ? null
              : (_) => services.selection.setFir(fir),
        ),
    ],
  );
}

/// The complete verdict plate and its wrapping reason in the answer strip.
class AnswerVerdict extends StatelessWidget {
  /// Creates the verdict from the already projected [decision].
  const AnswerVerdict({super.key, required this.decision, this.maxWidth = 420});

  /// The existing selection controller's projected advice.
  final ItemDecision decision;

  /// Maximum width available for the reason to wrap.
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth.clamp(1, double.infinity)),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final plate = IntrinsicWidth(child: VerdictPlate(decision: decision));
        final reason = Text(
          verdictReason(decision),
          key: const Key('answer-verdict-reason'),
        );
        if (constraints.maxWidth >= 600 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.2) {
          return Row(
            children: [
              plate,
              const SizedBox(width: 8),
              Expanded(child: reason),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [plate, reason],
        );
      },
    ),
  );
}
