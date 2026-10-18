import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../domain/catalog.dart';
import '../domain/settings.dart';

class HistoryController extends ChangeNotifier {
  HistoryController(this.database);
  final BlackgridDatabase database;
  List<ItemActivity> _rows = const [];
  List<ItemActivity> get rows => _rows;
  String? error;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      final rows = List<ItemActivity>.unmodifiable(
        await database.readActivity(),
      );
      if (_disposed) return;
      _rows = rows;
      error = null;
    } catch (_) {
      if (_disposed) return;
      error = 'Item activity could not be loaded.';
    }
    _notify();
  }

  /// Records an observation of [itemId] in [mode] from [source].
  ///
  /// Returns whether the write succeeded. On failure [error] names the
  /// [source] and listeners are notified, unless this controller was disposed.
  Future<bool> record(
    String itemId,
    GameMode mode,
    DateTime now, {
    ActivitySource source = ActivitySource.manual,
  }) async {
    try {
      await database.recordActivity(itemId, mode, now, source: source);
      await load();
      return true;
    } catch (_) {
      if (_disposed) return false;
      error = source == ActivitySource.scan
          ? 'Accepted scan was not recorded: local persistence failed.'
          : 'Manual inspection was not recorded: local persistence failed.';
      _notify();
      return false;
    }
  }
}
