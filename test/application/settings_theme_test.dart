import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory database whose settings saves can be made to fail.
class _ThemeDatabase extends BlackgridDatabase {
  _ThemeDatabase() : super(NativeDatabase.memory());

  /// Makes every save throw while set.
  bool failSaves = false;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    if (failSaves) throw StateError('synthetic save failure');
    await super.saveSettings(settings);
  }
}

void main() {
  late _ThemeDatabase db;
  late SettingsController controller;
  setUp(() {
    db = _ThemeDatabase();
    controller = SettingsController(db);
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  test('saved Dark choice is restored by load', () async {
    await controller.load();
    expect(await controller.setThemeChoice(ThemeChoice.dark), isTrue);

    final restarted = SettingsController(db);
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.settings.themeMode, ThemeChoice.dark);
    expect(restarted.loadNotice, isNull);
  });

  test(
    'failed theme save keeps the previous choice and shows the error',
    () async {
      await controller.load();
      await controller.setThemeChoice(ThemeChoice.light);
      db.failSaves = true;

      expect(await controller.setThemeChoice(ThemeChoice.dark), isFalse);
      expect(controller.settings.themeMode, ThemeChoice.light);
      expect(controller.error, isNotNull);
      expect(controller.busy, isFalse);
      expect((await db.readSettings()).settings.themeMode, ThemeChoice.light);
    },
  );
}
