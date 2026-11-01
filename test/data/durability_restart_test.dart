import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:test/test.dart';

import '../fixtures/m1/catalog/fixture.dart';
import 'support/reopenable_database.dart';

CustomPin _pin(String id) => CustomPin(
  id: id,
  mapId: 'customs',
  x: .5,
  y: .5,
  frame: 'legacy-normalized',
  frameRevision: 0,
  label: id,
  updatedAt: fixtureNow,
);

void main() {
  late ReopenableDatabase store;
  setUp(() async => store = await ReopenableDatabase.open());
  tearDown(() => store.delete());

  test('a removed pin stays removed after reopening', () async {
    final kept = _pin('kept');
    final removed = _pin('removed');
    await store.db.savePin(kept);
    await store.db.savePin(removed);
    await store.db.removePin(removed);
    final db = await store.reopen();
    expect((await db.readPins()).map((p) => p.id), ['kept']);
  });

  test('a settings save aborted by the database reads back the earlier settings after reopening', () async {
    await store.db.saveSettings(AppSettings(mode: GameMode.pve));
    await store.abortNextInsert('preferences');
    await expectLater(
      store.db.saveSettings(AppSettings(mode: GameMode.pvp)),
      throwsA(anything),
    );
    final db = await store.reopen();
    expect((await db.readSettings()).mode, GameMode.pve);
  });
}
