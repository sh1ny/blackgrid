import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/catalog.dart';
import '../maps/live_map_budget.dart';
import '../maps/live_map_normalizer.dart';
import 'live_map_normalizer_worker.dart';
import '../maps/live_map_snapshot.dart';
import '../maps/prepared_map.dart';

/// Identifies the start, cancellation and freshness fence of a refresh intent.
class LiveMapRefreshIntent {
  /// Creates a refresh intent captured before admission or queueing.
  const LiveMapRefreshIntent({
    required this.startedAt,
    this.cancellation,
    required this.isCurrent,
  });

  /// The original time at which this operation was requested.
  final DateTime startedAt;

  /// Completes when the owner cancels this operation.
  final Future<void>? cancellation;

  /// Whether this operation still owns the latest publication authority.
  final bool Function() isCurrent;
}

/// Configures deterministic HTTP and expanded-data resource limits.
class LiveMapRefreshLimits {
  /// Creates resource limits with the normative runtime defaults.
  const LiveMapRefreshLimits({
    this.maxRequestBytes = 16 * 1024 * 1024,
    this.maxTotalBytes = 64 * 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 30),
    this.overallTimeout = const Duration(seconds: 120),
    this.maxMaterializedBytes = 256 * 1024 * 1024,
    this.maxSerializedBytes = 64 * 1024 * 1024,
  });

  /// The maximum decoded bytes accepted from one response.
  final int maxRequestBytes;

  /// The maximum decoded bytes across all six source bodies.
  final int maxTotalBytes;

  /// The fixed deadline for each HTTP request.
  final Duration requestTimeout;

  /// The fixed deadline from intent through commit.
  final Duration overallTimeout;

  /// The maximum recursively materialized normalized data.
  final int maxMaterializedBytes;

  /// The maximum serialized normalized JSON payload.
  final int maxSerializedBytes;
}

/// Reports a source acquisition, validation or persistence failure.
class LiveMapRefreshException implements Exception {
  /// Creates a refresh failure with a source-specific explanation.
  const LiveMapRefreshException(this.message);

  /// The failure detail.
  final String message;

  @override
  String toString() => 'LiveMapRefreshException: $message';
}

/// Reports cancellation of a refresh intent.
class LiveMapRefreshCancelledException implements Exception {
  /// Creates a cancellation failure.
  const LiveMapRefreshCancelledException();

  @override
  String toString() => 'Live-map refresh was cancelled.';
}

/// Normalizes source bodies on a disposable worker and returns bounded JSON.
typedef LiveMapNormalizeRunner = Future<Uint8List> Function({
  required Map<LiveMapSourceDataset, Uint8List> sources,
  required Iterable<LiveMapBinding> bindings,
  required GameMode mode,
  required LiveMapBudget budget,
  required LiveMapRefreshIntent intent,
});

/// Acquires, validates and atomically persists a complete live-map snapshot.
class LiveMapRefreshAcquirer {
  /// Creates an acquirer using an injected shared HTTP client and snapshot store.
  LiveMapRefreshAcquirer({
    required this._client,
    required this._store,
    DateTime Function()? clock,
    this._limits = const LiveMapRefreshLimits(),
    Timer Function(Duration, void Function())? createTimer,
    LiveMapNormalizeRunner? normalize,
  }) : _clock = clock ?? DateTime.now,
       _createTimer = createTimer ?? Timer.new,
       _normalize = normalize ?? _normalizeLiveMapOffUi;

  final http.Client _client;
  final LiveMapStore _store;
  final DateTime Function() _clock;
  final LiveMapRefreshLimits _limits;
  final Timer Function(Duration, void Function()) _createTimer;
  final LiveMapNormalizeRunner _normalize;

  /// The configured deadline from intent creation through durable commit.
  Duration get overallTimeout => _limits.overallTimeout;

