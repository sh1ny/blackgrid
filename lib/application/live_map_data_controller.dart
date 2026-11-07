import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../data/live_map_refresh.dart';
import '../domain/catalog.dart';
import '../maps/live_map_normalizer.dart';
import '../maps/live_map_snapshot.dart';
import '../maps/prepared_map.dart';

/// Identifies the authority currently displayed for live marker data.
enum LiveMapDataSource { bundled, cached, refreshed, unavailable }

/// Describes selected-mode map-data status independently from marker content.
@immutable
class LiveMapDataState {
  /// Creates one immutable live-map status value.
  const LiveMapDataState({
    required this.mode,
    required this.dataMode,
    required this.source,
    required this.checkedAt,
    required this.failure,
    required this.refreshing,
  });

  /// The effective selected mode.
  final GameMode mode;

  /// The mode represented by [source].
  final GameMode dataMode;

  /// The authority currently selected for display.
  final LiveMapDataSource source;

  /// The last successful check time for [dataMode].
  final DateTime? checkedAt;

  /// The latest cache or refresh failure for the selected mode.
  final Object? failure;

  /// Whether the selected mode has a refresh in flight.
  final bool refreshing;

  LiveMapDataState _copyWith({
    LiveMapDataSource? source,
    GameMode? dataMode,
    DateTime? checkedAt,
    Object? failure,
    bool clearFailure = false,
    bool? refreshing,
  }) => LiveMapDataState(
    mode: mode,
    dataMode: dataMode ?? this.dataMode,
    source: source ?? this.source,
    checkedAt: checkedAt ?? this.checkedAt,
    failure: clearFailure ? null : failure ?? this.failure,
    refreshing: refreshing ?? this.refreshing,
  );
}

/// Publishes a marker inventory to the map.
///
/// `null` restores the bundled markers. [changed] is false when the new
/// inventory was derived from the same sources as the one it replaces.
typedef LiveMarkerPublisher = void Function(
  Map<String, List<PreparedMarker>>? markers, {
  required bool changed,
});

/// Derives marker inventories from source bodies, normally off the UI isolate.
typedef LiveMarkerBuilder = Future<Map<String, List<PreparedMarker>>> Function(
  LiveMapSnapshot snapshot,
  List<LiveMapBinding> bindings,
);

/// Owns the selected mode's map data: cache, background refresh and status.
class LiveMapDataController extends ChangeNotifier {
  /// Creates a controller.
  LiveMapDataController({
    required this._store,
    required this._fetcher,
    required this._publish,
    LiveMarkerBuilder? buildMarkers,
  }) : _buildMarkers = buildMarkers ?? _buildMarkersOffUi;

  final LiveMapStore _store;
  final LiveMapFetcher _fetcher;
  final LiveMarkerPublisher _publish;
  final LiveMarkerBuilder _buildMarkers;
  final Map<GameMode, ({PreparedMapPack pack, Future<void> work})> _refreshes =
      {};
  final Completer<void> _closed = Completer<void>();
  final Set<Future<void>> _work = {};

  LiveMapDataState _state = const LiveMapDataState(
    mode: GameMode.unknown,
    dataMode: GameMode.pvp,
    source: LiveMapDataSource.bundled,
    checkedAt: null,
    failure: null,
    refreshing: false,
  );
  int _selection = 0;
  int _publications = 0;
  PreparedMapPack? _pack;
  LiveMapSnapshot? _published;

  /// The selected mode's map-data status.
  LiveMapDataState get state => _state;

  bool get _isClosed => _closed.isCompleted;

