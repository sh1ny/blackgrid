/// Plain-words rows for an inspected item's requirements, with no widgets.
library;

import '../domain/catalog.dart';
import '../domain/decision.dart';

/// One requirement row, ready to show; every field is final display text.
class RequirementRowView {
  /// Creates a row view from already formatted text.
  const RequirementRowView({
    required this.title,
    required this.kindTag,
    required this.stateLabel,
    this.sourceLine,
    this.needs,
    this.remaining,
    this.foundInRaidLine,
    this.reason,
  });

  /// The task, hideout level, or craft or barter product the row is about.
  final String title;

  /// The kind tag: `Task`, `Hideout`, `Craft` or `Barter`.
  final String kindTag;

  /// The state in plain words, such as `Needed now` or `Optional use`.
  final String stateLabel;

  /// Where a craft or barter comes from, or `null` when there is nothing to say.
  final String? sourceLine;

  /// `Needs N` or `Tool, not used up`, or `null` when the count is unknown.
  final String? needs;

  /// `N remaining`, or `null` when the state makes the quantity meaningless.
  final String? remaining;

  /// The found-in-raid rule when the source states one, otherwise `null`.
  final String? foundInRaidLine;

  /// The decision reason without the source name; `null` on craft and barter.
  final String? reason;
}

/// Builds the display view of [need], resolving names through [catalog].
///
/// An id stands in for any item or trader name that [catalog] cannot resolve,
/// and [catalog] may be `null`. A craft or barter saved before display facts
/// existed keeps its stored source name as the title and has no source line.
RequirementRowView requirementRow(NeedReason need, CatalogSnapshot? catalog) {
  final r = need.requirement;
  final label = _stateLabel(need);
  final isObligation = switch (r.kind) {
    RequirementKind.task || RequirementKind.hideout => true,
    RequirementKind.craft || RequirementKind.barter => false,
  };
  final showRemaining = switch (label) {
    'Needed now' ||
    'Needed later' ||
    "Can't confirm" ||
    'Needs found in raid' => true,
    _ => false,
  };
  final remaining = need.remaining;
  final count = r.count;
  return RequirementRowView(
    title: _title(r, catalog),
    kindTag: switch (r.kind) {
      RequirementKind.task => 'Task',
      RequirementKind.hideout => 'Hideout',
      RequirementKind.craft => 'Craft',
      RequirementKind.barter => 'Barter',
    },
    stateLabel: label,
    sourceLine: _sourceLine(r, catalog),
    needs: r.tool == true
        ? 'Tool, not used up'
        : count == null
        ? null
        : 'Needs ${_formatCount(count)}',
    remaining: showRemaining && remaining != null
        ? '${_formatCount(remaining)} remaining'
        : null,
    foundInRaidLine: switch (r.foundInRaid) {
      true => 'Found in raid required',
      false => 'Found in raid not required',
      null => null,
    },
    reason: isObligation ? need.detail : null,
  );
}

/// Splits [reasons] into obligations and optional uses.
///
/// Obligations are the task and hideout rows, ordered needed now, needed later,
/// can't confirm, done, then the rest. Optional uses are the craft and barter
/// rows. Both keep the input (catalog) order within a state.
({List<NeedReason> obligations, List<NeedReason> optionalUses})
arrangeRequirementRows(List<NeedReason> reasons) {
  bool isObligation(NeedReason n) => switch (n.requirement.kind) {
    RequirementKind.task || RequirementKind.hideout => true,
    RequirementKind.craft || RequirementKind.barter => false,
  };
  const order = [
    NeedState.actionable,
    NeedState.future,
    NeedState.unresolved,
    NeedState.satisfied,
    NeedState.irrelevant,
  ];
  final obligations = <NeedReason>[
    for (final state in order)
      for (final n in reasons)
        if (isObligation(n) && n.state == state) n,
  ];
  return (
    obligations: obligations,
    optionalUses: [
      for (final n in reasons)
        if (!isObligation(n)) n,
    ],
  );
}

String _stateLabel(NeedReason need) {
  final r = need.requirement;
  final remaining = need.remaining;
  return switch (need.state) {
    NeedState.actionable => 'Needed now',
    NeedState.future => 'Needed later',
    NeedState.satisfied => 'Done',
    NeedState.unresolved => "Can't confirm",
    NeedState.irrelevant => switch (r.kind) {
      RequirementKind.craft || RequirementKind.barter => 'Optional use',
      RequirementKind.task || RequirementKind.hideout =>
        r.kind == RequirementKind.task && r.optional
            ? 'Optional objective'
            : r.foundInRaid == true && remaining != null && remaining > 0
            ? 'Needs found in raid'
            : 'Not for you',
    },
  };
}

String _title(ItemRequirement r, CatalogSnapshot? catalog) {
  switch (r.kind) {
    case RequirementKind.task:
      return r.sourceName;
    case RequirementKind.hideout:
      final level = r.stationLevel;
      return level == null ? r.sourceName : '${r.sourceName} level $level';
    case RequirementKind.craft:
    case RequirementKind.barter:
      final product = r.productItemId;
      if (product == null) return r.sourceName;
      final name = catalog?.items[product]?.name ?? product;
      final count = r.productCount;
      return count == null || count == 1
          ? name
          : '$name ×${_formatCount(count)}';
  }
}

String? _sourceLine(ItemRequirement r, CatalogSnapshot? catalog) {
  if (r.productItemId == null) return null;
  final String? origin;
  switch (r.kind) {
    case RequirementKind.task:
    case RequirementKind.hideout:
      return null;
    case RequirementKind.craft:
      final station = r.stationName ?? r.stationId;
      final level = r.stationLevel;
      origin = station == null
          ? null
          : level == null
          ? station
          : '$station level $level';
    case RequirementKind.barter:
      final id = r.traderId;
      final trader = id == null ? null : catalog?.traders[id]?.name ?? id;
      final level = r.traderLevel;
      origin = trader == null
          ? null
          : level == null
          ? trader
          : '$trader LL$level';
  }
  final unlock = r.unlockTaskName ?? r.unlockTaskId;
  if (unlock == null) return origin;
  return origin == null
      ? 'unlocked by $unlock'
      : '$origin, unlocked by $unlock';
}

/// Writes whole numbers without decimals and other numbers as they are.
String _formatCount(num value) =>
    value == value.truncate() ? value.truncate().toString() : '$value';
