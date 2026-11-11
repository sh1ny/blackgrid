import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/selection_controller.dart';
import '../data/vision/inspection_fir.dart';
import '../domain/catalog.dart';
import '../domain/decision.dart';
import '../domain/inspection_context.dart';
import '../domain/roubles.dart';
import '../domain/verdict_reason.dart';
import 'age_tick.dart';
import 'correction_offer_block.dart';
import 'ember/ember_tokens.dart';
import 'ember/theme_access.dart';
import 'freshness_tag.dart';
import 'item_icon.dart';
import 'labels.dart';
import 'verdict_plate.dart';

/// The one height the empty and ordinary single-line strip share.
const double _normalStripHeight = 100;

/// The shared current inspection shown before either workspace.
///
/// Selection and Found in raid remain owned by the existing selection
/// controller. The strip grows when the reason or text scale needs more room.
class AnswerStrip extends StatelessWidget {
  /// Creates the strip using the shared application [services].
  const AnswerStrip({
    super.key,
    required this.services,
    this.tickPeriod = const Duration(seconds: 5),
  });

  /// The current inspection and item icon cache.
  final AppServices services;

  /// How often the provenance age is refreshed.
  final Duration tickPeriod;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([services.selection, services.scans]),
    builder: (context, _) {
      final selection = services.selection;
      final item = selection.item;
      final decision = selection.decision;
      final latest = services.scans.latest;
      final offer = selection.correctionOffer;
      final actions = <Widget>[
        if (selection.isHistory)
          IconButton(
            tooltip: 'Close history inspection',
            onPressed: selection.closeHistory,
            icon: const Icon(Icons.close),
          ),
        if (latest != null && selection.scan?.reportId != latest.reportId)
          TextButton(
            onPressed: () {
              final current = services.scans.latest;
              if (current != null) selection.showScan(current);
            },
            child: const Text('Back to latest scan'),
          ),
      ];
      return Container(
        key: const Key('answer-strip'),
        constraints: const BoxConstraints(minHeight: _normalStripHeight),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.ember.panel,
          border: Border(bottom: BorderSide(color: context.ember.hairline)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            item == null || decision == null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selection.loadingHistory
                              ? 'Opening saved item data…'
                              : selection.selectedId == null
                              ? offer == null
                                    ? selection.scanRetired
                                          ? 'Last scan was in an earlier mode or session; scan again'
                                          : 'Find an item'
                                    : 'Scan needs review'
                              : 'Item data unavailable',
                        ),
                        if (selection.selectedId == null &&
                            !selection.loadingHistory &&
                            offer == null)
                          const Text('Search with Ctrl K'),
                        ...actions,
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final wide =
                          constraints.maxWidth >= 1300 &&
                          MediaQuery.textScalerOf(context).scale(1) <= 1.2;
                      final who = _WhoBlock(
                        services: services,
                        item: item,
                        tickPeriod: tickPeriod,
                      );
                      final answer = AnswerVerdict(
                        decision: decision,
                        maxWidth: wide ? double.infinity : 460,
                        control: FirControls(services: services),
                      );
                      final price = _PriceBlock(
                        decision: decision,
                        quoteAt: item.quoteAt,
                        now: selection.clock(),
                      );
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            who,
                            const SizedBox(width: 16),
                            Expanded(child: answer),
                            const SizedBox(width: 16),
                            for (final action in actions) ...[
                              action,
                              const SizedBox(width: 12),
                            ],
                            price,
                          ],
                        );
                      }
                      return Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [who, answer, ...actions, price],
                      );
                    },
                  ),
            if (selection.error != null)
              Text(
                selection.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (offer != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * .18).clamp(
                    64,
                    130,
                  ),
                ),
                child: SingleChildScrollView(
                  child: CorrectionOfferBlock(
                    selection: selection,
                    offer: offer,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// The item picture, its name and the line saying where the item came from.
class _WhoBlock extends StatelessWidget {
  const _WhoBlock({
    required this.services,
    required this.item,
    required this.tickPeriod,
  });

  final AppServices services;
  final CatalogItem item;
  final Duration tickPeriod;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ItemIcon(
        cache: services.itemIcons,
        itemId: item.id,
        iconLink: item.iconLink,
        size: 48,
        color: context.ember.accentText,
      ),
      const SizedBox(width: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, style: EmberType.title),
            AgeTick(
              clock: services.selection.clock,
              period: tickPeriod,
              builder: (context, now) => Text(
                provenanceLine(services.selection, now),
                key: const Key('answer-provenance'),
                style: EmberType.label.copyWith(
                  color: context.ember.inkSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// The words after a relative age: `3 min ago`, or `just now` when it is new.
String _ago(DateTime at, DateTime now) {
  final age = relativeAgeLabel(at, now);
  return age == 'just now' ? age : '$age ago';
}

/// The line under the item name saying where the shown item came from.
///
/// [now] is the current time in UTC. A scan number never appears.
String provenanceLine(SelectionController selection, DateTime now) {
  final saved = selection.historyRow;
  return switch ((saved, selection.scan, selection.correction)) {
    (final row?, _, _) =>
      'Current advice · saved ${_ago(row.observedAt, now)}'
          '${row.mode == selection.catalog.mode ? '' : ' in ${modeLabel(row.mode)}'}',
    (_, final scan?, _) => 'Accepted scan · ${_ago(scan.acceptedAt, now)}',
    (_, _, final correction?) =>
      'Corrected from a scan · ${_ago(correction.correctedAt, now)}'
          ' · chosen by hand',
    _ => 'Chosen by hand',
  };
}

/// The Flea and trader prices as aligned label and value rows, then the
/// freshness tag.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({
    required this.decision,
    required this.quoteAt,
    required this.now,
  });

  final ItemDecision decision;
  final DateTime? quoteAt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    final fleaPrice = decision.fleaEligible != false
        ? decision.fleaGross
        : null;
    final label = EmberType.label.copyWith(color: ember.inkSecondary);
    final value = EmberType.body.copyWith(color: ember.ink);
    TableRow row(String name, String main, String? detail) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text(name, style: label),
        ),
        Text(main, style: value),
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Text(detail ?? '', style: label),
        ),
      ],
    );
    return Column(
      key: const Key('answer-price'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            row(
              'Flea',
              fleaPrice != null
                  ? rub(fleaPrice)
                  : decision.fleaEligible == false
                  ? "Can't be sold on the Flea"
                  : 'Price unavailable',
              fleaPrice != null && decision.fleaPerSlot != null
                  ? '${rub(decision.fleaPerSlot)} / slot'
                  : null,
            ),
            row(
              'Trader',
              decision.traderGross == null
                  ? 'Price unavailable'
                  : rub(decision.traderGross),
              decision.traderGross == null ? null : decision.traderName,
            ),
          ],
        ),
        if (fleaPrice != null)
          FreshnessTag(
            quoteAt: quoteAt,
            now: now,
            fleaEligible: decision.fleaEligible,
          ),
      ],
    );
  }
}

