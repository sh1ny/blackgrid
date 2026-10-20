import 'package:flutter/foundation.dart';

import 'accepted_scan.dart';

/// The session's latest accepted scan, kept apart from the current selection.
///
/// Only the scan decision feed writes it: it advances when an accepted scan
/// becomes the selection and clears on a mode or session change. Manual,
/// history and correction selections never touch it. The record lives in
/// memory for one app run and is never restored from storage.
class SessionScanState extends ChangeNotifier {
  AcceptedScan? _latest;

  /// The highest report id ever advanced to, kept across [clear].
  int _mark = 0;

  /// The latest accepted scan, or `null` when none was accepted since startup
  /// or the last mode or session change.
  AcceptedScan? get latest => _latest;

  /// Whether the session has a latest accepted scan.
  bool get hasAcceptedScan => _latest != null;

  /// Makes [scan] the latest accepted scan when its report is newer than any
  /// seen before.
  ///
  /// A scan whose report id is not above the highest one seen, even one from
  /// before a [clear], changes nothing and does not notify.
  void advance(AcceptedScan scan) {
    if (scan.reportId <= _mark) return;
    _mark = scan.reportId;
    _latest = scan;
    notifyListeners();
  }

  /// Forgets the latest accepted scan after a mode or session change.
  ///
  /// The report-id mark stays, so an older scan can never come back.
  void clear() {
    if (_latest == null) return;
    _latest = null;
    notifyListeners();
  }
}
