import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/legacy_import.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../fixtures/m1/legacy/legacy_fixture.dart';

void main() {
  for (final version in [0, 1, 2, 3]) {
    test(
      'settings schema $version and nested scanner 0/1 preserve valuable fields only',
      () {
        for (final scanner in [0, 1]) {
          final p = parseLegacySources(
            legacyBytes(
              settings: syntheticSettings(version: version, scanner: scanner),
            ),
          );
          expect(p.settings!.mode, GameMode.pve);
          expect(p.settings!.selectedMap, 'customs');
          expect(p.settings!.markerFilters['CustomPins'], isTrue);
          expect(p.settings!.trackerEnabled, isTrue);
          expect(p.pins.single.x, 1.2);
          expect(p.exclusions, contains('ProtectedToken'));
          expect(p.exclusions, contains('Scanner.ScanHotkey'));
          expect(
            p.settings!.toJson().toString(),
            isNot(contains('NOT_A_TOKEN')),
          );
        }
      },
    );
  }
  for (final version in [0, 1, 2, 3]) {
    test(
      'settings schema $version accepts absent or empty unset selected map',
      () {
        for (final present in [false, true]) {
          final settings = syntheticSettings(version: version);
          if (present) {
            settings['LastSelectedMap'] = '';
          } else {
            settings.remove('LastSelectedMap');
          }
          final preview = parseLegacySources(legacyBytes(settings: settings));
          expect(preview.settings!.selectedMap, 'shoreline');
          expect(preview.settings!.mode, GameMode.pve);
          expect(preview.settings!.trackerEnabled, isTrue);
          expect(preview.settings!.markerFilters['CustomPins'], isTrue);
          expect(preview.pins.single.mapId, 'customs');
          expect(preview.pins.single.x, 1.2);
        }
      },
    );
    test(
      'settings schema $version rejects malformed selected map rather than defaulting',
      () {
        for (final value in <Object?>[
          null,
          0,
          false,
          [],
          {},
          'unknown-map',
          ' ',
        ]) {
          final settings = syntheticSettings(version: version);
          settings['LastSelectedMap'] = value;
          expect(
            () => parseLegacySources(legacyBytes(settings: settings)),
            throwsFormatException,
            reason: 'Only absent or exactly empty preferences are unset.',
          );
        }
      },
    );
  }
  for (final version in [0, 1]) {
    test(
      'history schema $version rejects explicit nonpositive revisions before source collision resolution',
      () {
        for (final revision in [0, -1]) {
          final rows = [
            activity(revision: 1),
            activity(revision: revision, time: '2026-10-06T00:01:00Z'),
          ];
          expect(
            () => parseLegacySources(
              legacyBytes(
                history: syntheticHistory(version: version, rows: rows),
              ),
            ),
            throwsFormatException,
            reason:
                'An invalid second row cannot be promoted above revision 1.',
          );
        }
      },
    );
  }
  test(
    'absent activity revisions synthesize positive input-order revisions only',
    () {
      final preview = parseLegacySources(
        legacyBytes(
          history: syntheticHistory(
            rows: [
              activity(id: 'synthetic-first', revision: null),
              activity(id: 'synthetic-second', revision: null),
              activity(id: 'synthetic-third', revision: 7),
            ],
          ),
        ),
      );
      expect(preview.winningActivity.map((row) => row.revision), [1, 2, 7]);
    },
  );
  test('zero revision collision rejects file preview without any destination or source mutation', () async {
    final directory = await Directory.systemTemp.createTemp(
      'blackgrid-invalid-revision-',
    );
    final bytes = legacyBytes(
      settings: syntheticSettings(),
      history: syntheticHistory(
        rows: [
          activity(revision: 1),
          activity(revision: 0, time: '2026-10-06T00:01:00Z'),
        ],
      ),
    );
    final settingsFile = File('${directory.path}/settings.json');
    final historyFile = File('${directory.path}/history.json');
    await settingsFile.writeAsBytes(bytes['settings']!);
    await historyFile.writeAsBytes(bytes['history']!);
    final databaseFile = File('${directory.path}/store.sqlite');
    var db = BlackgridDatabase(NativeDatabase(databaseFile));
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    await db.saveSettings(
      AppSettings(mode: GameMode.pvp, selectedMap: 'woods'),
    );
    await db.savePin(
      CustomPin(
        id: 'existing-pin',
        mapId: 'woods',
        x: .2,
        y: .3,
        frame: 'legacy-normalized',
        frameRevision: 0,
        label: 'Existing pin',
        updatedAt: DateTime.utc(2026),
      ),
    );
    await db.recordActivity(
      'synthetic-unmatched',
      GameMode.pve,
      DateTime.utc(2026),
    );
    final originalSettings = await db.select(db.preferences).get();
    final originalPins = await db.select(db.pinRecords).get();
    final originalActivity = await db.select(db.activityRecords).get();
    await expectLater(
      LegacyImport(db).previewFiles(
        settingsPath: settingsFile.path,
        historyPath: historyFile.path,
      ),
      throwsFormatException,
    );
    expect(await db.select(db.preferences).get(), originalSettings);
    expect(await db.select(db.pinRecords).get(), originalPins);
    expect(await db.select(db.activityRecords).get(), originalActivity);
    expect(await db.select(db.importRecords).get(), isEmpty);
    expect(await settingsFile.readAsBytes(), orderedEquals(bytes['settings']!));
    expect(await historyFile.readAsBytes(), orderedEquals(bytes['history']!));
    await db.close();
    db = BlackgridDatabase(NativeDatabase(databaseFile));
    expect(await db.select(db.preferences).get(), originalSettings);
    expect(await db.select(db.pinRecords).get(), originalPins);
    expect(await db.select(db.activityRecords).get(), originalActivity);
    expect(await db.select(db.importRecords).get(), isEmpty);
  });
  test('history root 0/1 aliases numeric enum values and missing revisions preserve identities', () {
    for (final version in [0, 1]) {
      final row = activity(mode: 1, source: 1, revision: null);
      row['CanonicalItemId'] = row.remove('ItemId');
      final history = syntheticHistory(version: version, rows: [row]);
      history['Entries'] = history.remove('Rows');
      history['Revision'] = history.remove('FileRevision');
      final p = parseLegacySources(legacyBytes(history: history));
      expect(p.winningActivity.single.mode, GameMode.pvp);
      expect(p.winningActivity.single.source, ActivitySource.importedScan);
      expect(p.winningActivity.single.revision, 1);
      expect(p.winningActivity.single.itemId, 'synthetic-unmatched');
      expect(p.winningActivity.single.toJson().keys, isNot(contains('FIR')));
    }
  });
  test('all source collisions are accounted with revision time stable order winner and destination preservation', () {
    final rows = [
      activity(revision: 1),
      activity(revision: 2),
      activity(revision: 2, time: '2026-10-06T00:01:00Z'),
      activity(revision: 2, time: '2026-10-06T00:01:00Z'),
    ];
    final p = parseLegacySources(
      legacyBytes(history: syntheticHistory(rows: rows)),
      destinationActivity: [
        ItemActivity(
          itemId: 'synthetic-unmatched',
          mode: GameMode.pve,
          source: ActivitySource.manual,
          observedAt: DateTime.utc(2026),
          revision: 99,
        ),
      ],
    );
    expect(p.accounting.length, 4);
    expect(
      p.winningActivity.single.observedAt,
      DateTime.utc(2026, 10, 6, 0, 1),
    );
    expect(p.accounting[2].disposition, 'destination conflict');
    expect(
      p.accounting
          .where((r) => r.disposition == 'source collision loser')
          .length,
      3,
    );
    expect(p.accounting[3].reason, contains('Input 2'));
    expect(p.accounting[0].reason, contains('revision 2 exceeds 1'));
    expect(p.accounting[1].reason, contains('later UTC'));
    expect(p.accounting[3].reason, contains('stable earlier input order'));
    expect(p.accounting[2].reason, contains('destination revision 99'));
  });
  test(
    'destination indexes preserve first activity and exact map pin identity',
    () {
      final settings = syntheticSettings();
      settings['CustomPinsByMap'] = {
        for (final map in ['customs', 'woods'])
          map: [
            {'id': 'synthetic-pin', 'normalizedX': 1.2, 'normalizedY': -.2},
          ],
      };
      final preview = parseLegacySources(
        legacyBytes(settings: settings, history: syntheticHistory()),
        destinationPins: [
          CustomPin(
            id: 'synthetic-pin',
            mapId: 'customs',
            x: 0,
            y: 0,
            frame: 'legacy-normalized',
            frameRevision: 0,
            label: 'Existing customs pin',
            updatedAt: DateTime.utc(2026),
          ),
        ],
        destinationActivity: [
          for (final revision in [99, 100])
            ItemActivity(
              itemId: 'synthetic-unmatched',
              mode: GameMode.pve,
              source: ActivitySource.manual,
              observedAt: DateTime.utc(2026),
              revision: revision,
            ),
          ItemActivity(
            itemId: 'synthetic-unmatched',
            mode: GameMode.pvp,
            source: ActivitySource.manual,
            observedAt: DateTime.utc(2026),
            revision: 101,
          ),
        ],
      );
      final pins = preview.accounting
          .where((row) => row.kind == 'pin')
          .toList();
      expect(pins.map((row) => row.key), [
        'customs:synthetic-pin',
        'woods:synthetic-pin',
      ]);
      expect(pins.map((row) => row.disposition), [
        'destination conflict',
        'add',
      ]);
      final history = preview.accounting.singleWhere(
        (row) => row.kind == 'activity',
      );
      expect(history.disposition, 'destination conflict');
      expect(history.reason, contains('destination revision 99'));
      expect(history.reason, isNot(contains('destination revision 100')));
      expect(history.reason, isNot(contains('destination revision 101')));
    },
  );
  test('duplicate supported JSON fields fail instead of silently losing a source record', () {
    for (final entry in [
      ('history', '{"SchemaVersion":0,"SchemaVersion":1,"Rows":[]}'),
      (
        'settings',
        '{"SchemaVersion":0,"CustomPinsByMap":{},"CustomPinsByMap":{}}',
      ),
    ]) {
      expect(
        () => parseLegacySources({entry.$1: utf8.encode(entry.$2)}),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'precise duplicate field diagnosis',
            contains('Duplicate'),
          ),
        ),
      );
    }
  });
  test('Labs legacy 0 to native 1 conversion ordinary and off-map with direct revision 1 preservation', () {
    final origin = convertLabsLegacy(0, 0);
    expect(origin.$1, closeTo(6.925 / 175, 1e-10));
    expect(origin.$2, closeTo(28.675 / 175, 1e-10));
    final off = convertLabsLegacy(-2, 3);
    expect(off.$1, closeTo(-319.675 / 175, 1e-10));
    expect(off.$2, closeTo(385.75 / 175, 1e-10));
    final settings = syntheticSettings();
    settings['CustomPinsByMap'] = {
      'labs': [
        {'id': 'synthetic-labs', 'normalizedX': -2, 'normalizedY': 3},
      ],
    };
    settings['CustomPinCoordinateRevisions'] = {'labs': 1};
    final pin = parseLegacySources(legacyBytes(settings: settings)).pins.single;
    expect(pin.mapId, 'thelab');
    expect(pin.x, -2);
    expect(pin.frameRevision, 1);
    expect(() => convertLabsLegacy(double.nan, 0), throwsFormatException);
  });
  test('unsupported versions modes frames and any malformed supported record reject entire candidate', () {
    final cases = <Map<String, Object?>>[
      syntheticSettings(version: 4),
      syntheticSettings(scanner: 2),
      {...syntheticSettings(), 'SaveMarkerFilters': 'true'},
      {
        ...syntheticSettings(),
        'CustomPinCoordinateRevisions': {'customs': 1},
      },
      {
        ...syntheticSettings(),
        'CustomPinsByMap': {'unknown-map': []},
      },
      {
        ...syntheticSettings(),
        'MarkerFilters': {'Labels': 1},
      },
    ];
    for (final settings in cases) {
      expect(
        () => parseLegacySources(legacyBytes(settings: settings)),
        throwsA(anything),
      );
    }
    expect(
      () => parseLegacySources(
        legacyBytes(history: syntheticHistory(version: 2)),
      ),
      throwsFormatException,
    );
    expect(
      () => parseLegacySources(
        legacyBytes(
          history: syntheticHistory(rows: [activity(mode: 'Unknown')]),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => parseLegacySources(
        legacyBytes(history: syntheticHistory(rows: [activity(source: 99)])),
      ),
      throwsFormatException,
    );
    expect(
      () => parseLegacySources(
        legacyBytes(
          history: syntheticHistory(rows: [activity(time: '2026-10-06')]),
        ),
      ),
      throwsFormatException,
    );
  });
  test('explicit file import is immutable atomic once-only and keeps existing destination by default', () async {
    final dir = await Directory.systemTemp.createTemp('blackgrid-import-');
    final bytes = legacyBytes(
      settings: syntheticSettings(),
      history: syntheticHistory(),
    );
    final settingsFile = File('${dir.path}/settings.json');
    final historyFile = File('${dir.path}/history.json');
    await settingsFile.writeAsBytes(bytes['settings']!);
    await historyFile.writeAsBytes(bytes['history']!);
    final db = BlackgridDatabase(NativeDatabase.memory());
    final importer = LegacyImport(db);
    await db.saveSettings(
      AppSettings(mode: GameMode.pvp, selectedMap: 'woods'),
    );
    final preview = await importer.previewFiles(
      settingsPath: settingsFile.path,
      historyPath: historyFile.path,
    );
    await importer.commit(preview, replaceExisting: false);
    expect((await db.readSettings()).selectedMap, 'woods');
    expect((await db.readActivity()).single.itemId, 'synthetic-unmatched');
    expect(await settingsFile.readAsBytes(), orderedEquals(bytes['settings']!));
    expect(await historyFile.readAsBytes(), orderedEquals(bytes['history']!));
    final repeated = await importer.previewFiles(
      settingsPath: settingsFile.path,
      historyPath: historyFile.path,
    );
    expect(repeated.alreadyImported, isTrue);
    await expectLater(
      importer.commit(repeated, replaceExisting: true),
      throwsStateError,
    );
    expect((await db.readActivity()).length, 1);
    await db.close();
    await dir.delete(recursive: true);
  });
  test('failed import transaction rolls back settings pins activity and marker together', () async {
    final db = BlackgridDatabase(NativeDatabase.memory());
    await db.readSettings();
    await db.customStatement(
      "CREATE TRIGGER fail_import BEFORE INSERT ON import_records BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
    );
    final p = parseLegacySources(
      legacyBytes(settings: syntheticSettings(), history: syntheticHistory()),
    );
    await expectLater(
      db.commitImport(p, replaceExisting: true),
      throwsA(anything),
    );
    expect((await db.readSettings()).mode, GameMode.unknown);
    expect(await db.readPins(), isEmpty);
    expect(await db.readActivity(), isEmpty);
    expect(await db.wasImported(p.digest), isFalse);
    await db.close();
  });
}
