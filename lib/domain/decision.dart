import 'catalog.dart';

enum Recommendation {
  keep,
  keepForLater,
  check,
  flea,
  trader,
  priceUnavailable,
}

enum NeedState { actionable, future, unresolved, satisfied, irrelevant }

/// An input the engine still needs before it can give a firm answer.
///
/// The engine records these in the order they are declared here, which is the
/// order the verdict reason names them.
enum OpenInput {
  /// Item data is missing or out of date.
  itemData,

  /// Tracker progress is missing or out of date.
  trackerProgress,

  /// Whether the item was found in raid is unknown.
  foundInRaid,

  /// A need could not be resolved from the data at hand.
  unresolvedNeed,

  /// Whether the item can be sold on the Flea is unknown.
  fleaEligibility,

  /// The Flea price time is over the freshness limit.
  priceTimeStale,

  /// The Flea price time is missing or in the future.
  priceTimeUnknown,
}

/// The warning the engine adds when found in raid is unknown for the item.
const String foundInRaidUnknownWarning = 'Found in raid unknown for this item';

class NeedReason {
  const NeedReason({
    required this.requirement,
    required this.state,
    required this.message,
    required this.detail,
    this.remaining,
  });
  final ItemRequirement requirement;
  final NeedState state;
  final String message;

  /// The reason itself, without the `<sourceName>: ` prefix of [message].
  final String detail;
  final num? remaining;
}

class ItemDecision {
  ItemDecision({
    required this.recommendation,
    required Iterable<NeedReason> reasons,
    required Iterable<String> warnings,
    this.fleaGross,
    this.traderGross,
    this.traderId,
    this.traderName,
    this.fleaPerSlot,
    this.traderPerSlot,
    this.firNeed,
    this.nonFirNeed,
    this.unknownFirNeed,
    this.fleaEligible,
    Iterable<OpenInput> openInputs = const [],
  }) : reasons = List.unmodifiable(reasons),
       warnings = List.unmodifiable(warnings),
       openInputs = List.unmodifiable(openInputs);
  final Recommendation recommendation;
  final List<NeedReason> reasons;
  final List<String> warnings;
  final num? fleaGross, traderGross, fleaPerSlot, traderPerSlot;
  final String? traderId, traderName;
  final num? firNeed, nonFirNeed, unknownFirNeed;
  final bool? fleaEligible;

  /// Why the decision is open, in the engine's fixed order; empty when firm.
  final List<OpenInput> openInputs;
}
