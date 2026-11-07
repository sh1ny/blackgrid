import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../maps/live_map_snapshot.dart';
import '../maps/live_map_budget.dart';
import '../maps/live_map_normalizer.dart';
import '../maps/prepared_map.dart';
import '../data/live_map_refresh.dart';

/// Identifies the authority currently displayed for live marker data.
enum LiveMapDataSource { bundled, cached, refreshed, unavailable }

/// Describes selected-mode refresh status independently from marker content.
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

  /// Whether the selected mode has pending or active refresh work.
  final bool refreshing;
}

/// Owns selected-mode cache authority and bounded background refresh work.
class LiveMapDataController extends ChangeNotifier {
  /// Creates a controller with preflighted publication over a shared store.
  ///
  /// [_preparePublication] validates and prepares an activation closure before
  /// durable refresh commits; cached authority activates its closure directly.
  LiveMapDataController({
    required this._store,
    required this._acquirer,
    required this._clock,
    required this._preparePublication,
    Timer Function(Duration, void Function())? createTimer,
  }) : _createTimer = createTimer ?? Timer.new;

  final LiveMapStore _store;
  final LiveMapRefreshAcquirer _acquirer;
  final DateTime Function() _clock;
  final void Function() Function(LiveMapSnapshot?, LiveMapBudget)
  _preparePublication;
  final Timer Function(Duration, void Function()) _createTimer;
  LiveMapDataState _state = const LiveMapDataState(
    mode: GameMode.unknown,
    dataMode: GameMode.pvp,
    source: LiveMapDataSource.bundled,
    checkedAt: null,
    failure: null,
    refreshing: false,
  );
  LiveMapDataState get state => _state;
  int _selection = 0;
  final Map<GameMode, int> _modeGeneration = {};
  final Map<GameMode, int> _publicationGeneration = {};
  final Map<GameMode, Future<void>> _joins = {};
  final Set<Future<void>> _cacheReads = {};
  _Intent? _active;
  _Intent? _pending;
  bool _closing = false;
  bool _detached = false;
  Future<void>? _closeFuture;
  PreparedMapPack? _selectedPack;
  List<LiveMapBinding> _selectedBindings = const [];

  /// Selects a mode's cache or honest bundled fallback and queues refresh.
  Future<void> selectMode({
    required GameMode mode,
    required PreparedMapPack? pack,
    required List<LiveMapBinding> bindings,
    Object? packFailure,
  }) async {
    if (_closing) return;
    _selectedPack = pack;
    _selectedBindings = List.unmodifiable(bindings);
    final selection = ++_selection;
    _cancelActive();
    final obsoletePending = _pending;
    obsoletePending?.cancel();
    obsoletePending?.timer?.cancel();
    if (obsoletePending != null) _finish(obsoletePending);
    _pending = null;
    final supported = mode != GameMode.unknown;
    _setState(
      LiveMapDataState(
        mode: mode,
        dataMode: GameMode.pvp,
        source: packFailure != null
            ? LiveMapDataSource.unavailable
            : LiveMapDataSource.bundled,
        checkedAt: null,
        failure: packFailure,
        refreshing: false,
      ),
    );
    if (pack != null) {
      try {
        _preparePublication(null, LiveMapBudget())();
      } catch (failure) {
        if (_state.mode == mode && !_closing) {
          _setState(
            LiveMapDataState(
              mode: mode,
              dataMode: GameMode.pvp,
              source: packFailure != null
                  ? LiveMapDataSource.unavailable
                  : LiveMapDataSource.bundled,
              checkedAt: null,
              failure: failure,
              refreshing: false,
            ),
          );
        }
      }
    }
    if (!supported || pack == null || packFailure != null) return;
    final compatibility = LiveMapCompatibility.fromPreparedPack(pack, bindings);
    final publicationGeneration = _publicationGeneration[mode] ?? 0;
    Object? cacheFailure;
    try {
      final reading = _store.read(
        mode,
        compatibility: compatibility,
        onRejected: (failure) => cacheFailure = failure,
      );
      final drain = reading.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      _cacheReads.add(drain);
      late final LiveMapSnapshot? snapshot;
      try {
        snapshot = await reading;
      } finally {
        _cacheReads.remove(drain);
      }
      final active = _active;
      if (active != null &&
          active.mode == mode &&
          active.selection == selection &&
          active.activate != null) {
        await active.done!.future;
      }
      if (_closing ||
          selection != _selection ||
          (_publicationGeneration[mode] ?? 0) != publicationGeneration) {
        return;
      }
      if (snapshot != null) {
        final activate = _preparePublication(snapshot, snapshot.budget);
        activate();
        if (_closing ||
            selection != _selection ||
            (_publicationGeneration[mode] ?? 0) != publicationGeneration) {
          return;
        }
        _setState(
          LiveMapDataState(
            mode: mode,
            dataMode: mode,
            source: LiveMapDataSource.cached,
            checkedAt: snapshot.checkedAt,
            failure:
                cacheFailure ?? (_state.mode == mode ? _state.failure : null),
            refreshing: _joinFor(mode) != null,
          ),
        );
        _publicationGeneration[mode] = publicationGeneration + 1;
      } else if (cacheFailure != null) {
        _setState(
          LiveMapDataState(
            mode: mode,
            dataMode: GameMode.pvp,
            source: LiveMapDataSource.bundled,
            checkedAt: null,
            failure: cacheFailure,
            refreshing: _joinFor(mode) != null,
          ),
        );
      }
    } catch (failure) {
      if (!_closing && selection == _selection) {
        _setState(
          LiveMapDataState(
            mode: mode,
            dataMode: GameMode.pvp,
            source: LiveMapDataSource.bundled,
            checkedAt: null,
            failure: failure,
            refreshing: _joinFor(mode) != null,
          ),
        );
      }
    }
    if (!_closing && selection == _selection) {
      _enqueue(mode: mode, pack: pack, bindings: bindings);
    }
  }

