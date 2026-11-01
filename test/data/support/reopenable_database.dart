import 'dart:io';

import 'package:blackgrid/data/database.dart';
import 'package:drift/native.dart';

/// A [BlackgridDatabase] on a temporary file that tests can close and reopen.
///
/// Reopening drops every `TEMP` trigger, so data that survives a simulated
/// failure was kept by the rollback and not by the trigger.
class ReopenableDatabase {
  ReopenableDatabase._(this._directory, this._file, this.db);

  final Directory _directory;
  final File _file;
  var _triggers = 0;

  /// The currently open database. It changes on every [reopen].
  BlackgridDatabase db;

  /// Creates a temporary directory and opens a database file inside it.
  static Future<ReopenableDatabase> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'blackgrid-reopen-',
    );
    final file = File('${directory.path}/store.sqlite');
    return ReopenableDatabase._(
      directory,
      file,
      BlackgridDatabase(NativeDatabase(file)),
    );
  }

  /// Closes the database and opens the same file again.
  Future<BlackgridDatabase> reopen() async {
    await db.close();
    return db = BlackgridDatabase(NativeDatabase(_file));
  }

  /// Closes the database and deletes its temporary directory.
  Future<void> delete() async {
    await db.close();
    await _directory.delete(recursive: true);
  }

  /// Makes inserts into [table] abort until the connection closes.
  ///
  /// Upserts count as inserts. With [onUpdate] the trigger fires before
  /// updates instead.
  Future<void> abortNextInsert(String table, {bool onUpdate = false}) =>
      db.customStatement(
        'CREATE TEMP TRIGGER abort_${_triggers++} '
        'BEFORE ${onUpdate ? 'UPDATE' : 'INSERT'} ON $table '
        "BEGIN SELECT RAISE(ABORT, 'test'); END",
      );

  /// Runs [sql] with [args], for writing rows the app would never produce.
  Future<void> writeRawRow(String sql, [List<Object?> args = const []]) =>
      db.customStatement(sql, args);
}
