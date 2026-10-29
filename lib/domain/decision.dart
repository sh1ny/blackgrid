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
  }) : reasons = List.unmodifiable(reasons),
       warnings = List.unmodifiable(warnings);
  final Recommendation recommendation;
  final List<NeedReason> reasons;
  final List<String> warnings;
  final num? fleaGross, traderGross, fleaPerSlot, traderPerSlot;
  final String? traderId, traderName;
  final num? firNeed, nonFirNeed, unknownFirNeed;
  final bool? fleaEligible;
}
