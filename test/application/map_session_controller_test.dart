import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/map_session_controller.dart';
import 'package:blackgrid/application/settings_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/game_paths.dart';
import 'package:blackgrid/data/screenshot_directory_watcher.dart';
import 'package:blackgrid/data/session_log_reader.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/map_session.dart';
import 'package:blackgrid/domain/raid_panel_text_parser.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory screenshots;
  late BlackgridDatabase database;
  late SettingsController settings;
  late SessionLogReader logs;
  late ScreenshotDirectoryWatcher watcher;
  late MapSessionController session;
  final now = DateTime(2026, 10, 7);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('blackgrid-map-session-');
    screenshots = await Directory(
      '${root.path}${Platform.pathSeparator}screenshots',
    ).create();
    database = BlackgridDatabase(NativeDatabase.memory());
    settings = SettingsController(database);
    await settings.load();
    await settings.setMode(GameMode.pvp);
    await settings.setMapInputs(
      gameLogDirectory: root.path,
      screenshotDirectory: screenshots.path,
    );
    logs = SessionLogReader(
      pollInterval: const Duration(days: 1),
      chunkBytes: 7,
    );
    watcher = ScreenshotDirectoryWatcher(
      stabilityDelay: Duration.zero,
      pollInterval: const Duration(days: 1),
    );
    session = MapSessionController(
      settings: settings,
      logReader: logs,
      screenshotWatcher: watcher,
      clock: () => now,
      recognize: (_) async => RaidPanelEvidence(
        state: RaidPanelState.recognized,
        extractNames: ['Fixture exit'],
      ),
    );
  });
  tearDown(() async {
    await session.close();
    settings.dispose();
    await database.close();
    await root.delete(recursive: true);
  });

  Future<File> log(
    String scene, {
    String mode = 'Pve',
    String folder = 'log_2026.10.07_0-52-00',
  }) async {
    final directory = await Directory(
      '${root.path}${Platform.pathSeparator}$folder',
    ).create();
    return File(
      '${directory.path}${Platform.pathSeparator}application.log',
    ).writeAsString(
      '${mode.isEmpty ? '' : 'Session mode: $mode\n'}application|scene preset path:maps/$scene.bundle\n',
      flush: true,
    );
  }

  Future<File> screenshot(int value, {String? name}) async {
    final filename = name ?? '2026-10-07[00-52]_$value, 0, 2_0, 0, 0, 1_0.png';
    // Finalize metadata outside the watched directory before publishing evidence.
    final staged = await File(
      '${root.path}${Platform.pathSeparator}$filename.stage',
    ).writeAsBytes([value], flush: true);
    await staged.setLastModified(now.add(Duration(minutes: value)));
    return staged.rename(
      '${screenshots.path}${Platform.pathSeparator}$filename',
    );
  }

  test('detected mode outranks fallback, manual follow-off and filter saves preserve authority', () async {
    await log('laboratory');
    await session.initialize();
    expect(session.effectiveMapId, 'thelab');
    expect(session.effectiveMode, GameMode.pve);
    await settings.setMap('woods');
    expect(session.effectiveMapId, 'woods');
    expect(settings.settings.followGameLogs, isFalse);
    expect((await database.readSettings()).settings.followGameLogs, isFalse);
    expect(session.state.mapDisagreement, isTrue);
    await settings.setMarker('PmcExtracts', false);
    expect(session.effectiveMapId, 'woods');
    await settings.setMapInputs(followGameLogs: true);
    expect(session.effectiveMapId, 'thelab');
    expect(settings.settings.selectedMap, 'woods');
    await settings.setMarker('PmcExtracts', true);
    expect(session.effectiveMapId, 'thelab');
    await settings.setMode(GameMode.seasonal);
    expect(session.effectiveMode, GameMode.pve);
    final epoch = session.state.sessionEpoch;
    await log('woods', mode: '', folder: 'log_2026.10.07_1-00-00');
    await logs.rescan();
    expect(session.effectiveMapId, 'woods');
    expect(session.effectiveMode, GameMode.seasonal);
    expect(session.state.sessionEpoch, greaterThan(epoch));
  });

  test('empty input settings bind auto-detected game folders', () async {
    await session.close();
    final install = await Directory('${root.path}${Platform.pathSeparator}EFT')
        .create();
    await Directory('${install.path}${Platform.pathSeparator}Logs').create();
    await Directory(
      '${install.path}${Platform.pathSeparator}Logs${Platform.pathSeparator}log_2026.10.07_10-25-14_1.2.0.0.47888',
    ).create();
    await File(
      '${install.path}${Platform.pathSeparator}Logs${Platform.pathSeparator}log_2026.10.07_10-25-14_1.2.0.0.47888${Platform.pathSeparator}application_000.log',
    ).writeAsString(
      'application|scene preset path:maps/laboratory.bundle\n',
      flush: true,
    );
    await settings.setMapInputs(gameLogDirectory: '', screenshotDirectory: '');
    logs = SessionLogReader(pollInterval: const Duration(days: 1));
    watcher = ScreenshotDirectoryWatcher(pollInterval: const Duration(days: 1));
    session = MapSessionController(
      settings: settings,
      logReader: logs,
      screenshotWatcher: watcher,
      clock: () => now,
      discovery: GamePathDiscovery(
        readRegistry: (key, value) async =>
            value == 'InstallLocation' ? install.path : null,
        environment: {'USERPROFILE': root.path},
      ),
    );
    await session.initialize();
    expect(
      session.state.logDirectory,
      '${install.path}${Platform.pathSeparator}Logs',
    );
    expect(session.state.logDirectoryDetected, isTrue);
    expect(session.state.detectedMapId, 'thelab');
    expect(
      session.state.screenshotDirectory,
      '${root.path}\\Documents\\Escape from Tarkov\\Screenshots',
    );
    expect(session.state.screenshotDirectoryDetected, isTrue);
    expect(session.state.screenshotStatus, MapInputStatus.missing);
  });

  test('watched screenshots apply to the selected map without an agreeing log session', () async {
    await settings.setMap('woods');
    await session.initialize();
    session.updateMapContext(_map('woods'), 1);
    await screenshot(1);
    await watcher.rescan();
    await _until(
      session,
      () => session.state.raidHighlightIds.contains('woods-exit'),
    );
    expect(session.state.playerSample!.metadata.position.x, 1);
    expect(session.state.assumedAssociation, isTrue);
  });

  test('missing push log leaves Logs status and screenshot labels unchanged', () async {
    await log('woods');
    // The backend log exists and is empty; only the notifications log is absent.
    await File(
      '${root.path}${Platform.pathSeparator}log_2026.10.07_0-52-00${Platform.pathSeparator}backend.log',
    ).writeAsString('', flush: true);
    await settings.setMapInputs(followGameLogs: true);
    await session.initialize();
    session.updateMapContext(_map('woods'), 1);
    await screenshot(1);
    await watcher.rescan();
    await _until(
      session,
      () => session.state.raidHighlightIds.contains('woods-exit'),
    );
    final state = session.state;
    expect(state.logStatus, MapInputStatus.watching);
    expect(state.logMessage, isNull);
    expect(state.detectedMapId, 'woods');
    expect(state.assumedAssociation, isFalse);
    expect(state.playerSample!.assumedAssociation, isFalse);
    expect(state.screenshotMessage, isNull);
    expect(state.raidLogsMessage, contains('notifications log'));
  });

  test('raid logs change keeps evidence with an unsupported scene', () async {
    final application = await log('nowhere');
    await settings.setMap('woods');
    await session.initialize();
    session.updateMapContext(_map('woods'), 1);
    expect(session.state.logStatus, MapInputStatus.unavailable);
    await screenshot(1);
    await session.readLatest();
    await _until(
      session,
      () => session.state.raidHighlightIds.contains('woods-exit'),
    );
    expect(session.state.playerSample, isNotNull);
    final epoch = session.state.sessionEpoch;
    expect(session.state.raidLogsMessage, isNotNull);

    // The push log appearing changes only the raid-logs line.
    await File(
      '${application.parent.path}${Platform.pathSeparator}push-notifications.log',
    ).writeAsString('', flush: true);
    await logs.rescan();

    expect(session.state.raidLogsMessage, contains('backend'));
    expect(session.state.logStatus, MapInputStatus.unavailable);
    expect(session.state.sessionEpoch, epoch);
    expect(session.state.playerSample, isNotNull);
    expect(session.state.raidEvidence, isNotNull);
    expect(session.state.raidHighlightIds, {'woods-exit'});
  });

  test(
    'disagreement blocks watched evidence; Read Latest remains visibly assumed',
    () async {
      await log('laboratory');
      await settings.setMap('woods');
      await session.initialize();
      session.updateMapContext(_map('woods'), 1);
      final first = await screenshot(1);
      await watcher.rescan();
      expect(session.state.mapDisagreement, isTrue);
      expect(session.state.playerSample, isNull);
      expect(session.state.raidEvidence, isNull);
      expect(session.state.raidHighlightIds, isEmpty);
      expect(session.state.savedScreenshotPath, isNull);
      expect(session.state.processingScreenshot, isFalse);
      expect(session.state.pendingScreenshotPath, isNull);
      expect(session.state.assumedAssociation, isFalse);
      expect(
        session.state.screenshotMessage,
        contains('watched screenshots are ignored'),
      );
      await session.readLatest();
      expect(session.state.playerSample!.metadata.position.x, 1);
      expect(session.state.assumedAssociation, isTrue);
      expect(session.state.raidHighlightIds, {'woods-exit'});
      expect(session.state.savedScreenshotPath, first.path);
      await settings.setMapInputs(followGameLogs: true);
      session.updateMapContext(_map('thelab'), 2);
      await watcher.rescan();
      expect(session.state.playerSample, isNull);
      expect(session.state.raidHighlightIds, isEmpty);
      await screenshot(2);
      await watcher.rescan();
      await _until(
        session,
        () => session.state.raidHighlightIds.contains('thelab-exit'),
      );
      expect(session.state.assumedAssociation, isFalse);
      expect(session.state.playerSample!.metadata.position.height, 0);
      final sample = session.state.playerSample;
      await log('not_supported');
      await logs.rescan();
      expect(session.state.detectedMapId, isNull);
      expect(session.state.playerSample, isNull);
      expect(session.state.raidHighlightIds, isEmpty);
      expect(
        sample!.ageAt(now.add(const Duration(minutes: 5))),
        const Duration(minutes: 3),
      );
    },
  );

  test('Read Latest old manual source preserves timestamp and absent metadata remains assumed', () async {
    final old = await screenshot(1, name: 'old.png');
    await old.setLastModified(now.subtract(const Duration(days: 1)));
    await session.initialize();
    session.updateMapContext(_map('shoreline'), 1);
    await session.readLatest();
    expect(session.state.playerSample, isNull);
    expect(session.state.assumedAssociation, isTrue);
    expect(
      session.state.savedScreenshotModifiedAt,
      now.subtract(const Duration(days: 1)),
    );
    expect(session.state.raidHighlightIds, {'shoreline-exit'});
  });

  test('marker context replacement refreshes exit matching and preserves player state', () async {
    await session.initialize();
    final map = _map('shoreline');
    session.updateMapContext(map, 1);
    await screenshot(1);
    await session.readLatest();
    final sample = session.state.playerSample!;
    expect(session.state.raidHighlightIds, {'shoreline-exit'});

    final refreshed = PreparedMarker(
      id: 'refreshed-exit',
      category: 'extracts',
      filterKey: 'SharedExtracts',
      name: 'Refreshed exit',
      position: GamePoint(1, 2),
      details: const {
        'aliases': ['Fixture exit'],
      },
      source: const {},
      outline: const [],
    );
    session.updateMapContext(map, 2, activeMarkers: [refreshed]);

    expect(session.state.playerSample, same(sample));
    expect(session.state.raidHighlightIds, {'refreshed-exit'});
    expect(session.state.raidEvidence?.state, RaidPanelState.recognized);
  });
  test('same-ID exit rename clears stale highlight and rematches saved OCR after restoration', () async {
    await session.initialize();
    final map = _map('shoreline');
    session.updateMapContext(map, 1);
    await screenshot(1);
    await session.readLatest();
    final sample = session.state.playerSample!;
    expect(session.state.raidEvidence?.state, RaidPanelState.recognized);
    expect(session.state.raidHighlightIds, {'shoreline-exit'});

    session.updateMapContext(
      map,
      2,
      activeMarkers: [_exitMarker('shoreline-exit', 'Renamed exit')],
    );

    expect(session.state.playerSample, same(sample));
    expect(session.state.raidEvidence?.state, RaidPanelState.unreadable);
    expect(session.state.raidEvidence?.extractNames, ['Fixture exit']);
    expect(session.state.raidHighlightIds, isEmpty);

    session.updateMapContext(
      map,
      3,
      activeMarkers: [_exitMarker('restored-exit', 'Fixture exit')],
    );

    expect(session.state.playerSample, same(sample));
    expect(session.state.raidEvidence?.state, RaidPanelState.recognized);
    expect(session.state.raidEvidence?.extractNames, ['Fixture exit']);
    expect(session.state.raidHighlightIds, {'restored-exit'});
  });

  test(
    'ambiguous saved OCR rematches when the current exits become unambiguous',
    () async {
      await session.initialize();
      final map = _map('shoreline');
      session.updateMapContext(map, 1);
      await screenshot(1);
      await session.readLatest();
      final sample = session.state.playerSample!;
      expect(session.state.raidEvidence?.state, RaidPanelState.recognized);

      session.updateMapContext(
        map,
        2,
        activeMarkers: [
          _exitMarker('fixture-a', 'Fixture exit A'),
          _exitMarker('fixture-b', 'Fixture exit B'),
        ],
      );

      expect(session.state.playerSample, same(sample));
      expect(session.state.raidEvidence?.state, RaidPanelState.ambiguous);
      expect(session.state.raidEvidence?.extractNames, ['Fixture exit']);
      expect(session.state.raidHighlightIds, isEmpty);

      session.updateMapContext(
        map,
        3,
        activeMarkers: [_exitMarker('fixture-a', 'Fixture exit A')],
      );

      expect(session.state.playerSample, same(sample));
      expect(session.state.raidEvidence?.state, RaidPanelState.recognized);
      expect(session.state.raidEvidence?.extractNames, ['Fixture exit']);
      expect(session.state.raidHighlightIds, {'fixture-a'});
    },
  );

  test('one active plus replaceable pending jobs fence older OCR and await shutdown drain', () async {
    await session.close();
    logs = SessionLogReader(pollInterval: const Duration(days: 1));
    watcher = ScreenshotDirectoryWatcher(
      stabilityDelay: Duration.zero,
      pollInterval: const Duration(days: 1),
    );
    final active = Completer<RaidPanelEvidence>();
    final started = Completer<void>();
    final processed = <int>[];
    session = MapSessionController(
      settings: settings,
      logReader: logs,
      screenshotWatcher: watcher,
      clock: () => now,
      recognize: (bytes) {
        processed.add(bytes.single);
        if (bytes.single == 1) {
          started.complete();
          return active.future;
        }
        return Future.value(RaidPanelEvidence(state: RaidPanelState.empty));
      },
    );
    await session.initialize();
    final map = _map('shoreline');
    session.updateMapContext(map, 1);
    await screenshot(1);
    final first = session.readLatest();
    await started.future;
    final secondFile = await screenshot(2);
    final second = session.readLatest();
    await _until(
      session,
      () => session.state.pendingScreenshotPath == secondFile.path,
    );
    final thirdFile = await screenshot(3);
    final third = session.readLatest();
    await _until(
      session,
      () => session.state.pendingScreenshotPath == thirdFile.path,
    );
    // Repeated same content context (pan/zoom consumer notifications) cannot fence OCR.
    session.updateMapContext(map, 1);
    active.complete(
      RaidPanelEvidence(
        state: RaidPanelState.recognized,
        extractNames: ['Fixture exit'],
      ),
    );
    await Future.wait([first, second, third]);
    expect(processed, [1, 3]);
    expect(session.state.playerSample!.metadata.position.x, 3);
    expect(session.state.raidEvidence!.state, RaidPanelState.empty);
    expect(session.state.raidHighlightIds, isEmpty);

    // A second owner proves close waits for in-flight recognition before disposal.
    await session.close();
    final drain = Completer<RaidPanelEvidence>();
    final drainingStarted = Completer<void>();
    session = MapSessionController(
      settings: settings,
      clock: () => now,
      screenshotWatcher: ScreenshotDirectoryWatcher(
        stabilityDelay: Duration.zero,
      ),
      recognize: (_) {
        drainingStarted.complete();
        return drain.future;
      },
    );
    await session.initialize();
    session.updateMapContext(map, 1);
    final pending = session.readLatest();
    await drainingStarted.future;
    var closed = false;
    final closing = session.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    drain.complete(
      RaidPanelEvidence(
        state: RaidPanelState.recognized,
        extractNames: ['Fixture exit'],
      ),
    );
    await Future.wait([closing, pending]);
    expect(closed, isTrue);
  });

  for (final change in ['map', 'content', 'session', 'directory']) {
    test('late recognition after $change changes cannot publish', () async {
      await session.close();
      final result = Completer<RaidPanelEvidence>();
      final started = Completer<void>();
      logs = SessionLogReader(pollInterval: const Duration(days: 1));
      await log('shoreline');
      session = MapSessionController(
        settings: settings,
        clock: () => now,
        logReader: logs,
        screenshotWatcher: ScreenshotDirectoryWatcher(
          stabilityDelay: Duration.zero,
        ),
        recognize: (_) {
          started.complete();
          return result.future;
        },
      );
      await session.initialize();
      final map = _map('shoreline');
      session.updateMapContext(map, 1);
      await screenshot(1);
      final read = session.readLatest();
      await started.future;
      final sampleBeforeContextChange = session.state.playerSample!;
      switch (change) {
        case 'map':
          await settings.setMap('woods');
        case 'content':
          session.updateMapContext(map, 2);
        case 'session':
          await log('shoreline', mode: '', folder: 'log_2026.10.07_1-00-00');
          await logs.rescan();
        case 'directory':
          await settings.setMapInputs(screenshotDirectory: '');
      }
      result.complete(
        RaidPanelEvidence(
          state: RaidPanelState.recognized,
          extractNames: ['Fixture exit'],
        ),
      );
      await read;
      if (change == 'content') {
        expect(session.state.playerSample, same(sampleBeforeContextChange));
      } else {
        expect(session.state.playerSample, isNull);
      }
      expect(session.state.raidEvidence, isNull);
      expect(session.state.raidHighlightIds, isEmpty);
      expect(session.state.readingLatest, isFalse);
    });
  }

  test(
    'transient log errors stay visible without clearing same-context evidence',
    () async {
      await session.close();
      final result = Completer<RaidPanelEvidence>();
      final started = Completer<void>();
      logs = SessionLogReader(pollInterval: const Duration(days: 1));
      final file = await log('shoreline');
      session = MapSessionController(
        settings: settings,
        clock: () => now,
        logReader: logs,
        screenshotWatcher: ScreenshotDirectoryWatcher(
          stabilityDelay: Duration.zero,
        ),
        recognize: (_) {
          started.complete();
          return result.future;
        },
      );
      await session.initialize();
      session.updateMapContext(_map('shoreline'), 1);
      expect(session.state.logStatus, MapInputStatus.watching);
      final epoch = session.state.sessionEpoch;
      await screenshot(1);
      final read = session.readLatest();
      await started.future;
      // A rejected record mid-recognition must not fence the in-flight job.
      await file.writeAsBytes([0xff, 10], mode: FileMode.append, flush: true);
      await logs.rescan();
      expect(session.state.logStatus, MapInputStatus.error);
      expect(session.state.logMessage, contains('Malformed'));
      result.complete(
        RaidPanelEvidence(
          state: RaidPanelState.recognized,
          extractNames: ['Fixture exit'],
        ),
      );
      await read;
      expect(session.state.sessionEpoch, epoch);
      expect(session.state.playerSample!.metadata.position.x, 1);
      expect(session.state.raidHighlightIds, {'shoreline-exit'});

      await file.writeAsString('clean\n', mode: FileMode.append, flush: true);
      await logs.rescan();
      expect(session.state.logStatus, MapInputStatus.watching);
      expect(session.state.playerSample!.metadata.position.x, 1);
      expect(session.state.raidEvidence!.state, RaidPanelState.recognized);
      expect(session.state.raidHighlightIds, {'shoreline-exit'});

      // A missing input still invalidates.
      await file.delete();
      await logs.rescan();
      expect(session.state.logStatus, MapInputStatus.missing);
      expect(session.state.playerSample, isNull);
      expect(session.state.raidHighlightIds, isEmpty);
    },
  );

  test(
    'partial, missing and unmatched evidence retain IDs; only empty clears',
    () async {
      await session.close();
      final outcomes = [
        RaidPanelEvidence(
          state: RaidPanelState.recognized,
          extractNames: ['Fixture exit'],
        ),
        RaidPanelEvidence(state: RaidPanelState.partial),
        RaidPanelEvidence(state: RaidPanelState.missing),
        RaidPanelEvidence(
          state: RaidPanelState.recognized,
          extractNames: ['Unknown exit'],
        ),
        RaidPanelEvidence(state: RaidPanelState.empty),
      ];
      session = MapSessionController(
        settings: settings,
        clock: () => now,
        screenshotWatcher: ScreenshotDirectoryWatcher(
          stabilityDelay: Duration.zero,
        ),
        recognize: (_) async => outcomes.removeAt(0),
      );
      await session.initialize();
      session.updateMapContext(_map('shoreline'), 1);
      await screenshot(1);
      for (final expected in [
        RaidPanelState.recognized,
        RaidPanelState.partial,
        RaidPanelState.missing,
        RaidPanelState.unreadable,
      ]) {
        await session.readLatest();
        expect(session.state.raidEvidence!.state, expected);
        expect(session.state.raidHighlightIds, {'shoreline-exit'});
      }
      await session.readLatest();
      expect(session.state.raidEvidence!.state, RaidPanelState.empty);
      expect(session.state.raidHighlightIds, isEmpty);
    },
  );

  Future<_ScriptedWatcher> scripted() async {
    await session.close();
    final scripted = _ScriptedWatcher();
    watcher = scripted;
    session = MapSessionController(
      settings: settings,
      logReader: SessionLogReader(pollInterval: const Duration(days: 1)),
      screenshotWatcher: scripted,
      clock: () => now,
      recognize: (_) async => RaidPanelEvidence(
        state: RaidPanelState.recognized,
        extractNames: ['Fixture exit'],
      ),
    );
    await session.initialize();
    session.updateMapContext(_map('shoreline'), 1);
    return scripted;
  }

  test(
    'map-controls: Read latest outcome reports each watcher result',
    () async {
      await screenshot(1);
      await session.initialize();
      session.updateMapContext(_map('shoreline'), 1);
      expect(await session.readLatest(), isA<ReadLatestApplied>());
      expect(session.state.savedScreenshotPath, isNotNull);

      final script = await scripted();
      for (final (result, expected) in <(ScreenshotRead, Type)>[
        (const ScreenshotEmpty(), ReadLatestNoScreenshot),
        (const ScreenshotUnavailable(), ReadLatestUnavailable),
        (const ScreenshotDiscarded(), ReadLatestSuperseded),
      ]) {
        final read = session.readLatest();
        await script.called;
        script.answer(result);
        expect((await read).runtimeType, expected, reason: '$result');
        expect(session.state.readingLatest, isFalse);
      }
    },
  );

  test('map-controls: Superseded read', () async {
    final script = await scripted();
    final results = <ScreenshotRead>[
      ScreenshotFound(
        SavedScreenshot(
          path: 'a.png',
          modifiedAt: now,
          bytes: Uint8List.fromList([1]),
          contentId: 'a',
        ),
      ),
      const ScreenshotEmpty(),
      const ScreenshotUnavailable(),
      const ScreenshotDiscarded(),
    ];
    var content = 1;
    for (final result in results) {
      // A later explicit read moves the order.
      final first = session.readLatest();
      await script.called;
      final second = session.readLatest();
      await script.called;
      script.answer(const ScreenshotEmpty(), call: 1);
      script.answer(result, call: 0);
      expect(await first, isA<ReadLatestSuperseded>(), reason: 'order $result');
      expect(await second, isA<ReadLatestNoScreenshot>());

      // A context change moves the context.
      final moved = session.readLatest();
      await script.called;
      session.updateMapContext(_map('shoreline'), ++content);
      script.answer(result);
      expect(
        await moved,
        isA<ReadLatestSuperseded>(),
        reason: 'context $result',
      );
      expect(session.state.readingLatest, isFalse);
    }

    // A watched screenshot advances the order without changing the context.
    final raced = session.readLatest();
    await script.called;
    script.emit(
      SavedScreenshot(
        path: 'watched.png',
        modifiedAt: now.add(const Duration(minutes: 1)),
        bytes: Uint8List.fromList([1]),
        contentId: 'w',
      ),
    );
    script.answer(const ScreenshotUnavailable());
    expect(await raced, isA<ReadLatestSuperseded>(), reason: 'watched');

    // Closing supersedes whatever the watcher returned.
    for (final result in results) {
      final fresh = await scripted();
      final read = session.readLatest();
      await fresh.called;
      final closing = session.close();
      fresh.answer(result);
      expect(await read, isA<ReadLatestSuperseded>(), reason: 'closed $result');
      await closing;
    }
    expect(await session.readLatest(), isA<ReadLatestSuperseded>());
  });

  test('map-controls: Raid match time follows the panel highlights', () async {
    await session.close();
    final panels = [
      RaidPanelEvidence(
        state: RaidPanelState.recognized,
        extractNames: ['Fixture exit'],
      ),
      RaidPanelEvidence(state: RaidPanelState.partial),
      RaidPanelEvidence(state: RaidPanelState.empty),
    ];
    session = MapSessionController(
      settings: settings,
      clock: () => now,
      screenshotWatcher: ScreenshotDirectoryWatcher(
        stabilityDelay: Duration.zero,
      ),
      recognize: (_) async => panels.removeAt(0),
    );
    await session.initialize();
    final map = _map('shoreline');
    session.updateMapContext(map, 1);
    expect(session.raidMatchedAt, isNull);

    // The value is the screenshot's time, not the clock's.
    await screenshot(1);
    await session.readLatest();
    final first = now.add(const Duration(minutes: 1));
    expect(session.state.raidHighlightIds, {'shoreline-exit'});
    expect(session.raidMatchedAt, first);

    // The re-match on a marker change reads no new screenshot.
    session.updateMapContext(
      map,
      2,
      activeMarkers: [_exitMarker('refreshed-exit', 'Fixture exit')],
    );
    expect(session.state.raidHighlightIds, {'refreshed-exit'});
    expect(session.raidMatchedAt, first);

    // A later screenshot with no panel keeps the earlier match and its time.
    await screenshot(2);
    await session.readLatest();
    expect(session.state.raidEvidence!.state, RaidPanelState.partial);
    expect(session.raidMatchedAt, first);

    // An empty panel replaces the match, and its time.
    await screenshot(3);
    await session.readLatest();
    expect(session.state.raidHighlightIds, isEmpty);
    expect(session.raidMatchedAt, now.add(const Duration(minutes: 3)));

    // Invalidation clears it.
    await settings.setMap('woods');
    expect(session.raidMatchedAt, isNull);
  });
}

