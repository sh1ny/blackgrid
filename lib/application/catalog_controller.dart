import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../domain/catalog_store.dart';
import '../data/catalog_client.dart';

/// Builds the player-facing text for a catalog failure of [kind].
///
/// The first sentence names the cause. The second says whether item data is
/// still in use, which [kept] reports: `true` when a snapshot survives the
/// failure.
String catalogFailureMessage(CatalogFailure kind, {required bool kept}) {
  final cause = switch (kind) {
    CatalogFailure.transport =>
      'Item data could not be downloaded: no connection to tarkov.dev.',
    CatalogFailure.http =>
      'Item data could not be downloaded: tarkov.dev answered with an error.',
    CatalogFailure.invalid =>
      'Item data from tarkov.dev was incomplete or invalid.',
    CatalogFailure.save => 'Item data could not be saved on this computer.',
  };
  return kept
      ? '$cause The last item data is still in use.'
      : '$cause No item data is available yet.';
}

enum CatalogStatus { missing, loading, current, stale, failed }

class CatalogController extends ChangeNotifier {
  CatalogController({
    required this._store,
    required this._client,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final CatalogStore _store;
  final CatalogClient _client;
  final DateTime Function() _clock;
  final Map<GameMode, Future<void>> _refreshes = {};
  final Map<GameMode, int> _refreshGenerations = {};
  GameMode mode = GameMode.unknown;
  CatalogSnapshot? snapshot;
  CatalogStatus status = CatalogStatus.missing;
  String? error;
  CatalogFailure? _failure;
  int authorityVersion = 0;
  int _generation = 0;
  int _refreshPublication = 0;
  bool _disposed = false;
  Timer? _expiry;
  bool get loading => status == CatalogStatus.loading;
  void _publish() {
    if (!_disposed) {
      authorityVersion++;
      notifyListeners();
    }
  }

  Future<void> setMode(GameMode value) async {
    _expiry?.cancel();
    final generation = ++_generation;
    final refreshPublication = _refreshPublication;
    mode = value;
    snapshot = null;
    error = null;
    _failure = null;
    status = value == GameMode.unknown
        ? CatalogStatus.missing
        : CatalogStatus.loading;
    _publish();
    if (value == GameMode.unknown) return;
    try {
      final cached = await _store.loadCatalog(value);
      // A committed refresh owns publication over this earlier cache read.
      if (_disposed ||
          generation != _generation ||
          refreshPublication != _refreshPublication) {
        return;
      }
      snapshot = cached;
      status = cached == null ? CatalogStatus.missing : CatalogStatus.stale;
      // A refresh that failed first described the failure without this cache.
      if (_failure case final failure?) {
        error = catalogFailureMessage(failure, kept: cached != null);
      }
    } on Object {
      if (_disposed ||
          generation != _generation ||
          refreshPublication != _refreshPublication) {
        return;
      }
      status = CatalogStatus.failed;
      error = 'Stored catalog unavailable';
    }
    _publish();
  }

  Future<void> refresh() {
    if (mode == GameMode.unknown || _disposed) return Future.value();
    final key = mode;
    final existing = _refreshes[key];
    _refreshGenerations[key] = _generation;
    if (existing != null) {
      status = CatalogStatus.loading;
      error = null;
      _failure = null;
      _publish();
      return existing;
    }
    final future = _refresh(key);
    _refreshes[key] = future;
    return future.whenComplete(() {
      if (identical(_refreshes[key], future)) {
        _refreshes.remove(key);
        _refreshGenerations.remove(key);
      }
    });
  }

  Future<void> _refresh(GameMode key) async {
    status = CatalogStatus.loading;
    error = null;
    _failure = null;
    _publish();
    var failure = CatalogFailure.invalid;
    try {
      final CatalogSnapshot candidate;
      try {
        candidate = await _client.fetch(key);
      } on CatalogException catch (e) {
        failure = e.kind;
        rethrow;
      }
      failure = CatalogFailure.save;
      await _store.commitCatalog(candidate);
      if (_disposed || _refreshGenerations[key] != _generation || mode != key) {
        return;
      }
      _refreshPublication++;
      snapshot = candidate;
      status = candidate.authoritativeAt(_clock())
          ? CatalogStatus.current
          : CatalogStatus.stale;
      _expiry?.cancel();
      if (status == CatalogStatus.current) {
        // Authority is measured from download time only; source times are
        // evidence and must not move this deadline.
        final expires = candidate.observedAt.add(const Duration(hours: 24));
        _expiry = Timer(
          expires.difference(_clock()) + const Duration(milliseconds: 1),
          updateAge,
        );
      }
    } on Object {
      if (_disposed || _refreshGenerations[key] != _generation || mode != key) {
        return;
      }
      status = snapshot == null ? CatalogStatus.failed : CatalogStatus.stale;
      _failure = failure;
      error = catalogFailureMessage(failure, kept: snapshot != null);
    }
    _publish();
  }

  void updateAge() {
    if (status == CatalogStatus.current &&
        snapshot?.authoritativeAt(_clock()) != true) {
      status = CatalogStatus.stale;
      _publish();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _expiry?.cancel();
    super.dispose();
  }
}
