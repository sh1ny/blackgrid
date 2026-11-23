import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/screenshot_folder_lister.dart';
import '../domain/alert_rules.dart';
import '../domain/raid_lifecycle.dart';
import '../domain/screenshot_cleanup.dart';
import 'recycle_port.dart';
import 'settings_controller.dart';

/// The outcome of one raid's screenshot cleanup.
@immutable
class ScreenshotCleanupResult {
  /// Creates a cleanup outcome from the observed counts and conditions.
  const ScreenshotCleanupResult({
    this.moved = 0,
    this.notMoved = 0,
    this.unconfirmed = 0,
    this.folderUnreadable = false,
    this.claimFailed = false,
    this.noScreenshots = false,
    this.unavailable = false,
    this.skippedRaids = 0,
  });

  /// The number of confirmed moves.
  final int moved;

  /// The number of files confirmed not moved.
  final int notMoved;

  /// The number of files whose move could not be confirmed.
  final int unconfirmed;

  /// Whether the screenshot folder could not be read.
  final bool folderUnreadable;

  /// Whether the raid could not be durably claimed before moving files.
  final bool claimFailed;

  /// Whether no screenshots matched the raid.
  final bool noScreenshots;

  /// Whether the recycle port is unavailable for this app run.
  final bool unavailable;

  /// The number of raid cleanups skipped because the queue was full.
  final int skippedRaids;
}

/// Serializes fresh raid screenshot cleanups through the recycle port.
class ScreenshotCleanupController extends ChangeNotifier {
  /// Subscribes to cleanup-eligible lifecycle [transitions].
  ScreenshotCleanupController({
    required Stream<RaidTransition> transitions,
    required SettingsController settings,
    required this._folder,
    required this._listFolder,
    required this._claim,
    required this._recycle,
    required this._clock,
    Duration Function(int)? backstop,
    this._cancelWait = const Duration(seconds: 30),
  }) : _settings = settings,
       _backstop = backstop ?? _defaultBackstop {
    _onSettingsChanged();
    _subscription = transitions.listen(_onTransition);
    settings.addListener(_onSettingsChanged);
  }

  static Duration _defaultBackstop(int count) => Duration(seconds: 10 + count);
  final SettingsController _settings;
  final Future<String> Function() _folder;
  final Future<bool> Function(LogRecordId) _claim;
  final Future<ScreenshotFolderListing> Function(String) _listFolder;
  final RecyclePort _recycle;
  final DateTime Function() _clock;
  final Duration Function(int) _backstop;
  final Duration _cancelWait;
  late final StreamSubscription<RaidTransition> _subscription;
  final Queue<Raid> _pending = Queue<Raid>();
  Raid? _active;
  Raid? _restartEnding;
  DateTime? _enabledSince;
  int _enableEpoch = 0;
  bool _disposed = false;
  bool _running = false;
  bool _unavailable = false;
  int _skipped = 0;
  ScreenshotCleanupResult? _lastResult;

  /// The latest finished cleanup, or `null` before the first cleanup.
  ScreenshotCleanupResult? get lastResult => _lastResult;

  void _onSettingsChanged() {
    if (!_settings.settings.cleanUpRaidScreenshots) {
      if (_enabledSince != null) _enableEpoch++;
      _enabledSince = null;
      _pending.clear();
      _restartEnding = null;
    } else {
      _enabledSince ??= _clock();
    }
  }

  void _onTransition(RaidTransition transition) {
    if (_disposed) return;
    final now = _clock();
    final enabledSince = _enabledSince;
    final held = _restartEnding;
    _restartEnding = null;
    if (held != null &&
        transition is QueueEnteredTransition &&
        enabledSince != null &&
        _fresh(transition.time, now)) {
      _enqueue(held);
    }
    if (transition is! RaidEndedTransition ||
        enabledSince == null ||
        transition.time.isBefore(enabledSince) ||
        transition.time.isAfter(now)) {
      return;
    }
    if (transition.cause == RaidEndCause.clientRestart) {
      _restartEnding = transition.raid;
    } else if (_fresh(transition.time, now)) {
      _enqueue(transition.raid);
    }
  }

  bool _fresh(DateTime time, DateTime now) =>
      !time.isAfter(now) && isFreshLogTime(time, now);

  void _enqueue(Raid raid) {
    if (_unavailable) return;
    final id = raid.startId;
    if (_active?.startId == id ||
        _pending.any((queued) => queued.startId == id)) {
      return;
    }
    if (_running && _pending.length >= 4) {
      _skipped++;
      return;
    }
    _pending.addLast(raid);
    if (!_running) unawaited(_runQueue());
  }

