import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../data/game_log/session_folder_read.dart';
import '../data/game_log/session_folders.dart';
import '../domain/catalog.dart';
import '../domain/local_progress.dart';
import '../domain/local_progress_store.dart';
import '../domain/progress_id.dart';
import '../domain/progress_wipe_store.dart';
import '../domain/raid_lifecycle.dart';
import '../domain/task_log_events.dart';
import 'local_progress_access.dart';
import 'raid_timers_controller.dart';

/// The operation that produced a log-reading result.
enum TaskLogRunKind { catchUp, replay, newWipe }

/// The outcome and diagnostics of one log-reading operation.
final class TaskLogRunResult {
  /// Creates a completed operation result.
  const TaskLogRunResult({
    required this.kind,
    required this.modes,
    required this.finishedAt,
    this.foldersRead = 0,
    this.eventsRecorded = 0,
    this.skippedNoMode = 0,
    this.rejectedRecords = 0,
    this.identityOverBudget = 0,
    this.conflictingRecords = 0,
    this.unreadableFolders = 0,
    this.stoppedByRaid = false,
    this.failure,
    this.lastStoredFolder,
    this.retryFrom,
  });

  /// The operation performed.
  final TaskLogRunKind kind;

  /// The affected modes.
  final Set<GameMode> modes;

  /// The time the operation finished.
  final DateTime finishedAt;

  /// The number of readable folders processed.
  final int foldersRead;

  /// The number of newly stored events.
  final int eventsRecorded;

  /// The number of messages without a recognised mode.
  final int skippedNoMode;

  /// The number of malformed log records.
  final int rejectedRecords;

  /// The number of messages whose identity could not be encoded.
  final int identityOverBudget;

  /// The number of records rejected by the progress store.
  final int conflictingRecords;

  /// The number of folders that could not be read.
  final int unreadableFolders;

  /// Whether a raid stopped the operation between folders.
  final bool stoppedByRaid;

  /// The failure that stopped the operation, if any.
  final String? failure;

  /// The last folder stored in this operation, even if its watermark was newer.
  final String? lastStoredFolder;

  /// The selected replay date to use again after a failure or raid stop.
  final DateTime? retryFrom;
}

/// Observable local task progress and log-reading controls.
abstract interface class TaskLogProgressSource implements Listenable {
  /// The active wipe for each mode.
  Map<GameMode, ProgressWipe> get wipes;

  /// Modes whose active cycles could not be opened.
  Set<GameMode> get unavailableModes;

  /// Whether a log-reading operation is active.
  bool get running;

  /// The current reason a new operation cannot start, if any.
  String? get disabledReason;

  /// The most recently completed operation.
  TaskLogRunResult? get lastResult;

  /// The current save error and counted live-record skips, if any.
  String? get error;

  /// The folder currently being read, if any.
  String? get currentReadFolder;

  /// The oldest known session folder date, if any.
  DateTime? get oldestFolderDate;

  /// Replays a mode's logs from [startDate].
  Future<void> replay(GameMode mode, DateTime startDate);

  /// Starts a fresh cycle and replays its logs from [startDate].
  Future<void> startNewWipe(GameMode mode, DateTime startDate);
}

Future<FolderTaskRead> _readInIsolate(String path) =>
    Isolate.run(() => readSessionFolderTasks(path));

DateTime _date(DateTime value) => DateTime(value.year, value.month, value.day);

class _OperationFailure implements Exception {
  _OperationFailure(this.message, [this.failure]);
  final String message;
  final ProgressStoreFailure? failure;
  @override
  String toString() => message;
}

String _failureMessage(ProgressStoreFailure failure) => switch (failure) {
  ProgressInvalidInput(:final reason) => reason,
  ProgressIdentityConflict(:final reason) => reason,
  ProgressStorageFailure(:final reason) => reason,
  ProgressUnavailable(:final reason) => reason,
  ProgressUndoConflict(:final reason) => reason,
  ProgressBusy() => 'The local progress store is busy.',
  ProgressStaleCursor() => 'The local progress cursor is stale.',
};

