import 'package:flutter/material.dart';

import '../domain/price_freshness.dart';
import 'ember/theme_access.dart';
import 'labels.dart';

/// The words of the freshness tag for [freshness], or `null` when none shows.
///
/// A fresh price reads `Prices 11:08` with the local time of the quote, taken
/// relative to [now]. A stale one reads `price 3 h old` or `price 2 d old`, and
/// an unknown one reads `price time unknown`.
String? freshnessLabel(
  PriceFreshness freshness, {
  required DateTime now,
}) => switch (freshness) {
  PriceHidden() => null,
  PriceFresh(:final time) => 'Prices ${localTimeLabel(time, now: now)}',
  PriceStale(:final amount, unit: PriceAgeUnit.hours) => 'price $amount h old',
  PriceStale(:final amount, unit: PriceAgeUnit.days) => 'price $amount d old',
  PriceUnknown() => 'price time unknown',
};

/// The tag on the decision card's price row that says how old the Flea price
/// is.
///
/// A price within [priceFreshnessLimit] gets plain `inkTertiary` text. A stale,
/// unknown or future price takes the warning style (`warnBg` fill, `warnInk`
/// text). Nothing is built when the item cannot be sold on the Flea. The widget
/// is pure: the caller passes [now], so the card's own periodic rebuild keeps
/// it current.
class FreshnessTag extends StatelessWidget {
  /// Creates the tag for a Flea price quoted at [quoteAt], as of [now].
  ///
  /// [fleaEligible] is the decision's Flea eligibility, where `false` hides
  /// the tag.
  const FreshnessTag({
    super.key,
    required this.quoteAt,
    required this.now,
    required this.fleaEligible,
  });

  /// When the Flea price was quoted, or `null` when that is not known.
  final DateTime? quoteAt;

  /// The current time.
  final DateTime now;

  /// Whether the item can be sold on the Flea, or `null` when not known.
  final bool? fleaEligible;

  @override
  Widget build(BuildContext context) {
    final freshness = priceFreshness(quoteAt, now, fleaEligible: fleaEligible);
    final label = freshnessLabel(freshness, now: now);
    if (label == null) return const SizedBox.shrink();
    final ember = context.ember;
    final warn = freshness is! PriceFresh;
    return Container(
      key: const Key('freshness-tag'),
      padding: warn
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : EdgeInsets.zero,
      decoration: warn
          ? BoxDecoration(
              color: ember.warnBg,
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Text(
        label,
        style: TextStyle(
          color: warn ? ember.warnInk : ember.inkTertiary,
          fontSize: 12,
        ),
      ),
    );
  }
}
