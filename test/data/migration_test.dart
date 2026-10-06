import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  test('committed v1 schema migrates additively to v2 retaining preferences and activity', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(1);
    final settings = jsonEncode(
      AppSettings(mode: GameMode.pve, selectedMap: 'woods').toJson(),
    );
    schema.rawDatabase.execute(
      'INSERT INTO preferences(id,payload) VALUES (?,?)',
      [1, settings],
    );
    schema.rawDatabase.execute(
      'INSERT INTO activity_records(item_id,mode,source,observed_at,revision) VALUES (?,?,?,?,?)',
      ['synthetic-item', 'pve', 'importedManual', 1791244800, 7],
    );
    final db = BlackgridDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    expect((await db.readSettings()).selectedMap, 'woods');
    expect((await db.readActivity()).single.revision, 7);
    expect((await db.select(db.importRecords).get()), isEmpty);
    await db.close();
  });
  test(
    'newer schema refuses without downgrade reset deletion or byte mutation',
    () async {
      final dir = await Directory.systemTemp.createTemp('blackgrid-newer-');
      final file = File('${dir.path}/future.sqlite');
      final raw = sqlite3.open(file.path);
      raw.execute('CREATE TABLE future_user_data(value TEXT NOT NULL)');
      raw.execute(
        "INSERT INTO future_user_data VALUES ('synthetic durable record')",
      );
      raw.execute('PRAGMA user_version = 99');
      raw.close();
      final before = await file.readAsBytes();
      final db = BlackgridDatabase(NativeDatabase(file));
      await expectLater(db.readSettings(), throwsA(anything));
      await db.close();
      expect(await file.readAsBytes(), orderedEquals(before));
      final after = sqlite3.open(file.path);
      expect(after.select('PRAGMA user_version').single.values.single, 99);
      expect(
        after.select('SELECT value FROM future_user_data').single['value'],
        'synthetic durable record',
      );
      after.close();
      await dir.delete(recursive: true);
    },
  );
}
