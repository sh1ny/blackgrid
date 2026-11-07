import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'package:blackgrid/data/live_map_refresh.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/maps/live_map_budget.dart';
import 'package:blackgrid/maps/live_map_inventory.dart';
import 'package:blackgrid/maps/live_map_normalizer.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/prepared_map.dart';

import '../../tool/maps/calibration.dart' show calibrationFor;
import '../support/prepared_pack_manifest.dart' show minimalPreparedMap;

final _now = DateTime.utc(2026, 1, 2);
const _datasets = LiveMapSourceDataset.values;

Map<String, Object?> _body(LiveMapSourceDataset dataset) => switch (dataset) {
  LiveMapSourceDataset.maps => {
    'data': {'maps': <String, Object?>{}, 'mobs': <String, Object?>{}},
  },
  LiveMapSourceDataset.mapTranslations => {'data': <String, Object?>{}},
  LiveMapSourceDataset.tasks => {
    'data': {'tasks': <String, Object?>{}, 'questItems': <String, Object?>{}},
  },
  LiveMapSourceDataset.taskTranslations => {'data': <String, Object?>{}},
  LiveMapSourceDataset.traders => {'data': <String, Object?>{}},
  LiveMapSourceDataset.traderTranslations => {'data': <String, Object?>{}},
};

Uint8List _jsonBytes(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

Map<String, Object?> _expandedSource(
  int positions, {
  String description = 'Inspect the shared nested location.',
}) {
  final datasets = [for (final dataset in _datasets) _body(dataset)];
  (datasets[0]['data']! as Map<String, Object?>)['maps'] = {
    'customs': {
      'id': 'source-customs',
      'normalizedName': 'customs',
      for (final category in [
        'extracts',
        'transits',
        'spawns',
        'locks',
        'hazards',
        'lootContainers',
        'lootLoose',
        'switches',
        'stationaryWeapons',
        'btrStops',
      ])
        category: <Object?>[],
      'bosses': <Object?>[],
    },
  };
  (datasets[1]['data']! as Map<String, Object?>)['customs'] = 'Customs';
  (datasets[2]['data']! as Map<String, Object?>)['tasks'] = {
    'task-1': {
      'id': 'task-1',
      'name': 'TASK_NAME',
      'trader': 'trader-1',
      'wikiLink': 'https://example.invalid/task',
      'objectives': [
        {
          'id': 'objective-1',
          'description': 'OBJECTIVE_DESCRIPTION',
          'zones': [
            for (var index = 0; index < positions; index++)
              {
                'id': 'zone-$index',
                'map': 'source-customs',
                'position': {'x': index, 'y': index + 1, 'z': index + 2},
              },
          ],
          'possibleLocations': <Object?>[],
        },
      ],
    },
  };
  (datasets[3]['data']! as Map<String, Object?>).addAll({
    'TASK_NAME': 'Synthetic task',
    'OBJECTIVE_DESCRIPTION': description,
  });
  (datasets[4]['data']! as Map<String, Object?>)['trader-1'] = {
    'id': 'trader-1',
    'name': 'TRADER_NAME',
  };
  (datasets[5]['data']! as Map<String, Object?>)['TRADER_NAME'] =
      'Synthetic trader';
  return {
    for (var index = 0; index < _datasets.length; index++)
      _datasets[index].name: datasets[index],
  };
}

List<http.StreamedResponse> _responsesForExpandedSource(
  int positions, {
  String description = 'Inspect the shared nested location.',
}) {
  final sources = _expandedSource(positions, description: description);
  return [
    for (final dataset in _datasets)
      _response(200, body: sources[dataset.name]),
  ];
}

LiveMapSourceBody _source(
  LiveMapSourceDataset dataset, {
  String? etag,
  String? lastModified,
  Uint8List? bytes,
}) => LiveMapSourceBody(
  dataset: dataset,
  bytes: bytes ?? _jsonBytes(_body(dataset)),
  etag: etag,
  lastModified: lastModified,
);

LiveMapSnapshot _snapshot({
  List<LiveMapSourceBody>? sources,
  DateTime? checkedAt,
  Uint8List? normalizedPayload,
  PreparedMapPack? pack,
  List<LiveMapBinding> bindings = const [],
}) {
  final inventoryBudget = LiveMapBudget();
  final compactPayload =
      normalizedPayload ??
      LiveMapInventory.fromMarkers(
        maps: {for (final map in (pack ?? _pack).maps) map.id: map.markers},
        budget: inventoryBudget,
      ).encode(budget: inventoryBudget);
  return LiveMapSnapshot(
    mode: GameMode.pve,
    checkedAt: checkedAt ?? _now,
    normalizedPayload: compactPayload,
    sources: sources ?? [for (final dataset in _datasets) _source(dataset)],
    formatVersion: liveMapSnapshotFormatVersion,
    normalizerVersion: liveMapNormalizerVersion,
    compatibility: LiveMapCompatibility.fromPreparedPack(
      pack ?? _pack,
      bindings,
    ),
  );
}

class _Store implements LiveMapStore {
  _Store(this.value);

  LiveMapSnapshot? value;
  int commits = 0;
  Object? commitError;
  LiveMapSnapshot? committed;
  Completer<void>? commitStarted;
  Completer<void>? commitGate;

  @override
  Future<LiveMapSnapshot?> read(
    GameMode mode, {
    required LiveMapCompatibility compatibility,
    void Function(Object failure)? onRejected,
  }) async => value?.compatibility.fingerprint == compatibility.fingerprint
      ? value
      : null;

  @override
  Future<void> commit(LiveMapSnapshot snapshot, {LiveMapBudget? budget}) async {
    commits++;
    commitStarted?.complete();
    if (commitGate != null) await commitGate!.future;
    if (commitError case final error?) throw error;
    committed = snapshot;
    value = snapshot;
  }
}

class _Client extends http.BaseClient {
  _Client(this.responses, {this.onSend});

  final List<http.StreamedResponse> responses;
  final Future<void> Function()? onSend;
  final List<http.BaseRequest> requests = [];
  int closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (onSend != null) await onSend!();
    if (responses.isEmpty) throw StateError('Unexpected additional request.');
    return responses.removeAt(0);
  }

  @override
  void close() => closes++;
}

