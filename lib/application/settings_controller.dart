import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../domain/catalog.dart';
import '../domain/settings.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this.database);
  final BlackgridDatabase database;
  AppSettings _settings = AppSettings();
  List<CustomPin> _pins = const [];
  AppSettings get settings => _settings;
  List<CustomPin> get pins => _pins;
  String? error;
  bool busy = false;
  bool _settingsUnreadable = false;
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
    await _readPins();
    notifyListeners();
  }

  Future<void> _readPins() async {
    final read = await database.readPins();
    _pins = List.unmodifiable(read.pins);
    _pinsSkipped = read.skipped;
  }

  Future<bool> save(AppSettings value) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await database.saveSettings(value);
      _settings = value;
      _settingsUnreadable = false;
      return true;
    } catch (_) {
      error = 'Settings could not be saved. Your previous settings are kept.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

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
    }
  }
}
