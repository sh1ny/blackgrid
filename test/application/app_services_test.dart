import 'dart:async';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/credential_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
