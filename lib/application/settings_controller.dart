import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../domain/catalog.dart';
import '../domain/settings.dart';
import 'raid_timers_controller.dart';

class SettingsController extends ChangeNotifier
    implements RaidTimerSettingsSource {
  SettingsController(this.database);
  final BlackgridDatabase database;
  AppSettings _settings = AppSettings();
  List<CustomPin> _pins = const [];
  AppSettings get settings => _settings;
  List<CustomPin> get pins => _pins;

  @override
  RaidTimerSettings get raidTimers => _settings.raidTimers;

  String? error;
  bool busy = false;
  bool _settingsUnreadable = false;
  bool _loaded = false;
  bool _flushAfterBusy = false;
  final Map<GameMode, DateTime> _pendingStarts = {};
  int _pinsSkipped = 0;

  /// What the last load could not read, or `null` when everything was readable.
  ///
  /// Joins a sentence about the settings record, recomputed by every [load]
  /// and cleared by a successful [save], with a sentence counting the saved
  /// pins that were skipped, recomputed after every pin read. It is separate
  /// from [error], which only reports failed saves.
  String? get loadNotice {
    final parts = [
      if (_settingsUnreadable)
        'Your saved settings could not be read. '
            'Default settings are in use until you change one.',
      if (_pinsSkipped == 1)
        '1 saved pin could not be read and is not shown.'
      else if (_pinsSkipped > 1)
        '$_pinsSkipped saved pins could not be read and are not shown.',
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  Future<void> load() async {
    final stored = await database.readSettings();
    final saved = stored.settings;
    _settings = saved.saveMarkerFilters
        ? saved
        : saved.copyWith(markerFilters: const {});
    _settingsUnreadable = stored.unreadable;
    _loaded = true;
    await _readPins();
    notifyListeners();
  }

  Future<void> _readPins() async {
    final read = await database.readPins();
    _pins = List.unmodifiable(read.pins);
    _pinsSkipped = read.skipped;
  }

  /// The cooldown starts the timers use: the stored starts max-merged with
  /// the starts still waiting for a successful save.
  @override
  Map<GameMode, DateTime> get effectiveScavCooldownStarts => Map.unmodifiable(
    _maxMerge(_settings.raidTimers.scavCooldownStarts, _pendingStarts),
  );

  static Map<GameMode, DateTime> _maxMerge(
    Map<GameMode, DateTime> a,
    Map<GameMode, DateTime> b,
  ) {
    final merged = {...a};
    for (final MapEntry(:key, :value) in b.entries) {
      final current = merged[key];
      if (current == null || value.isAfter(current)) merged[key] = value;
    }
    return merged;
  }

  /// Records the start of [mode]'s scav cooldown without ever moving it back.
  ///
  /// A start at or before the stored or pending one changes nothing. A later
  /// one is kept pending and saved at once, or right after the save in flight.
  /// Nothing is saved before [load] completes or while the stored record is
  /// unreadable: the user's first save writes the pending starts then.
  @override
  Future<void> recordScavCooldownStart(GameMode mode, DateTime start) async {
    final current = effectiveScavCooldownStarts[mode];
    if (current != null && !start.isAfter(current)) return;
    _pendingStarts[mode] = start;
    notifyListeners();
    if (busy) {
      _flushAfterBusy = true;
      return;
    }
    if (!_loaded || _settingsUnreadable) return;
    await _write(_settings);
    await _flushQueued();
  }

  /// Writes [value] with every start max-merged with the stored and pending
  /// ones, so no caller can move a cooldown start back.
  Future<bool> _write(AppSettings value) async {
    busy = true;
    error = null;
    notifyListeners();
    final sent = Map.of(_pendingStarts);
    final merged = value.copyWith(
      raidTimers: value.raidTimers.copyWith(
        scavCooldownStarts: _maxMerge(
          _maxMerge(
            value.raidTimers.scavCooldownStarts,
            _settings.raidTimers.scavCooldownStarts,
          ),
          sent,
        ),
      ),
    );
    try {
      await database.saveSettings(merged);
      _settings = merged;
      _settingsUnreadable = false;
      for (final MapEntry(:key, :value) in sent.entries) {
        final pending = _pendingStarts[key];
        if (pending != null && !pending.isAfter(value)) {
          _pendingStarts.remove(key);
        }
      }
      return true;
    } catch (_) {
      error = 'Settings could not be saved. Your previous settings are kept.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Saves the starts recorded while another write was in flight.
  ///
  /// A start recorded while this flush writes queues another round, so the
  /// loop ends only when no start arrived during the last write.
  Future<void> _flushQueued() async {
    while (_flushAfterBusy) {
      _flushAfterBusy = false;
      if (!_loaded || _settingsUnreadable || _pendingStarts.isEmpty) return;
      await _write(_settings);
    }
  }

  Future<bool> save(AppSettings value) async {
    if (busy) return false;
    final saved = await _write(value);
    await _flushQueued();
    return saved;
  }

  Future<bool> setRaidTimers(RaidTimerSettings timers) =>
      save(_settings.copyWith(raidTimers: timers));

  /// Sets [mode]'s Fence reputation, rounded to two decimals.
  Future<bool> setFenceReputation(GameMode mode, double value) => save(
    _settings.copyWith(
      raidTimers: _settings.raidTimers.copyWith(
        fenceReputation: {
          ..._settings.raidTimers.fenceReputation,
          mode: (value * 100).round() / 100,
        },
      ),
    ),
  );

  Future<bool> setMode(GameMode mode) => save(_settings.copyWith(mode: mode));
  Future<bool> setMap(String map) =>
      save(_settings.copyWith(selectedMap: map, followGameLogs: false));

  Future<bool> setMapInputs({
    String? gameLogDirectory,
    String? screenshotDirectory,
    bool? followGameLogs,
  }) => save(
    _settings.copyWith(
      gameLogDirectory: gameLogDirectory,
      screenshotDirectory: screenshotDirectory,
      followGameLogs: followGameLogs,
    ),
  );
  Future<bool> setMarker(String key, bool value) => save(
    _settings.copyWith(markerFilters: {..._settings.markerFilters, key: value}),
  );
  Future<bool> savePin(CustomPin pin) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      pin.validate();
      await database.savePin(pin);
      await _readPins();
      error = null;
      notifyListeners();
      return true;
    } catch (_) {
      error = 'Pin could not be saved. Check its position.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
      await _flushQueued();
    }
  }

  Future<bool> removePin(CustomPin pin) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await database.removePin(pin);
      await _readPins();
      error = null;
      notifyListeners();
      return true;
    } catch (_) {
      error = 'Pin could not be removed. The pin is kept.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
      await _flushQueued();
    }
  }
}
