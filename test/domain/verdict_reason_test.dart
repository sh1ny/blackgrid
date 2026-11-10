import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/need_title.dart';
import 'package:blackgrid/domain/verdict_reason.dart';

import '../ui/support/plain_language_check.dart';

NeedReason need(
  String source,
  NeedState state, {
  num? remaining,
  bool? foundInRaid,
  RequirementKind kind = RequirementKind.task,
  int? stationLevel,
}) => NeedReason(
  requirement: ItemRequirement(
    kind: kind,
    stationLevel: stationLevel,
    sourceId: 'source-$source',
    sourceName: source,
    id: 'req-$source',
    itemIds: const ['item-a'],
    progressIds: const [],
    count: remaining,
    foundInRaid: foundInRaid,
    gate: RequirementGate(),
  ),
  state: state,
  message: '$source: detail',
  detail: 'detail',
  remaining: remaining,
);

ItemDecision decision(
  Recommendation recommendation, {
  List<NeedReason> reasons = const [],
  List<OpenInput> open = const [],
  num? fleaGross,
  num? traderGross,
  String? traderName,
  bool? fleaEligible,
}) => ItemDecision(
  recommendation: recommendation,
  reasons: reasons,
  warnings: const [],
  openInputs: open,
  fleaGross: fleaGross,
  traderGross: traderGross,
  traderName: traderName,
  fleaEligible: fleaEligible,
);

