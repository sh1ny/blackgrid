import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blackgrid/application/live_map_data_controller.dart';
import 'package:blackgrid/data/live_map_refresh.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/maps/live_map_snapshot.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/prepared_pack_manifest.dart' show minimalPreparedMap;

void main() {
  late _Store store;
  late _Fetcher fetcher;
  late List<(String?, bool)> published;
  late LiveMapDataController controller;

  setUp(() {
    store = _Store();
    fetcher = _Fetcher();
    published = [];
    controller = LiveMapDataController(
      store: store,
      fetcher: fetcher,
      publish: (markers, {required changed}) =>
          published.add((markers?['customs']?.single.id, changed)),
      buildMarkers: (snapshot, bindings) async {
        final tag = _tag(snapshot);
        if (tag == 'bad') throw const FormatException('malformed maps');
        return {
          'customs': [_marker(tag)],
        };
      },
    );
  });

  tearDown(() async {
    await controller.close();
    controller.dispose();
  });

  test(
    'without a cache the bundled markers show until a refresh lands',
    () async {
      await controller.selectMode(mode: GameMode.pve, pack: _pack);

      expect(published, [(null, false)]);
      expect(controller.state.source, LiveMapDataSource.bundled);
      expect(controller.state.dataMode, GameMode.pvp);
      expect(controller.state.refreshing, isTrue);

      await fetcher.complete(_snapshot(GameMode.pve, 'fresh'));
      await controller.refresh();

      expect(published.last, ('fresh', true));
      expect(store.saved[GameMode.pve], isNotNull);
      expect(controller.state.source, LiveMapDataSource.refreshed);
      expect(controller.state.dataMode, GameMode.pve);
      expect(controller.state.checkedAt, DateTime.utc(2026));
      expect(controller.state.refreshing, isFalse);
    },
  );

  test(
    'a cache shows at once and supplies validators to the refresh',
    () async {
      final cached = _snapshot(GameMode.pve, 'cached', DateTime.utc(2020));
      store.saved[GameMode.pve] = cached;

      await controller.selectMode(mode: GameMode.pve, pack: _pack);

      expect(published.last, ('cached', true));
      expect(controller.state.source, LiveMapDataSource.cached);
      expect(controller.state.checkedAt, DateTime.utc(2020));
      expect((await fetcher.call()).previous, same(cached));
    },
  );

  test('a failed refresh keeps the cache and reports the failure', () async {
    store.saved[GameMode.pve] = _snapshot(GameMode.pve, 'cached');
    await controller.selectMode(mode: GameMode.pve, pack: _pack);

    await fetcher.fail(const LiveMapRefreshException('maps: HTTP 503'));
    await controller.refresh();

    expect(published.last.$1, 'cached');
    expect(controller.state.source, LiveMapDataSource.cached);
    expect(controller.state.failure.toString(), 'maps: HTTP 503');
    expect(store.commits, 0);
  });

  test('malformed downloaded data is neither stored nor shown', () async {
    await controller.selectMode(mode: GameMode.pve, pack: _pack);

    await fetcher.complete(_snapshot(GameMode.pve, 'bad'));
    await controller.refresh();

    expect(published, [(null, false)]);
    expect(store.commits, 0);
    expect(controller.state.failure, isA<FormatException>());
  });

  test(
    'an unusable cache falls back to bundled markers and still refreshes',
    () async {
      store.saved[GameMode.pve] = _snapshot(GameMode.pve, 'bad');

      await controller.selectMode(mode: GameMode.pve, pack: _pack);

      expect(published, [(null, false)]);
      expect(controller.state.source, LiveMapDataSource.bundled);
      expect(controller.state.failure, isA<FormatException>());
      await fetcher.call();
      expect(fetcher.calls, hasLength(1));
    },
  );

  test('a manual refresh joins the one in flight', () async {
    await controller.selectMode(mode: GameMode.pve, pack: _pack);

    final manual = controller.refresh();
    await fetcher.complete(_snapshot(GameMode.pve, 'fresh'));
    await manual;

    expect(fetcher.calls, hasLength(1));
    expect(published.last.$1, 'fresh');
  });

  test('a reloaded pack starts its own refresh instead of joining', () async {
    await controller.selectMode(mode: GameMode.pve, pack: _pack);
    await fetcher.call();
    final reloaded = PreparedMapPack(
      version: 'reloaded',
      assetRoot: 'test',
      maps: _pack.maps,
    );

    await controller.selectMode(mode: GameMode.pve, pack: reloaded);
    await fetcher.complete(_snapshot(GameMode.pve, 'stale'));
    await fetcher.complete(_snapshot(GameMode.pve, 'fresh'), 1);
    await controller.refresh();

    expect(fetcher.calls, hasLength(2));
    expect(published.last, ('fresh', true));
    expect(controller.state.refreshing, isFalse);
  });

  test('a late result for a previous mode is stored but not shown', () async {
    await controller.selectMode(mode: GameMode.pve, pack: _pack);
    final pveRefresh = controller.refresh();
    await controller.selectMode(mode: GameMode.seasonal, pack: _pack);

    await fetcher.complete(_snapshot(GameMode.pve, 'late'));
    await pveRefresh;

    expect(published.map((entry) => entry.$1), isNot(contains('late')));
    expect(store.saved[GameMode.pve], isNotNull);
    expect(controller.state.mode, GameMode.seasonal);
    expect(controller.state.source, LiveMapDataSource.bundled);
  });

  test(
    'a refresh that confirms the same content keeps the selection',
    () async {
      store.saved[GameMode.pve] = _snapshot(
        GameMode.pve,
        'same',
        DateTime.utc(2020),
      );
      await controller.selectMode(mode: GameMode.pve, pack: _pack);

      await fetcher.complete(_snapshot(GameMode.pve, 'same'));
      await controller.refresh();

      expect(published.last, ('same', false));
      expect(controller.state.checkedAt, DateTime.utc(2026));
    },
  );

  test('a broken pack reports the map unavailable and does no work', () async {
    final failure = StateError('pack missing');

    await controller.selectMode(
      mode: GameMode.pve,
      pack: _pack,
      packFailure: failure,
    );
    await controller.refresh();

    expect(controller.state.source, LiveMapDataSource.unavailable);
    expect(controller.state.failure, same(failure));
    expect(published, isEmpty);
    expect(store.reads, 0);
    expect(fetcher.calls, isEmpty);
  });

  test('the unknown mode shows bundled markers without refreshing', () async {
    await controller.selectMode(mode: GameMode.unknown, pack: _pack);
    await controller.refresh();

    expect(published, [(null, false)]);
    expect(fetcher.calls, isEmpty);
  });

  test('closing cancels the download and stores nothing', () async {
    await controller.selectMode(mode: GameMode.pve, pack: _pack);
    final call = await fetcher.call();

    await controller.close();

    await expectLater(
      call.result.future,
      throwsA(isA<LiveMapRefreshException>()),
    );

    expect(store.commits, 0);
  });
}

