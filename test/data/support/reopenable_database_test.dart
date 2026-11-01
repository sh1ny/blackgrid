import 'package:test/test.dart';

import 'reopenable_database.dart';

void main() {
  test('a temp trigger does not survive reopening', () async {
    final store = await ReopenableDatabase.open();
    addTearDown(store.delete);
    await store.abortNextInsert('pin_records');
    await expectLater(
      store.writeRawRow(
        'INSERT INTO pin_records (map_id, pin_id, payload) VALUES (?, ?, ?)',
        ['m', 'p', '{}'],
      ),
      throwsA(anything),
    );
    await store.reopen();
    await store.writeRawRow(
      'INSERT INTO pin_records (map_id, pin_id, payload) VALUES (?, ?, ?)',
      ['m', 'p', '{}'],
    );
    final rows = await store.db.customSelect('SELECT * FROM pin_records').get();
    expect(rows, hasLength(1));
  });
}
