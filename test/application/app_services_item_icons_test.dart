import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/item_icon_cache.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/item_icon_client.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/credential_store.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../fixtures/m1/catalog/fixture.dart';

const _iconHost = 'assets.tarkov.dev';
const _iconLink = 'https://assets.tarkov.dev/item-a-icon.webp';

class _NoCredentials implements CredentialStore {
  @override
  Future<String?> readCredential(GameMode mode) async => null;
  @override
  Future<void> writeCredential(GameMode mode, String token) async {}
  @override
  Future<void> removeCredential(GameMode mode) async {}
}

/// Serves the catalog fixture and records every request.
class _RecordingClient extends http.BaseClient {
  _RecordingClient() : _wire = wireFixture();

  final Map<String, dynamic> _wire;
  final requests = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final key = request.url.pathSegments.last;
    final body = _wire.containsKey(key) ? jsonEncode(_wire[key]) : '{}';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      _wire.containsKey(key) ? 200 : 404,
    );
  }

  bool get sentIconRequest => requests.any((u) => u.host == _iconHost);
}

/// An icon request that never answers; it records abort and close in order.
class _StallingIconClient extends http.BaseClient {
  final events = <String>[];
  final iconRequestSent = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.host != _iconHost) {
      return Future.value(http.StreamedResponse(const Stream.empty(), 404));
    }
    final pending = Completer<http.StreamedResponse>();
    if (request is http.Abortable) {
      unawaited(
        request.abortTrigger?.then((_) {
          events.add('abort');
          if (!pending.isCompleted) {
            pending.completeError(http.RequestAbortedException());
          }
        }),
      );
    }
    events.add('send');
    iconRequestSent.complete();
    return pending.future;
  }

  @override
  void close() => events.add('close');
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('blackgrid-icons-app-');
  });

  tearDown(() => root.delete(recursive: true));

  test('committing a catalog with icon links sends no icon request', () async {
    final client = _RecordingClient();
    final database = BlackgridDatabase(NativeDatabase.memory());
    final services = AppServices(
      database: database,
      credentials: _NoCredentials(),
      clock: () => fixtureNow,
      client: client,
      itemIcons: ItemIconCache(
        database: database,
        client: ItemIconClient(client: client),
        directory: Directory('${root.path}/item-icons'),
      ),
    );
    addTearDown(services.dispose);
    await services.settings.save(
      AppSettings(mode: GameMode.pvp, selectedMap: 'woods'),
    );

    await services.initialize();
    await services.automaticRefreshes;

    expect(services.catalog.status, CatalogStatus.current);
    expect(services.catalog.snapshot?.items['item-a']?.iconLink, _iconLink);
    expect(client.requests, isNotEmpty);
    expect(client.sentIconRequest, isFalse);
  });

  test('AppServices without itemIcons uses the disabled cache', () async {
    final client = _RecordingClient();
    final services = AppServices(
      database: BlackgridDatabase(NativeDatabase.memory()),
      credentials: _NoCredentials(),
      clock: () => fixtureNow,
      client: client,
    );
    addTearDown(services.dispose);
    await services.initialize();

    final lease = services.itemIcons.acquire('item-a', _iconLink);
    addTearDown(lease.release);

    expect(lease.value, const GenericItemIcon());
    expect(client.sentIconRequest, isFalse);
  });

  test(
    'dispose aborts an in-flight icon request before the client closes',
    () async {
      final client = _StallingIconClient();
      final database = BlackgridDatabase(NativeDatabase.memory());
      final services = AppServices(
        database: database,
        credentials: _NoCredentials(),
        clock: () => fixtureNow,
        client: client,
        itemIcons: ItemIconCache(
          database: database,
          client: ItemIconClient(client: client),
          directory: Directory('${root.path}/item-icons'),
        ),
      );
      await services.initialize();
      services.itemIcons.acquire('item-a', _iconLink);
      await client.iconRequestSent.future;

      await services.dispose();

      expect(client.events, ['send', 'abort', 'close']);
    },
  );
}
