import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/credential_store.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';

class _EmptyCredentials implements CredentialStore {
  @override
  Future<String?> readCredential(GameMode mode) async => null;
  @override
  Future<void> writeCredential(GameMode mode, String token) async {}
  @override
  Future<void> removeCredential(GameMode mode) async {}
}

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

class DelayedCredentials implements CredentialStore {
  final reads = <GameMode, Completer<String?>>{};
  @override
  Future<String?> readCredential(GameMode mode) =>
      (reads[mode] = Completer<String?>()).future;
  @override
  Future<void> writeCredential(GameMode mode, String token) async {}
  @override
  Future<void> removeCredential(GameMode mode) async {}
}

void main() {
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
      // refresh runs. No credential is saved, so the tracker must stay silent.
      final wire = wireFixture();
      final requests = <http.Request>[];
      final services = AppServices(
        database: BlackgridDatabase(NativeDatabase.memory()),
        credentials: _EmptyCredentials(),
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
      // Saved Map inputs must not reach the tracker. Which catalog routes were
      // fetched depends on whether the cached load or the log read finishes
      // first, so only the hosts are asserted.
      await services.automaticRefreshes;
      expect(requests, isNotEmpty);
      expect(requests.map((r) => r.url.host), everyElement('json.tarkov.dev'));
      expect(
        requests.where((r) => r.url.host == 'api.tarkovtracker.org'),
        isEmpty,
      );
    },
  );
  test(
    'review 1 rejected busy preference cannot cancel a durable mode transition',
    () async {
      final credentials = DelayedCredentials();
      final services = AppServices(
        database: BlackgridDatabase(NativeDatabase.memory()),
        credentials: credentials,
        client: MockClient((r) async => http.Response('', 503)),
      );
      addTearDown(services.dispose);
      await services.initialize();
      final first = services.setMode(GameMode.pve);
      expect(await services.setMode(GameMode.pvp), isFalse);
      while (!credentials.reads.containsKey(GameMode.pve)) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(services.catalog.mode, GameMode.pve);
      expect(services.progress.mode, GameMode.pve);
      credentials.reads[GameMode.pve]!.complete(null);
      expect(await first, isTrue);
      expect(services.settings.settings.mode, GameMode.pve);
      expect(services.catalog.mode, GameMode.pve);
    },
  );
  test(
    'review 1 obsolete credential read cannot restore catalog activity mode',
    () async {
      final credentials = DelayedCredentials();
      final services = AppServices(
        database: BlackgridDatabase(NativeDatabase.memory()),
        credentials: credentials,
        client: MockClient((r) async => http.Response('', 503)),
      );
      addTearDown(services.dispose);
      await services.initialize();
      final first = services.setMode(GameMode.pve);
      while (!credentials.reads.containsKey(GameMode.pve)) {
        await Future<void>.delayed(Duration.zero);
      }
      final second = services.setMode(GameMode.pvp);
      while (!credentials.reads.containsKey(GameMode.pvp)) {
        await Future<void>.delayed(Duration.zero);
      }
      credentials.reads[GameMode.pvp]!.complete(null);
      await second;
      credentials.reads[GameMode.pve]!.complete(null);
      await first;
      expect(services.settings.settings.mode, GameMode.pvp);
      expect(services.progress.mode, GameMode.pvp);
      expect(services.catalog.mode, GameMode.pvp);
      expect(services.selection.inspectionMode, GameMode.pvp);
    },
  );
}