  /// Selects [mode]: shows its cached snapshot, otherwise the bundled
  /// regular-mode markers, then refreshes it in the background.
  ///
  /// A non-null [packFailure] or a null [pack] reports the map as unavailable
  /// and does no map-data work.
  Future<void> selectMode({
    required GameMode mode,
    required PreparedMapPack? pack,
    Object? packFailure,
  }) => _track(() async {
    if (_isClosed) return;
    final selection = ++_selection;
    _pack = pack;
    final usable = pack != null && packFailure == null;
    _setState(
      LiveMapDataState(
        mode: mode,
        dataMode: GameMode.pvp,
        source: usable
            ? LiveMapDataSource.bundled
            : LiveMapDataSource.unavailable,
        checkedAt: null,
        failure: packFailure,
        refreshing: pack != null && identical(_refreshes[mode]?.pack, pack),
      ),
    );
    if (!usable) return;
    _show(null);
    if (mode == GameMode.unknown) return;

    final publications = _publications;
    try {
      final cached = await _store.read(mode);
      if (cached != null) {
        final markers = await _buildMarkers(cached, pack.liveMapBindings);
        if (selection == _selection && publications == _publications) {
          _show(cached, markers);
          _setState(
            _state._copyWith(
              source: LiveMapDataSource.cached,
              dataMode: mode,
              checkedAt: cached.checkedAt,
            ),
          );
        }
      }
    } catch (failure) {
      if (selection == _selection) {
        _setState(_state._copyWith(failure: failure));
      }
    }
    if (selection == _selection) unawaited(refresh());
  });

  /// Refreshes the selected mode, joining a refresh already in flight for the
  /// same mode and pack.
  Future<void> refresh() {
    final mode = _state.mode;
    final pack = _pack;
    if (_isClosed ||
        mode == GameMode.unknown ||
        pack == null ||
        _state.source == LiveMapDataSource.unavailable) {
      return Future.value();
    }
    final running = _refreshes[mode];
    if (running != null && identical(running.pack, pack)) return running.work;
    final work = _track(() => _refresh(mode, pack));
    _refreshes[mode] = (pack: pack, work: work);
    _setState(_state._copyWith(refreshing: true));
    return work;
  }

  Future<void> _refresh(GameMode mode, PreparedMapPack pack) async {
    bool selected() =>
        !_isClosed && _state.mode == mode && identical(_pack, pack);
    try {
      final previous = await _store.read(mode);
      final fresh = await _fetcher.fetch(
        mode,
        previous: previous,
        cancel: _closed.future,
      );
      final markers = await _buildMarkers(fresh, pack.liveMapBindings);
      if (_isClosed) return;
      await _store.commit(fresh);
      if (!selected()) return;
      _show(fresh, markers);
      _setState(
        _state._copyWith(
          source: LiveMapDataSource.refreshed,
          dataMode: mode,
          checkedAt: fresh.checkedAt,
          clearFailure: true,
        ),
      );
    } catch (failure) {
      if (selected()) _setState(_state._copyWith(failure: failure));
    } finally {
      if (identical(_refreshes[mode]?.pack, pack)) _refreshes.remove(mode);
      if (selected()) _setState(_state._copyWith(refreshing: false));
    }
  }

  void _show(
    LiveMapSnapshot? snapshot, [
    Map<String, List<PreparedMarker>>? markers,
  ]) {
    final changed = snapshot == null
        ? _published != null
        : !snapshot.sameContent(_published);
    _published = snapshot;
    ++_publications;
    _publish(markers, changed: changed);
  }

  Future<void> _track(Future<void> Function() body) {
    final work = body();
    _work.add(work);
    work.whenComplete(() => _work.remove(work)).ignore();
    return work;
  }

  void _setState(LiveMapDataState next) {
    _state = next;
    if (!_isClosed) notifyListeners();
  }

  /// Stops notifying, cancels downloads and waits for in-flight work, so the
  /// database can be closed afterwards.
  Future<void> close() async {
    if (!_isClosed) _closed.complete();
    await Future.wait([
      for (final work in _work.toList()) work.catchError((Object _) {}),
    ]);
  }
}

Future<Map<String, List<PreparedMarker>>> _buildMarkersOffUi(
  LiveMapSnapshot snapshot,
  List<LiveMapBinding> bindings,
) {
  final sources = <LiveMapSourceDataset, Uint8List>{
    for (final MapEntry(:key, :value) in snapshot.sources.entries)
      key: value.bytes,
  };
  final mode = snapshot.mode;
  return Isolate.run(
    () => buildLiveMarkers(sources: sources, bindings: bindings, mode: mode),
  );
}
