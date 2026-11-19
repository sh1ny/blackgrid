import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/progress_wipe_store.dart';
import 'package:drift/native.dart';

/// An in-memory database whose wipe history cannot be read, so local progress
/// fails to load.
class ProgressReadFailingDatabase extends BlackgridDatabase {
  /// Creates the database over an in-memory executor.
  ProgressReadFailingDatabase() : super(NativeDatabase.memory());

  /// The error text the failed read carries.
  static const failure = 'synthetic wipe history failure';

  @override
  Future<List<ProgressWipe>> readProgressWipes() async =>
      throw StateError(failure);
}
