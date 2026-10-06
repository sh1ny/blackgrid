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
  Future<void> load() async {
    try {
      _rows = List.unmodifiable(await database.readActivity());
      error = null;
    } catch (_) {
      error = 'Item activity could not be loaded.';
    }
    notifyListeners();
  }

  Future<bool> record(String itemId, GameMode mode, DateTime now) async {
    try {
      await database.recordActivity(itemId, mode, now);
      await load();
      return true;
    } catch (_) {
      error = 'Manual inspection was not recorded: local persistence failed.';
      notifyListeners();
      return false;
    }
  }
}
