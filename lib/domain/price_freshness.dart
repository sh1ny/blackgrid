/// How long a Flea price counts as current.
///
/// The decision engine and the freshness tag both read this one limit.
const priceFreshnessLimit = Duration(hours: 1);

/// The unit of a stale price's age.
enum PriceAgeUnit {
  /// Whole hours, used under 48 hours.
  hours,

  /// Whole days, used from 48 hours.
  days,
}

/// How old the Flea price is, for the tag on the decision card's price row.
sealed class PriceFreshness {
  const PriceFreshness();
}

/// No tag: the item cannot be sold on the Flea, so the Flea price time does
/// not matter.
final class PriceHidden extends PriceFreshness {
  /// Creates the hidden state.
  const PriceHidden();
}

/// The price time is within [priceFreshnessLimit].
final class PriceFresh extends PriceFreshness {
  /// Creates a fresh state for a price quoted at [time].
  const PriceFresh(this.time);

  /// When the price was quoted.
  final DateTime time;
}

/// The price time is past [priceFreshnessLimit].
final class PriceStale extends PriceFreshness {
  /// Creates a stale state aged [amount] whole [unit]s.
  const PriceStale(this.amount, this.unit);

  /// The whole number of [unit]s the price has aged.
  final int amount;

  /// Hours under 48 hours, days from then on.
  final PriceAgeUnit unit;
}

/// The price time is missing or later than now.
final class PriceUnknown extends PriceFreshness {
  /// Creates the unknown state.
  const PriceUnknown();
}

/// Classifies a Flea price quoted at [quoteAt] as of [now].
///
/// The result is hidden when [fleaEligible] is `false`, because the engine then
/// ignores the Flea price time. A time within [priceFreshnessLimit] is fresh.
/// A missing or future time is unknown. Anything older is stale, in whole hours
/// under 48 hours and whole days from then on.
PriceFreshness priceFreshness(
  DateTime? quoteAt,
  DateTime now, {
  required bool? fleaEligible,
}) {
  if (fleaEligible == false) return const PriceHidden();
  if (quoteAt == null || quoteAt.isAfter(now)) return const PriceUnknown();
  final age = now.difference(quoteAt);
  if (age <= priceFreshnessLimit) return PriceFresh(quoteAt);
  return age.inHours < 48
      ? PriceStale(age.inHours, PriceAgeUnit.hours)
      : PriceStale(age.inDays, PriceAgeUnit.days);
}
