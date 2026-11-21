import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/audio_port.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/local_progress_store.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/fake_audio_port.dart';

Future<void> _whenMapSession(
  AppServices services,
  bool Function() predicate,
) async {
  if (predicate()) return;
  final complete = Completer<void>();
  void changed() {
    if (predicate() && !complete.isCompleted) complete.complete();
  }

  services.mapSession.addListener(changed);
  try {
    changed();
    await complete.future.timeout(const Duration(seconds: 5));
  } finally {
    services.mapSession.removeListener(changed);
  }
}

/// A database whose stored-catalog reads can be held per mode.
class _DelayedCatalogDatabase extends BlackgridDatabase {
  _DelayedCatalogDatabase() : super(NativeDatabase.memory());

  /// Whether stored-catalog reads wait for the test.
  bool hold = false;
  final reads = <GameMode, Completer<CatalogSnapshot?>>{};
  final _entered = <GameMode, Completer<void>>{};

  /// Completes when a held read for [mode] starts waiting.
  Future<void> entered(GameMode mode) =>
      (_entered[mode] ??= Completer<void>()).future;

  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) {
    if (!hold) return super.loadCatalog(mode);
    final gate = reads[mode] = Completer<CatalogSnapshot?>();
    final signal = _entered[mode] ??= Completer<void>();
    if (!signal.isCompleted) signal.complete();
    return gate.future;
  }
}