  Future<void> _runQueue() async {
    _running = true;
    while (!_disposed && _pending.isNotEmpty) {
      final raid = _pending.removeFirst();
      _active = raid;
      await _cleanup(raid);
      _active = null;
    }
    _running = false;
  }

  void _publish({
    int moved = 0,
    int notMoved = 0,
    int unconfirmed = 0,
    bool folderUnreadable = false,
    bool claimFailed = false,
    bool noScreenshots = false,
    bool unavailable = false,
  }) {
    if (_disposed) return;
    _lastResult = ScreenshotCleanupResult(
      moved: moved,
      notMoved: notMoved,
      unconfirmed: unconfirmed,
      folderUnreadable: folderUnreadable,
      claimFailed: claimFailed,
      noScreenshots: noScreenshots,
      unavailable: unavailable,
      skippedRaids: _skipped,
    );
    _skipped = 0;
    notifyListeners();
  }

  Future<void> _cleanup(Raid raid) async {
    final epoch = _enableEpoch;
    bool canDispatch() =>
        !_disposed && _enabledSince != null && epoch == _enableEpoch;

    final String folder;
    try {
      folder = await _folder();
    } catch (_) {
      if (canDispatch()) _publish(folderUnreadable: true);
      return;
    }
    if (!canDispatch()) return;
    if (folder.isEmpty) {
      _publish(folderUnreadable: true);
      return;
    }
    final ScreenshotFolderListing listing;
    try {
      listing = await _listFolder(folder);
    } catch (_) {
      if (canDispatch()) _publish(folderUnreadable: true);
      return;
    }
    if (!canDispatch()) return;
    if (listing is! ScreenshotFolderListed) {
      _publish(folderUnreadable: true);
      return;
    }
    final names = pickRaidScreenshots(listing.entries, raid);
    if (names.isEmpty) {
      _publish(noScreenshots: true);
      return;
    }
    try {
      if (!await _claim(raid.startId)) return;
    } catch (_) {
      if (canDispatch()) _publish(claimFailed: true);
      return;
    }
    if (!canDispatch()) return;

    var moved = 0;
    var notMoved = 0;
    var unconfirmed = 0;
    for (var offset = 0; offset < names.length; offset += 64) {
      if (_disposed) return;
      final end = offset + 64 < names.length ? offset + 64 : names.length;
      final batch = names.sublist(offset, end);
      final Future<RecycleReply> future;
      try {
        future = _recycle.recycle(folder, batch);
      } catch (_) {
        unconfirmed += batch.length;
        continue;
      }
      final RecycleReply? reply;
      try {
        reply = await future
            .then<RecycleReply?>((value) => value)
            .timeout(_backstop(batch.length), onTimeout: () => null);
      } catch (_) {
        unconfirmed += batch.length;
        continue;
      }
      if (_disposed) return;
      if (reply == null) {
        unawaited(_cancel());
        _publish(
          moved: moved,
          notMoved: notMoved + names.length - end,
          unconfirmed: unconfirmed + batch.length,
        );
        try {
          await future.timeout(_cancelWait);
        } on TimeoutException {
          _unavailable = true;
          _pending.clear();
          if (!_disposed) {
            final previous = _lastResult;
            _lastResult = ScreenshotCleanupResult(
              moved: moved,
              notMoved: notMoved + names.length - end,
              unconfirmed: unconfirmed + batch.length,
              unavailable: true,
              skippedRaids: previous?.skippedRaids ?? 0,
            );
            notifyListeners();
          }
        } catch (_) {
          // A failed late reply still means the port has drained.
        }
        return;
      }
      if (reply is RecycleCallFailure) {
        notMoved += batch.length;
      } else if (reply is RecycleUnknownOutcome) {
        unconfirmed += batch.length;
      } else if (reply is RecycleStatuses) {
        for (final name in batch) {
          final status = reply.statuses[name];
          if (status is RecycleMoved) {
            moved++;
          } else if (status is! RecycleMissing) {
            notMoved++;
          }
        }
      }
    }
    _publish(moved: moved, notMoved: notMoved, unconfirmed: unconfirmed);
  }

  Future<void> _cancel() async {
    try {
      await _recycle.cancel();
    } catch (_) {
      // Cancellation is best effort; the outstanding reply remains the drain.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pending.clear();
    _restartEnding = null;
    _settings.removeListener(_onSettingsChanged);
    unawaited(_subscription.cancel());
    unawaited(_cancel());
    super.dispose();
  }
}