  /// Joins the selected mode's refresh or requests its next bounded slot.
  Future<void> refresh() {
    final mode = _state.mode;
    final pack = _selectedPack;
    if (_closing ||
        mode == GameMode.unknown ||
        pack == null ||
        _state.source == LiveMapDataSource.unavailable) {
      return Future<void>.value();
    }
    final join = _joinFor(mode);
    if (join != null) return join;
    _enqueue(mode: mode, pack: pack, bindings: _selectedBindings);
    return _joinFor(mode) ?? Future<void>.value();
  }

  void _enqueue({
    required GameMode mode,
    required PreparedMapPack pack,
    required List<LiveMapBinding> bindings,
  }) {
    if (_joinFor(mode) != null) return;
    final intent = _Intent(
      mode,
      pack,
      List.unmodifiable(bindings),
      _clock(),
      _selection,
    );
    final done = Completer<void>();
    intent.done = done;
    _joins[mode] = done.future;
    final remaining = intent.startedAt
        .add(_acquirer.overallTimeout)
        .difference(_clock());
    intent.timer = _createTimer(
      remaining.isNegative ? Duration.zero : remaining,
      () => _expire(intent),
    );
    if (_active == null) {
      _start(intent);
    } else {
      final obsolete = _pending;
      obsolete?.cancel();
      obsolete?.timer?.cancel();
      if (obsolete != null) _finish(obsolete);
      _pending = intent;
      _publishRefreshing();
    }
  }

  Future<void>? _joinFor(GameMode mode) {
    final join = _joins[mode];
    if (join == null) return null;
    final intent = identical(_active?.done?.future, join)
        ? _active
        : identical(_pending?.done?.future, join)
        ? _pending
        : null;
    if (intent == null || intent.cancelled || intent.selection != _selection) {
      return null;
    }
    return join;
  }

  void _start(_Intent intent) {
    if (_closing || intent.cancelled) {
      _finish(intent);
      return;
    }
    if (intent.deadlineReached ||
        !_clock().isBefore(intent.startedAt.add(_acquirer.overallTimeout))) {
      if (!identical(_pending, intent)) _pending = intent;
      intent.deadlineReached = true;
      _expire(intent);
      return;
    }
    _active = intent;
    _publishRefreshing();
    final generation = (_modeGeneration[intent.mode] ?? 0) + 1;
    _modeGeneration[intent.mode] = generation;
    final refreshIntent = LiveMapRefreshIntent(
      startedAt: intent.startedAt,
      cancellation: intent.cancelledFuture,
      isCurrent: () =>
          !_closing &&
          !intent.cancelled &&
          (_modeGeneration[intent.mode] ?? 0) == generation,
    );
    void handleFailure(Object failure) {
      if (!_closing &&
          (!intent.cancelled || intent.deadlineReached) &&
          intent.selection == _selection &&
          _state.mode == intent.mode) {
        final effectiveFailure = intent.deadlineReached
            ? LiveMapResourceLimitException(
                'Live-map refresh exceeded its overall deadline.',
              )
            : failure;
        _setState(
          LiveMapDataState(
            mode: intent.mode,
            dataMode:
                _state.source == LiveMapDataSource.bundled ||
                    _state.source == LiveMapDataSource.unavailable
                ? GameMode.pvp
                : intent.mode,
            source: _state.source,
            checkedAt: _state.checkedAt,
            failure: effectiveFailure,
            refreshing: false,
          ),
        );
      }
    }

    unawaited(
      _acquirer
          .refresh(
            mode: intent.mode,
            intent: refreshIntent,
            pack: intent.pack,
            bindings: intent.bindings,
            beforeCommit: (snapshot, budget) {
              intent.activate = _preparePublication(snapshot, budget);
            },
          )
          .then<void>((snapshot) {
            if (_closing ||
                intent.cancelled ||
                intent.selection != _selection ||
                _state.mode != intent.mode ||
                (_modeGeneration[intent.mode] ?? 0) != generation) {
              return;
            }
            final activate = intent.activate;
            if (activate == null) {
              throw StateError(
                'Refresh completed without prepared publication.',
              );
            }
            activate();
            if (_closing ||
                intent.cancelled ||
                intent.selection != _selection ||
                _state.mode != intent.mode ||
                (_modeGeneration[intent.mode] ?? 0) != generation) {
              return;
            }
            _publicationGeneration[intent.mode] =
                (_publicationGeneration[intent.mode] ?? 0) + 1;
            _setState(
              LiveMapDataState(
                mode: intent.mode,
                dataMode: intent.mode,
                source: LiveMapDataSource.refreshed,
                checkedAt: snapshot.checkedAt,
                failure: null,
                refreshing: false,
              ),
            );
          })
          .catchError((Object failure) => handleFailure(failure))
          .whenComplete(() => _finish(intent)),
    );
  }

