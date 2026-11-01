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
      final read = await database.readActivity();
      if (_disposed) return;
      _rows = List<ItemActivity>.unmodifiable(read.rows);
      error = switch (read.skipped) {
        0 => null,
        1 => '1 history entry could not be read and is not shown.',
        final n => '$n history entries could not be read and are not shown.',
      };
    } catch (_) {
      if (_disposed) return;
      error = 'History could not be loaded.';
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
          ? 'The accepted scan was not recorded in history.'
          : 'The item you looked up was not recorded in history.';
      _notify();
      return false;
    }
  }
}