T _value<T>(ProgressResult<T> result) => switch (result) {
  ProgressSuccess<T>(:final value) => value,
  ProgressFailure<T>(:final failure) => throw _OperationFailure(
    _failureMessage(failure),
    failure,
  ),
};

class _Run {
  _Run(this.kind, this.modes);
  final TaskLogRunKind kind;
  final Set<GameMode> modes;
  int foldersRead = 0;
  int eventsRecorded = 0;
  int skippedNoMode = 0;
  int rejectedRecords = 0;
  int identityOverBudget = 0;
  int conflictingRecords = 0;
  int unreadableFolders = 0;
  bool stoppedByRaid = false;
  String? failure;
  String? lastStoredFolder;
  DateTime? replayStart;

  TaskLogRunResult finish(DateTime time) => TaskLogRunResult(
    kind: kind,
    modes: Set.unmodifiable(modes),
    finishedAt: time,
    foldersRead: foldersRead,
    eventsRecorded: eventsRecorded,
    skippedNoMode: skippedNoMode,
    rejectedRecords: rejectedRecords,
    identityOverBudget: identityOverBudget,
    conflictingRecords: conflictingRecords,
    unreadableFolders: unreadableFolders,
    stoppedByRaid: stoppedByRaid,
    failure: failure,
    lastStoredFolder: lastStoredFolder,
    retryFrom:
        kind == TaskLogRunKind.replay && (failure != null || stoppedByRaid)
        ? replayStart
        : null,
  );
}