http.StreamedResponse _response(
  int status, {
  Object? body,
  Map<String, String> headers = const {},
}) => http.StreamedResponse(
  Stream<List<int>>.value(body == null ? <int>[] : _jsonBytes(body)),
  status,
  headers: headers,
);

class _ResponseBeforeCancellationClient extends http.BaseClient {
  _ResponseBeforeCancellationClient({
    required this.response,
    required this.cancellation,
  });

  final http.StreamedResponse response;
  final Completer<void> cancellation;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final result = Completer<http.StreamedResponse>();
    scheduleMicrotask(() => result.complete(response));
    scheduleMicrotask(() => cancellation.complete());
    return result.future;
  }

  @override
  void close() {}
}

class _FakeTime {
  DateTime value = _now;
  final List<_FakeTimer> timers = [];

  DateTime call() => value;

  Timer createTimer(Duration duration, void Function() callback) {
    final timer = _FakeTimer(value.add(duration), callback);
    timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    value = value.add(duration);
    for (final timer in [...timers]) {
      if (timer.isActive && !timer.deadline.isAfter(value)) {
        timer.fire();
      }
    }
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.deadline, this.callback);

  final DateTime deadline;
  final void Function() callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;
}

class _Clock extends _FakeTime {}

LiveMapRefreshIntent _intent({
  DateTime? startedAt,
  Future<void>? cancellation,
  bool Function()? isCurrent,
}) => LiveMapRefreshIntent(
  startedAt: startedAt ?? _now,
  cancellation: cancellation,
  isCurrent: isCurrent ?? () => true,
);

final _pack = PreparedMapPack(
  version: 'refresh-test',
  assetRoot: 'test',
  maps: const [],
);

final _expandedPack = PreparedMapPack(
  version: 'expanded-refresh-test',
  assetRoot: 'test',
  maps: [
    PreparedMap.fromJson(
      minimalPreparedMap('source-customs'),
      assetRoot: 'test',
    ),
  ],
);

final _expandedBindings = [
  LiveMapBinding(
    sourceKey: 'customs',
    mapId: 'source-customs',
    calibration: calibrationFor('customs'),
  ),
];