class _ScriptedWatcher extends ScreenshotDirectoryWatcher {
  final List<Completer<ScreenshotRead>> _reads = [];
  Completer<void> _called = Completer<void>();
  final StreamController<SavedScreenshot> _emitted =
      StreamController<SavedScreenshot>.broadcast(sync: true);

  /// Completes when the next read starts.
  Future<void> get called => _called.future;

  @override
  Stream<SavedScreenshot> get screenshots => _emitted.stream;

  @override
  Future<ScreenshotRead> readLatest() {
    final read = Completer<ScreenshotRead>();
    _reads.add(read);
    _called.complete();
    _called = Completer<void>();
    return read.future;
  }

  /// Answers the newest unanswered read, or read number [call] since reset.
  void answer(ScreenshotRead result, {int? call}) {
    final read = call == null
        ? _reads.lastWhere((read) => !read.isCompleted)
        : _reads[call];
    read.complete(result);
    if (_reads.every((read) => read.isCompleted)) _reads.clear();
  }

  void emit(SavedScreenshot saved) => _emitted.add(saved);
}

Future<void> _until(
  MapSessionController session,
  bool Function() condition,
) async {
  if (condition()) return;
  final completer = Completer<void>();
  void changed() {
    if (condition() && !completer.isCompleted) completer.complete();
  }

  session.addListener(changed);
  try {
    await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    session.removeListener(changed);
  }
}

