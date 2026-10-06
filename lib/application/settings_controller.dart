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
  Future<void> load() async {
    final saved = await database.readSettings();
    _settings = saved.saveMarkerFilters
        ? saved
        : saved.copyWith(markerFilters: const {});
    _pins = List.unmodifiable(await database.readPins());
    notifyListeners();
  }

  Future<bool> save(AppSettings value) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await database.saveSettings(value);
      _settings = value;
      return true;
    } catch (_) {
      error =
          'Preferences could not be saved; previous durable settings remain.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> setMode(GameMode mode) => save(_settings.copyWith(mode: mode));
  Future<bool> setMap(String map) => save(_settings.copyWith(selectedMap: map));
  Future<bool> setMarker(String key, bool value) => save(
    _settings.copyWith(markerFilters: {..._settings.markerFilters, key: value}),
  );
  Future<bool> savePin(CustomPin pin) async {
    try {
      pin.validate();
      await database.savePin(pin);
      _pins = List.unmodifiable(await database.readPins());
      error = null;
      notifyListeners();
      return true;
    } catch (_) {
      error =
          'Pin could not be saved. Check its coordinates and supported frame.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> removePin(CustomPin pin) async {
    try {
      await database.removePin(pin);
      _pins = List.unmodifiable(await database.readPins());
      error = null;
      notifyListeners();
      return true;
    } catch (_) {
      error = 'Pin removal failed; the durable record remains.';
      notifyListeners();
      return false;
    }
  }
}
