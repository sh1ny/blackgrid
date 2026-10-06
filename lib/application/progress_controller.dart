import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../domain/credential_store.dart';
import '../domain/progress.dart';
import '../data/tracker_client.dart';

enum ProgressStatus { missing, loading, current, stale, failed, cooldown }

class ProgressController extends ChangeNotifier {
  ProgressController({
    required this._store,
    required this._client,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final CredentialStore _store;
  final TrackerClient _client;
  final DateTime Function() _clock;
  GameMode mode = GameMode.unknown;
  ProgressStatus status = ProgressStatus.missing;
  ProgressSnapshot? snapshot;
  String? error;
  DateTime? cooldownUntil;
  int authorityVersion = 0;
  int _session = 0;
  String? _credential;
  Future<void>? _refreshing;
  Future<void> _credentialOperation = Future.value();
  Timer? _expiry;
  bool _disposed = false;
  bool get loading => status == ProgressStatus.loading;
  bool get hasCredential => _credential != null;
  Duration? get cooldown => cooldownUntil == null
      ? null
      : cooldownUntil!.difference(_clock()).isNegative
      ? Duration.zero
      : cooldownUntil!.difference(_clock());
  void _publish() {
    if (!_disposed) {
      authorityVersion++;
      notifyListeners();
    }
  }

  int _invalidate() {
    _expiry?.cancel();
    snapshot = null;
    _credential = null;
    _refreshing = null;
    cooldownUntil = null;
    error = null;
    status = ProgressStatus.missing;
    return ++_session;
  }

  Future<void> setMode(GameMode value) async {
    final session = _invalidate();
    mode = value;
    _publish();
    if (value == GameMode.unknown) return;
    try {
      await _credentialOperation;
      final token = await _store.readCredential(value);
      if (_disposed || session != _session) return;
      _credential = token;
      status = token == null ? ProgressStatus.missing : ProgressStatus.stale;
    } on Object {
      if (_disposed || session != _session) return;
      status = ProgressStatus.failed;
      error = 'Protected credential unavailable';
    }
    _publish();
  }

  Future<void> saveCredential(String token) {
    final key = mode;
    if (key == GameMode.unknown) return Future.value();
    final session = _invalidate();
    _publish();
    if (!TrackerClient.validToken(key, token)) {
      status = ProgressStatus.failed;
      error = 'Credential prefix does not match selected mode';
      _publish();
      return Future.value();
    }
    final operation = _credentialOperation.then((_) async {
      try {
        await _store.writeCredential(key, token);
        if (_disposed || session != _session || mode != key) return;
        _credential = token;
        status = ProgressStatus.stale;
      } on Object {
        if (_disposed || session != _session || mode != key) return;
        status = ProgressStatus.failed;
        error = 'Protected credential save failed';
      }
      _publish();
    });
    _credentialOperation = operation;
    return operation;
  }

  Future<void> removeCredential() {
    final key = mode;
    if (key == GameMode.unknown) return Future.value();
    final session = _invalidate();
    _publish();
    final operation = _credentialOperation.then((_) async {
      try {
        await _store.removeCredential(key);
      } on Object {
        if (_disposed || session != _session || mode != key) return;
        status = ProgressStatus.failed;
        error = 'Protected credential removal failed';
        _publish();
      }
    });
    _credentialOperation = operation;
    return operation;
  }

  Future<void> refresh() {
    if (_disposed || mode == GameMode.unknown || _credential == null) {
      return Future.value();
    }
    if (status == ProgressStatus.cooldown &&
        (cooldownUntil == null || _clock().isBefore(cooldownUntil!))) {
      return Future.value();
    }
    if (_refreshing != null) return _refreshing!;
    final future = _refresh(mode, _credential!, _session, snapshot);
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
  }

  Future<void> _refresh(
    GameMode key,
    String token,
    int session,
    ProgressSnapshot? previous,
  ) async {
    status = ProgressStatus.loading;
    error = null;
    _publish();
    try {
      final candidate = await _client.fetch(
        mode: key,
        token: token,
        credentialSession: session,
        previous: previous,
      );
      if (_disposed || session != _session || mode != key) return;
      snapshot = candidate;
      status = ProgressStatus.current;
      cooldownUntil = null;
      _expiry?.cancel();
      _expiry = Timer(const Duration(minutes: 15), updateAge);
    } on TrackerException catch (failure) {
      if (_disposed || session != _session || mode != key) return;
      error = failure.toString();
      if (failure.invalidatesAuthority) {
        snapshot = null;
        _expiry?.cancel();
      }
      if (failure.failure == TrackerFailure.cooldown) {
        status = ProgressStatus.cooldown;
        cooldownUntil = failure.cooldownUntil;
      } else {
        status = snapshot == null
            ? ProgressStatus.failed
            : ProgressStatus.stale;
      }
    } on Object {
      if (_disposed || session != _session || mode != key) return;
      error = 'Tracker unavailable';
      status = snapshot == null ? ProgressStatus.failed : ProgressStatus.stale;
    }
    _publish();
  }

  void updateAge() {
    if (status == ProgressStatus.current &&
        snapshot?.authoritativeAt(_clock()) != true) {
      status = ProgressStatus.stale;
      _publish();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _expiry?.cancel();
    super.dispose();
  }
}