PreparedMarker _exitMarker(String id, String name) => PreparedMarker(
  id: id,
  category: 'extracts',
  filterKey: 'SharedExtracts',
  name: name,
  position: GamePoint(1, 2),
  details: const {},
  source: const {},
  outline: const [],
);

PreparedMap _map(String id) => PreparedMap.fromJson({
  'id': id,
  'name': id,
  'kind': 'raster',
  'geometry': {
    'bounds': [
      [0, 0],
      [256, 256],
    ],
    'rotation': 0,
    'affine': [1, 0, 1, 256],
    'projection': 'native-pixels',
    'nativeZoom': 0,
    'pinFrame': id == 'thelab' ? 'labs-native-normalized' : 'legacy-normalized',
    'coordinateRevision': id == 'thelab' ? 1 : 0,
  },
  'artworkFrame': {
    'width': 256,
    'height': 256,
    'nativeTilePixels': 256,
    'tileStride': 256,
    'tileImageExtent': 256,
  },
  'displayCrop': {'left': 0, 'top': 0, 'right': 256, 'bottom': 256},
  'floors': [
    {
      'id': 'ground',
      'base': true,
      'manual': true,
      'exclusive': false,
      'attachedIds': <String>[],
      'artwork': {
        'tiles': [
          {'x': 0, 'y': 0, 'empty': false, 'path': 'base.png'},
        ],
      },
    },
  ],
  'markers': [
    {
      'id': '$id-exit',
      'name': 'Fixture exit',
      'category': 'extracts',
      'position': {'x': 1, 'z': 2},
      'details': <String, dynamic>{},
      'source': <String, dynamic>{},
    },
  ],
  'labels': <Object>[],
  'attribution': {'author': 'Synthetic saved-evidence behavior fixture'},
}, assetRoot: 'fixture/');
