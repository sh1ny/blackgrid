import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/catalog.dart';
import '../domain/progress.dart';
import 'wire_json.dart';

enum TrackerFailure {
  unavailable,
  authentication,
  permission,
  mode,
  identity,
  malformed,
  cooldown,
}

class TrackerException implements Exception {
  const TrackerException(this.failure, {this.cooldownUntil});
  final TrackerFailure failure;
  final DateTime? cooldownUntil;
  bool get invalidatesAuthority =>
      failure != TrackerFailure.unavailable &&
      failure != TrackerFailure.cooldown;
  @override
  String toString() => switch (failure) {
    TrackerFailure.unavailable => 'Tracker transport unavailable',
    TrackerFailure.authentication => 'Tracker credential denied',
    TrackerFailure.permission => 'Tracker read permission unavailable',
    TrackerFailure.mode => 'Tracker mode mismatch',
    TrackerFailure.identity => 'Tracker account mismatch',
    TrackerFailure.malformed => 'Tracker response invalid',
    TrackerFailure.cooldown => 'Tracker refresh cooldown',
  };
}

class TrackerClient {
  TrackerClient({
    required this._client,
    DateTime Function()? clock,
    this.userAgent = 'Blackgrid/0.1.0',
  }) : _clock = clock ?? DateTime.now {
    if (userAgent.length < 5 || userAgent.length > 200) {
      throw ArgumentError('Invalid client identity');
    }
  }
  final http.Client _client;
  final DateTime Function() _clock;
  final String userAgent;
  static bool validToken(GameMode mode, String token) {
    final prefix = switch (mode) {
      GameMode.unknown => null,
      GameMode.pvp => 'PVP_',
      GameMode.pve => 'PVE_',
      GameMode.seasonal => 'SZN_',
    };
    return prefix != null &&
        token.startsWith(prefix) &&
        token.length > prefix.length &&
        !RegExp(r'\s').hasMatch(token);
  }

