import 'dart:async';
import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';

/// Opens real SQLite with deferred transactions so WAL readers can race writers.
///
/// NativeDatabase's default BEGIN IMMEDIATE reserves the writer lock even for
/// reads. Only the transaction start changes here; all SQL and returned rows
/// still come from the native SQLite delegate, with Drift's transaction lock.
QueryExecutor deferredSqlite(File file) => DelegatedDatabase(
  _DeferredDelegate(NativeDatabase(file).delegate),
  isSequential: false,
);

class _DeferredDelegate extends DatabaseDelegate {
  _DeferredDelegate(this.inner);
  final DatabaseDelegate inner;

  @override
  TransactionDelegate get transactionDelegate =>
      const NoTransactionDelegate(start: 'BEGIN DEFERRED');
  @override
  DbVersionDelegate get versionDelegate => inner.versionDelegate;
  @override
  FutureOr<bool> get isOpen => inner.isOpen;
  @override
  bool get isInTransaction => inner.isInTransaction;
  @override
  set isInTransaction(bool value) => inner.isInTransaction = value;
  @override
  Future<void> open(QueryExecutorUser db) => inner.open(db);
  @override
  void notifyDatabaseOpened(OpeningDetails details) =>
      inner.notifyDatabaseOpened(details);
  @override
  Future<QueryResult> runSelect(String sql, List<Object?> args) =>
      inner.runSelect(sql, args);
  @override
  Future<int> runInsert(String sql, List<Object?> args) =>
      inner.runInsert(sql, args);
  @override
  Future<int> runUpdate(String sql, List<Object?> args) =>
      inner.runUpdate(sql, args);
  @override
  Future<void> runCustom(String sql, List<Object?> args) =>
      inner.runCustom(sql, args);
  @override
  Future<void> runBatched(BatchedStatements statements) =>
      inner.runBatched(statements);
  @override
  Future<void> close() => inner.close();
}
