import 'dart:async';

import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../domain/local_progress.dart';
import '../domain/local_progress_store.dart';
import 'local_progress_access.dart';
import 'raid_timers_controller.dart';

/// The player level register.
const playerLevelTarget = ProgressTarget(
  kind: ProgressEntityKind.player,
  id: 'self',
  field: ProgressField.level,
);

/// The player faction register.
const playerFactionTarget = ProgressTarget(
  kind: ProgressEntityKind.player,
  id: 'self',
  field: ProgressField.faction,
);

/// The player edition register.
const playerEditionTarget = ProgressTarget(
  kind: ProgressEntityKind.player,
  id: 'self',
  field: ProgressField.edition,
);

String _failureMessage(ProgressStoreFailure failure) => switch (failure) {
  ProgressInvalidInput(:final reason) => reason,
  ProgressIdentityConflict(:final reason) => reason,
  ProgressBusy() => 'Local progress is busy.',
  ProgressStorageFailure(:final reason) => reason,
  ProgressUnavailable(:final reason) => reason,
  ProgressStaleCursor() => 'Progress changed while it was being read.',
  ProgressUndoConflict() => 'This value changed; it now shows the latest.',
};

/// Projects the effective mode's local progress and validates manual entries.
///
/// Reads are limited to one in flight while attached. Changes arriving during
/// that read are coalesced into one further read of the current mode.
class ManualProgressController extends ChangeNotifier {
  /// Creates a controller over the shared progress queue and effective mode.
  ManualProgressController({
    required LocalProgressAccess access,
    required RaidTimerCatalogSource catalog,
    required this._modeChanges,
    required GameMode Function() effectiveMode,
  }) : _access = access,
       _catalog = catalog,
       _effectiveMode = effectiveMode,
       _mode = effectiveMode(),
       _revision = access.progressRevision,
       _loaded = access.loaded,
       _loadError = access.loadError,
       _catalogMode = catalog.mode,
       _catalogSnapshot = catalog.snapshot {
    _unavailable = access.unavailableModes.contains(_mode);
    _access.addListener(_onAccess);
    _catalog.addListener(_onCatalog);
    _modeChanges.addListener(_onMode);
  }

  final LocalProgressAccess _access;
  final RaidTimerCatalogSource _catalog;
  final Listenable _modeChanges;
  final GameMode Function() _effectiveMode;
  GameMode _mode;
  int _revision;
  bool _loaded;
  String? _loadError;
  late bool _unavailable;
  GameMode _catalogMode;
  CatalogSnapshot? _catalogSnapshot;
  int _attachments = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _reading = false;
  bool _dirty = false;
  bool _loading = false;
  String? _readError;
  ProgressScope? _scope;
  Map<ProgressTarget, ProgressEvent> _winners = const {};
  final Set<(GameMode, ProgressTarget)> _pending = {};
  final Map<(GameMode, ProgressTarget), _RowFailure> _failures = {};

  /// The current effective game mode.
  GameMode get mode => _mode;

  /// The scope of the most recently read projection.
  ProgressScope? get scope => _scope;

  /// The most recently read winners of the effective mode.
  Map<ProgressTarget, ProgressEvent> get winners => _winners;

  /// Whether a projection read is in progress for the visible part.
  bool get loading => _loading;

  /// Whether the effective mode has an active wipe.
  bool get hasWipe => _access.wipes.containsKey(_mode);

  /// Why entries cannot currently be made, or `null` when they can.
  String? get disabledReason {
    if (_mode == GameMode.unknown) return 'Choose a game mode.';
    if (!_access.loaded) {
      final error = _access.loadError;
      return error == null
          ? 'Local progress is not loaded yet.'
          : 'Local progress could not be loaded: $error';
    }
    if (_access.unavailableModes.contains(_mode)) {
      return 'This wipe cannot be read.';
    }
    return _readError;
  }

