import 'package:blackgrid_progress/blackgrid_progress.dart'
    show ProgressCatalog;

import 'catalog.dart';
import 'decision.dart';
import 'inspection_context.dart';
import 'price_freshness.dart';
import 'local_progress.dart' show ProgressTaskStatus;
import 'progress_facts.dart';

class DecisionEngine {
  const DecisionEngine();

  ItemDecision evaluate(CatalogItem item, InspectionContext context) {
    final catalog = context.catalog;
    final progress = context.progress;
    final catalogKnown =
        catalog != null &&
        catalog.mode == context.mode &&
        context.mode != GameMode.unknown &&
        catalog.items.containsKey(item.id) &&
        !context.catalogStale &&
        catalog.authoritativeAt(context.now);
    final progressKnown =
        progress != null &&
        progress.mode == context.mode &&
        context.mode != GameMode.unknown;
    final warnings = <String>[];
    final open = <OpenInput>[];
    if (!catalogKnown) {
      warnings.add('Item data missing or out of date');
      open.add(OpenInput.itemData);
    }
    if (!progressKnown) {
      warnings.add('Progress unavailable');
      open.add(OpenInput.progress);
    }
    if (context.fir == FirState.unknown) {
      warnings.add(foundInRaidUnknownWarning);
      open.add(OpenInput.foundInRaid);
    }
    final requirements =
        catalog?.requirementIndex[item.id] ?? const <ItemRequirement>[];
    final reasons = <NeedReason>[];
    for (final r in requirements) {
      reasons.add(
        _need(
          r,
          catalogKnown && progressKnown ? progress : null,
          context.fir,
          catalog?.progressCatalog,
        ),
      );
    }
    num? total(bool? fir) {
      if (!catalogKnown || !progressKnown) return null;
      num sum = 0;
      if (fir != null &&
          reasons.any(
            (r) =>
                r.requirement.foundInRaid == null &&
                r.state != NeedState.irrelevant &&
                r.state != NeedState.satisfied,
          )) {
        return null;
      }
      for (final r in reasons) {
        if (r.requirement.foundInRaid != fir ||
            r.state == NeedState.satisfied ||
            r.state == NeedState.irrelevant &&
                (r.remaining == null || r.remaining == 0)) {
          continue;
        }
        // An alternative group describes a shared quantity, not this item's exact obligation.
        if (r.remaining == null || r.requirement.itemIds.length > 1) {
          return null;
        }
        sum += r.remaining!;
      }
      return sum;
    }

    final flea = _positive(item.fleaPrice);
    CashOffer? best;
    if (catalog != null) {
      for (final offer in item.sellOffers) {
        if (offer.barter ||
            offer.currency != 'RUB' ||
            _positive(offer.price) == null ||
            catalog.traders[offer.traderId]?.name?.trim().isNotEmpty != true) {
          continue;
        }
        if (best == null ||
            offer.price! > best.price! ||
            offer.price == best.price &&
                offer.traderId.compareTo(best.traderId) < 0) {
          best = offer;
        }
      }
    }
    final eligible = _fleaEligible(
      item,
      progressKnown ? progress : null,
      context.fir,
    );
    final unresolved = reasons.any((r) => r.state == NeedState.unresolved);
    if (unresolved) open.add(OpenInput.unresolvedNeed);
    if (eligible == null) {
      warnings.add(
        'Not known whether this item can be sold on the flea market',
      );
      open.add(OpenInput.fleaEligibility);
    }
    final quote = item.quoteAt;
    final quoteInFuture = quote != null && quote.isAfter(context.now);
    final marketKnown =
        quote != null &&
        !quoteInFuture &&
        context.now.difference(quote) <= priceFreshnessLimit;
    if (!marketKnown && eligible != false) {
      warnings.add('Flea price time unknown or more than an hour old');
      open.add(
        quote == null || quoteInFuture
            ? OpenInput.priceTimeUnknown
            : OpenInput.priceTimeStale,
      );
    }
    final Recommendation recommendation;
    if (reasons.any((r) => r.state == NeedState.actionable)) {
      recommendation = Recommendation.keep;
    } else if (reasons.any((r) => r.state == NeedState.future)) {
      recommendation = Recommendation.keepForLater;
    } else if (!catalogKnown ||
        !progressKnown ||
        context.fir == FirState.unknown ||
        unresolved ||
        eligible == null ||
        (!marketKnown && eligible != false)) {
      recommendation = Recommendation.check;
    } else if (eligible == true &&
        flea != null &&
        (best == null || flea > best.price!)) {
      recommendation = Recommendation.flea;
    } else if (best != null) {
      recommendation = Recommendation.trader;
    } else {
      recommendation = Recommendation.priceUnavailable;
    }
    final slots = item.slots;
    return ItemDecision(
      recommendation: recommendation,
      reasons: reasons,
      warnings: warnings,
      fleaGross: flea,
      traderGross: best?.price,
      traderId: best?.traderId,
      traderName: best == null ? null : catalog?.traders[best.traderId]?.name,
      fleaPerSlot: _perSlot(flea, slots),
      traderPerSlot: _perSlot(best?.price, slots),
      firNeed: total(true),
      nonFirNeed: total(false),
      unknownFirNeed: total(null),
      fleaEligible: eligible,
      openInputs: open,
    );
  }