/// Per-item Found in raid selector shared with manual inspection.
class FirControls extends StatelessWidget {
  /// Creates a selector bound to [services]' selection controller.
  ///
  /// A non-null [caption] replaces the derived scan/manual source note.
  const FirControls({super.key, required this.services, this.caption});

  /// The owner of the current item's FIR state.
  final AppServices services;

  /// An optional replacement for the derived source note.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ember = context.ember;
    final selection = services.selection;
    final effective = selection.fir;
    final note =
        caption ??
        switch (selection.firSource) {
          FirSource.unset => null,
          FirSource.manual => 'Manual override',
          FirSource.scan => switch (selection.detectedFir!.reason) {
            InspectionFirReason.iconFound ||
            InspectionFirReason.iconAbsent => 'From scan',
            InspectionFirReason.cornerCutOff => 'From scan · corner cut off',
            InspectionFirReason.cornerUnreadable =>
              'From scan · corner unreadable',
          },
        };
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Found in raid',
          style: EmberType.label.copyWith(color: ember.inkSecondary),
        ),
        SegmentedButton<FirState>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          style: SegmentedButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          segments: [
            for (final fir in FirState.values)
              ButtonSegment(
                value: fir,
                label: Text(switch (fir) {
                  FirState.unknown => 'Unknown',
                  FirState.yes => 'Yes',
                  FirState.no => 'No',
                }),
              ),
          ],
          selected: {effective},
          onSelectionChanged: selection.item == null
              ? null
              : (chosen) => selection.setFir(
                  chosen.isEmpty ? effective : chosen.single,
                ),
        ),
        if (note != null)
          Text(
            note,
            key: const Key('fir-source'),
            style: EmberType.label.copyWith(color: ember.inkTertiary),
          ),
      ],
    );
  }
}

/// The verdict plate, its optional control and the wrapping reason below.
class AnswerVerdict extends StatelessWidget {
  /// Creates the verdict from the already projected [decision].
  ///
  /// A [control] sits beside the plate, wrapping directly under it when the
  /// two do not fit on one line.
  const AnswerVerdict({
    super.key,
    required this.decision,
    this.maxWidth = 420,
    this.control,
  });

  /// The existing selection controller's projected advice.
  final ItemDecision decision;

  /// Maximum width available for the reason to wrap.
  final double maxWidth;

  /// The widget shown beside the plate, such as the Found in raid control.
  final Widget? control;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth.clamp(1, double.infinity)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IntrinsicWidth(child: VerdictPlate(decision: decision)),
            ?control,
          ],
        ),
        const SizedBox(height: 6),
        Text(verdictReason(decision), key: const Key('answer-verdict-reason')),
      ],
    ),
  );
}