void main() {
  test('Keep names the first actionable need with its count', () {
    final d = decision(
      Recommendation.keep,
      reasons: [
        need('Debut', NeedState.future, remaining: 1),
        need('Shortage', NeedState.actionable, remaining: 3, foundInRaid: true),
        need('Other', NeedState.actionable, remaining: 9),
      ],
    );
    expect(verdictReason(d), 'Needed now for Shortage: 3 found in raid');
  });

  test('Keep with an unknown count has no number', () {
    final d = decision(
      Recommendation.keep,
      reasons: [need('Shortage', NeedState.actionable)],
    );
    expect(verdictReason(d), 'Needed now for Shortage');
  });

  test('Keep for later names the first future need', () {
    final d = decision(
      Recommendation.keepForLater,
      reasons: [
        need('Debut', NeedState.satisfied, remaining: 0),
        need(
          'Medstation',
          NeedState.future,
          remaining: 2,
          kind: RequirementKind.hideout,
        ),
        need('Later task', NeedState.future, remaining: 5),
      ],
    );
    expect(verdictReason(d), 'Needed later for Medstation: 2');
  });

  test('Check with only found in raid open names it', () {
    final d = decision(
      Recommendation.check,
      open: const [OpenInput.foundInRaid],
    );
    expect(verdictReason(d), 'Found in raid unknown for this item');
  });

  test('Check names the first open input in the fixed order', () {
    final d = decision(
      Recommendation.check,
      reasons: [need('Shortage', NeedState.unresolved)],
      open: const [
        OpenInput.trackerProgress,
        OpenInput.foundInRaid,
        OpenInput.unresolvedNeed,
        OpenInput.fleaEligibility,
        OpenInput.priceTimeStale,
      ],
    );
    expect(verdictReason(d), 'Tracker progress missing or out of date');
    final later = decision(
      Recommendation.check,
      open: const [OpenInput.fleaEligibility, OpenInput.priceTimeUnknown],
    );
    expect(verdictReason(later), 'Not known if it can be sold on the Flea');
  });

  test('Check wording for each open input', () {
    String reasonFor(OpenInput input) => verdictReason(
      decision(
        Recommendation.check,
        reasons: [need('Shortage', NeedState.unresolved)],
        open: [input],
      ),
    );
    expect(reasonFor(OpenInput.itemData), 'Item data missing or out of date');
    expect(
      reasonFor(OpenInput.trackerProgress),
      'Tracker progress missing or out of date',
    );
    expect(
      reasonFor(OpenInput.foundInRaid),
      'Found in raid unknown for this item',
    );
    expect(
      reasonFor(OpenInput.unresolvedNeed),
      "Can't tell yet if Shortage needs it",
    );
    expect(
      reasonFor(OpenInput.fleaEligibility),
      'Not known if it can be sold on the Flea',
    );
    expect(
      reasonFor(OpenInput.priceTimeStale),
      'Flea price is over an hour old',
    );
    expect(reasonFor(OpenInput.priceTimeUnknown), 'Flea price time unknown');
  });

  test('found in raid outranks an unresolved found-in-raid need', () {
    final d = decision(
      Recommendation.check,
      reasons: [
        need('Shortage', NeedState.unresolved, remaining: 2, foundInRaid: true),
      ],
      open: const [OpenInput.foundInRaid, OpenInput.unresolvedNeed],
    );
    expect(
      verdictReason(d),
      'Found in raid unknown: Shortage needs it found in raid',
    );
  });

  test('Found in raid unknown names the first need that requires it', () {
    final d = decision(
      Recommendation.check,
      reasons: [
        need('Plain', NeedState.unresolved, remaining: 1),
        need(
          'Medstation',
          NeedState.unresolved,
          remaining: 2,
          foundInRaid: true,
          kind: RequirementKind.hideout,
          stationLevel: 1,
        ),
        need('Later', NeedState.unresolved, remaining: 2, foundInRaid: true),
      ],
      open: const [OpenInput.foundInRaid],
    );
    expect(
      verdictReason(d),
      'Found in raid unknown: Medstation level 1 needs it found in raid',
    );
  });

  test('Needs that do not apply are skipped', () {
    final d = decision(
      Recommendation.check,
      reasons: [
        need('Optional', NeedState.irrelevant, remaining: 1, foundInRaid: true),
        need('Shortage', NeedState.unresolved, remaining: 2, foundInRaid: true),
      ],
      open: const [OpenInput.foundInRaid],
    );
    expect(
      verdictReason(d),
      'Found in raid unknown: Shortage needs it found in raid',
    );
    final none = decision(
      Recommendation.check,
      reasons: [
        need('Optional', NeedState.irrelevant, remaining: 1, foundInRaid: true),
      ],
      open: const [OpenInput.foundInRaid],
    );
    expect(verdictReason(none), 'Found in raid unknown for this item');
  });

  test('needTitle names a station level or a task', () {
    expect(
      needTitle(
        need(
          'Medstation',
          NeedState.future,
          kind: RequirementKind.hideout,
          stationLevel: 1,
        ).requirement,
      ),
      'Medstation level 1',
    );
    expect(
      needTitle(
        need(
          'Medstation',
          NeedState.future,
          kind: RequirementKind.hideout,
        ).requirement,
      ),
      'Medstation',
    );
    expect(needTitle(need('Debut', NeedState.future).requirement), 'Debut');
  });

  test('Flea compares gross prices with the best trader', () {
    final d = decision(
      Recommendation.flea,
      fleaGross: 38277,
      traderGross: 7695,
      traderName: 'Therapist',
      fleaEligible: true,
    );
    expect(verdictReason(d), 'Flea pays more than Therapist (₽7695)');
  });

  test('Trader wording for each engine path', () {
    String reasonFor({num? flea, bool? eligible}) => verdictReason(
      decision(
        Recommendation.trader,
        fleaGross: flea,
        traderGross: 7695,
        traderName: 'Therapist',
        fleaEligible: eligible,
      ),
    );
    expect(
      reasonFor(flea: 9000, eligible: false),
      "Can't be sold on the Flea; Therapist pays ₽7695",
    );
    expect(reasonFor(eligible: true), 'No Flea price; Therapist pays ₽7695');
    expect(
      reasonFor(flea: 7695, eligible: true),
      'Therapist pays at least the Flea (₽7695)',
    );
  });

  test('Flea with no trader offer', () {
    final d = decision(Recommendation.flea, fleaGross: 400, fleaEligible: true);
    expect(verdictReason(d), 'No trader buys it for roubles');
  });

  test('Price unavailable wording', () {
    expect(
      verdictReason(decision(Recommendation.priceUnavailable)),
      'No Flea or trader cash price for this item',
    );
  });

  test('every verdict gets a non-empty reason even with no data', () {
    for (final r in Recommendation.values) {
      expect(verdictReason(decision(r)), isNotEmpty, reason: '$r');
    }
  });

  test('the reason wording keeps developer terms out', () {
    final path = 'lib/domain/verdict_reason.dart';
    final hits = findBannedTermHits(path, File(path).readAsStringSync());
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
