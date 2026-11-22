import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/screenshot_folder_lister.dart';
import '../domain/alert_rules.dart';
import '../domain/raid_lifecycle.dart';
import '../domain/screenshot_cleanup.dart';
import 'raid_timers_controller.dart';
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

  /// Whether no screenshots matched the raid.
  final bool noScreenshots;

  /// Whether the recycle port is unavailable for this app run.
  final bool unavailable;

  /// The number of raid cleanups skipped because the queue was full.
  final int skippedRaids;
}

/// Serializes fresh raid screenshot cleanups through the recycle port.
class ScreenshotCleanupController extends ChangeNotifier {
  /// Subscribes to [lifecycle] and uses the injected boundaries for cleanup.
  ScreenshotCleanupController({
    required RaidTimerLifecycleSource lifecycle,
    required SettingsController settings,
    required this._folder,
    required this._listFolder,
    required this._recycle,
    required this._clock,
    Duration Function(int)? backstop,
    this._cancelWait = const Duration(seconds: 30),
  }) : _settings = settings,
       _backstop = backstop ?? _defaultBackstop {
    _subscription = lifecycle.transitions.listen(_onTransition);
    settings.addListener(_onSettingsChanged);
  }

  static Duration _defaultBackstop(int count) => Duration(seconds: 10 + count);
  final SettingsController _settings;
  final String Function() _folder;
  final Future<ScreenshotFolderListing> Function(String) _listFolder;
  final RecyclePort _recycle;
  final DateTime Function() _clock;
  final Duration Function(int) _backstop;
  final Duration _cancelWait;
  late final StreamSubscription<RaidTransition> _subscription;
  final Queue<Raid> _pending = Queue<Raid>();
  final Queue<LogRecordId> _cleaned = Queue<LogRecordId>();
  Raid? _active;
  Raid? _restartEnding;
  bool _disposed = false;
  bool _running = false;
  bool _unavailable = false;
  int _skipped = 0;
  ScreenshotCleanupResult? _lastResult;

  /// The latest finished cleanup, or `null` before the first cleanup.
  ScreenshotCleanupResult? get lastResult => _lastResult;

  void _onSettingsChanged() {
    if (!_settings.settings.cleanUpRaidScreenshots) {
      _pending.clear();
      _restartEnding = null;
    }
  }

  void _onTransition(RaidTransition transition) {
    if (_disposed) return;
    final held = _restartEnding;
    _restartEnding = null;
    if (held != null &&
        transition is QueueEnteredTransition &&
        _settings.settings.cleanUpRaidScreenshots &&
        isFreshLogTime(transition.time, _clock())) {
      _enqueue(held);
    }
    if (transition is! RaidEndedTransition ||
        !_settings.settings.cleanUpRaidScreenshots) {
      return;
    }
    if (transition.cause == RaidEndCause.clientRestart) {
      _restartEnding = transition.raid;
    } else if (isFreshLogTime(transition.time, _clock())) {
      _enqueue(transition.raid);
    }
  }

  void _enqueue(Raid raid) {
    final id = raid.startId;
    if (_active?.startId == id ||
        _cleaned.contains(id) ||
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
      try {
        await _cleanup(raid);
      } catch (_) {
        if (!_disposed) _publish();
      }
      _cleaned.addLast(raid.startId);
      if (_cleaned.length > 16) _cleaned.removeFirst();
      _active = null;
    }
    _running = false;
  }

  void _publish({
    int moved = 0,
    int notMoved = 0,
    int unconfirmed = 0,
    bool folderUnreadable = false,
    bool noScreenshots = false,
    bool unavailable = false,
  }) {
    if (_disposed) return;
    _lastResult = ScreenshotCleanupResult(
      moved: moved,
      notMoved: notMoved,
      unconfirmed: unconfirmed,
      folderUnreadable: folderUnreadable,
      noScreenshots: noScreenshots,
      unavailable: unavailable,
      skippedRaids: _skipped,
    );
    _skipped = 0;
    notifyListeners();
  }

  Future<void> _cleanup(Raid raid) async {
    if (_unavailable) {
      _publish(unavailable: true);
      return;
    }
    final folder = _folder();
    if (folder.isEmpty) {
      _publish(folderUnreadable: true);
      return;
    }
    final ScreenshotFolderListing listing;
    try {
      listing = await _listFolder(folder);
    } catch (_) {
      _publish(folderUnreadable: true);
      return;
    }
    if (_disposed) return;
    if (listing is! ScreenshotFolderListed) {
      _publish(folderUnreadable: true);
      return;
    }
    final names = pickRaidScreenshots(listing.entries, raid);
    if (names.isEmpty) {
      _publish(noScreenshots: true);
      return;
    }
    var moved = 0;
    var notMoved = 0;
    for (var offset = 0; offset < names.length; offset += 64) {
      if (_disposed) return;
      final end = offset + 64 < names.length ? offset + 64 : names.length;
      final batch = names.sublist(offset, end);
      final Future<RecycleReply> future;
      try {
        future = _recycle.recycle(folder, batch);
      } catch (_) {
        notMoved += batch.length;
        continue;
      }
      final RecycleReply? reply;
      try {
        reply = await future
            .then<RecycleReply?>((value) => value)
            .timeout(_backstop(batch.length), onTimeout: () => null);
      } catch (_) {
        notMoved += batch.length;
        continue;
      }
      if (_disposed) return;
      if (reply == null) {
        unawaited(_cancel());
        _publish(
          moved: moved,
          notMoved: notMoved + names.length - end,
          unconfirmed: batch.length,
        );
        try {
          await future.timeout(_cancelWait);
        } on TimeoutException {
          _unavailable = true;
          if (!_disposed) {
            final previous = _lastResult;
            _lastResult = ScreenshotCleanupResult(
              moved: moved,
              notMoved: notMoved + names.length - end,
              unconfirmed: batch.length,
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
    _publish(moved: moved, notMoved: notMoved);
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
