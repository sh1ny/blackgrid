import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/data/live_map_refresh.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  final checkedAt = DateTime.utc(2026, 11, 7);

  LiveMapFetcher fetcher(
    _FakeClient client, {
    LiveMapRefreshLimits limits = const LiveMapRefreshLimits(),
  }) => LiveMapFetcher(client: client, clock: () => checkedAt, limits: limits);

  test('downloads all six sources from the mode route', () async {
    final client = _FakeClient((dataset) => _Reply.ok('body:${dataset.path}'));

    final snapshot = await fetcher(client).fetch(GameMode.seasonal);

    expect(client.requests.map((request) => request.url.toString()), [
      for (final dataset in LiveMapSourceDataset.values)
        'https://json.tarkov.dev/pvp-season/${dataset.path}',
    ]);
    expect(snapshot.mode, GameMode.seasonal);
    expect(snapshot.checkedAt, checkedAt);
    expect(
      utf8.decode(snapshot.sources[LiveMapSourceDataset.tasks]!.bytes),
      'body:tasks',
    );
    expect(snapshot.sources[LiveMapSourceDataset.tasks]!.etag, '"tasks-1"');
  });

  test(
    'revalidates with ETag, then Last-Modified, and reuses 304 bodies',
    () async {
      final previous = LiveMapSnapshot(
        mode: GameMode.pve,
        checkedAt: DateTime.utc(2020),
        sources: [
          for (final dataset in LiveMapSourceDataset.values)
            LiveMapSourceBody(
              dataset: dataset,
              bytes: _bytes('old:${dataset.path}'),
              etag: dataset == LiveMapSourceDataset.maps ? '"m"' : null,
              lastModified: dataset == LiveMapSourceDataset.tasks
                  ? 'Mon'
                  : null,
            ),
        ],
      );
      final client = _FakeClient(
        (dataset) => dataset == LiveMapSourceDataset.traders
            ? _Reply.ok('new:traders')
            : _Reply(304, ''),
      );

      final snapshot = await fetcher(client)
          .fetch(GameMode.pve, previous: previous);

      final headers = {
        for (final request in client.requests)
          request.url.pathSegments.last: request.headers,
      };
      expect(headers['maps'], {'If-None-Match': '"m"'});
      expect(headers['tasks'], {'If-Modified-Since': 'Mon'});
      expect(headers['traders'], isEmpty);
      expect(
        utf8.decode(snapshot.sources[LiveMapSourceDataset.maps]!.bytes),
        'old:maps',
      );
      expect(snapshot.sources[LiveMapSourceDataset.maps]!.etag, '"m"');
      expect(
        utf8.decode(snapshot.sources[LiveMapSourceDataset.traders]!.bytes),
        'new:traders',
      );
    },
  );

  test('a 304 without a cached body fails', () async {
    final client = _FakeClient((_) => _Reply(304, ''));

    await expectLater(
      fetcher(client).fetch(GameMode.pvp),
      _failsWith('maps: server reported no change, but nothing is cached'),
    );
  });

  test('a redirect fails instead of being followed', () async {
    final client = _FakeClient(
      (dataset) => dataset == LiveMapSourceDataset.tasks
          ? _Reply(302, '', headers: {'location': 'https://example.com'})
          : _Reply.ok('{}'),
    );

    await expectLater(
      fetcher(client).fetch(GameMode.pvp),
      _failsWith('tasks: redirects are not accepted'),
    );
    expect(
      client.requests.every((request) => !request.followRedirects),
      isTrue,
    );
  });

  test('an HTTP error fails without retrying', () async {
    final client = _FakeClient((_) => _Reply(503, ''));

    await expectLater(
      fetcher(client).fetch(GameMode.pvp),
      _failsWith('maps: HTTP 503'),
    );
    expect(client.requests, hasLength(1));
  });

  test('a response over the per-request limit fails', () async {
    final client = _FakeClient((_) => _Reply.ok('x' * 11));

    await expectLater(
      fetcher(
        client,
        limits: const LiveMapRefreshLimits(maxRequestBytes: 10),
      ).fetch(GameMode.pvp),
      _failsWith('maps: map data is too large'),
    );
  });

  test('responses over the total limit fail', () async {
    final client = _FakeClient((_) => _Reply.ok('x' * 10));

    await expectLater(
      fetcher(
        client,
        limits: const LiveMapRefreshLimits(maxTotalBytes: 25),
      ).fetch(GameMode.pvp),
      _failsWith('tasks: map data is too large'),
    );
  });

  test('a request that outlives its deadline is aborted', () async {
    final client = _FakeClient((_) => const _Hang());

    await expectLater(
      fetcher(
        client,
        limits: const LiveMapRefreshLimits(
          requestTimeout: Duration(milliseconds: 1),
        ),
      ).fetch(GameMode.pvp),
      _failsWith('maps: request timed out'),
    );
  });

  test('the whole download has a deadline', () async {
    final client = _FakeClient((_) => const _Hang());

    await expectLater(
      fetcher(
        client,
        limits: const LiveMapRefreshLimits(
          overallTimeout: Duration(milliseconds: 1),
        ),
      ).fetch(GameMode.pvp),
      _failsWith('maps: map data download timed out'),
    );
  });

  test('cancellation aborts the request in flight', () async {
    final client = _FakeClient((_) => const _Hang());
    final cancel = Completer<void>();
    final sent = client.sent.first;

    final fetching = fetcher(client).fetch(GameMode.pvp, cancel: cancel.future);
    await sent;
    cancel.complete();

    await expectLater(
      fetching,
      _failsWith('maps: map data download was cancelled'),
    );
  });
}

Matcher _failsWith(String message) => throwsA(
  isA<LiveMapRefreshException>().having(
    (error) => error.message,
    'message',
    message,
  ),
);

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

sealed class _Response {
  const _Response();
}

class _Reply extends _Response {
  _Reply(this.status, this.body, {this.headers = const {}});

  _Reply.ok(this.body) : status = 200, headers = const {};

  final int status;
  final String body;
  final Map<String, String> headers;
}

class _Hang extends _Response {
  const _Hang();
}

/// Answers each source by dataset, recording requests and honouring aborts.
class _FakeClient extends http.BaseClient {
  _FakeClient(this._answer);

  final _Response Function(LiveMapSourceDataset dataset) _answer;
  final List<http.BaseRequest> requests = [];
  final StreamController<void> _sent = StreamController.broadcast();

  Stream<void> get sent => _sent.stream;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    _sent.add(null);
    final dataset = LiveMapSourceDataset.values.singleWhere(
      (value) => value.path == request.url.pathSegments.last,
    );
    final abort = (request as http.Abortable).abortTrigger!;
    switch (_answer(dataset)) {
      case _Reply(:final status, :final body, :final headers):
        return http.StreamedResponse(
          Stream.value(utf8.encode(body)),
          status,
          headers: {
            if (status == 200) 'etag': '"${dataset.path}-1"',
            ...headers,
          },
        );
      case _Hang():
        await abort;
        throw http.RequestAbortedException(request.url);
    }
  }
}
