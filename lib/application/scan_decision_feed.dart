import 'dart:async';

import 'package:flutter/foundation.dart';

import 'catalog_controller.dart';
import 'scan_coordinator.dart';
import 'scan_correction.dart';
import 'scan_epoch.dart';
import 'selection_controller.dart';

/// Carries each accepted scan from the scanner into the selection.
///
/// The feed listens to an [AcceptedScanSource] and acts once per accepted
/// report id. A scan is applied only when it began in the current epoch and
/// matched the live catalog; otherwise it is dropped from the decision path
/// and its evidence stays published. The coordinator never imports selection
/// or history.
class ScanDecisionFeed {
  /// Creates a feed and starts listening to [source].
  ///
  /// The scan already accepted when the feed is built is not applied. [epoch]
  /// reads the app's current epoch.
  ScanDecisionFeed({
    required this.source,
    required this.selection,
    required this.catalog,
    required this._epoch,
  }) : _consumed = source.lastAccepted?.id ?? 0,
       _offered = source.latest?.id ?? 0 {
    source.addListener(_onSource);
  }

  /// Where accepted scans come from.
  final AcceptedScanSource source;

  /// The selection an accepted scan is applied to.
  final SelectionController selection;

  /// The live catalog the fences check against.
  final CatalogController catalog;

  final ScanEpoch Function() _epoch;

  /// The highest accepted report id seen so far.
  int _consumed;

  /// The highest report id considered for a correction offer so far.
  int _offered;

  /// Handles one notification: the accepted scan first, so that it clears any
  /// offer, then the latest report for a new offer.
  void _onSource() {
    _applyAccepted();
    _offerLatest();
  }

  void _offerLatest() {
    final report = source.latest;
    if (report == null || report.id <= _offered) return;
    // Raised before the fences, so a fenced or dismissed offer never returns.
    _offered = report.id;
    final offer = correctionOfferFor(report);
    if (offer == null) return;
    if (offer.epoch != _epoch()) {
      debugPrint(
        'Offer for scan ${report.id} fenced (epoch): it began in '
        '${offer.epoch}, now ${_epoch()}.',
      );
      return;
    }
    if (offer.mode != catalog.mode) {
      debugPrint(
        'Offer for scan ${report.id} fenced (mode): matched in '
        '${offer.mode}, now ${catalog.mode}.',
      );
      return;
    }
    selection.offerCorrection(offer);
  }

  void _applyAccepted() {
    final report = source.lastAccepted;
    if (report == null || report.id <= _consumed) return;
    // Raised before the fences, so a fenced scan is never retried.
    _consumed = report.id;
    // A newer accepted scan clears an older offer even when it is fenced
    // below, since it is never reconsidered.
    final offer = selection.correctionOffer;
    if (offer != null && offer.reportId < report.id) {
      selection.dismissCorrection();
    }
    if (report.epoch != _epoch()) {
      debugPrint(
        'Scan ${report.id} fenced (epoch): it began in ${report.epoch}, '
        'now ${_epoch()}.',
      );
      return;
    }
    final mode = report.catalogMode;
    if (mode == null || mode != catalog.mode) {
      debugPrint(
        'Scan ${report.id} fenced (mode): matched in $mode, '
        'now ${catalog.mode}.',
      );
      return;
    }
    if (report case ScanReport(
      end: ScanAccepted(:final itemId),
      :final catalogRevision?,
      :final epoch?,
    )) {
      if (catalog.snapshot?.items[itemId] == null) {
        debugPrint(
          'Scan ${report.id} fenced (catalog): $itemId is not in the '
          'current catalog.',
        );
        return;
      }
      unawaited(
        selection.selectScan(
          reportId: report.id,
          itemId: itemId,
          mode: mode,
          catalogRevision: catalogRevision,
          epoch: epoch,
        ),
      );
    }
  }

  /// Retires the scan on selection after a mode transition or a session
  /// change.
  void epochChanged() => selection.retireScan();

  /// Stops listening to the source.
  void dispose() => source.removeListener(_onSource);
}