  NeedReason _need(
    ItemRequirement r,
    ProgressFacts? p,
    FirState fir,
    ProgressCatalog? progressCatalog,
  ) {
    NeedReason reason(NeedState state, String detail, [num? remaining]) =>
        NeedReason(
          requirement: r,
          state: state,
          message: '${r.sourceName}: $detail',
          detail: detail,
          remaining: remaining,
        );
    if (r.optional ||
        r.kind == RequirementKind.craft ||
        r.kind == RequirementKind.barter) {
      return reason(
        NeedState.irrelevant,
        'optional use, not an automatic obligation',
      );
    }
    if (p == null) {
      return reason(NeedState.unresolved, 'Progress or item data unknown');
    }
    var started = false;
    if (r.kind == RequirementKind.task) {
      // ADR-0043 order: a recorded finished, failed or started state decides
      // before any gate does.
      switch (p.taskState(r.sourceId)) {
        case ProgressTaskStatus.finished:
          return reason(NeedState.satisfied, 'task completed', 0);
        case ProgressTaskStatus.failed
            when progressCatalog?.tasksById[r.sourceId]?.restartable != true:
          return reason(
            NeedState.satisfied,
            'task failed; no active obligation',
            0,
          );
        case ProgressTaskStatus.started:
          started = true;
        case ProgressTaskStatus.failed || null:
          break;
      }
    } else {
      final stationId = r.stationId;
      final level = r.stationLevel;
      if (stationId == null || level == null) {
        return reason(NeedState.unresolved, 'station module status unknown');
      }
      if (p.stationLevel(stationId) >= level) {
        return reason(NeedState.satisfied, 'station module completed', 0);
      }
    }
    final gate = started ? NeedState.actionable : _gate(r, p);
    if (gate == NeedState.irrelevant) {
      return reason(gate, 'does not apply to you', 0);
    }
    if (r.ambiguousProgressIdentity) {
      return reason(
        NeedState.unresolved,
        'several tasks share this progress, so it cannot be told apart',
      );
    }
    final isTask = r.kind == RequirementKind.task;
    // Hideout parts are never recorded: they count 0 until the level is built.
    int count(String id) => isTask ? p.objectiveCount(id) : 0;
    bool complete(String id) => isTask && p.objectiveComplete(id);
    final completionId = r.completionId;
    if (completionId != null
        ? complete(completionId)
        : r.progressIds.any(complete)) {
      return reason(NeedState.satisfied, 'requirement completed', 0);
    }
    if (r.count == null || !r.count!.isFinite || r.count! < 0) {
      return reason(
        NeedState.unresolved,
        'progress or amount needed is unknown',
      );
    }
    if (r.count == 0) {
      return reason(NeedState.satisfied, 'no quantity required', 0);
    }
    num? remaining;
    for (final id in r.progressIds) {
      final value = (r.count! - count(id)).clamp(0, r.count!);
      if (remaining == null || value > remaining) remaining = value;
    }
    if (remaining == 0) {
      return reason(NeedState.satisfied, 'quantity satisfied', 0);
    }
    if (r.foundInRaid == null) {
      return reason(
        NeedState.unresolved,
        'whether it must be found in raid is unknown',
        remaining,
      );
    }
    if (r.foundInRaid == true && fir == FirState.no) {
      return reason(
        NeedState.irrelevant,
        'needs a found-in-raid item; this one is not',
        remaining,
      );
    }
    if (r.foundInRaid == true && fir == FirState.unknown) {
      return reason(
        NeedState.unresolved,
        'needs a found-in-raid item; unknown for this one',
        remaining,
      );
    }
    if (gate == NeedState.unresolved) {
      return reason(
        gate,
        'not known yet whether you can do this (level, trader, skill or another requirement)',
        remaining,
      );
    }
    return reason(
      gate,
      gate == NeedState.future ? 'needed later' : 'needed now',
      remaining,
    );
  }