  void _expire(_Intent intent) {
    if (_closing || intent.cancelled) return;
    intent.deadlineReached = true;
    if (identical(_pending, intent)) {
      intent.cancel();
      _pending = null;
      final failure = LiveMapResourceLimitException(
        'Live-map refresh exceeded its overall deadline.',
      );
      if (intent.selection == _selection && _state.mode == intent.mode) {
        _setState(
          LiveMapDataState(
            mode: intent.mode,
            dataMode: _state.dataMode,
            source: _state.source,
            checkedAt: _state.checkedAt,
            failure: failure,
            refreshing: false,
          ),
        );
      }
      _finish(intent);
      return;
    }
    if (identical(_active, intent)) intent.cancel();
  }

  void _finish(_Intent intent) {
    intent.timer?.cancel();
    if (identical(_active, intent)) _active = null;
    if (identical(_pending, intent)) _pending = null;
    if (identical(_joins[intent.mode], intent.done?.future)) {
      _joins.remove(intent.mode);
    }
    if (!intent.done!.isCompleted) intent.done!.complete();
    final next = _pending;
    if (!_closing && next != null) {
      _pending = null;
      _start(next);
    } else if (!_closing && _state.refreshing) {
      _setState(
        LiveMapDataState(
          mode: _state.mode,
          dataMode: _state.dataMode,
          source: _state.source,
          checkedAt: _state.checkedAt,
          failure: _state.failure,
          refreshing: false,
        ),
      );
    }
  }

  void _cancelActive() => _active?.cancel();

  void _publishRefreshing() {
    if (_state.mode == GameMode.unknown) return;
    _setState(
      LiveMapDataState(
        mode: _state.mode,
        dataMode: _state.dataMode,
        source: _state.source,
        checkedAt: _state.checkedAt,
        failure: _state.failure,
        refreshing: true,
      ),
    );
  }

  void _setState(LiveMapDataState next) {
    _state = next;
    if (!_detached) notifyListeners();
  }

  /// Fences notifications immediately and drains work before dependencies close.
  Future<void> close() => _closeFuture ??= _beginClose();

  Future<void> _beginClose() async {
    _closing = true;
    _detached = true;
    _cancelActive();
    final pendingIntent = _pending;
    pendingIntent?.cancel();
    pendingIntent?.timer?.cancel();
    if (pendingIntent != null) _finish(pendingIntent);
    final active = _active?.done?.future;
    await Future.wait([..._cacheReads, ?active]);
  }

  @override
  void dispose() {
    _detached = true;
    _closing = true;
    _cancelActive();
    _active?.timer?.cancel();
    _pending?.cancel();
    _pending?.timer?.cancel();
    super.dispose();
  }
}

class _Intent {
  _Intent(this.mode, this.pack, this.bindings, this.startedAt, this.selection);
  final GameMode mode;
  final PreparedMapPack pack;
  final List<LiveMapBinding> bindings;
  final DateTime startedAt;
  final int selection;
  final _cancel = Completer<void>();
  Completer<void>? done;
  Timer? timer;
  bool cancelled = false;
  bool deadlineReached = false;
  void Function()? activate;
  Future<void> get cancelledFuture => _cancel.future;
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    if (!_cancel.isCompleted) _cancel.complete();
  }
}