  /// Refreshes and commits one compatible six-source candidate.
  ///
  /// Calls [beforeCommit] with the candidate and this operation's budget before
  /// durable storage, allowing publication preparation to reject it atomically.
  Future<LiveMapSnapshot> refresh({
    required GameMode mode,
    required LiveMapRefreshIntent intent,
    required PreparedMapPack pack,
    required Iterable<LiveMapBinding> bindings,
    void Function(LiveMapSnapshot snapshot, LiveMapBudget budget)? beforeCommit,
  }) async {
    if (mode == GameMode.unknown) {
      throw const LiveMapRefreshException('Unknown game mode.');
    }
    final route = switch (mode) {
      GameMode.pve => 'pve',
      GameMode.seasonal => 'pvp-season',
      GameMode.pvp => 'regular',
      GameMode.unknown => throw const LiveMapRefreshException(
        'Unknown game mode.',
      ),
    };
    final bindingList = List<LiveMapBinding>.unmodifiable(bindings);
    final compatibility = LiveMapCompatibility.fromPreparedPack(
      pack,
      bindingList,
    );
    final budget = LiveMapBudget(
      maxMaterializedBytes: _limits.maxMaterializedBytes,
      maxSerializedBytes: _limits.maxSerializedBytes,
    );
    final totalDeadline = intent.startedAt.add(_limits.overallTimeout);
    var cancelled = false;
    var timedOut = false;
    var cancellationSeen = false;
    final cancelSignal = Completer<void>();
    void checkFence() {
      if (cancelled) throw const LiveMapRefreshCancelledException();
      if (!intent.isCurrent()) {
        throw const LiveMapRefreshException(
          'Refresh no longer has publication authority.',
        );
      }
      if (timedOut || !_clock().isBefore(totalDeadline)) {
        throw const LiveMapResourceLimitException(
          'Live-map refresh exceeded its overall deadline.',
        );
      }
    }

    intent.cancellation?.then((_) {
      cancellationSeen = true;
      cancelled = true;
      if (!cancelSignal.isCompleted) cancelSignal.complete();
    });
    final overallTimer = _createTimer(
      totalDeadline.difference(_clock()).isNegative
          ? Duration.zero
          : totalDeadline.difference(_clock()),
      () {
        timedOut = true;
        if (!cancelSignal.isCompleted) cancelSignal.complete();
      },
    );
    try {
      checkFence();
      final prior = await Future.any<LiveMapSnapshot?>([
        _store.read(mode, compatibility: compatibility),
        cancelSignal.future.then((_) {
          checkFence();
          throw const LiveMapRefreshCancelledException();
        }),
      ]);
      checkFence();
      if (prior != null) {
        budget.reserveMaterialized(
          prior.normalizedPayload.length +
              prior.sources.fold<int>(
                0,
                (total, source) => total + source.bytes.length,
              ) +
              512 +
              prior.sources.length * 64,
        );
      }
      final oldByDataset = <LiveMapSourceDataset, LiveMapSourceBody>{
        for (final source in prior?.sources ?? const <LiveMapSourceBody>[])
          source.dataset: source,
      };
      final accumulated = <LiveMapSourceBody>[];
      var totalBytes = 0;
      for (final dataset in LiveMapSourceDataset.values) {
        checkFence();
        final cached = oldByDataset[dataset];
        final headers = <String, String>{};
        if (cached?.etag case final String etag when etag.isNotEmpty) {
          headers['If-None-Match'] = etag;
        } else if (cached?.lastModified case final String lastModified
            when lastModified.isNotEmpty) {
          headers['If-Modified-Since'] = lastModified;
        }
        final requestAbort = Completer<void>();
        final request = http.AbortableRequest(
          'GET',
          _endpoint(route, dataset),
          abortTrigger: requestAbort.future,
        )..headers.addAll(headers);
        request.followRedirects = false;
        cancelSignal.future.then((_) {
          if (!requestAbort.isCompleted) requestAbort.complete();
        });
        final requestDeadline = _clock().add(_limits.requestTimeout);
        var requestTimedOut = false;
        final requestTimer = _createTimer(
          requestDeadline.difference(_clock()).isNegative
              ? Duration.zero
              : requestDeadline.difference(_clock()),
          () {
            requestTimedOut = true;
            if (!requestAbort.isCompleted) requestAbort.complete();
          },
        );
        final responseResult = Completer<http.StreamedResponse>();
        final sending = _client.send(request);
        sending.then(
          (response) {
            if (responseResult.isCompleted) {
              _discardResponse(response);
            } else {
              responseResult.complete(response);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!responseResult.isCompleted) {
              responseResult.completeError(error, stackTrace);
            }
          },
        );
        requestAbort.future.then((_) {
          if (responseResult.isCompleted) return;
          if (requestTimedOut) {
            responseResult.completeError(
              const LiveMapResourceLimitException(
                'Live-map request exceeded its deadline.',
              ),
            );
          } else {
            responseResult.completeError(
              const LiveMapRefreshCancelledException(),
            );
          }
        });
        http.StreamedResponse response;
        try {
          response = await responseResult.future.timeout(
            _remaining(requestDeadline),
            onTimeout: () {
              requestTimedOut = true;
              if (!requestAbort.isCompleted) requestAbort.complete();
              throw const LiveMapResourceLimitException(
                'Live-map request exceeded its deadline.',
              );
            },
          );
        } on TimeoutException {
          requestTimer.cancel();
          throw const LiveMapResourceLimitException(
            'Live-map request exceeded its deadline.',
          );
        } catch (error) {
          requestTimer.cancel();
          if (requestTimedOut) {
            throw const LiveMapResourceLimitException(
              'Live-map request exceeded its deadline.',
            );
          }
          checkFence();
          throw LiveMapRefreshException(
            '${dataset.name}: request failed: $error',
          );
        }
        late final StreamIterator<List<int>> responseStream;
        try {
          responseStream = StreamIterator<List<int>>(response.stream);
        } catch (_) {
          requestTimer.cancel();
          _discardResponse(response);
          rethrow;
        }
        var responseStreamCancelled = false;
        var responseStreamStarted = false;
        Future<void> cancelResponseStream() async {
          if (responseStreamCancelled) return;
          responseStreamCancelled = true;
          if (responseStreamStarted) {
            await responseStream.cancel();
          } else {
            await response.stream.listen((_) {}).cancel();
          }
        }

        Future<bool> moveNextResponseChunk() {
          responseStreamStarted = true;
          return responseStream.moveNext();
        }

        try {
          checkFence();
        } catch (_) {
          requestTimer.cancel();
          await cancelResponseStream();
          rethrow;
        }
        if (_isRedirect(response.statusCode) ||
            response.headers.containsKey('location')) {
          requestTimer.cancel();
          await cancelResponseStream();
          throw LiveMapRefreshException(
            '${dataset.name}: redirects are not accepted.',
          );
        }
        final status = response.statusCode;
        if (status == 304) {
          requestTimer.cancel();
          await cancelResponseStream();
          if (cached == null) {
            throw LiveMapRefreshException(
              '${dataset.name}: unusable 304 response.',
            );
          }
          totalBytes += cached.bytes.length;
          if (cached.bytes.length > _limits.maxRequestBytes ||
              totalBytes > _limits.maxTotalBytes) {
            throw const LiveMapResourceLimitException(
              'Cached live-map source bodies exceed the byte limit.',
            );
          }
          accumulated.add(
            cached.withValidators(
              etag: response.headers['etag'] ?? cached.etag,
              lastModified:
                  response.headers['last-modified'] ?? cached.lastModified,
              budget: budget,
            ),
          );
          continue;
        }
        if (status != 200) {
          requestTimer.cancel();
          await cancelResponseStream();
          throw LiveMapRefreshException('${dataset.name}: HTTP $status.');
        }
        final bytes = BytesBuilder(copy: false);
        var sourceLength = 0;
        try {
          while (await Future.any<bool>([
            moveNextResponseChunk(),
            requestAbort.future.then((_) {
              if (requestTimedOut) {
                throw const LiveMapResourceLimitException(
                  'Live-map request exceeded its deadline.',
                );
              }
              throw const LiveMapRefreshCancelledException();
            }),
          ])) {
            checkFence();
            final chunk = responseStream.current;
            if (sourceLength + chunk.length > _limits.maxRequestBytes ||
                totalBytes + sourceLength + chunk.length >
                    _limits.maxTotalBytes) {
              throw const LiveMapResourceLimitException(
                'Live-map response bodies exceed the byte limit.',
              );
            }
            budget.reserveMaterialized(chunk.length);
            bytes.add(chunk);
            sourceLength += chunk.length;
          }
        } catch (_) {
          requestTimer.cancel();
          await cancelResponseStream();
          if (requestTimedOut) {
            throw const LiveMapResourceLimitException(
              'Live-map request exceeded its deadline.',
            );
          }
          checkFence();
          rethrow;
        } finally {
          requestTimer.cancel();
          await cancelResponseStream();
        }
        budget.reserveMaterialized(sourceLength);
        totalBytes += sourceLength;
        accumulated.add(
          LiveMapSourceBody(
            dataset: dataset,
            bytes: bytes.takeBytes(),
            etag: response.headers['etag'],
            lastModified: response.headers['last-modified'],
            budget: budget,
          ),
        );
        // Only the body's private bytes survive. The stream fragments and
        // takeBytes() buffer are no longer retained.
        budget.releaseMaterialized(sourceLength * 2);
      }
      checkFence();
      final rawSources = <LiveMapSourceDataset, Uint8List>{
        for (final source in accumulated) source.dataset: source.bytes,
      };
      budget.reserveValue([
        for (final binding in bindingList) binding.calibration,
      ]);
      final workerIntent = LiveMapRefreshIntent(
        startedAt: intent.startedAt,
        cancellation: cancelSignal.future,
        isCurrent: intent.isCurrent,
      );
      late final Uint8List payload;
      try {
        payload = await _normalize(
          sources: rawSources,
          bindings: bindingList,
          mode: mode,
          budget: budget,
          intent: workerIntent,
        );
      } catch (error) {
        checkFence();
        if (error is FormatException) {
          throw LiveMapRefreshException(error.message.toString());
        }
        rethrow;
      }
      if (budget.serializedBytes == 0) {
        budget.reserveSerialized(payload.length);
      } else if (budget.serializedBytes != payload.length) {
        throw StateError(
          'Normalizer serialized-byte accounting is inconsistent.',
        );
      }
      budget.reserveMaterialized(payload.length);
      budget.reserveMaterialized(512 + accumulated.length * 64);
      checkFence();
      final candidate = LiveMapSnapshot(
        mode: mode,
        checkedAt: _clock(),
        normalizedPayload: payload,
        sources: accumulated,
        formatVersion: liveMapSnapshotFormatVersion,
        normalizerVersion: liveMapNormalizerVersion,
        compatibility: compatibility,
        budget: budget,
      );
      checkFence();
      beforeCommit?.call(candidate, budget);
      checkFence();
      final committing = _store.commit(candidate, budget: budget);
      await committing;
      if (cancellationSeen || timedOut || !intent.isCurrent()) {
        if (timedOut) {
          throw const LiveMapResourceLimitException(
            'Live-map refresh exceeded its overall deadline.',
          );
        }
        throw const LiveMapRefreshCancelledException();
      }
      return candidate;
    } finally {
      overallTimer.cancel();
    }
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(_clock());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

void _discardResponse(http.StreamedResponse response) {
  try {
    unawaited(
      response.stream.listen((_) {}).cancel().catchError((Object _) {}),
    );
  } on Object {
    // A previously listened or failed stream has no remaining ownership here.
  }
}

bool _isRedirect(int status) => status >= 300 && status < 400 && status != 304;

Uri _endpoint(String route, LiveMapSourceDataset dataset) {
  final path = switch (dataset) {
    LiveMapSourceDataset.maps => 'maps',
    LiveMapSourceDataset.mapTranslations => 'maps_en',
    LiveMapSourceDataset.tasks => 'tasks',
    LiveMapSourceDataset.taskTranslations => 'tasks_en',
    LiveMapSourceDataset.traders => 'traders',
    LiveMapSourceDataset.traderTranslations => 'traders_en',
  };
  return Uri.https('json.tarkov.dev', '/$route/$path');
}

int _materializedValueSize(Object? value) {
  var total = 0;
  void visit(Object? current) {
    if (current == null || current is bool || current is num) {
      total += 32;
    } else if (current is String) {
      total += 32 + current.length * 2;
    } else if (current is List) {
      total += 48 + current.length * 24;
      for (final item in current) {
        visit(item);
      }
    } else if (current is Map) {
      total += 96 + current.length * 48;
      for (final entry in current.entries) {
        visit(entry.key);
        visit(entry.value);
      }
    }
  }

  visit(value);
  return total;
}

Future<Uint8List> _normalizeLiveMapOffUi({
  required Map<LiveMapSourceDataset, Uint8List> sources,
  required Iterable<LiveMapBinding> bindings,
  required GameMode mode,
  required LiveMapBudget budget,
  required LiveMapRefreshIntent intent,
}) async {
  var transferBytes = 256 + sources.length * 64;
  for (final source in sources.values) {
    transferBytes += source.length;
  }
  var bindingTransferBytes = 0;
  for (final binding in bindings) {
    bindingTransferBytes += 128 + _materializedValueSize(binding.calibration);
  }
  budget.reserveMaterialized(transferBytes + bindingTransferBytes);
  try {
    return await normalizeLiveMapInWorker(
      sources: sources,
      bindings: bindings,
      mode: mode,
      maxMaterializedBytes:
          budget.maxMaterializedBytes - budget.materializedBytes,
      maxSerializedBytes: budget.maxSerializedBytes,
      reserveHandoff: budget.reserveMaterialized,
      releaseHandoff: budget.releaseMaterialized,
      cancellation: intent.cancellation,
    );
  } finally {
    budget.releaseMaterialized(transferBytes + bindingTransferBytes);
  }
}