  Future<http.Response> _get(String path, String token, {String? etag}) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      Uri.https('api.tarkovtracker.org', '/$path'),
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers.addAll({
      'Accept': 'application/json',
      'User-Agent': userAgent,
      'Authorization': 'Bearer $token',
      'If-None-Match': ?etag,
    });
    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              abort.complete();
              throw const TrackerException(TrackerFailure.unavailable);
            },
          );
    } on Object {
      throw const TrackerException(TrackerFailure.unavailable);
    }
    if (response.statusCode == 401) {
      throw const TrackerException(TrackerFailure.authentication);
    }
    if (response.statusCode == 403) {
      throw const TrackerException(TrackerFailure.permission);
    }
    if (response.statusCode == 429) {
      final value = response.headers['retry-after']?.trim() ?? '';
      final seconds = int.tryParse(value);
      final now = _clock().toUtc();
      DateTime? deadline;
      if (seconds != null && seconds >= 0) {
        try {
          deadline = now.add(Duration(seconds: seconds));
        } on Object {
          // Out-of-range values use the same finite unknown-header cooldown.
        }
      } else {
        try {
          deadline = HttpDate.parse(value).toUtc();
        } on HttpException {
          // Missing and malformed headers cannot lock the credential session.
        }
      }
      throw TrackerException(
        TrackerFailure.cooldown,
        cooldownUntil: deadline ?? now.add(const Duration(seconds: 60)),
      );
    }
    if (response.statusCode != 200 &&
        !(path == 'progress' && response.statusCode == 304)) {
      throw const TrackerException(TrackerFailure.unavailable);
    }
    return response;
  }

  Future<ProgressSnapshot> fetch({
    required GameMode mode,
    required String token,
    required int credentialSession,
    ProgressSnapshot? previous,
  }) async {
    if (!validToken(mode, token)) {
      throw const TrackerException(TrackerFailure.mode);
    }
    final tokenResponse = await _get('token', token);
    final String owner;
    try {
      final j = decodeWireObject(tokenResponse.body);
      if (j['success'] != true) {
        throw const TrackerException(TrackerFailure.authentication);
      }
      final permissions = _array(j['permissions']);
      if (permissions.any(
        (v) => v is! String || !['GP', 'TP', 'WP'].contains(v),
      )) {
        throw const TrackerException(TrackerFailure.malformed);
      }
      if (!permissions.contains('GP')) {
        throw const TrackerException(TrackerFailure.permission);
      }
      if (j['token'] != token) {
        throw const TrackerException(TrackerFailure.authentication);
      }
      if (j['gameMode'] != mode.trackerMode) {
        throw const TrackerException(TrackerFailure.mode);
      }
      owner = _string(j['owner']);
      _stringValue(j['note']);
      _integer(j['calls'], min: 0);
    } on TrackerException {
      rethrow;
    } on Object {
      throw const TrackerException(TrackerFailure.malformed);
    }
    final reusable =
        previous != null &&
        previous.mode == mode &&
        previous.credentialSession == credentialSession &&
        previous.owner == owner;
    if (previous != null &&
        previous.credentialSession == credentialSession &&
        previous.owner != owner) {
      throw const TrackerException(TrackerFailure.identity);
    }
    final cached = reusable ? previous : null;
    final response = await _get('progress', token, etag: cached?.etag);
    if (response.statusCode == 304) {
      if (cached == null || cached.etag == null) {
        throw const TrackerException(TrackerFailure.malformed);
      }
      return cached.renewed(_clock().toUtc(), response.headers['etag']);
    }
    try {
      final j = decodeWireObject(response.body);
      if (j['success'] != true) {
        throw const TrackerException(TrackerFailure.malformed);
      }
      final data = _object(j['data']);
      final meta = _object(j['meta']);
      if (meta['gameMode'] != mode.trackerMode) {
        throw const TrackerException(TrackerFailure.mode);
      }
      if (_string(data['userId']) != owner || _string(meta['self']) != owner) {
        throw const TrackerException(TrackerFailure.identity);
      }
      _stringValue(data['displayName']);
      final level = _integer(data['playerLevel'], min: 1, max: 79);
      final edition = _integer(data['gameEdition'], min: 1);
      final faction = _string(data['pmcFaction']);
      if (!['USEC', 'BEAR'].contains(faction)) {
        throw const TrackerException(TrackerFailure.malformed);
      }
      return ProgressSnapshot(
        mode: mode,
        credentialSession: credentialSession,
        owner: owner,
        observedAt: _clock().toUtc(),
        playerLevel: level,
        gameEdition: edition,
        faction: faction,
        tasks: _entities(data['tasksProgress'], tasks: true),
        objectives: _entities(
          data['taskObjectivesProgress'],
          counts: true,
          invalid: true,
        ),
        modules: _entities(data['hideoutModulesProgress']),
        parts: _entities(data['hideoutPartsProgress'], counts: true),
        etag: response.headers['etag'],
      );
    } on TrackerException {
      rethrow;
    } on Object {
      throw const TrackerException(TrackerFailure.malformed);
    }
  }
}

Map<String, dynamic> _object(Object? v) {
  if (v is! Map) throw const FormatException('Invalid object');
  return Map<String, dynamic>.from(v);
}

List<dynamic> _array(Object? v) {
  if (v is! List) throw const FormatException('Invalid array');
  return v;
}

String _string(Object? v) {
  if (v is! String || v.isEmpty) {
    throw const FormatException('Invalid identity');
  }
  return v;
}

void _stringValue(Object? v) {
  if (v is! String) throw const FormatException('Invalid string');
}

int _integer(Object? v, {required int min, int? max}) {
  if (v is! int || v < min || (max != null && v > max)) {
    throw const FormatException('Invalid integer');
  }
  return v;
}

bool? _bool(Object? v) {
  if (v == null) return null;
  if (v is! bool) throw const FormatException('Invalid boolean');
  return v;
}

Map<String, EntityProgress> _entities(
  Object? wire, {
  bool tasks = false,
  bool counts = false,
  bool invalid = false,
}) {
  final result = <String, EntityProgress>{};
  for (final raw in _array(wire)) {
    final j = _object(raw);
    final id = _string(j['id']);
    final complete = _bool(j['complete']);
    if (complete == null || result.containsKey(id)) {
      throw const FormatException('Invalid progress identity');
    }
    final count = j['count'];
    if (counts &&
        count != null &&
        (count is! num || !count.isFinite || count < 0)) {
      throw const FormatException('Invalid progress count');
    }
    result[id] = EntityProgress(
      complete: complete,
      count: counts ? count as num? : null,
      failed: tasks ? _bool(j['failed']) : null,
      invalid: tasks || invalid ? _bool(j['invalid']) : null,
    );
  }
  return result;
}
