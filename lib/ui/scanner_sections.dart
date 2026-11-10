import 'package:flutter/material.dart';

import '../application/selection_controller.dart';
import '../domain/decision.dart';
import '../domain/roubles.dart';
import 'ember/ember_tokens.dart';
import 'ember/theme_access.dart';
import 'evidence_panels.dart';
import 'freshness_tag.dart';

/// A flat section of the Scanner's main column: a sentence-case title, a
/// subtitle and a body, with a hairline under the heading.
///
/// It has no card, border or fill of its own, so it sits on the column surface.
class ScannerSection extends StatelessWidget {
  /// Creates a section called [title] that holds [child].
  const ScannerSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  /// The sentence-case title.
  final String title;

  /// The line under the [title].
  final String subtitle;

  /// The section body.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: EmberType.uiHeading.copyWith(color: ember.ink)),
        Text(
          subtitle,
          style: EmberType.label.copyWith(color: ember.inkSecondary),
        ),
        const SizedBox(height: EmberSpace.sm),
        Divider(height: 1, thickness: 1, color: ember.hairline),
        const SizedBox(height: EmberSpace.sm),
        child,
      ],
    );
  }
}

/// The text that stands in for [selection]'s missing item, in the words of
/// [subject] (`needs` or `prices`).
String _emptyText(SelectionController selection, String subject) =>
    selection.selectedId == null
    ? 'Pick or scan an item to see its $subject.'
    : 'Item data unavailable';

/// [value] as a whole number, or `Unknown` when it is not known.
String _whole(num? value) => value == null
    ? 'Unknown'
    : value % 1 == 0
    ? value.toInt().toString()
    : '$value';

/// What the inspected item is still needed for.
///
/// It opens with the still-needed totals, then the decision's warnings in
/// warning ink (without the one that repeats the found-in-raid question the
/// answer strip already asks), then the item's requirement rows. It reads the
/// same `selection.decision` over `inspectionCatalog` for a history item as
/// for a live one.
class WhySection extends StatelessWidget {
  /// Creates the section over [selection], keeping optional uses in
  /// [expansion].
  const WhySection({
    super.key,
    required this.selection,
    required this.expansion,
  });

  /// The selection whose decision is shown.
  final SelectionController selection;

  /// The optional-uses expansion state, owned by the Scanner screen.
  final RequirementExpansion expansion;

  @override
  Widget build(BuildContext context) => ScannerSection(
    title: 'Why',
    subtitle: 'What this item is still needed for',
    child: ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final decision = selection.decision;
        if (decision == null) return Text(_emptyText(selection, 'needs'));
        final ember = context.ember;
        final warnings = [
          for (final warning in decision.warnings)
            if (warning != foundInRaidUnknownWarning) warning,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Still needed · Found in raid ${_whole(decision.firNeed)}'
              ' · Not found in raid ${_whole(decision.nonFirNeed)}',
              key: const Key('why-summary'),
              style: EmberType.body.copyWith(
                color: ember.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(top: EmberSpace.xs),
                child: Text(
                  warning,
                  style: EmberType.body.copyWith(color: ember.warnInk),
                ),
              ),
            const SizedBox(height: EmberSpace.sm),
            if (decision.reasons.isEmpty)
              Text(
                'No catalog requirement references. '
                'Tracker progress may still be unknown.',
                style: EmberType.label.copyWith(color: ember.inkSecondary),
              )
            else
              RequirementList(
                reasons: decision.reasons,
                catalog: selection.inspectionCatalog,
                expansion: expansion,
              ),
          ],
        );
      },
    ),
  );
}

/// The inspected item's Flea and trader prices, per item and per slot.
///
/// The Flea price is tarkov.dev's 24 hour average, before Flea fees. Values
/// are right-aligned in tabular figures, and a price that is missing reads
/// `Price unavailable` rather than leaving a blank.
class PricesSection extends StatelessWidget {
  /// Creates the section over [selection].
  const PricesSection({super.key, required this.selection});

  /// The selection whose decision and item are shown.
  final SelectionController selection;

  @override
  Widget build(BuildContext context) => ScannerSection(
    title: 'Prices',
    subtitle: 'Prices are per item and per slot, before Flea fees',
    child: ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final decision = selection.decision;
        final item = selection.item;
        if (decision == null || item == null) {
          return Text(_emptyText(selection, 'prices'));
        }
        final fleaSold = decision.fleaEligible != false;
        final fleaPrice = fleaSold ? decision.fleaGross : null;
        String price(num? value) =>
            value == null ? 'Price unavailable' : rub(value);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PriceRow(
              key: const Key('prices-flea'),
              label: 'Flea',
              detail: fleaSold ? '24 h average' : null,
              value: Text(
                fleaSold ? price(fleaPrice) : "Can't be sold on the Flea",
              ),
            ),
            _PriceRow(
              key: const Key('prices-trader'),
              label: 'Trader',
              detail: decision.traderGross == null ? null : decision.traderName,
              value: Text(price(decision.traderGross)),
            ),
            if (fleaSold)
              _PriceRow(
                key: const Key('prices-per-slot-flea'),
                label: 'Per slot',
                detail: 'Flea',
                value: Text(
                  price(fleaPrice == null ? null : decision.fleaPerSlot),
                ),
              ),
            _PriceRow(
              key: const Key('prices-per-slot-trader'),
              label: fleaSold ? '' : 'Per slot',
              detail: 'Trader',
              value: Text(
                price(
                  decision.traderGross == null ? null : decision.traderPerSlot,
                ),
              ),
            ),
            _PriceRow(
              key: const Key('prices-updated'),
              label: 'Updated',
              detail: 'tarkov.dev',
              value: fleaPrice == null
                  ? const SizedBox.shrink()
                  : FreshnessTag(
                      quoteAt: item.quoteAt,
                      now: selection.clock().toUtc(),
                      fleaEligible: decision.fleaEligible,
                    ),
            ),
          ],
        );
      },
    ),
  );
}

/// One dense price row: a label, a detail and a right-aligned value.
class _PriceRow extends StatelessWidget {
  const _PriceRow({
    super.key,
    required this.label,
    required this.detail,
    required this.value,
  });

  final String label;
  final String? detail;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EmberSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 76 * scale,
            child: Text(
              label,
              style: EmberType.label.copyWith(color: ember.inkSecondary),
            ),
          ),
          Expanded(
            child: Text(
              detail ?? '',
              style: EmberType.label.copyWith(color: ember.inkSecondary),
            ),
          ),
          // The value's slot is twice the detail's, and the value sits at its
          // end, so the values share one right edge and wrap before they
          // overflow.
          Flexible(
            flex: 2,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: DefaultTextStyle.merge(
                style: EmberType.body.copyWith(color: ember.ink),
                textAlign: TextAlign.end,
                child: value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