void main() {
  /// Services in PvP with the fixture catalog, whose `task-a` has the counter
  /// objective `find-a`, and the manual projection attached.
  Future<AppServices> questServices() async {
    final services = AppServices(
      database: BlackgridDatabase(NativeDatabase.memory()),
      clock: () => fixtureNow,
      client: MockClient((request) async => http.Response('', 503)),
    );
    addTearDown(services.dispose);
    await services.settings.save(AppSettings(mode: GameMode.pvp));
    await services.mapSession.initialize();
    await services.localProgress.ready;
    await services.catalog.setMode(GameMode.pvp);
    services.catalog.snapshot = fixtureCatalog();
    services.manualProgress.attach();
    addTearDown(services.manualProgress.detach);
    return services;
  }

  /// Completes once [ready] holds for the manual projection.
  Future<void> whenProjected(
    AppServices services,
    bool Function() ready,
  ) async {
    if (ready()) return;
    final done = Completer<void>();
    void check() {
      if (ready() && !done.isCompleted) done.complete();
    }

    services.manualProgress.addListener(check);
    try {
      await done.future.timeout(const Duration(seconds: 5));
    } finally {
      services.manualProgress.removeListener(check);
    }
  }

  test('quest progress and the marker filter work offline', () async {
    final services = await questServices();

    await services.manualProgress.setTaskState(
      'task-a',
      ProgressTaskStatus.started,
    );
    await services.manualProgress.setObjectiveComplete('find-a', true);
    await services.localProgress.settled;
    await whenProjected(
      services,
      () =>
          services.manualProgress.questMarkerFilter?.doneObjectiveIds.contains(
            'find-a',
          ) ??
          false,
    );

    final filter = services.manualProgress.questMarkerFilter!;
    expect(filter.startedTaskIds, {'task-a'});
    expect(filter.doneObjectiveIds, {'find-a'});
    final task = services.manualProgress.questChecklist().tasks.single;
    expect(task.id, 'task-a');
    expect(
      task.objectives.firstWhere((objective) => objective.id == 'find-a').done,
      isTrue,
    );
  });

  test(
    'local progress subscribes before the first log bind and is disposed',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'blackgrid-task-progress-',
      );
      final folder = await Directory(
        '${root.path}/log_2026.10.31_22-00-00_1.3.0.0.48484',
      ).create();
      await File('${folder.path}/application_000.log').writeAsString(
        '2026-10-31 22:00:10.000|1.3.0.0.48484|Info|application|Session mode: Pve\n',
      );
      await File('${folder.path}/push-notifications_000.log').writeAsString(
        '2026-10-31 22:01:00.000|1.3.0.0.48484|Info|push-notifications|'
        'Got notification | ChatMessageReceived\n'
        '${const JsonEncoder.withIndent('  ').convert({
          'type': 'new_message',
          'message': {'type': 10, 'templateId': 'first-task description'},
        })}\n',
      );
      final database = BlackgridDatabase(NativeDatabase.memory());
      final services = AppServices(
        database: database,
        client: MockClient((request) async => http.Response('', 503)),
      );
      var disposed = false;
      addTearDown(() async {
        if (!disposed) await services.dispose();
        await root.delete(recursive: true);
      });
      await services.settings.save(AppSettings(gameLogDirectory: root.path));
      await services.initialize();
      await services.localProgress.settled;

      final wipe = services.localProgress.wipes[GameMode.pve]!;
      final history = await database.readProgressHistory(wipe.scope);
      expect(history, isA<ProgressSuccess<ProgressHistoryPage>>());
      final events =
          (history as ProgressSuccess<ProgressHistoryPage>).value.events;
      expect(events, hasLength(1));
      expect(events.single.target.id, 'first-task');
      expect(
        events.single.value,
        const ProgressTaskState(ProgressTaskStatus.started),
      );

      await services.dispose();
      disposed = true;
      expect(
        () => services.localProgress.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );
    },
  );
  test('a finished raid in the logs starts the active mode cooldown', () async {
    final root = await Directory.systemTemp.createTemp('blackgrid-timers-');
    final folder = await Directory(
      '${root.path}/log_2026.10.31_22-00-00_1.3.0.0.48484',
    ).create();
    String line(String log, String message, String time) =>
        '2026-10-31 $time|1.3.0.0.48484|Info|$log|$message\n';
    await File('${folder.path}/application_000.log').writeAsString(
      line('application', 'Session mode: Pve', '22:00:10.000') +
          line(
            'application',
            'PrepareSelectedProfileLocally ProfileId:aaaa AccountId:1',
            '22:00:30.000',
          ) +
          line('application', 'Matching with group id: 1', '22:02:00.000') +
          line('application', 'GameStarted: 7', '22:03:00.000'),
    );
    await File('${folder.path}/backend_000.log').writeAsString(
      line(
        'backend',
        'WebSocketSharp - binary message received: type=Notification, '
            'trackingId=t1, payloadType=userMatchOver, payloadLength=393',
        '22:09:04.000',
      ),
    );
    final services = AppServices(
      database: BlackgridDatabase(NativeDatabase.memory()),
      client: MockClient((request) async => http.Response('', 503)),
    );
    addTearDown(() async {
      await services.dispose();
      await root.delete(recursive: true);
    });
    await services.settings.save(AppSettings(gameLogDirectory: root.path));
    await services.initialize();

    expect(services.catalog.mode, GameMode.pve);
    expect(
      services.settings.effectiveScavCooldownStarts[GameMode.pve],
      DateTime(2026, 10, 31, 22, 9, 4),
    );
  });
  test(
    'the alerts controller hears the first log replay and is disposed',
    () async {
      final root = await Directory.systemTemp.createTemp('blackgrid-alerts-');
      final folder = await Directory(
        '${root.path}/log_2026.10.31_22-00-00_1.3.0.0.48484',
      ).create();
      String line(String message, String time) =>
          '2026-10-31 $time|1.3.0.0.48484|Info|application|$message\n';
      await File('${folder.path}/application_000.log').writeAsString(
        line('Session mode: Pve', '22:00:10.000') +
            line(
              'PrepareSelectedProfileLocally ProfileId:aaaa AccountId:1',
              '22:00:30.000',
            ) +
            line('Matching with group id: 1', '22:01:00.000') +
            line('MatchingCompleted: 1', '22:02:30.000'),
      );
      final audio = FakeAudioPort()..autoComplete = const AudioOk();
      final services = AppServices(
        database: BlackgridDatabase(NativeDatabase.memory()),
        client: MockClient((request) async => http.Response('', 503)),
        // Two seconds after the match was found: only that line is fresh.
        clock: () => DateTime(2026, 10, 31, 22, 2, 32),
        audioPort: audio,
      );
      var disposed = false;
      addTearDown(() async {
        if (!disposed) await services.dispose();
        await root.delete(recursive: true);
      });
      await services.settings.save(AppSettings(gameLogDirectory: root.path));
      await services.initialize();
      await pumpEventQueue();

      // Built before the first bind: the replay reached the controller.
      expect(audio.playCalls.map((call) => call.args['text']), [
        'Match found',
      ]);

      await services.dispose();
      disposed = true;
      await pumpEventQueue();
      expect(audio.calls.last.method, 'stop');
      expect(
        () => services.alerts.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );
    },
  );
  test('the local stats controller is built and disposed with the services', () async {
    final services = AppServices(
      database: BlackgridDatabase(NativeDatabase.memory()),
      client: MockClient((request) async => http.Response('', 503)),
    );
    // Built: a live controller accepts listeners and follows the catalog mode.
    services.localStats.addListener(() {});
    expect(
      services.localStats.modeKnown,
      services.catalog.mode != GameMode.unknown,
    );

    await services.dispose();

    // Disposed: a disposed ChangeNotifier refuses new listeners.
    expect(
      () => services.localStats.addListener(() {}),
      throwsA(isA<FlutterError>()),
    );
  });
  test(
    'saved log context outranks fallback without overwriting manual settings',
    () async {
      final root = await Directory.systemTemp.createTemp('blackgrid-m5-app-');
      final first = await Directory('${root.path}/first/log_2026.10.07_0-52-00')
          .create(recursive: true);
      await File('${first.path}/2026.10.07 application.log').writeAsString(
        'Session mode: Pve\r\n'
        'application|scene preset path:maps/laboratory.bundle\r\n',
      );
      // Records every request. Catalog datasets are answered, so the automatic
      // refresh runs.
      final wire = wireFixture();
      final requests = <http.Request>[];
      final services = AppServices(
        database: BlackgridDatabase(NativeDatabase.memory()),
        clock: () => fixtureNow,
        client: MockClient((request) async {
          requests.add(request);
          final key = request.url.pathSegments.last;
          return wire.containsKey(key)
              ? http.Response(jsonEncode(wire[key]), 200)
              : http.Response('{}', 404);
        }),
      );
      addTearDown(() async {
        await services.dispose();
        await root.delete(recursive: true);
      });
      await services.settings.save(
        AppSettings(
          mode: GameMode.pvp,
          selectedMap: 'woods',
          gameLogDirectory: '${root.path}/first',
        ),
      );
      await services.initialize();
      expect(services.maps.selectedMapId, 'thelab');
      expect(services.catalog.mode, GameMode.pve);
      expect(services.progress.mode, GameMode.pve);
      expect(services.settings.settings.selectedMap, 'woods');
      expect(services.settings.settings.mode, GameMode.pvp);

      await services.settings.setMarker('PmcExtracts', false);
      expect(services.maps.selectedMapId, 'thelab');
      await services.settings.setMap('shoreline');
      expect(services.maps.selectedMapId, 'shoreline');
      expect(services.settings.settings.followGameLogs, isFalse);
      expect(services.catalog.mode, GameMode.pve);

      await services.settings.setMapInputs(followGameLogs: true);
      expect(services.maps.selectedMapId, 'thelab');
      expect(services.settings.settings.selectedMap, 'shoreline');
      expect(await services.setMode(GameMode.seasonal), isTrue);
      expect(services.catalog.mode, GameMode.pve);
      expect(services.settings.settings.mode, GameMode.seasonal);

      final second = await Directory(
        '${root.path}/second/log_2026.10.07_1-00-00',
      ).create(recursive: true);
      await File('${second.path}/2026.10.07 application.log')
          .writeAsString('application|scene preset path:maps/woods.bundle\n');
      final rebound = _whenMapSession(
        services,
        () => services.mapSession.state.detectedMapId == 'woods',
      );
      await services.settings.setMapInputs(
        gameLogDirectory: '${root.path}/second',
      );
      await rebound;
      expect(services.maps.selectedMapId, 'woods');
      expect(services.catalog.mode, GameMode.seasonal);
      expect(services.progress.mode, GameMode.seasonal);
      expect(services.settings.settings.selectedMap, 'shoreline');
      expect(services.scans.hasAcceptedScan, isFalse);
      // Which catalog routes were fetched depends on whether the cached load
      // or the log read finishes first, so only the hosts are asserted.
      await services.automaticRefreshes;
      expect(requests, isNotEmpty);
      expect(requests.map((r) => r.url.host), everyElement('json.tarkov.dev'));
    },
  );
  test(
    'review 1 rejected busy preference cannot cancel a durable mode transition',
    () async {
      final database = _DelayedCatalogDatabase();
      final services = AppServices(
        database: database,
        client: MockClient((r) async => http.Response('', 503)),
      );
      addTearDown(services.dispose);
      await services.initialize();
      database.hold = true;
      final first = services.setMode(GameMode.pve);
      expect(await services.setMode(GameMode.pvp), isFalse);
      await database.entered(GameMode.pve);
      expect(services.catalog.mode, GameMode.pve);
      expect(services.progress.mode, GameMode.pve);
      database.reads[GameMode.pve]!.complete(null);
      expect(await first, isTrue);
      expect(services.settings.settings.mode, GameMode.pve);
      expect(services.catalog.mode, GameMode.pve);
    },
  );
  test(
    'review 1 obsolete catalog read cannot restore catalog activity mode',
    () async {
      final database = _DelayedCatalogDatabase();
      final services = AppServices(
        database: database,
        client: MockClient((r) async => http.Response('', 503)),
      );
      addTearDown(services.dispose);
      await services.initialize();
      database.hold = true;
      final first = services.setMode(GameMode.pve);
      await database.entered(GameMode.pve);
      final second = services.setMode(GameMode.pvp);
      await database.entered(GameMode.pvp);
      database.reads[GameMode.pvp]!.complete(null);
      await second;
      database.reads[GameMode.pve]!.complete(null);
      await first;
      expect(services.settings.settings.mode, GameMode.pvp);
      expect(services.progress.mode, GameMode.pvp);
      expect(services.catalog.mode, GameMode.pvp);
      expect(services.selection.inspectionMode, GameMode.pvp);
    },
  );
}