  NeedState _gate(ItemRequirement r, ProgressFacts p) {
    final g = r.gate;
    var future = false;
    var unknown = g.incomplete || g.unknownTraderOrSkill;
    if (r.kind == RequirementKind.task &&
        (g.minPlayerLevel == null ||
            g.faction == null ||
            g.taskStatuses == null ||
            g.editions == null && g.editionIds == null)) {
      unknown = true;
    }
    if (g.faction != null && g.faction != 'Any') {
      if (p.faction == null) {
        unknown = true;
      } else if (g.faction!.toUpperCase() != p.faction) {
        return NeedState.irrelevant;
      }
    }
    // The item data's edition values have no reviewed mapping to the recorded
    // edition, so any listed edition leaves the gate unknown.
    if (g.editionIds?.isNotEmpty == true || g.editions?.isNotEmpty == true) {
      unknown = true;
    }
    final minLevel = g.minPlayerLevel;
    if (minLevel != null && minLevel > 1) {
      final level = p.level;
      if (level == null) {
        unknown = true;
      } else if (level < minLevel) {
        future = true;
      }
    }
    for (final e
        in (g.taskStatuses ?? const <String, List<String>>{}).entries) {
      if (e.value.isEmpty) {
        unknown = true;
        continue;
      }
      final String? status = switch (p.taskState(e.key)) {
        ProgressTaskStatus.finished => 'complete',
        ProgressTaskStatus.failed => 'failed',
        ProgressTaskStatus.started || null => null,
      };
      if (status == null) {
        if (e.value.length == 1 && e.value.single == 'complete') {
          future = true;
        } else {
          unknown = true;
        }
      } else if (!e.value.contains(status)) {
        if (status == 'failed' && e.value.contains('complete')) {
          return NeedState.irrelevant;
        }
        unknown = true;
      }
    }
    for (final e in (g.stations ?? const <String, int>{}).entries) {
      if (p.stationLevel(e.key) < e.value) future = true;
    }
    final stationId = r.stationId;
    final stationLevel = r.stationLevel;
    if (r.kind == RequirementKind.hideout &&
        stationId != null &&
        stationLevel != null &&
        stationLevel > 1 &&
        p.stationLevel(stationId) < stationLevel - 1) {
      future = true;
    }
    return unknown
        ? NeedState.unresolved
        : future
        ? NeedState.future
        : NeedState.actionable;
  }

  bool? _fleaEligible(CatalogItem item, ProgressFacts? progress, FirState fir) {
    if (item.noFlea == true || fir == FirState.no) return false;
    if (item.noFlea == null ||
        item.minLevelForFlea == null ||
        item.minLevelForFlea! < 0 ||
        progress?.level == null ||
        fir == FirState.unknown) {
      return null;
    }
    return progress!.level! >= item.minLevelForFlea!;
  }
}

num? _positive(num? value) =>
    value != null && value.isFinite && value > 0 ? value : null;
num? _perSlot(num? value, num? slots) {
  if (value == null || slots == null) return null;
  final result = value / slots;
  return result.isFinite ? result : null;
}
