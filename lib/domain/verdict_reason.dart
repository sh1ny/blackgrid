import 'decision.dart';
import 'roubles.dart';

/// The one-line, plain-language reason shown below a verdict.
///
/// It is derived from [decision] alone and is never empty. Flea and Trader
/// lines quote the gross prices the engine compared.
String verdictReason(ItemDecision decision) =>
    switch (decision.recommendation) {
      Recommendation.keep => _need(
        'Needed now for',
        decision.reasons.where((r) => r.state == NeedState.actionable),
      ),
      Recommendation.keepForLater => _need(
        'Needed later for',
        decision.reasons.where((r) => r.state == NeedState.future),
      ),
      Recommendation.check => _check(decision),
      Recommendation.flea => _flea(decision),
      Recommendation.trader => _trader(decision),
      Recommendation.priceUnavailable =>
        'No Flea or trader cash price for this item',
    };

String _need(String lead, Iterable<NeedReason> candidates) {
  if (candidates.isEmpty) return '$lead one of your tasks or hideout upgrades';
  final need = candidates.first;
  final name = need.requirement.sourceName;
  final count = need.remaining;
  if (count == null) return '$lead $name';
  final amount = count % 1 == 0 ? count.toInt().toString() : '$count';
  final suffix = need.requirement.foundInRaid == true ? ' found in raid' : '';
  return '$lead $name: $amount$suffix';
}

String _check(ItemDecision decision) {
  const order = OpenInput.values;
  final open = decision.openInputs;
  for (final input in order) {
    if (!open.contains(input)) continue;
    return switch (input) {
      OpenInput.itemData => 'Item data missing or out of date',
      OpenInput.trackerProgress => 'Tracker progress missing or out of date',
      OpenInput.foundInRaid => 'Found in raid unknown for this item',
      OpenInput.unresolvedNeed => _unresolved(decision),
      OpenInput.fleaEligibility => 'Not known if it can be sold on the Flea',
      OpenInput.priceTimeStale => 'Flea price is over an hour old',
      OpenInput.priceTimeUnknown => 'Flea price time unknown',
    };
  }
  return 'Some of what is needed to decide is not known yet';
}

String _unresolved(ItemDecision decision) {
  for (final r in decision.reasons) {
    if (r.state == NeedState.unresolved) {
      return "Can't tell yet if ${r.requirement.sourceName} needs it";
    }
  }
  return "Can't tell yet if a task or upgrade needs it";
}

String _flea(ItemDecision decision) {
  if (decision.traderGross == null) return 'No trader buys it for roubles';
  return 'Flea pays more than ${_traderName(decision)} (${rub(decision.traderGross)})';
}

String _trader(ItemDecision decision) {
  final name = _traderName(decision);
  final price = rub(decision.traderGross);
  if (decision.fleaEligible == false) {
    return "Can't be sold on the Flea; $name pays $price";
  }
  if (decision.fleaGross == null) return 'No Flea price; $name pays $price';
  return '$name pays at least the Flea ($price)';
}

String _traderName(ItemDecision decision) {
  final name = decision.traderName?.trim();
  return name == null || name.isEmpty ? 'A trader' : name;
}