  /// The progress catalog when its snapshot belongs to the effective mode.
  ProgressCatalog? get progressCatalog {
    final snapshot = _catalog.snapshot;
    if (_mode == GameMode.unknown ||
        _catalog.mode != _mode ||
        snapshot?.mode != _mode) {
      return null;
    }
    return snapshot?.progressCatalog;
  }

  /// Traders with more than one known loyalty level.
  List<CatalogTraderLevels> get traders => List.unmodifiable(
    (progressCatalog?.traders ?? const <CatalogTraderLevels>[]).where(
      (trader) => (trader.levels?.length ?? 0) > 1,
    ),
  );

  /// The effective mode's known hideout stations.
  List<HideoutStation> get stations =>
      progressCatalog?.stations ?? const <HideoutStation>[];

  /// The edition identifiers supported by the availability rules.
  List<String> get editions => List.unmodifiable(editionTable.editions);

  /// Begins observing the current projection while a view is mounted.
  void attach() {
    if (_disposed) return;
    _attachments++;
    if (_attachments != 1) return;
    _generation++;
    _requestRead();
  }

  /// Stops projection reads when the last attached view is removed.
  void detach() {
    if (_attachments == 0) return;
    _attachments--;
    if (_attachments != 0) return;
    _generation++;
    _dirty = false;
    _loading = false;
    _scope = null;
    _winners = const {};
  }

  /// The winning value, or explicit unknown when no value has been recorded.
  ProgressValue value(ProgressTarget target) =>
      _winners[target]?.value ?? const ProgressUnset();

  /// The source label for a known value, if any.
  String? sourceLabel(ProgressTarget target) {
    final event = _winners[target];
    if (event == null || event.value is ProgressUnset) return null;
    return event.source == ProgressSource.log
        ? 'From game logs'
        : 'Set by hand';
  }

  /// The action offered for the current manual winner, if any.
  String? actionLabel(ProgressTarget target) {
    final event = _winners[target];
    if (event == null || event.source != ProgressSource.manual) return null;
    return event.undoOf == null ? 'Undo' : 'Redo';
  }

  /// Whether an action for this register and mode is in flight.
  bool pending(ProgressTarget target) => _pending.contains((_mode, target));

  /// The most recent action failure for this register and mode, if any.
  String? failure(ProgressTarget target) => _failures[(_mode, target)]?.message;

  /// Whether this known value can be cleared now.
  bool canClear(ProgressTarget target) =>
      disabledReason == null &&
      !pending(target) &&
      value(target) is! ProgressUnset;

  /// Sets a whole player level between 1 and 79.
  Future<void> setLevel(String input) async {
    final text = input.trim();
    final number = RegExp(r'^\d+$').hasMatch(text) ? int.tryParse(text) : null;
    if (number == null || number < 1 || number > 79) {
      _invalid(playerLevelTarget, 'Level must be from 1 to 79.');
      return;
    }
    await _append(playerLevelTarget, ProgressInteger(number));
  }

  /// Sets the player faction to `bear` or `usec`.
  Future<void> setFaction(String faction) async {
    if (faction != 'bear' && faction != 'usec') {
      _invalid(playerFactionTarget, 'Choose BEAR or USEC.');
      return;
    }
    await _append(playerFactionTarget, ProgressText(faction));
  }

  /// Sets a player edition from the reviewed edition table.
  Future<void> setEdition(String edition) async {
    if (!editionTable.editions.contains(edition)) {
      _invalid(playerEditionTarget, 'Choose a known edition.');
      return;
    }
    await _append(playerEditionTarget, ProgressText(edition));
  }

