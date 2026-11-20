import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/catalog.dart';
import '../domain/local_progress_store.dart';
import '../domain/progress_facts.dart';
import 'local_progress_access.dart';
import 'raid_timers_controller.dart';

/// Whether [ProgressAuthority] holds facts for its mode.
enum ProgressAuthorityStatus {
  /// The first read for the mode has not ended, or local progress is opening.
  loading,

  /// The facts of the mode's active wipe are published.
  local,

  /// The mode is unknown, the store failed to open, the mode's wipe history is
  /// unavailable, or the last read failed. There are no facts.
  unavailable,
}

/// Publishes the local progress facts of the applied mode.
///
/// It follows the mode source (the catalog's applied mode) and listens to
/// [LocalProgressAccess], reading [LocalProgressAccess.readCurrent] on a mode
/// change and on each revision, load or availability change. One read runs at
/// a time; a request made during a read is remembered and read afterwards. A
/// generation counter drops a read that a mode switch or an unavailability
/// outlived.
///
/// While [status] is [ProgressAuthorityStatus.loading] or
/// [ProgressAuthorityStatus.unavailable], [facts] is `null`, so advice never
/// treats unread or unreadable progress as empty. A re-read for the same mode
/// keeps the last facts and the `local` status until it ends.
class ProgressAuthority extends ChangeNotifier
    implements RaidTimerProgressSource {
  /// Starts following [modeChanges] and [access], and begins the first read.
  ///
  /// [mode] reads the applied mode; [modeChanges] notifies when it may have
  /// changed.
  ProgressAuthority({
    required this._access,
    required this._modeChanges,
    required GameMode Function() mode,
  }) : _modeOf = mode {
    _mode = _modeOf();
    _revision = _access.progressRevision;
    _loaded = _access.loaded;
    _loadError = _access.loadError;
    _blocked = _isBlocked();
    _status = _blocked
        ? ProgressAuthorityStatus.unavailable
        : ProgressAuthorityStatus.loading;
    _access.addListener(_onAccess);
    _modeChanges.addListener(_onMode);
    _requestRead();
  }

  final LocalProgressAccess _access;
  final Listenable _modeChanges;
  final GameMode Function() _modeOf;

  late GameMode _mode;
  late ProgressAuthorityStatus _status;
  late int _revision;
  late bool _loaded;
  late bool _blocked;
  String? _loadError;
  ProgressFacts? _facts;
  int _generation = 0;
  bool _reading = false;
  bool _dirty = false;
  bool _disposed = false;

  /// The applied mode the facts belong to.
  @override
  GameMode get mode => _mode;

  /// Whether the facts of [mode] are loading, published or unavailable.
  ProgressAuthorityStatus get status => _status;

  /// The facts of [mode], or `null` unless [status] is
  /// [ProgressAuthorityStatus.local].
  @override
  ProgressFacts? get facts => _facts;

  bool _isBlocked() =>
      _mode == GameMode.unknown ||
      _access.loadError != null ||
      _access.unavailableModes.contains(_mode);

  void _onMode() {
    final next = _modeOf();
    if (next == _mode || _disposed) return;
    _mode = next;
    _generation++;
    _facts = null;
    _blocked = _isBlocked();
    _status = _blocked
        ? ProgressAuthorityStatus.unavailable
        : ProgressAuthorityStatus.loading;
    // A read of the old mode may still be running; this waits behind it.
    _requestRead();
    notifyListeners();
  }

  void _onAccess() {
    if (_disposed) return;
    final revision = _access.progressRevision;
    final loaded = _access.loaded;
    final loadError = _access.loadError;
    final blocked = _isBlocked();
    if (revision == _revision &&
        loaded == _loaded &&
        loadError == _loadError &&
        blocked == _blocked) {
      return;
    }
    final wasBlocked = _blocked;
    final wasLoaded = _loaded;
    final revisionChanged = revision != _revision;
    _revision = revision;
    _loaded = loaded;
    _loadError = loadError;
    _blocked = blocked;
    if (blocked) {
      if (!wasBlocked) _generation++;
      _facts = null;
      _status = ProgressAuthorityStatus.unavailable;
      _dirty = false;
      notifyListeners();
      return;
    }
    if (wasBlocked || (wasLoaded && !loaded)) {
      // Back from unavailable, or the store closed: nothing held is current.
      _generation++;
      _facts = null;
      _status = ProgressAuthorityStatus.loading;
    }
    if (revisionChanged || wasBlocked || loaded != wasLoaded) _requestRead();
    notifyListeners();
  }

  void _requestRead() {
    if (_disposed) return;
    if (_blocked || !_loaded) {
      _dirty = false;
      return;
    }
    if (_reading) {
      _dirty = true;
      return;
    }
    _reading = true;
    _dirty = false;
    unawaited(_read(_mode, _generation));
  }

  Future<void> _read(GameMode readMode, int generation) async {
    ProgressResult<LocalProgressSnapshot> result;
    try {
      result = await _access.readCurrent(readMode);
    } catch (error) {
      debugPrint('Local progress read threw: $error');
      result = const ProgressFailure(ProgressInvalidInput('read threw'));
    }
    _reading = false;
    if (_disposed) return;
    if (generation == _generation) {
      switch (result) {
        case ProgressSuccess<LocalProgressSnapshot>(:final value):
          _facts = ProgressFacts.fromWinners(readMode, value.winners);
          _status = ProgressAuthorityStatus.local;
        case ProgressFailure<LocalProgressSnapshot>():
          _facts = null;
          _status = ProgressAuthorityStatus.unavailable;
      }
      notifyListeners();
    }
    if (_dirty) _requestRead();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _access.removeListener(_onAccess);
    _modeChanges.removeListener(_onMode);
    super.dispose();
  }
}
