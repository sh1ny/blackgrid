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
import 'history_controller.dart';

class SelectionController extends ChangeNotifier {
  SelectionController({
    required this.database,
    required this.catalog,
    required this.progress,
    required this.history,
    DateTime Function()? clock,
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
  final DecisionEngine _engine = DecisionEngine();
  Timer? _timer;
  String query = '';
  String? _manualId;
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
  CatalogItem? get item =>
      inspectionCatalog?.items[_historyRow?.itemId ?? _manualId];
  String? get selectedId => _historyRow?.itemId ?? _manualId;
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
    _historyRow = null;
    _historyCatalog = null;
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

  Future<void> openHistory(ItemActivity row) async {
    final generation = ++_generation;
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