  /// Sets a listed trader's loyalty to one of its known levels.
  Future<void> setLoyalty(String traderId, int level) async {
    final target = ProgressTarget(
      kind: ProgressEntityKind.trader,
      id: traderId,
      field: ProgressField.loyalty,
    );
    final available = progressCatalog?.traders;
    var valid = false;
    if (available != null) {
      for (final trader in available) {
        final levels = trader.levels;
        if (trader.id == traderId && levels != null && levels.length > 1) {
          valid = levels.contains(level);
          break;
        }
      }
    }
    if (!valid) {
      _invalid(target, 'Choose a known trader loyalty level.');
      return;
    }
    await _append(target, ProgressInteger(level));
  }

  /// Sets a listed station to not built or one of its catalog levels.
  Future<void> setStationLevel(String stationId, int level) async {
    final target = ProgressTarget(
      kind: ProgressEntityKind.station,
      id: stationId,
      field: ProgressField.level,
    );
    final station = progressCatalog?.stationsById[stationId];
    if (station == null ||
        (level != 0 && !station.levels.any((item) => item.level == level))) {
      _invalid(target, 'Choose a known station level.');
      return;
    }
    await _append(target, ProgressInteger(level));
  }

  /// Sets a listed task's state, or clears it when [state] is `null`.
  Future<void> setTaskState(String taskId, ProgressTaskStatus? state) async {
    final target = ProgressTarget(
      kind: ProgressEntityKind.task,
      id: taskId,
      field: ProgressField.state,
    );
    if (progressCatalog?.tasksById.containsKey(taskId) != true) {
      _invalid(target, 'Task data is not loaded for this task.');
      return;
    }
    await _append(
      target,
      state == null ? const ProgressUnset() : ProgressTaskState(state),
    );
  }

  /// Clears a known value to explicit unknown.
  Future<void> clear(ProgressTarget target) async {
    if (!canClear(target)) return;
    await _append(target, const ProgressUnset());
  }

  /// Undoes or redoes the currently shown manual winner.
  Future<void> undoOrRedo(ProgressTarget target) async {
    final event = _winners[target];
    if (event == null || event.source != ProgressSource.manual) return;
    final submittingMode = _mode;
    await _perform(
      target,
      (mode) => event.undoOf == null
          ? _access.undo(mode, event.scope.cycleId, event.eventId)
          : _access.redo(mode, event.scope.cycleId, event.eventId),
      submittingMode: submittingMode,
      refreshOnConflict: true,
    );
  }

  /// Finds up to 50 task names containing the trimmed query, ignoring case.
  List<CatalogTask> searchTasks(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final results = <CatalogTask>[];
    for (final task in progressCatalog?.tasks ?? const <CatalogTask>[]) {
      if (task.name.toLowerCase().contains(needle)) {
        results.add(task);
        if (results.length == 50) break;
      }
    }
    return List.unmodifiable(results);
  }

  /// Whether the search has more matching tasks than the display limit.
  bool searchTruncated(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return false;
    var matches = 0;
    for (final task in progressCatalog?.tasks ?? const <CatalogTask>[]) {
      if (task.name.toLowerCase().contains(needle) && ++matches > 50) {
        return true;
      }
    }
    return false;
  }

  void _invalid(ProgressTarget target, String message) {
    if (_disposed || disabledReason != null || pending(target)) return;
    _failures[(_mode, target)] = _RowFailure(message);
    notifyListeners();
  }

  Future<void> _append(ProgressTarget target, ProgressValue value) => _perform(
    target,
    (mode) => _access.appendManual(mode, target, value),
    submittingMode: _mode,
  );

  Future<void> _perform(
    ProgressTarget target,
    Future<ProgressResult<ProgressEvent>> Function(GameMode) action, {
    required GameMode submittingMode,
    bool refreshOnConflict = false,
  }) async {
    final key = (submittingMode, target);
    if (_disposed || disabledReason != null || !_pending.add(key)) return;
    _failures.remove(key);
    notifyListeners();
    final result = await action(submittingMode);
    _pending.remove(key);
    if (_disposed) return;
    switch (result) {
      case ProgressSuccess<ProgressEvent>():
        if (_mode == submittingMode) _requestRead();
      case ProgressFailure<ProgressEvent>(:final failure):
        final rowFailure = _RowFailure(_failureMessage(failure));
        if (refreshOnConflict &&
            failure is ProgressUndoConflict &&
            _mode == submittingMode) {
          // Preserve the conflict through the refresh that it triggers.
          rowFailure.preserveForRefresh = _reading;
          _requestRead();
        }
        _failures[key] = rowFailure;
    }
    notifyListeners();
  }