void main() {
  group('conditional source acquisition', () {
    test(
      'requests the six exact upstream paths for every supported mode',
      () async {
        const routes = {
          GameMode.pvp: 'regular',
          GameMode.pve: 'pve',
          GameMode.seasonal: 'pvp-season',
        };
        for (final entry in routes.entries) {
          final client = _Client([
            for (final dataset in _datasets)
              _response(200, body: _body(dataset)),
          ]);
          final acquirer = LiveMapRefreshAcquirer(
            client: client,
            store: _Store(null),
            clock: _Clock().call,
          );

          await acquirer.refresh(
            mode: entry.key,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          );

          expect(client.requests.map((request) => request.url.path), [
            '/${entry.value}/maps',
            '/${entry.value}/maps_en',
            '/${entry.value}/tasks',
            '/${entry.value}/tasks_en',
            '/${entry.value}/traders',
            '/${entry.value}/traders_en',
          ]);
        }
      },
    );

    test(
      'prefers ETag to Last-Modified and requests six sources once',
      () async {
        final prior = _snapshot(
          sources: [
            _source(_datasets[0], etag: 'tag-0', lastModified: 'date-0'),
            _source(_datasets[1], lastModified: 'date-1'),
            ...[
              _datasets[2],
              _datasets[3],
              _datasets[4],
              _datasets[5],
            ].map(_source),
          ],
        );
        final client = _Client([for (var i = 0; i < 6; i++) _response(304)]);
        final store = _Store(prior);
        final acquirer = LiveMapRefreshAcquirer(
          client: client,
          store: store,
          clock: _Clock().call,
        );

        await acquirer.refresh(
          mode: GameMode.pve,
          intent: _intent(),
          pack: _pack,
          bindings: const [],
        );

        expect(client.requests, hasLength(6));
        expect(client.requests[0].headers['If-None-Match'], 'tag-0');
        expect(
          client.requests[0].headers,
          isNot(contains('If-Modified-Since')),
        );
        expect(client.requests[1].headers['If-Modified-Since'], 'date-1');
        for (final request in client.requests.skip(2)) {
          expect(request.headers, isNot(contains('If-None-Match')));
          expect(request.headers, isNot(contains('If-Modified-Since')));
        }
        expect(store.commits, 1);
      },
    );

    test('200 replaces body and clears both absent validators', () async {
      final prior = _snapshot(
        sources: [
          _source(_datasets[0], etag: 'old-tag', lastModified: 'old-date'),
          ..._datasets.skip(1).map(_source),
        ],
      );
      final client = _Client([
        _response(200, body: _body(_datasets[0]), headers: {'etag': 'new-tag'}),
        for (var i = 1; i < 6; i++) _response(304),
      ]);
      final store = _Store(prior);

      final result =
          await LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: _Clock().call,
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          );

      expect(result.sources.first.etag, 'new-tag');
      expect(result.sources.first.lastModified, isNull);
      expect(
        result.sources.first.bytes,
        orderedEquals(_jsonBytes(_body(_datasets[0]))),
      );
      expect(client.requests.first.headers['If-None-Match'], 'old-tag');
      expect(store.value, same(result));
    });

    test(
      '304 merges returned validators and preserves omitted cached validators',
      () async {
        final prior = _snapshot(
          sources: [
            _source(_datasets[0], etag: 'old-tag', lastModified: 'old-date'),
            ..._datasets.skip(1).map(_source),
          ],
        );
        final exactBytes = prior.sources.first.bytes;
        final client = _Client([
          _response(304, headers: {'etag': 'new-tag'}),
          for (var i = 1; i < 6; i++) _response(304),
        ]);
        final result =
            await LiveMapRefreshAcquirer(
              client: client,
              store: _Store(prior),
              clock: _Clock().call,
            ).refresh(
              mode: GameMode.pve,
              intent: _intent(),
              pack: _pack,
              bindings: const [],
            );

        expect(result.sources.first.bytes, orderedEquals(exactBytes));
        expect(result.sources.first.etag, 'new-tag');
        expect(result.sources.first.lastModified, 'old-date');
      },
    );

    test(
      'unusable 304 fails without retry or changing stored authority',
      () async {
        final store = _Store(null);
        final client = _Client([_response(304)]);

        await expectLater(
          LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: _Clock().call,
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          ),
          throwsA(isA<LiveMapRefreshException>()),
        );
        expect(client.requests, hasLength(1));
        expect(store.commits, 0);
        expect(store.value, isNull);
      },
    );

    test(
      'mixed 200 and exact cached 304 bodies commit one six-source snapshot',
      () async {
        final prior = _snapshot();
        final client = _Client([
          _response(200, body: _body(_datasets[0]), headers: {'etag': 'fresh'}),
          for (var i = 1; i < 6; i++) _response(304),
        ]);
        final store = _Store(prior);
        final result =
            await LiveMapRefreshAcquirer(
              client: client,
              store: store,
              clock: _Clock().call,
            ).refresh(
              mode: GameMode.pve,
              intent: _intent(),
              pack: _pack,
              bindings: const [],
            );

        expect(
          result.sources.map((source) => source.dataset),
          orderedEquals(_datasets),
        );
        expect(
          result.sources.skip(1).map((source) => source.bytes),
          orderedEquals(prior.sources.skip(1).map((source) => source.bytes)),
        );
        expect(store.committed, same(result));
      },
    );

    test(
      'late source failure and storage rollback preserve bodies and validators',
      () async {
        final prior = _snapshot(
          sources: [
            _source(_datasets[0], etag: 'trusted-0'),
            ..._datasets.skip(1).map(_source),
          ],
        );
        final failedClient = _Client([
          _response(
            200,
            body: _body(_datasets[0]),
            headers: {'etag': 'poisoned'},
          ),
          for (var i = 1; i < 5; i++) _response(200, body: _body(_datasets[i])),
          _response(503),
        ]);
        final sourceStore = _Store(prior);
        await expectLater(
          LiveMapRefreshAcquirer(
            client: failedClient,
            store: sourceStore,
            clock: _Clock().call,
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          ),
          throwsA(isA<LiveMapRefreshException>()),
        );
        expect(sourceStore.value, same(prior));
        expect(sourceStore.commits, 0);
        expect(failedClient.requests, hasLength(6));

        final commitClient = _Client([
          for (var i = 0; i < 6; i++) _response(200, body: _body(_datasets[i])),
        ]);
        final commitStore = _Store(prior)
          ..commitError = StateError('transaction rejected');
        await expectLater(
          LiveMapRefreshAcquirer(
            client: commitClient,
            store: commitStore,
            clock: _Clock().call,
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          ),
          throwsA(isA<StateError>()),
        );
        expect(commitStore.value, same(prior));
        expect(commitStore.commits, 1);
      },
    );
  });

  group('bounded streamed acquisition', () {
    test(
      'accepts exact per-source and aggregate decoded-byte boundaries',
      () async {
        final payloads = [
          for (final dataset in _datasets) _jsonBytes(_body(dataset)),
        ];
        final total = payloads.fold<int>(0, (sum, bytes) => sum + bytes.length);
        final client = _Client([
          for (var i = 0; i < 6; i++)
            http.StreamedResponse(
              Stream<List<int>>.fromIterable([
                payloads[i].sublist(0, payloads[i].length - 1),
                payloads[i].sublist(payloads[i].length - 1),
              ]),
              200,
            ),
        ]);
        final limits = LiveMapRefreshLimits(
          maxRequestBytes: payloads
              .map((bytes) => bytes.length)
              .reduce((a, b) => a > b ? a : b),
          maxTotalBytes: total,
        );
        final store = _Store(null);

        await LiveMapRefreshAcquirer(
          client: client,
          store: store,
          clock: _Clock().call,
          limits: limits,
        ).refresh(
          mode: GameMode.pve,
          intent: _intent(),
          pack: _pack,
          bindings: const [],
        );
        expect(store.commits, 1);
      },
    );

    test(
      'counts cached 304 bodies in total and rejects over-limit before commit',
      () async {
        final prior = _snapshot();
        final sizes = prior.sources
            .map((source) => source.bytes.length)
            .toList();
        final total = sizes.fold<int>(0, (sum, size) => sum + size);
        final store = _Store(prior);
        final client = _Client([for (var i = 0; i < 6; i++) _response(304)]);
        await expectLater(
          LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: _Clock().call,
            limits: LiveMapRefreshLimits(maxTotalBytes: total - 1),
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          ),
          throwsA(isA<LiveMapResourceLimitException>()),
        );
        expect(store.value, same(prior));
        expect(store.commits, 0);
      },
    );

    test('refuses redirects and never issues a follow-up request', () async {
      final client = _Client([
        _response(302, headers: {'location': 'https://elsewhere.invalid'}),
      ]);
      final store = _Store(null);
      await expectLater(
        LiveMapRefreshAcquirer(
          client: client,
          store: store,
          clock: _Clock().call,
        ).refresh(
          mode: GameMode.pve,
          intent: _intent(),
          pack: _pack,
          bindings: const [],
        ),
        throwsA(isA<LiveMapRefreshException>()),
      );
      expect(client.requests, hasLength(1));
      expect(store.commits, 0);
    });

    test(
      'cancellation after headers cancels the unlistened response stream',
      () async {
        final time = _Clock();
        final cancellation = Completer<void>();
        var streamCancelled = false;
        final responseStream = StreamController<List<int>>()
          ..onCancel = () => streamCancelled = true;
        final client = _ResponseBeforeCancellationClient(
          response: http.StreamedResponse(responseStream.stream, 200),
          cancellation: cancellation,
        );
        final store = _Store(null);

        await expectLater(
          LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: time.call,
            createTimer: time.createTimer,
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(cancellation: cancellation.future),
            pack: _pack,
            bindings: const [],
          ),
          throwsA(isA<LiveMapRefreshCancelledException>()),
        );

        expect(streamCancelled, isTrue);
        expect(time.timers, isNotEmpty);
        expect(time.timers.every((timer) => !timer.isActive), isTrue);
        expect(store.commits, 0);
      },
    );

    test(
      'cancellation aborts in-flight request and does not close shared client',
      () async {
        final cancellation = Completer<void>();
        final bodyStarted = Completer<void>();
        final streamController = StreamController<List<int>>(
          onListen: bodyStarted.complete,
        );
        var streamCancelled = false;
        final response = http.StreamedResponse(streamController.stream, 200);
        streamController.onCancel = () => streamCancelled = true;
        final client = _Client([response]);
        final store = _Store(null);
        final pending =
            LiveMapRefreshAcquirer(
              client: client,
              store: store,
              clock: _Clock().call,
            ).refresh(
              mode: GameMode.pve,
              intent: _intent(cancellation: cancellation.future),
              pack: _pack,
              bindings: const [],
            );
        await bodyStarted.future;
        cancellation.complete();

        await expectLater(
          pending,
          throwsA(isA<LiveMapRefreshCancelledException>()),
        );
        expect(streamCancelled, isTrue);
        expect(client.closes, 0);
        expect(store.commits, 0);
      },
    );

    test('fixed request deadline covers stalled response headers', () async {
      final time = _Clock();
      final sendStarted = Completer<void>();
      final releaseSend = Completer<void>();
      final client = _Client(
        [_response(200, body: _body(_datasets.first))],
        onSend: () async {
          sendStarted.complete();
          await releaseSend.future;
        },
      );
      final store = _Store(null);
      final pending =
          LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: time.call,
            createTimer: time.createTimer,
            limits: const LiveMapRefreshLimits(
              requestTimeout: Duration(seconds: 5),
              overallTimeout: Duration(minutes: 2),
            ),
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          );
      await sendStarted.future;
      time.elapse(const Duration(seconds: 5));
      releaseSend.complete();
      await expectLater(pending, throwsA(isA<LiveMapResourceLimitException>()));
      expect(store.commits, 0);
    });

    test('fixed request deadline covers a stalled response body', () async {
      final time = _Clock();
      final bodyStarted = Completer<void>();
      var bodyCancelled = false;
      final stream = StreamController<List<int>>(onListen: bodyStarted.complete)
        ..onCancel = () => bodyCancelled = true;
      final client = _Client([http.StreamedResponse(stream.stream, 200)]);
      final store = _Store(null);
      final pending =
          LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: time.call,
            createTimer: time.createTimer,
            limits: const LiveMapRefreshLimits(
              requestTimeout: Duration(seconds: 5),
              overallTimeout: Duration(minutes: 2),
            ),
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          );
      await bodyStarted.future;
      time.elapse(const Duration(seconds: 5));
      await expectLater(pending, throwsA(isA<LiveMapResourceLimitException>()));
      expect(store.commits, 0);
      expect(bodyCancelled, isTrue);
    });

    test(
      'overall deadline includes time spent queued before acquisition',
      () async {
        final time = _Clock();
        final client = _Client([]);
        final store = _Store(null);
        time.elapse(const Duration(seconds: 20));

        await expectLater(
          LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: time.call,
            createTimer: time.createTimer,
            limits: const LiveMapRefreshLimits(
              overallTimeout: Duration(seconds: 10),
            ),
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(startedAt: _now),
            pack: _pack,
            bindings: const [],
          ),
          throwsA(isA<LiveMapResourceLimitException>()),
        );

        expect(client.requests, isEmpty);
        expect(store.commits, 0);
      },
    );

    test('overall deadline includes time spent in normalization', () async {
      final time = _Clock();
      final entered = Completer<void>();
      final release = Completer<void>();
      final client = _Client([
        for (var i = 0; i < 6; i++) _response(200, body: _body(_datasets[i])),
      ]);
      final store = _Store(null);
      final pending =
          LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: time.call,
            createTimer: time.createTimer,
            limits: const LiveMapRefreshLimits(
              overallTimeout: Duration(seconds: 10),
            ),
            normalize:
                ({
                  required sources,
                  required bindings,
                  required mode,
                  required budget,
                  required intent,
                }) async {
                  entered.complete();
                  await release.future;
                  return _jsonBytes({'normalized': true});
                },
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          );
      await entered.future;
      time.elapse(const Duration(seconds: 10));
      release.complete();
      await expectLater(pending, throwsA(isA<LiveMapResourceLimitException>()));
      expect(store.commits, 0);
    });

    test('an already-started transaction drains after deadline before refresh fails', () async {
      final time = _Clock();
      final store = _Store(null)
        ..commitStarted = Completer<void>()
        ..commitGate = Completer<void>();
      final client = _Client([
        for (var i = 0; i < 6; i++) _response(200, body: _body(_datasets[i])),
      ]);
      var completed = false;
      final pending =
          LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: time.call,
            createTimer: time.createTimer,
            limits: const LiveMapRefreshLimits(
              overallTimeout: Duration(seconds: 10),
            ),
            normalize: ({
              required sources,
              required bindings,
              required mode,
              required budget,
              required intent,
            }) async => _jsonBytes({'normalized': true}),
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          );
      pending.then(
        (_) => completed = true,
        onError: (Object _) => completed = true,
      );
      await store.commitStarted!.future;
      time.elapse(const Duration(seconds: 10));
      await Future<void>.value();
      expect(completed, isFalse);
      store.commitGate!.complete();
      await expectLater(pending, throwsA(isA<LiveMapResourceLimitException>()));
      expect(completed, isTrue);
      expect(store.committed, isNotNull);
    });

    test('latest-operation fence rejects before starting a commit', () async {
      final prior = _snapshot();
      final store = _Store(prior);
      final client = _Client([
        for (var i = 0; i < 6; i++) _response(200, body: _body(_datasets[i])),
      ]);
      await expectLater(
        LiveMapRefreshAcquirer(
          client: client,
          store: store,
          clock: _Clock().call,
          normalize: ({
            required sources,
            required bindings,
            required mode,
            required budget,
            required intent,
          }) async => _jsonBytes({'normalized': true}),
        ).refresh(
          mode: GameMode.pve,
          intent: _intent(isCurrent: () => false),
          pack: _pack,
          bindings: const [],
        ),
        throwsA(isA<LiveMapRefreshException>()),
      );
      expect(store.value, same(prior));
      expect(store.commits, 0);
    });
  });

  group('incremental expanded marker budgets', () {
    test('fragmented responses cannot bypass materialized admission', () async {
      final prior = _snapshot();
      final store = _Store(prior);
      final payload = Uint8List.fromList([
        ...List<int>.filled(96, 32),
        ..._jsonBytes(_body(LiveMapSourceDataset.maps)),
      ]);
      final client = _Client([
        http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            for (final byte in payload) Uint8List.fromList([byte]),
          ]),
          200,
        ),
        for (final dataset in _datasets.skip(1))
          _response(200, body: _body(dataset)),
      ]);
      var normalized = false;

      await expectLater(
        LiveMapRefreshAcquirer(
          client: client,
          store: store,
          clock: () => _now,
          limits: const LiveMapRefreshLimits(maxMaterializedBytes: 8192),
          normalize:
              ({
                required sources,
                required bindings,
                required mode,
                required budget,
                required intent,
              }) async {
                normalized = true;
                return LiveMapInventory.fromMarkers(
                  maps: const {},
                  budget: budget,
                ).encode(budget: budget);
              },
        ).refresh(
          mode: GameMode.pve,
          intent: _intent(),
          pack: _pack,
          bindings: const [],
        ),
        throwsA(isA<LiveMapResourceLimitException>()),
      );
      expect(normalized, isFalse);
      expect(store.commits, 0);
      expect(store.value, same(prior));
    });

    test('response views account for their complete backing buffers', () async {
      final prior = _snapshot();
      final store = _Store(prior);
      final payload = _jsonBytes(_body(LiveMapSourceDataset.maps));
      final backing = Uint8List(64 * 1024)
        ..setRange(0, payload.length, payload);
      final client = _Client([
        http.StreamedResponse(
          Stream<List<int>>.value(
            Uint8List.sublistView(backing, 0, payload.length),
          ),
          200,
        ),
        for (final dataset in _datasets.skip(1))
          _response(200, body: _body(dataset)),
      ]);
      var normalized = false;

      await expectLater(
        LiveMapRefreshAcquirer(
          client: client,
          store: store,
          clock: () => _now,
          limits: const LiveMapRefreshLimits(maxMaterializedBytes: 8192),
          normalize:
              ({
                required sources,
                required bindings,
                required mode,
                required budget,
                required intent,
              }) async {
                normalized = true;
                return LiveMapInventory.fromMarkers(
                  maps: const {},
                  budget: budget,
                ).encode(budget: budget);
              },
        ).refresh(
          mode: GameMode.pve,
          intent: _intent(),
          pack: _pack,
          bindings: const [],
        ),
        throwsA(isA<LiveMapResourceLimitException>()),
      );
      expect(normalized, isFalse);
      expect(store.commits, 0);
      expect(store.value, same(prior));
    });

    test('preserves mixed fragment bytes while ignoring empty views', () async {
      final store = _Store(null);
      final payload = _jsonBytes(_body(LiveMapSourceDataset.maps));
      final emptyBacking = Uint8List(64 * 1024);
      final client = _Client([
        http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            for (var i = 0; i < 100; i++)
              Uint8List.sublistView(emptyBacking, 0, 0),
            Uint8List.fromList(payload.sublist(0, 5)),
            List<int>.of(payload.sublist(5)),
            <int>[],
          ]),
          200,
        ),
        for (final dataset in _datasets.skip(1))
          _response(200, body: _body(dataset)),
      ]);
      var normalized = false;

      final result =
          await LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: () => _now,
            limits: const LiveMapRefreshLimits(maxMaterializedBytes: 16 * 1024),
            normalize:
                ({
                  required sources,
                  required bindings,
                  required mode,
                  required budget,
                  required intent,
                }) async {
                  normalized = true;
                  expect(
                    sources[LiveMapSourceDataset.maps],
                    orderedEquals(payload),
                  );
                  return LiveMapInventory.fromMarkers(
                    maps: const {},
                    budget: budget,
                  ).encode(budget: budget);
                },
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _pack,
            bindings: const [],
          );

      expect(normalized, isTrue);
      expect(result.sources.first.bytes, orderedEquals(payload));
      expect(store.commits, 1);
    });

    test('releases streamed acquisition buffers before later sources and normalization', () async {
      final store = _Store(null);
      final client = _Client([
        for (final dataset in _datasets)
          http.StreamedResponse(
            Stream.value(
              utf8.encode('${' ' * 1024}${jsonEncode(_body(dataset))}'),
            ),
            200,
          ),
      ]);
      var materializedAtNormalization = 0;
      var retainedSourceBytes = 0;
      final acquirer = LiveMapRefreshAcquirer(
        client: client,
        store: store,
        clock: () => _now,
        limits: const LiveMapRefreshLimits(maxMaterializedBytes: 16 * 1024),
        normalize:
            ({
              required sources,
              required bindings,
              required mode,
              required budget,
              required intent,
            }) async {
              retainedSourceBytes = sources.values.fold(
                0,
                (total, bytes) => total + bytes.length,
              );
              materializedAtNormalization = budget.materializedBytes;
              return LiveMapInventory.fromMarkers(
                maps: const {},
                budget: budget,
              ).encode(budget: budget);
            },
      );

      final snapshot = await acquirer.refresh(
        mode: GameMode.pve,
        intent: _intent(),
        pack: _pack,
        bindings: const [],
      );

      expect(retainedSourceBytes, greaterThan(0));
      expect(
        materializedAtNormalization,
        greaterThanOrEqualTo(retainedSourceBytes),
      );
      expect(
        materializedAtNormalization,
        lessThan(retainedSourceBytes * 2),
        reason:
            'stream fragments and takeBytes buffers must be released '
            'while the private source bodies remain charged',
      );
      expect(
        LiveMapInventory.decode(
          snapshot.normalizedPayload,
          budget: LiveMapBudget(),
        ).maps,
        isEmpty,
      );
      expect(snapshot.sources.map((source) => source.dataset), _datasets);
      expect(store.committed, same(snapshot));
    });

    test('releases temporary JSON text before decoding another source', () {
      final budget = LiveMapBudget(maxMaterializedBytes: 4096);
      final first = budget.decodeJson(
        Uint8List.fromList(utf8.encode('${' ' * 1024}1')),
      );
      final second = budget.decodeJson(
        Uint8List.fromList(utf8.encode('${' ' * 1024}2')),
      );

      expect([first, second], [1, 2]);
    });
    test('fitting repeated-position candidate normalizes and commits complete output', () async {
      final sources = _expandedSource(24);
      final store = _Store(null);
      final client = _Client(_responsesForExpandedSource(24));

      final result =
          await LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: _Clock().call,
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _expandedPack,
            bindings: _expandedBindings,
          );

      final normalized = LiveMapInventory.decode(
        result.normalizedPayload,
        budget: LiveMapBudget(),
      ).maps;
      final markers = normalized['source-customs']!;
      expect(markers, hasLength(24));
      expect(
        markers.map((marker) => marker.name),
        everyElement('Inspect the shared nested location.'),
      );
      expect(markers.map((marker) => marker.id).toSet(), hasLength(24));
      expect(
        markers.map((marker) => marker.details['id']),
        everyElement('objective-1'),
      );
      expect(
        markers.map((marker) => (marker.details['quest'] as Map)['id']),
        everyElement('task-1'),
      );
      expect(
        markers.map((marker) => (marker.details['location'] as Map)['id']),
        [for (var index = 0; index < 24; index++) 'zone-$index'],
      );
      expect(
        markers.map(
          (marker) =>
              (marker.position.x, marker.position.z, marker.position.height),
        ),
        [
          for (var index = 0; index < 24; index++)
            (index, index + 2, index + 1),
        ],
      );
      expect(
        markers.map((marker) => (marker.details['quest'] as Map)['name']),
        everyElement('Synthetic task'),
      );
      expect(result.sources, hasLength(6));
      expect(store.committed, same(result));
      expect(sources, hasLength(6));
    });

    test(
      'materialized-only overflow rejects candidate before durable commit',
      () async {
        final prior = _snapshot(
          pack: _expandedPack,
          bindings: _expandedBindings,
        );
        final store = _Store(prior);
        final client = _Client(
          _responsesForExpandedSource(
            24,
            description: 'shared nested detail ' * 200,
          ),
        );

        await expectLater(
          LiveMapRefreshAcquirer(
            client: client,
            store: store,
            clock: _Clock().call,
            limits: const LiveMapRefreshLimits(maxMaterializedBytes: 500000),
          ).refresh(
            mode: GameMode.pve,
            intent: _intent(),
            pack: _expandedPack,
            bindings: _expandedBindings,
          ),
          throwsA(isA<LiveMapResourceLimitException>()),
        );

        expect(store.value, same(prior));
        expect(store.commits, 0);
      },
    );

    test('serialized-only overflow rejects real normalized candidate before commit', () async {
      final prior = _snapshot(pack: _expandedPack, bindings: _expandedBindings);
      final store = _Store(prior);
      final client = _Client(
        _responsesForExpandedSource(
          24,
          description: 'shared nested detail ' * 200,
        ),
      );

      await expectLater(
        LiveMapRefreshAcquirer(
          client: client,
          store: store,
          clock: _Clock().call,
          limits: const LiveMapRefreshLimits(maxSerializedBytes: 8),
        ).refresh(
          mode: GameMode.pve,
          intent: _intent(),
          pack: _expandedPack,
          bindings: _expandedBindings,
        ),
        throwsA(isA<LiveMapResourceLimitException>()),
      );

      expect(store.value, same(prior));
      expect(store.commits, 0);
    });

    test('charges every repeated task and position occurrence before copy', () {
      final budget = LiveMapBudget(
        maxMaterializedBytes: 100000,
        maxSerializedBytes: 100000,
      );
      final repeated = {
        'details': {
          'objective': 'same nested value',
          'locations': [1, 2, 3],
        },
      };
      budget.reserveValue(repeated, copies: 25);
      final once = LiveMapBudget(
        maxMaterializedBytes: 100000,
        maxSerializedBytes: 100000,
      );
      once.reserveValue(repeated);
      expect(budget.materializedBytes, equals(once.materializedBytes * 25));
    });

    test('overlapping old and candidate trees are charged until old copies release', () {
      Map<String, String>? oldCopy = {'source': 'x' * 300};
      final candidate = {'candidate': 'y' * 700};
      final measurement = LiveMapBudget()..reserveValue(oldCopy);
      final oldCharge = measurement.materializedBytes;
      measurement.reserveValue(candidate);
      final candidateCharge = measurement.materializedBytes - oldCharge;
      final budget = LiveMapBudget(
        maxMaterializedBytes: oldCharge + candidateCharge - 1,
      )..reserveValue(oldCopy);

      expect(
        () => budget.reserveValue(candidate),
        throwsA(isA<LiveMapResourceLimitException>()),
      );
      expect(budget.materializedBytes, oldCharge);
      oldCopy = null;
      budget.releaseMaterialized(oldCharge);
      budget.reserveValue(candidate);
      expect(budget.materializedBytes, candidateCharge);
    });

    test('bounded JSON encoding counts UTF-8, escapes, punctuation and repeated copies', () {
      final value = {
        'punctuation': [
          {'label': '雪\\n\u0001', 'n': 1},
          {'label': '雪\\n\u0001', 'n': 1},
        ],
      };
      final budget = LiveMapBudget(
        maxMaterializedBytes: 100000,
        maxSerializedBytes: 100000,
      );
      final encoded = budget.encodeJson(value);
      expect(encoded, orderedEquals(_jsonBytes(value)));
      expect(budget.serializedBytes, encoded.length);
      expect(encoded.length, greaterThan(value.toString().length));
    });

    test(
      'materialized budget rejects an oversized recursive value before copy',
      () {
        final hugeNested = {
          'task': {
            'objective': {
              'location': {'description': 'x' * 2000},
            },
          },
        };
        var copies = 0;
        final budget = LiveMapBudget(
          maxMaterializedBytes: 64,
          maxSerializedBytes: 100000,
        );
        void emit() {
          budget.reserveValue(hugeNested);
          copies++;
          Map<String, Object?>.of(hugeNested);
        }

        expect(emit, throwsA(isA<LiveMapResourceLimitException>()));
        expect(copies, 0);
        expect(budget.materializedBytes, lessThanOrEqualTo(64));
      },
    );

    test('bounded serialized budget rejects expanded UTF-8 output', () {
      final budget = LiveMapBudget(
        maxMaterializedBytes: 100000,
        maxSerializedBytes: 16,
      );
      budget.reserveValue({
        'text': '雪' * 20,
        'values': [1, 2, 3],
      });

      expect(
        () => budget.encodeJson({
          'text': '雪' * 20,
          'values': [1, 2, 3],
        }),
        throwsA(isA<LiveMapResourceLimitException>()),
      );
      expect(budget.materializedBytes, greaterThan(0));
    });

    test(
      'bounded JSON decode rejects container-heavy trees before decoding',
      () {
        final encoded = Uint8List.fromList(
          utf8.encode('[${List.filled(300, '{}').join(',')}]'),
        );
        final budget = LiveMapBudget(
          maxMaterializedBytes: 3000,
          maxSerializedBytes: 10000,
        );

        expect(
          () => budget.decodeJson(encoded),
          throwsA(isA<LiveMapResourceLimitException>()),
        );
        expect(budget.materializedBytes, greaterThan(0));
        expect(budget.materializedBytes, lessThanOrEqualTo(3000));
      },
    );

    test(
      'bounded JSON decode charges escaped and non-ASCII UTF-16 strings',
      () {
        final encoded = Uint8List.fromList(utf8.encode('{"text":"雪\\u0001"}'));
        final budget = LiveMapBudget(
          maxMaterializedBytes: 10000,
          maxSerializedBytes: 10000,
        );

        final decoded = budget.decodeJson(encoded) as Map<String, dynamic>;

        expect(decoded['text'], '雪\u0001');
        expect(budget.materializedBytes, greaterThan(encoded.length));
      },
    );

    test(
      'SDK JSON encoding preserves astral and lone-surrogate code units',
      () {
        final original = String.fromCharCodes([0x1f600, 0xd800]);
        final value = {'text': original};
        final budget = LiveMapBudget(
          maxMaterializedBytes: 10000,
          maxSerializedBytes: 10000,
        );

        final encoded = budget.encodeJson(value);
        final decoded =
            jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;

        expect(encoded, orderedEquals(utf8.encode(jsonEncode(value))));
        expect((decoded['text']! as String).codeUnits, original.codeUnits);
        expect(budget.serializedBytes, encoded.length);
      },
    );

    test('normalizer reserves repeated emitted marker trees before constructing output', () {
      final expanded = _expandedSource(24, description: 'Tâche objective');
      final sources = LiveMapSourceBodies(
        maps: expanded[LiveMapSourceDataset.maps.name] as Map<String, dynamic>,
        mapTranslations:
            expanded[LiveMapSourceDataset.mapTranslations.name]
                as Map<String, dynamic>,
        tasks:
            expanded[LiveMapSourceDataset.tasks.name] as Map<String, dynamic>,
        taskTranslations:
            expanded[LiveMapSourceDataset.taskTranslations.name]
                as Map<String, dynamic>,
        traders:
            expanded[LiveMapSourceDataset.traders.name] as Map<String, dynamic>,
        traderTranslations:
            expanded[LiveMapSourceDataset.traderTranslations.name]
                as Map<String, dynamic>,
      );
      final budget = LiveMapBudget(
        maxMaterializedBytes: 2000000,
        maxSerializedBytes: 100000,
      );
      final normalized = normalizeLiveMapData(
        sources: sources,
        bindings: _expandedBindings,
        mode: 'pve',
        reserveMaterialization: budget.reserveMaterialized,
      );

      final markers = normalized['source-customs']!;
      expect(markers, hasLength(24));
      expect(
        markers.map((marker) => marker['name']),
        everyElement('Tâche objective'),
      );
      expect(
        ((markers.first['details'] as Map)['quest'] as Map)['name'],
        'Synthetic task',
      );
      final task =
          ((sources.tasks['data'] as Map)['tasks'] as Map)['task-1'] as Map;
      final objective = (task['objectives'] as List).single;
      final minimum = LiveMapBudget(maxMaterializedBytes: 2000000)
        ..reserveValue(task, copies: 24)
        ..reserveValue(objective, copies: 24);
      expect(
        budget.materializedBytes,
        greaterThanOrEqualTo(minimum.materializedBytes),
      );
    });
  });
}
