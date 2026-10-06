import 'dart:convert';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/credential_store.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';

class MemoryCredentials implements CredentialStore {
  final values = <GameMode, String>{};
  @override
  Future<String?> readCredential(GameMode mode) async => values[mode];
  @override
  Future<void> writeCredential(GameMode mode, String token) async {
    values[mode] = token;
  }

  @override
  Future<void> removeCredential(GameMode mode) async {
    values.remove(mode);
  }
}

class M1Harness {
  M1Harness({BlackgridDatabase? database}) {
    final wire = wireFixture();
    db = database ?? BlackgridDatabase(NativeDatabase.memory());
    services = AppServices(
      database: db,
      credentials: credentials,
      clock: () => fixtureNow,
      client: MockClient((request) async {
        requests.add(request);
        if (failNetwork) return http.Response('synthetic unavailable', 503);
        final key = request.url.pathSegments.last;
        if (wire.containsKey(key)) {
          return http.Response(jsonEncode(wire[key]), 200);
        }
        return http.Response('{}', 404);
      }),
    );
  }
  late final BlackgridDatabase db;
  late final AppServices services;
  final credentials = MemoryCredentials();
  final requests = <http.Request>[];
  bool failNetwork = false;
  Future<void> initialize({
    GameMode mode = GameMode.pvp,
    bool refresh = true,
  }) async {
    await services.initialize();
    await services.setMode(mode);
    if (refresh && mode != GameMode.unknown) await services.catalog.refresh();
  }

  Future<void> dispose() => services.dispose();
}
