import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/catalog.dart';
import '../maps/live_map_snapshot.dart';

/// Byte and time limits for one live-map download.
class LiveMapRefreshLimits {
  /// Creates limits with the default runtime values.
  const LiveMapRefreshLimits({
    this.maxRequestBytes = 16 * 1024 * 1024,
    this.maxTotalBytes = 64 * 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 30),
    this.overallTimeout = const Duration(seconds: 120),
  });

  /// The most bytes accepted from one response.
  final int maxRequestBytes;

  /// The most bytes accepted across all six sources.
  final int maxTotalBytes;

  /// The deadline for each request, including reading its body.
  final Duration requestTimeout;

  /// The deadline for downloading all six sources.
  final Duration overallTimeout;
}

/// Reports why a live-map download failed.
class LiveMapRefreshException implements Exception {
  /// Creates a failure with a source-specific message.
  const LiveMapRefreshException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Downloads the six json.tarkov.dev sources for one game mode.
class LiveMapFetcher {
  /// Creates a fetcher over a shared HTTP client.
  LiveMapFetcher({
    required this._client,
    DateTime Function()? clock,
    this.limits = const LiveMapRefreshLimits(),
  }) : _clock = clock ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _clock;

  /// The limits applied to every download.
  final LiveMapRefreshLimits limits;

  /// Downloads a complete snapshot for [mode].
  ///
  /// Each source is revalidated against [previous] with its ETag, otherwise
  /// its Last-Modified date; a 304 reuses the previous body. Any failure,
  /// redirect, limit breach or completion of [cancel] fails the whole
  /// download with a [LiveMapRefreshException]. There are no retries.
  Future<LiveMapSnapshot> fetch(
    GameMode mode, {
    LiveMapSnapshot? previous,
    Future<void>? cancel,
  }) async {
    final route = liveMapRoute(mode);
    final stop = Completer<String>();
    void stopWith(String reason) {
      if (!stop.isCompleted) stop.complete(reason);
    }

    final overall = Timer(
      limits.overallTimeout,
      () => stopWith('map data download timed out'),
    );
    cancel?.then((_) => stopWith('map data download was cancelled'));
    try {
      final sources = <LiveMapSourceBody>[];
      var total = 0;
      for (final dataset in LiveMapSourceDataset.values) {
        final body = await _fetchOne(
          Uri.https('json.tarkov.dev', '/$route/${dataset.path}'),
          dataset,
          previous?.sources[dataset],
          stop.future,
          remainingBytes: limits.maxTotalBytes - total,
        );
        total += body.bytes.length;
        sources.add(body);
      }
      return LiveMapSnapshot(mode: mode, checkedAt: _clock(), sources: sources);
    } finally {
      overall.cancel();
    }
  }

  Future<LiveMapSourceBody> _fetchOne(
    Uri uri,
    LiveMapSourceDataset dataset,
    LiveMapSourceBody? cached,
    Future<String> stopped, {
    required int remainingBytes,
  }) async {
    final name = dataset.path;
    final abort = Completer<void>();
    var reason = '';
    void abortWith(String why) {
      if (abort.isCompleted) return;
      reason = why;
      abort.complete();
    }

    final timer = Timer(
      limits.requestTimeout,
      () => abortWith('request timed out'),
    );
    unawaited(stopped.then(abortWith));
    final request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: abort.future,
    )..followRedirects = false;
    if (cached?.etag case final String etag when etag.isNotEmpty) {
      request.headers['If-None-Match'] = etag;
    } else if (cached?.lastModified case final String date
        when date.isNotEmpty) {
      request.headers['If-Modified-Since'] = date;
    }
    try {
      final response = await _client.send(request);
      final status = response.statusCode;
      if (status != 200) {
        unawaited(response.stream.listen(null).cancel());
        if (status == 304 && cached != null) {
          if (cached.bytes.length > remainingBytes) {
            throw LiveMapRefreshException('$name: map data is too large');
          }
          return LiveMapSourceBody(
            dataset: dataset,
            bytes: cached.bytes,
            etag: response.headers['etag'] ?? cached.etag,
            lastModified:
                response.headers['last-modified'] ?? cached.lastModified,
          );
        }
        throw LiveMapRefreshException(switch (status) {
          304 => '$name: server reported no change, but nothing is cached',
          >= 300 && < 400 => '$name: redirects are not accepted',
          _ => '$name: HTTP $status',
        });
      }
      final limit = remainingBytes < limits.maxRequestBytes
          ? remainingBytes
          : limits.maxRequestBytes;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > limit) {
          throw LiveMapRefreshException('$name: map data is too large');
        }
        bytes.add(chunk);
      }
      return LiveMapSourceBody(
        dataset: dataset,
        bytes: bytes.takeBytes(),
        etag: response.headers['etag'],
        lastModified: response.headers['last-modified'],
      );
    } on http.RequestAbortedException {
      throw LiveMapRefreshException('$name: $reason');
    } on LiveMapRefreshException {
      rethrow;
    } on Exception catch (error) {
      if (abort.isCompleted) throw LiveMapRefreshException('$name: $reason');
      throw LiveMapRefreshException('$name: request failed: $error');
    } finally {
      timer.cancel();
    }
  }
}
