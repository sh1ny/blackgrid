import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../domain/catalog.dart';
import '../domain/decision.dart';
import '../domain/decision_engine.dart';
import '../domain/inspection_context.dart';
import '../domain/settings.dart';
import 'catalog_controller.dart';
import 'progress_controller.dart';
import 'accepted_scan.dart';
import 'history_controller.dart';
import 'scan_correction.dart';
import 'scan_epoch.dart';

class SelectionController extends ChangeNotifier {
  SelectionController({
    required this.database,
    required this.catalog,
    required this.progress,
    required this.history,
    DateTime Function()? clock,
    this._epoch,
  }) : clock = clock ?? DateTime.now {
    catalog.addListener(_onAuthority);
    progress.addListener(_onAuthority);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      catalog.updateAge();
      progress.updateAge();
      _onAuthority();
    });
  }
  final BlackgridDatabase database;
  final CatalogController catalog;
  final ProgressController progress;
  final HistoryController history;
  final DateTime Function() clock;

  /// Reads the app's current epoch, or null when a pick is never fenced by it.
  final ScanEpoch Function()? _epoch;
  final DecisionEngine _engine = DecisionEngine();
  Timer? _timer;
  String query = '';
  String? _manualId;
  String? _scanItemId;
  AcceptedScan? _scan;
  ScanCorrection? _correction;
  ScanCorrectionOffer? _offer;
  ItemActivity? _historyRow;
  CatalogSnapshot? _historyCatalog;
  FirState _fir = FirState.unknown;
  FirState get fir => _fir;
  ItemActivity? get historyRow => _historyRow;
  bool get isHistory => _historyRow != null;
  GameMode get inspectionMode => _historyRow?.mode ?? catalog.mode;
  bool get _usesLiveCatalog => !isHistory || catalog.mode == inspectionMode;
  CatalogSnapshot? get inspectionCatalog =>
      _usesLiveCatalog ? catalog.snapshot ?? _historyCatalog : _historyCatalog;
  CatalogItem? get item => inspectionCatalog?.items[selectedId];
  String? get selectedId =>
      _historyRow?.itemId ?? _scanItemId ?? _correction?.itemId ?? _manualId;

  /// The accepted scan the card shows, or null when another source is current.
  AcceptedScan? get scan => _scan;

  /// Whether the last scan was retired, for the card's retired message.
  ///
  /// The next select or open clears it.
  bool get scanRetired => _scanRetired;
  bool _scanRetired = false;

  /// The correction the player picked, or null when another source is current.
  ///
  /// It is never an [AcceptedScan]: [scan] stays null while it is current.
  ScanCorrection? get correction => _correction;

  /// The current correction offer, or null when there is none.
  ScanCorrectionOffer? get correctionOffer => _offer;

  /// The offer's candidates that the live catalog holds, in rank order.
  ///
  /// A candidate whose item the live catalog lacks is left out.
  List<CorrectionCandidate> get correctionCandidates {
    final items = catalog.snapshot?.items;
    final offer = _offer;
    if (items == null || offer == null) return const [];
    return [
      for (final candidate in offer.candidates)
        if (items[candidate.id] case final found?)
          (item: found, score: candidate.score),
    ];
  }

  /// The live catalog items matching the offer's search text, in ID order, at
  /// most [correctionSearchLimit].
  List<CatalogItem> get correctionResults {
    final offer = _offer;
    if (offer == null) return const [];
    return catalog.snapshot?.searchWords(
          offer.query,
          limit: correctionSearchLimit,
        ) ??
        const [];
  }

  List<CatalogItem> get results => catalog.snapshot?.search(query) ?? const [];
  ItemDecision? _decision;
  ItemDecision? get decision => _decision;
  String? error;
  bool loadingHistory = false;
  int _generation = 0;
  String? _authority;
  bool _disposed = false;

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void setFir(FirState value) {
    _fir = value;
    _project();
    notifyListeners();
  }

  Future<void> selectManual(CatalogItem value) async {
    final generation = ++_generation;
    _manualId = value.id;
    _clearScan();
    _correction = null;
    _offer = null;
    _scanRetired = false;
    _historyRow = null;
    _historyCatalog = null;
    loadingHistory = false;
    _fir = FirState.unknown;
    error = null;
    _authority = _fingerprint();
    _project();
    notifyListeners();
    final mode = catalog.mode;
    final recorded = await history.record(value.id, mode, clock().toUtc());
    if (_disposed || generation != _generation) return;
    if (!recorded) error = history.error;
    notifyListeners();
  }

  /// Selects the item a scan matched and records it as scan activity.
  ///
  /// The acceptance time comes from [clock] when this is called, never from the
  /// scan report. It times the record, the history write and the card's age.
  /// An item missing from the current catalog changes and records nothing.
  Future<void> selectScan({
    required int reportId,
    required String itemId,
    required GameMode mode,
    required String catalogRevision,
    required ScanEpoch epoch,
  }) async {
    if (catalog.snapshot?.items[itemId] == null) return;
    final generation = ++_generation;
    final acceptedAt = clock().toUtc();
    _scanItemId = itemId;
    _scan = null;
    _correction = null;
    _offer = null;
    _scanRetired = false;
    _manualId = null;
    _historyRow = null;
    _historyCatalog = null;
    loadingHistory = false;
    _fir = FirState.unknown;
    error = null;
    _authority = _fingerprint();
    _project();
    final decision = _decision;
    if (decision != null) {
      _scan = AcceptedScan(
        reportId: reportId,
        itemId: itemId,
        mode: mode,
        catalogRevision: catalogRevision,
        acceptedAt: acceptedAt,
        epoch: epoch,
        decisionAtAcceptance: decision,
      );
    }
    notifyListeners();
    final recorded = await history.record(
      itemId,
      mode,
      acceptedAt,
      source: ActivitySource.scan,
    );
    if (_disposed || generation != _generation) return;
    if (!recorded) error = history.error;
    notifyListeners();
  }

  /// Drops the scan or correction source and the offer when a mode or session
  /// change invalidates them.
  ///
  /// FIR resets for every source. Only a scan or correction source is cleared,
  /// flagged as retired and fenced from a pending history write, so a history
  /// load in flight keeps running.
  void retireScan() {
    final wasScan = _scanItemId != null || _correction != null;
    _fir = FirState.unknown;
    _offer = null;
    if (wasScan) {
      ++_generation;
      _clearScan();
      _correction = null;
      _scanRetired = true;
      error = null;
    }
    _authority = _fingerprint();
    _project();
    notifyListeners();
  }

  /// Shows [offer] as the current correction offer, replacing any older one.
  ///
  /// The caller has already fenced it against the current epoch and mode. The
  /// selection, the decision and the history do not change.
  void offerCorrection(ScanCorrectionOffer offer) {
    _offer = offer;
    notifyListeners();
  }

  /// Sets the offer's search text without touching the selection or [query].
  ///
  /// With no current offer nothing changes.
  void setCorrectionQuery(String value) {
    final offer = _offer;
    if (offer == null || offer.query == value) return;
    _offer = offer.withQuery(value);
    notifyListeners();
  }

  /// Clears the offer and changes nothing else.
  void dismissCorrection() {
    if (_offer == null) return;
    _offer = null;
    notifyListeners();
  }

  /// Makes [itemId] the current selection as a correction of scan [reportId].
  ///
  /// It applies only while the offer for [reportId] is current, the epoch and
  /// the live mode are those the offer was made in, and the live catalog holds
  /// [itemId]. Otherwise nothing changes. A pick closes an open history view,
  /// resets FIR, clears the offer and records manual activity at the time of
  /// the pick, taken from [clock]. A failed write keeps the correction and
  /// replaces the error with the correction's own message.
  Future<void> selectCorrection(int reportId, String itemId) async {
    final offer = _offer;
    if (offer == null || offer.reportId != reportId) {
      debugPrint('Correction pick for scan $reportId ignored: offer replaced.');
      return;
    }
    final read = _epoch;
    if (read != null && read() != offer.epoch) {
      debugPrint('Correction pick for scan $reportId ignored: epoch changed.');
      return;
    }
    final snapshot = catalog.snapshot;
    if (catalog.mode != offer.mode || snapshot == null) {
      debugPrint('Correction pick for scan $reportId ignored: mode changed.');
      return;
    }
    if (snapshot.items[itemId] == null) {
      debugPrint('Correction pick for scan $reportId ignored: $itemId gone.');
      return;
    }
    final generation = ++_generation;
    final correctedAt = clock().toUtc();
    _correction = ScanCorrection(
      reportId: reportId,
      itemId: itemId,
      mode: offer.mode,
      catalogRevision: snapshot.revision,
      correctedAt: correctedAt,
      epoch: offer.epoch,
    );
    _offer = null;
    _manualId = null;
    _clearScan();
    _scanRetired = false;
    _historyRow = null;
    _historyCatalog = null;
    loadingHistory = false;
    _fir = FirState.unknown;
    error = null;
    _authority = _fingerprint();
    _project();
    notifyListeners();
    final recorded = await history.record(itemId, offer.mode, correctedAt);
    if (_disposed || generation != _generation) return;
    if (!recorded) {
      error = 'Correction was not recorded: local persistence failed.';
    }
    notifyListeners();
  }

  void _clearScan() {
    _scanItemId = null;
    _scan = null;
  }

  Future<void> openHistory(ItemActivity row) async {
    final generation = ++_generation;
    _clearScan();
    _correction = null;
    _offer = null;
    _scanRetired = false;
    _historyRow = row;
    _historyCatalog = null;
    _fir = FirState.unknown;
    loadingHistory = true;
    error = null;
    _project();
    notifyListeners();
    try {
      final snapshot = await database.loadCatalog(row.mode);
      if (_disposed || generation != _generation) return;
      _historyCatalog = snapshot;
      if (snapshot?.items[row.itemId] == null) error = 'Stored identity is not present in this mode’s current catalog. The activity row is retained.';
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = 'Stored-mode catalog could not be opened.';
      }
    }
    if (_disposed || generation != _generation) return;
    loadingHistory = false;
    _authority = _fingerprint();
    _project();
    notifyListeners();
  }

  void closeHistory() {
    ++_generation;
    _clearScan();
    _correction = null;
    _scanRetired = false;
    _historyRow = null;
    _historyCatalog = null;
    loadingHistory = false;
    _fir = FirState.unknown;
    error = null;
    _authority = _fingerprint();
    _project();
    notifyListeners();
  }

  String _fingerprint() {
    final snapshot = inspectionCatalog;
    final now = clock().toUtc();
    final relevantProgress = progress.mode == inspectionMode ? progress : null;
    return '${catalog.mode.name}:${inspectionMode.name}:${snapshot?.revision}:${snapshot?.authoritativeAt(now)}:'
        '${_usesLiveCatalog ? catalog.status.name : ''}:${relevantProgress?.authorityVersion}:'
        '${relevantProgress?.snapshot?.authoritativeAt(now)}';
  }

  void _onAuthority() {
    if (_disposed) return;
    final fingerprint = _fingerprint();
    if (fingerprint != _authority) {
      _fir = FirState.unknown;
      _authority = fingerprint;
    }
    _project();
    notifyListeners();
  }

  void _project() {
    final selected = item;
    if (selected == null) {
      _decision = null;
      return;
    }
    final progressMatches = progress.mode == inspectionMode;
    _decision = _engine.evaluate(
      selected,
      InspectionContext(
        mode: inspectionMode,
        now: clock().toUtc(),
        catalog: inspectionCatalog,
        progress: progressMatches ? progress.snapshot : null,
        fir: _fir,
        catalogStale:
            _usesLiveCatalog && catalog.status != CatalogStatus.current,
        progressStale:
            !progressMatches || progress.status != ProgressStatus.current,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    catalog.removeListener(_onAuthority);
    progress.removeListener(_onAuthority);
    super.dispose();
  }
}