final _pack = PreparedMapPack(
  version: 'controller-test',
  assetRoot: 'test',
  maps: [
    PreparedMap.fromJson(minimalPreparedMap('customs'), assetRoot: 'test'),
  ],
);

LiveMapSnapshot _snapshot(GameMode mode, String tag, [DateTime? checkedAt]) =>
    LiveMapSnapshot(
      mode: mode,
      checkedAt: checkedAt ?? DateTime.utc(2026),
      sources: [
        for (final dataset in LiveMapSourceDataset.values)
          LiveMapSourceBody(
            dataset: dataset,
            bytes: Uint8List.fromList(utf8.encode(tag)),
          ),
      ],
    );

String _tag(LiveMapSnapshot snapshot) =>
    utf8.decode(snapshot.sources[LiveMapSourceDataset.maps]!.bytes);

PreparedMarker _marker(String id) => PreparedMarker(
  id: id,
  category: 'extracts',
  filterKey: 'Extracts',
  name: id,
  position: GamePoint(0, 0),
  details: const {},
  source: const {},
  outline: const [],
);

class _Store implements LiveMapStore {
  final Map<GameMode, LiveMapSnapshot> saved = {};
  int reads = 0;
  int commits = 0;

  @override
  Future<LiveMapSnapshot?> read(GameMode mode) async {
    reads++;
    return saved[mode];
  }

  @override
  Future<void> commit(LiveMapSnapshot snapshot) async {
    commits++;
    saved[snapshot.mode] = snapshot;
  }
}

class _FetchCall {
  _FetchCall(this.previous, this.cancel);

  final LiveMapSnapshot? previous;
  final Future<void>? cancel;
  final Completer<LiveMapSnapshot> result = Completer();
}

/// Records each download and lets the test decide its outcome.
///
/// Like the real fetcher, a download fails once its cancel signal fires.
class _Fetcher extends LiveMapFetcher {
  _Fetcher() : super(client: _UnusedClient());

  final List<_FetchCall> calls = [];
  final StreamController<void> _added = StreamController.broadcast(sync: true);

  /// The [index]th download, once the controller has started it.
  Future<_FetchCall> call([int index = 0]) async {
    if (calls.length <= index) {
      await _added.stream.firstWhere((_) => calls.length > index);
    }
    return calls[index];
  }

  Future<void> complete(LiveMapSnapshot snapshot, [int index = 0]) async =>
      (await call(index)).result.complete(snapshot);

  Future<void> fail(Object error, [int index = 0]) async =>
      (await call(index)).result.completeError(error);

  @override
  Future<LiveMapSnapshot> fetch(
    GameMode mode, {
    LiveMapSnapshot? previous,
    Future<void>? cancel,
  }) {
    final call = _FetchCall(previous, cancel);
    cancel?.then((_) {
      if (!call.result.isCompleted) {
        call.result.completeError(const LiveMapRefreshException('cancelled'));
      }
    });
    calls.add(call);
    _added.add(null);
    return call.result.future;
  }
}

class _UnusedClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnsupportedError('The fake fetcher never sends requests.');
}
