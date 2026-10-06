import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../domain/catalog_store.dart';
import '../data/catalog_client.dart';

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
    _publish();
    try {
      final candidate = await _client.fetch(key);
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
        var expires = candidate.observedAt.add(const Duration(hours: 24));
        for (final time in candidate.sourceTimestamps.values) {
          if (time != null &&
              time.add(const Duration(hours: 24)).isBefore(expires)) {
            expires = time.add(const Duration(hours: 24));
          }
        }
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
      error = 'Catalog refresh failed; last-good data retained';
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
