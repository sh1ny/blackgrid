import 'catalog.dart';
import 'decision.dart';
import 'inspection_context.dart';
import 'progress.dart';

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
        context.mode != GameMode.unknown &&
        !context.progressStale &&
        progress.authoritativeAt(context.now);
    final warnings = <String>[];
    if (!catalogKnown) {
      warnings.add('Item data missing or out of date');
    }
    if (!progressKnown) warnings.add('Tracker progress missing or out of date');
    if (context.fir == FirState.unknown) {
      warnings.add('Found in raid unknown for this item');
    }
    final requirements =
        catalog?.requirementIndex[item.id] ?? const <ItemRequirement>[];
    final reasons = <NeedReason>[];
    for (final r in requirements) {
      reasons.add(
        _need(r, catalogKnown && progressKnown ? progress : null, context.fir),
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
    if (eligible == null) {
      warnings.add(
        'Not known whether this item can be sold on the flea market',
      );
    }
    final quote = item.quoteAt;
    final marketKnown =
        quote != null &&
        !quote.isAfter(context.now) &&
        context.now.difference(quote) <= const Duration(hours: 1);
    if (!marketKnown && eligible != false) {
      warnings.add('Flea price time unknown or more than an hour old');
    }
    final unresolved = reasons.any((r) => r.state == NeedState.unresolved);
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
    );
  }

  NeedReason _need(ItemRequirement r, ProgressSnapshot? p, FirState fir) {
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
      return reason(
        NeedState.unresolved,
        'Tracker progress or item data unknown',
      );
    }
    final gate = _gate(r, p);
    if (gate == NeedState.irrelevant) {
      return reason(gate, 'does not apply to you', 0);
    }
    EntityProgress? parent;
    if (r.kind == RequirementKind.task) {
      parent = p.tasks[r.sourceId];
      if (parent?.invalid == true) {
        return reason(NeedState.unresolved, 'task status invalid');
      }
      if (parent?.complete == true || parent?.failed == true) {
        return reason(
          NeedState.satisfied,
          parent!.complete
              ? 'task completed'
              : 'task failed; no active obligation',
          0,
        );
      }
      if (parent == null || parent.invalid != false || parent.failed == null) {
        return reason(NeedState.unresolved, 'task status unknown or invalid');
      }
    } else {
      parent = p.modules[r.sourceId];
      if (parent?.complete == true) {
        return reason(NeedState.satisfied, 'station module completed', 0);
      }
      if (parent == null) {
        return reason(NeedState.unresolved, 'station module status unknown');
      }
    }
    if (r.ambiguousProgressIdentity) {
      return reason(
        NeedState.unresolved,
        'several tasks share this progress, so it cannot be told apart',
      );
    }
    final entries = r.progressIds
        .map(
          (id) =>
              r.kind == RequirementKind.task ? p.objectives[id] : p.parts[id],
        )
        .toList();
    final completion = r.completionId == null
        ? null
        : (r.kind == RequirementKind.task
              ? p.objectives[r.completionId]
              : p.parts[r.completionId]);
    if (r.completionId != null
        ? completion?.complete == true && completion?.invalid != true
        : entries.any((v) => v?.complete == true && v?.invalid != true)) {
      return reason(NeedState.satisfied, 'requirement completed', 0);
    }
    if (entries.any((v) => v == null || v.invalid == true) ||
        r.count == null ||
        !r.count!.isFinite ||
        r.count! < 0) {
      return reason(
        NeedState.unresolved,
        'progress or amount needed is unknown',
      );
    }
    if (r.count == 0) {
      return reason(NeedState.satisfied, 'no quantity required', 0);
    }
    num? remaining;
    for (final e in entries) {
      if (e!.count == null || !e.count!.isFinite || e.count! < 0) {
        return reason(
          NeedState.unresolved,
          'how many you still need is unknown',
        );
      }
      final value = (r.count! - e.count!).clamp(0, r.count!);
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

  NeedState _gate(ItemRequirement r, ProgressSnapshot p) {
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
    // The live catalog also uses edition string IDs. Tracker only documents
    // a numeric edition; without an authoritative mapping this gate is unknown.
    if (g.editionIds?.isNotEmpty == true) unknown = true;
    if (g.editions?.isNotEmpty == true) {
      if (p.gameEdition == null) {
        unknown = true;
      } else if (!g.editions!.contains(p.gameEdition) &&
          g.editionIds?.isNotEmpty != true) {
        return NeedState.irrelevant;
      }
    }
    if (g.minPlayerLevel != null) {
      if (p.playerLevel == null) {
        unknown = true;
      } else if (p.playerLevel! < g.minPlayerLevel!) {
        future = true;
      }
    }
    for (final e
        in (g.taskStatuses ?? const <String, List<String>>{}).entries) {
      final task = p.tasks[e.key];
      if (task == null || task.invalid == true || e.value.isEmpty) {
        unknown = true;
        continue;
      }
      final String? status = task.complete
          ? 'complete'
          : task.failed == true
          ? 'failed'
          : null;
      if (status == null) {
        if (e.value.length == 1 &&
            e.value.single == 'complete' &&
            task.failed == false &&
            task.invalid == false) {
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
      final module = p.modules['${e.key}-${e.value}'];
      if (module == null) {
        unknown = true;
      } else if (!module.complete) {
        future = true;
      }
    }
    if (r.kind == RequirementKind.hideout &&
        r.stationLevel != null &&
        r.stationLevel! > 1) {
      final prior = p.modules['${r.stationId}-${r.stationLevel! - 1}'];
      if (prior == null) {
        unknown = true;
      } else if (!prior.complete) {
        future = true;
      }
    }
    return unknown
        ? NeedState.unresolved
        : future
        ? NeedState.future
        : NeedState.actionable;
  }

  bool? _fleaEligible(
    CatalogItem item,
    ProgressSnapshot? progress,
    FirState fir,
  ) {
    if (item.noFlea == true || fir == FirState.no) return false;
    if (item.noFlea == null ||
        item.minLevelForFlea == null ||
        item.minLevelForFlea! < 0 ||
        progress?.playerLevel == null ||
        fir == FirState.unknown) {
      return null;
    }
    return progress!.playerLevel! >= item.minLevelForFlea!;
  }
}

num? _positive(num? value) =>
    value != null && value.isFinite && value > 0 ? value : null;
num? _perSlot(num? value, num? slots) {
  if (value == null || slots == null) return null;
  final result = value / slots;
  return result.isFinite ? result : null;
}