  void _onAccess() {
    final revision = _access.progressRevision;
    final loaded = _access.loaded;
    final loadError = _access.loadError;
    final unavailable = _access.unavailableModes.contains(_mode);
    final changed =
        revision != _revision ||
        loaded != _loaded ||
        loadError != _loadError ||
        unavailable != _unavailable;
    if (!changed) return;
    if ((!loaded && _loaded) || (unavailable && !_unavailable)) {
      _generation++;
    }
    final shouldRead =
        revision != _revision ||
        loaded != _loaded ||
        unavailable != _unavailable;
    _revision = revision;
    _loaded = loaded;
    _loadError = loadError;
    _unavailable = unavailable;
    if (shouldRead) _requestRead();
    if (!_disposed) notifyListeners();
  }

  void _onCatalog() {
    final mode = _catalog.mode;
    final snapshot = _catalog.snapshot;
    if (mode == _catalogMode && identical(snapshot, _catalogSnapshot)) return;
    _catalogMode = mode;
    _catalogSnapshot = snapshot;
    _requestRead();
    if (!_disposed) notifyListeners();
  }

  void _onMode() {
    final next = _effectiveMode();
    if (next == _mode) return;
    _mode = next;
    _unavailable = _access.unavailableModes.contains(next);
    _generation++;
    _scope = null;
    _winners = const {};
    _readError = null;
    _loading = false;
    _requestRead();
    if (!_disposed) notifyListeners();
  }

  void _requestRead() {
    if (_disposed || _attachments == 0) return;
    if (_mode == GameMode.unknown ||
        !_access.loaded ||
        _access.unavailableModes.contains(_mode)) {
      _dirty = false;
      _loading = false;
      return;
    }
    if (_reading) {
      _dirty = true;
      return;
    }
    _reading = true;
    _dirty = false;
    _loading = true;
    final readMode = _mode;
    final generation = _generation;
    final oldFailures = <(GameMode, ProgressTarget), _RowFailure>{
      for (final entry in _failures.entries)
        if (entry.key.$1 == readMode) entry.key: entry.value,
    };
    unawaited(_read(readMode, generation, oldFailures));
  }

  Future<void> _read(
    GameMode readMode,
    int generation,
    Map<(GameMode, ProgressTarget), _RowFailure> oldFailures,
  ) async {
    final result = await _access.readCurrent(readMode);
    _reading = false;
    if (_disposed) return;
    final current =
        _attachments > 0 && generation == _generation && readMode == _mode;
    if (current) {
      switch (result) {
        case ProgressSuccess<LocalProgressSnapshot>(:final value):
          _scope = value.scope;
          _winners = value.winners;
          _readError = null;
          for (final entry in oldFailures.entries) {
            if (identical(_failures[entry.key], entry.value)) {
              if (entry.value.preserveForRefresh) {
                entry.value.preserveForRefresh = false;
              } else {
                _failures.remove(entry.key);
              }
            }
          }
        case ProgressFailure<LocalProgressSnapshot>(:final failure):
          _readError =
              'Progress could not be read: ${_failureMessage(failure)}';
      }
      _loading = false;
    }
    if (_dirty) _requestRead();
    if (current) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _access.removeListener(_onAccess);
    _catalog.removeListener(_onCatalog);
    _modeChanges.removeListener(_onMode);
    super.dispose();
  }
}

class _RowFailure {
  _RowFailure(this.message);
  final String message;
  bool preserveForRefresh = false;
}
