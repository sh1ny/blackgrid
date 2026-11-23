import 'dart:io';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  const id = LogRecordId('session', LogFile.application, 531);

  test(
    'a claimed raid is still refused after closing and reopening storage',
    () async {
      final root = await Directory.systemTemp.createTemp('cleanup-claim-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/blackgrid.sqlite');
      final first = BlackgridDatabase(NativeDatabase(file));
      try {
        expect(await first.claimScreenshotCleanup(id), isTrue);
      } finally {
        await first.close();
      }

      final reopened = BlackgridDatabase(NativeDatabase(file));
      addTearDown(reopened.close);
      expect(await reopened.claimScreenshotCleanup(id), isFalse);
      for (final distinctId in const [
        LogRecordId('other-session', LogFile.application, 531),
        LogRecordId('session', LogFile.backend, 531),
        LogRecordId('session', LogFile.application, 532),
      ]) {
        expect(await reopened.claimScreenshotCleanup(distinctId), isTrue);
        expect(await reopened.claimScreenshotCleanup(distinctId), isFalse);
      }
    },
  );

  test('schema 9 upgrades additively and admits exactly one claim', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final old = await verifier.schemaAt(9);
    addTearDown(old.close);
    old.rawDatabase.execute(
      'INSERT INTO progress_meta (id, device_id) VALUES (?, ?)',
      [0, 'device-9'],
    );
    final database = BlackgridDatabase(old.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, database.schemaVersion);
    expect(
      (await database.select(database.progressMeta).getSingle()).deviceId,
      'device-9',
    );
    expect(
      await database.select(database.screenshotCleanupClaims).get(),
      isEmpty,
    );
    expect(
      await Future.wait([
        database.claimScreenshotCleanup(id),
        database.claimScreenshotCleanup(id),
      ]),
      unorderedEquals([true, false]),
    );
  });

  test('storage failure throws instead of returning a duplicate', () async {
    final database = BlackgridDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customStatement('PRAGMA query_only = ON');

    await expectLater(
      database.claimScreenshotCleanup(id),
      throwsA(isA<SqliteException>()),
    );
  });
}