/// Owns active wipes and serializes all local progress operations.
class TaskLogProgressController extends ChangeNotifier
    implements TaskLogProgressSource, LocalProgressAccess {
  /// Subscribes immediately and loads the active wipes and their cycles.
  TaskLogProgressController({
    required this._store,
    required this._wipeStore,
    required this._lifecycle,
    required this._logRoot,
    Future<List<SessionFolder>> Function(String)? folderLister,
    Future<FolderTaskRead> Function(String)? folderReader,
    DateTime Function()? clock,
    String Function()? newId,
  }) : _folderLister = folderLister ?? listSessionFolders,
       _folderReader = folderReader ?? _readInIsolate,
       _clock = clock ?? DateTime.now,
       _newId = newId ?? newProgressId {
    _subscription = _lifecycle.transitions.listen(_onTransition);
    _lifecycle.addListener(_onLifecycle);
    ready = enqueueProgress(_load);
    _onLifecycle();
  }

  final LocalProgressStore _store;
  final ProgressWipeStore _wipeStore;
  final RaidTimerLifecycleSource _lifecycle;
  final String Function() _logRoot;
  final Future<List<SessionFolder>> Function(String) _folderLister;
  final Future<FolderTaskRead> Function(String) _folderReader;
  final DateTime Function() _clock;
  final String Function() _newId;
  late final StreamSubscription<RaidTransition> _subscription;
  Future<void> _queue = Future.value();
  Future<void>? _runFuture;
  Future<void>? _closing;
  bool _closed = false;
  bool _disposed = false;
  bool _catchUpPending = true;
  String? _deviceId;
  bool _wipesLoaded = false;
  bool _loaded = false;
  String? _loadError;
  int _progressRevision = 0;
  int _liveNoMode = 0;
  int _liveIdentityOverBudget = 0;
  int _liveConflicting = 0;
  final _wipes = <GameMode, ProgressWipe>{};
  final _unavailable = <GameMode>{};
  bool _running = false;
  String? _error;
  final _catchUpModes = <GameMode>{};
  String? _refusal;
  String? _currentReadFolder;
  DateTime? _oldestFolderDate;
  TaskLogRunResult? _lastResult;

  /// Completes after the initial wipe and device state has been loaded.
  late final Future<void> ready;

  /// Completes when all currently admitted runs and queued operations drain.
  Future<void> get settled async {
    await ready;
    while (true) {
      final run = _runFuture;
      if (run != null) await run;
      final queue = _queue;
      await queue;
      if (identical(run, _runFuture) && identical(queue, _queue)) return;
    }
  }

  /// Serializes a progress operation with the controller's reads and writes.
  Future<T> enqueueProgress<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  bool get loaded => _loaded;
  @override
  String? get loadError => _loadError;
  @override
  int get progressRevision => _progressRevision;

  @override
  Map<GameMode, ProgressWipe> get wipes => Map.unmodifiable(_wipes);
  @override
  Set<GameMode> get unavailableModes => Set.unmodifiable(_unavailable);
  @override
  bool get running => _running;
  @override
  String? get disabledReason => _guardReason ?? _refusal;
  @override
  TaskLogRunResult? get lastResult => _lastResult;
  @override
  String? get error {
    final skipped = _liveNoMode + _liveIdentityOverBudget + _liveConflicting;
    if (skipped == 0) return _error;
    final notice =
        'Live records skipped: $_liveNoMode no mode · '
        '$_liveIdentityOverBudget record IDs too long · '
        '$_liveConflicting conflicting records.';
    return _error == null ? notice : '$_error\n$notice';
  }

  @override
  String? get currentReadFolder => _currentReadFolder;
  @override
  DateTime? get oldestFolderDate => _oldestFolderDate;

  String? get _guardReason {
    if (_running) return 'Another log read is running.';
    if (_logRoot().isEmpty) return 'No game log directory is configured.';
    if (_lifecycle.state.currentFolder == null) {
      return 'The live log folder is not known yet.';
    }
    if (_inRaid) return 'Log reading is not available during a raid.';
    return null;
  }

  bool get _inRaid => switch (_lifecycle.state.phase) {
    RaidPhase.inQueue ||
    RaidPhase.matchFound ||
    RaidPhase.raidStarting ||
    RaidPhase.inRaid => true,
    RaidPhase.unknown || RaidPhase.inMenus || RaidPhase.raidEnded => false,
  };

  void _notify() {
    if (!_closed && !_disposed) notifyListeners();
  }

  void _progressChanged() {
    _progressRevision++;
    _notify();
  }

  void _markUnavailable(ProgressStoreFailure failure) {
    if (failure is ProgressUnavailable &&
        _wipes[failure.scope.mode]?.scope == failure.scope &&
        _unavailable.add(failure.scope.mode)) {
      _progressChanged();
    }
  }

  Future<ProgressResult<T>> _access<T>(Future<T> Function() operation) {
    if (_closed) {
      return Future.value(
        ProgressFailure<T>(
          const ProgressStorageFailure('Local progress is closed.'),
        ),
      );
    }
    return enqueueProgress(() async {
      try {
        return ProgressSuccess<T>(await operation());
      } on _OperationFailure catch (error) {
        final failure = error.failure ?? ProgressStorageFailure(error.message);
        _markUnavailable(failure);
        return ProgressFailure<T>(failure);
      } catch (error) {
        return ProgressFailure<T>(ProgressStorageFailure(error.toString()));
      }
    });
  }

  void _checkAccess(GameMode mode) {
    if (mode == GameMode.unknown) {
      throw _OperationFailure(
        'A game mode is required.',
        const ProgressInvalidInput('A game mode is required.'),
      );
    }
    if (!_loaded) {
      throw _OperationFailure(
        _loadError ?? 'Local progress is not loaded.',
        ProgressStorageFailure(_loadError ?? 'Local progress is not loaded.'),
      );
    }
    if (_unavailable.contains(mode)) {
      final scope = _wipes[mode]!.scope;
      throw _OperationFailure(
        'The active wipe for ${mode.name} is unavailable.',
        ProgressUnavailable(
          scope: scope,
          reason: 'The active wipe is unavailable.',
        ),
      );
    }
  }

  ProgressWipe _matchingWipe(GameMode mode, String cycleId) {
    _checkAccess(mode);
    final wipe = _wipes[mode];
    if (wipe == null || wipe.cycleId != cycleId) {
      throw _OperationFailure(
        'The active wipe has changed.',
        const ProgressUndoConflict('The active wipe has changed.'),
      );
    }
    return wipe;
  }

  Never _undoConflict() => throw _OperationFailure(
    'The value has changed.',
    const ProgressUndoConflict('The value has changed.'),
  );

  Future<Map<ProgressTarget, ProgressEvent>> _readWinners(
    ProgressScope scope,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final winners = <ProgressTarget, ProgressEvent>{};
      ProgressCurrentCursor? cursor;
      while (true) {
        final result = await _store.readProgressCurrent(scope, cursor: cursor);
        if (result is ProgressFailure<ProgressCurrentPage> &&
            result.failure is ProgressStaleCursor &&
            attempt == 0) {
          break;
        }
        final page = _value(result);
        for (final event in page.events) {
          winners[event.target] = event;
        }
        cursor = page.nextCursor;
        if (cursor == null) return winners;
      }
    }
    throw StateError('Current progress traversal did not finish.');
  }

  Future<ProgressEvent> _appendManualEvent(
    ProgressWipe wipe,
    ProgressTarget target,
    ProgressValue value, {
    int? afterOccurredAtMs,
  }) async {
    final occurredAtMs = _clock().toUtc().millisecondsSinceEpoch;
    final event = ProgressEvent(
      eventId: _newId(),
      deviceId: _deviceId!,
      occurredAtMs:
          afterOccurredAtMs != null && occurredAtMs <= afterOccurredAtMs
          ? afterOccurredAtMs + 1
          : occurredAtMs,
      scope: wipe.scope,
      source: ProgressSource.manual,
      target: target,
      value: value,
    );
    final result = _value(
      await _store.appendProgressEvents(wipe.scope, [event]),
    );
    if (result.insertedCount > 0) _progressChanged();
    return event;
  }

  @override
  Future<ProgressResult<ProgressEvent>> appendManual(
    GameMode mode,
    ProgressTarget target,
    ProgressValue value,
  ) => _access(() async {
    _checkAccess(mode);
    final today = _date(_clock());
    final folder = _lifecycle.state.currentFolder;
    final folderTime = folder == null ? null : parseSessionFolderTime(folder);
    final folderDate = folderTime == null ? null : _date(folderTime);
    final start = folderDate != null && folderDate.isBefore(today)
        ? folderDate
        : today;
    final wipe = await _ensureWipe(mode, start);
    return _appendManualEvent(wipe, target, value);
  });

  @override
  Future<ProgressResult<ProgressEvent>> undo(
    GameMode mode,
    String cycleId,
    String targetEventId,
  ) => _access(() async {
    final wipe = _matchingWipe(mode, cycleId);
    final target = _value(
      await _store.readProgressEvent(wipe.scope, targetEventId),
    );
    if (target == null ||
        target.source != ProgressSource.manual ||
        target.undoOf != null) {
      _undoConflict();
    }
    final event = _value(
      await _store.undoProgress(
        wipe.scope,
        targetEventId: targetEventId,
        requestEventId: _newId(),
      ),
    );
    _progressChanged();
    return event;
  });

  @override
  Future<ProgressResult<ProgressEvent>> redo(
    GameMode mode,
    String cycleId,
    String undoEventId,
  ) => _access(() async {
    final wipe = _matchingWipe(mode, cycleId);
    final undo = _value(
      await _store.readProgressEvent(wipe.scope, undoEventId),
    );
    if (undo == null ||
        undo.source != ProgressSource.manual ||
        undo.undoOf == null) {
      _undoConflict();
    }
    final winners = await _readWinners(wipe.scope);
    if (winners[undo.target]?.eventId != undo.eventId) _undoConflict();
    final target = _value(
      await _store.readProgressEvent(wipe.scope, undo.undoOf!),
    );
    if (target == null ||
        target.source != ProgressSource.manual ||
        target.undoOf != null ||
        target.target != undo.target) {
      _undoConflict();
    }
    return _appendManualEvent(
      wipe,
      target.target,
      target.value,
      afterOccurredAtMs: undo.occurredAtMs,
    );
  });

  @override
  Future<ProgressResult<LocalProgressSnapshot>> readCurrent(GameMode mode) =>
      _access(() async {
        _checkAccess(mode);
        final wipe = _wipes[mode];
        if (wipe == null) {
          return LocalProgressSnapshot(scope: null, winners: const {});
        }
        return LocalProgressSnapshot(
          scope: wipe.scope,
          winners: await _readWinners(wipe.scope),
        );
      });

  Future<void> _load() async {
    try {
      final rows = await _wipeStore.readProgressWipes();
      for (final wipe in rows) {
        _wipes[wipe.mode] = wipe;
        _catchUpModes.add(wipe.mode);
        // Availability is established by opening each active cycle below.
      }
      _wipesLoaded = true;
      for (final wipe in rows) {
        final result = await _store.openProgressCycle(wipe.scope);
        if (result is ProgressFailure<ProgressCycle>) {
          if (_unavailable.add(wipe.mode)) _progressChanged();
          _error =
              'Some task progress could not be opened: ${_failureMessage(result.failure)}';
        }
      }
      _deviceId = _value(await _store.progressDeviceId());
      _loaded = true;
    } catch (error) {
      _loadError = 'Some task progress could not be loaded: $error';
      _error = _loadError;
    }
    _notify();
  }

  void _onLifecycle() {
    if (_closed) return;
    _refusal = null;
    _notify();
    if (_catchUpPending && _guardReason == null) {
      _catchUpPending = false;
      _beginRun(TaskLogRunKind.catchUp, null, null);
    }
  }

  void _onTransition(RaidTransition transition) {
    if (_closed || transition is! TaskTransition) return;
    final mode = transition.mode;
    if (mode == null || mode == GameMode.unknown) {
      _liveNoMode++;
      _notify();
      return;
    }
    unawaited(
      enqueueProgress(() async {
        final run = _Run(TaskLogRunKind.catchUp, {mode});
        try {
          final folderDate = _date(
            parseSessionFolderTime(transition.id.folder) ?? transition.time,
          );
          final wipe = _wipes[mode];
          if (wipe != null && folderDate.isBefore(_date(wipe.startDate))) {
            return;
          }
          await _recordChunk(mode, [transition], folderDate, run);
          if (run.identityOverBudget != 0) {
            _error = 'Some task progress could not be saved because a record identity is invalid.';
            _notify();
          }
        } catch (error) {
          _error = 'Some task progress could not be saved: $error';
          _notify();
        } finally {
          _liveIdentityOverBudget += run.identityOverBudget;
          _liveConflicting += run.conflictingRecords;
          _notify();
        }
      }),
    );
  }

  Future<ProgressWipe> _createWipe(GameMode mode, DateTime start) async {
    if (!_wipesLoaded || _deviceId == null) {
      throw _OperationFailure(
        'Local progress could not be loaded; restart Blackgrid before recording.',
      );
    }
    final cycle = _value(await _store.createProgressCycle(mode));
    final wipe = ProgressWipe(
      mode: mode,
      cycleId: cycle.scope.cycleId,
      startDate: _date(start),
      lastFolder: null,
      updatedAtMs: _clock().millisecondsSinceEpoch,
    );
    await _wipeStore.replaceProgressWipe(wipe);
    _wipes[mode] = wipe;
    _unavailable.remove(mode);
    _progressChanged();
    return wipe;
  }

  Future<ProgressWipe> _ensureWipe(GameMode mode, DateTime start) async {
    if (_unavailable.contains(mode)) {
      throw _OperationFailure(
        'The active wipe for ${mode.name} is unavailable.',
      );
    }
    return _wipes[mode] ?? await _createWipe(mode, start);
  }

  Future<void> _recordChunk(
    GameMode mode,
    List<TaskTransition> tasks,
    DateTime start,
    _Run run,
  ) async {
    final wipe = await _ensureWipe(mode, start);
    final device = _deviceId;
    if (device == null) {
      throw _OperationFailure('The local device identity is unavailable.');
    }
    final events = <ProgressEvent>[];
    for (final task in tasks) {
      final event = taskLogEvent(
        transition: task,
        cycleId: wipe.cycleId,
        deviceId: device,
      );
      if (event == null) {
        run.identityOverBudget++;
      } else {
        events.add(event);
      }
    }
    if (events.isEmpty) return;
    final result = await _store.appendProgressEvents(wipe.scope, events);
    if (result is ProgressSuccess<ProgressAppendResult>) {
      run.eventsRecorded += result.value.insertedCount;
      if (result.value.insertedCount > 0) _progressChanged();
      _error = null;
      _notify();
      return;
    }
    final failure = (result as ProgressFailure<ProgressAppendResult>).failure;
    _markUnavailable(failure);
    if (failure is! ProgressIdentityConflict &&
        failure is! ProgressInvalidInput) {
      throw _OperationFailure(_failureMessage(failure));
    }
    if (events.length == 1) {
      run.conflictingRecords++;
      _error =
          'Some task progress could not be saved: ${_failureMessage(failure)}';
      _notify();
      return;
    }
    var rejected = false;
    for (final event in events) {
      final single = await _store.appendProgressEvents(wipe.scope, [event]);
      if (single is ProgressSuccess<ProgressAppendResult>) {
        run.eventsRecorded += single.value.insertedCount;
        if (single.value.insertedCount > 0) _progressChanged();
      } else {
        final reason =
            (single as ProgressFailure<ProgressAppendResult>).failure;
        _markUnavailable(reason);
        if (reason is! ProgressIdentityConflict &&
            reason is! ProgressInvalidInput) {
          throw _OperationFailure(_failureMessage(reason));
        }
        run.conflictingRecords++;
        rejected = true;
      }
    }
    _error = rejected
        ? 'Some task progress could not be saved because a record was rejected.'
        : null;
    _notify();
  }

  @override
  Future<void> replay(GameMode mode, DateTime startDate) =>
      _beginRun(TaskLogRunKind.replay, mode, startDate);

  @override
  Future<void> startNewWipe(GameMode mode, DateTime startDate) =>
      _beginRun(TaskLogRunKind.newWipe, mode, startDate);

  Future<void> _beginRun(TaskLogRunKind kind, GameMode? mode, DateTime? start) {
    final reason = _guardReason;
    if (_closed ||
        reason != null ||
        mode == GameMode.unknown ||
        (kind == TaskLogRunKind.replay && _unavailable.contains(mode))) {
      _refusal = reason ?? 'The active wipe is unavailable.';
      if (!_closed &&
          reason == null &&
          kind == TaskLogRunKind.replay &&
          mode != null &&
          _unavailable.contains(mode)) {
        _lastResult = TaskLogRunResult(
          kind: kind,
          modes: {mode},
          finishedAt: _clock(),
          failure: _refusal,
          retryFrom: start == null ? null : _date(start),
        );
        _error = _refusal;
        _refusal = null;
      }
      _notify();
      return Future.value();
    }
    _refusal = null;
    _running = true;
    final root = _logRoot();
    final liveFolder = _lifecycle.state.currentFolder!;
    final run = _Run(kind, mode == null ? <GameMode>{} : {mode});
    if (kind == TaskLogRunKind.replay && start != null) {
      run.replayStart = _date(start);
    }
    // Enqueue the switch immediately: already published live events precede it,
    // and later live events observe the newly selected cycle.
    Future<void>? prepare;
    if (mode != null) {
      prepare = enqueueProgress(() async {
        if (kind == TaskLogRunKind.newWipe) {
          await _createWipe(mode, start!);
        } else {
          await _ensureWipe(mode, start!);
        }
      });
    }
    _notify();
    final future = _performRun(run, root, liveFolder, mode, start, prepare);
    _runFuture = future;
    return future;
  }

  bool _inRange(ProgressWipe wipe, SessionFolder folder) =>
      !_date(folder.time).isBefore(_date(wipe.startDate)) &&
      (wipe.lastFolder == null ||
          compareSessionFolderNames(wipe.lastFolder!, folder.name) < 0);

  Future<void> _performRun(
    _Run run,
    String root,
    String liveFolder,
    GameMode? target,
    DateTime? start,
    Future<void>? prepare,
  ) async {
    try {
      if (prepare != null) {
        await prepare;
      } else {
        await ready;
      }
      if (!_wipesLoaded || _deviceId == null) {
        throw _OperationFailure(
          'Local progress could not be loaded; restart Blackgrid before reading logs.',
        );
      }
      if (run.kind == TaskLogRunKind.catchUp) {
        run.modes.addAll(_catchUpModes);
        if (_unavailable.isNotEmpty) {
          run.failure = 'Some active wipes are unavailable.';
        }
      }
      final folders = List<SessionFolder>.of(await _folderLister(root));
      folders.sort((a, b) => compareSessionFolderNames(a.name, b.name));
      if (folders.isNotEmpty) _oldestFolderDate = _date(folders.first.time);
      _notify();
      for (final folder in folders) {
        if (run.kind == TaskLogRunKind.catchUp) {
          if (compareSessionFolderNames(folder.name, liveFolder) >= 0 ||
              !_wipes.values.any(
                (wipe) =>
                    run.modes.contains(wipe.mode) &&
                    !_unavailable.contains(wipe.mode) &&
                    _inRange(wipe, folder),
              )) {
            continue;
          }
        } else if (_date(folder.time).isBefore(_date(start!))) {
          continue;
        }
        if (_inRaid || _closed) {
          run.stoppedByRaid = _inRaid;
          break;
        }
        _currentReadFolder = folder.name;
        _notify();
        FolderTaskRead read;
        try {
          read = await _folderReader(folder.path);
        } catch (_) {
          run.unreadableFolders++;
          continue;
        }
        if (read.unreadable) {
          run.unreadableFolders++;
          continue;
        }
        run.foldersRead++;
        run.skippedNoMode += read.skippedNoMode;
        run.rejectedRecords += read.rejected;
        final eligible = <GameMode>{};
        if (target != null) {
          eligible.add(target);
        } else {
          for (final wipe in _wipes.values) {
            if (!_unavailable.contains(wipe.mode) && _inRange(wipe, folder)) {
              eligible.add(wipe.mode);
            }
          }
        }
        final tasks = <TaskTransition>[];
        for (final task in read.tasks) {
          final mode = task.mode;
          if (mode == null || mode == GameMode.unknown) {
            run.skippedNoMode++;
            continue;
          }
          if (target != null && mode != target) continue;
          if (target == null && _unavailable.contains(mode)) continue;
          if (target == null &&
              _wipes.containsKey(mode) &&
              !eligible.contains(mode)) {
            continue;
          }
          eligible.add(mode);
          tasks.add(task);
        }
        for (var index = 0; index < tasks.length;) {
          final mode = tasks[index].mode!;
          var end = index + 1;
          while (end < tasks.length &&
              tasks[end].mode == mode &&
              end - index < progressPageLimit) {
            end++;
          }
          final chunk = tasks.sublist(index, end);
          await enqueueProgress(
            () => _recordChunk(mode, chunk, _date(folder.time), run),
          );
          run.modes.add(mode);
          index = end;
        }
        await enqueueProgress(() async {
          final now = _clock().millisecondsSinceEpoch;
          for (final mode in eligible) {
            final wipe = _wipes[mode];
            if (wipe == null || _unavailable.contains(mode)) continue;
            var newStart = wipe.startDate;
            var last = wipe.lastFolder;
            if (target == mode && _date(start!).isBefore(_date(newStart))) {
              await _wipeStore.moveProgressWipeStartEarlier(
                mode,
                _date(start),
                now,
              );
              newStart = _date(start);
            }
            if (compareSessionFolderNames(folder.name, liveFolder) < 0 &&
                (last == null ||
                    compareSessionFolderNames(last, folder.name) < 0)) {
              await _wipeStore.advanceProgressWipeFolder(
                mode,
                folder.name,
                now,
              );
              last = folder.name;
            }
            _wipes[mode] = ProgressWipe(
              mode: mode,
              cycleId: wipe.cycleId,
              startDate: newStart,
              lastFolder: last,
              updatedAtMs: now,
            );
          }
        });
        run.lastStoredFolder = folder.name;
        _notify();
        if (_inRaid) {
          run.stoppedByRaid = true;
          break;
        }
      }
    } catch (error) {
      run.failure = error.toString();
      _error = 'Some task progress could not be saved: $error';
    } finally {
      _currentReadFolder = null;
      _lastResult = run.finish(_clock());
      _running = false;
      _refusal = null;
      _notify();
      if (!_closed && _catchUpPending) _onLifecycle();
    }
  }

  /// Stops subscriptions and drains admitted work before storage is closed.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _lifecycle.removeListener(_onLifecycle);
    await _subscription.cancel();
    await settled;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
