import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:blackgrid/data/tracker_client.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/progress.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/stalling_http_client.dart';

Map<String, Object?> tokenWire(String token, {GameMode mode = GameMode.pvp}) =>
    {
      'success': true,
      'permissions': ['GP'],
      'token': token,
      'owner': 'synthetic-owner',
      'note': 'Synthetic',
      'calls': 0,
      'gameMode': mode.trackerMode,
    };

void main() {
  const token = 'PVP_synthetic-fixture-only';
  for (final path in ['token', 'progress']) {
    for (final body in [false, true]) {
      testWidgets(
        'review 2 Tracker $path ${body ? 'body' : 'headers'} stall releases and next fetch works',
        (tester) async {
          final transport = StallingHttpClient(
            stallPath: path,
            body: body,
            responses: {'token': tokenWire(token), 'progress': progressWire()},
          );
          addTearDown(transport.close);
          final c = TrackerClient(client: transport, clock: () => fixtureNow);
          Object? failure;
          var finished = false;
          final pending = c
              .fetch(mode: GameMode.pvp, token: token, credentialSession: 1)
              .then(
                (_) {
                  finished = true;
                },
                onError: (Object error) {
                  failure = error;
                  finished = true;
                },
              );
          await tester.pump();
          await tester.pump(const Duration(seconds: 31));
          expect(finished, isTrue);
          expect(
            failure,
            isA<TrackerException>().having(
              (e) => e.failure,
              'safe failure',
              TrackerFailure.unavailable,
            ),
          );
          expect(transport.aborts, 1);
          await pending;
          transport.stall = false;
          final next = await c.fetch(
            mode: GameMode.pvp,
            token: token,
            credentialSession: 1,
          );
          expect(next.mode, GameMode.pvp);
        },
      );
    }
  }
  TrackerClient client({
    Map<String, dynamic>? progress,
    Map<String, Object?>? tokenInfo,
    int progressStatus = 200,
    int tokenStatus = 200,
    Map<String, String> headers = const {},
    List<http.Request>? requests,
  }) => TrackerClient(
    client: MockClient((r) async {
      requests?.add(r);
      return r.url.path == '/token'
          ? http.Response(
              jsonEncode(tokenInfo ?? tokenWire(token)),
              tokenStatus,
              headers: headers,
            )
          : http.Response(
              progressStatus == 304
                  ? ''
                  : jsonEncode(progress ?? progressWire()),
              progressStatus,
              headers: headers,
            );
    }),
    clock: () => fixtureNow,
  );
  Future<ProgressSnapshot> fetch(
    TrackerClient c, {
    ProgressSnapshot? previous,
  }) => c.fetch(
    mode: GameMode.pvp,
    token: token,
    credentialSession: 1,
    previous: previous,
  );
  test('current OpenAPI successful GET-only fixed host headers and memory snapshot', () async {
    final requests = <http.Request>[];
    final p = await fetch(
      client(requests: requests, headers: {'etag': 'W/"synthetic"'}),
    );
    expect(p.playerLevel, 30);
    expect(p.parts['part-a']!.count, 1);
    expect(p.observedAt, fixtureNow);
    expect(p.etag, 'W/"synthetic"');
    expect(requests.map((r) => r.url.path), ['/token', '/progress']);
    for (final r in requests) {
      expect(r.method, 'GET');
      expect(r.followRedirects, isFalse);
      expect(r.url.host, 'api.tarkovtracker.org');
      expect(r.url.scheme, 'https');
      expect(r.headers['Authorization'], 'Bearer $token');
      expect(r.headers['User-Agent'], 'Blackgrid/0.1.0');
    }
    expect(() => p.tasks.clear(), throwsUnsupportedError);
  });
  for (final mode in [GameMode.pvp, GameMode.pve, GameMode.seasonal]) {
    test('explicit ${mode.name} prefix and authoritative mode', () async {
      final t =
          '${switch (mode) {
            GameMode.pvp => 'PVP',
            GameMode.pve => 'PVE',
            _ => 'SZN',
          }}_synthetic-only';
      final p = progressWire();
      p['meta']['gameMode'] = mode.trackerMode;
      final c = TrackerClient(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode(r.url.path == '/token' ? tokenWire(t, mode: mode) : p),
            200,
          ),
        ),
        clock: () => fixtureNow,
      );
      expect(
        (await c.fetch(mode: mode, token: t, credentialSession: 1)).mode,
        mode,
      );
    });
  }
  test(
    'unknown/legacy/wrong-prefix/empty-prefix token emits no request',
    () async {
      var requests = 0;
      final c = TrackerClient(
        client: MockClient((r) async {
          requests++;
          return http.Response('', 200);
        }),
      );
      for (final pair in [
        (GameMode.unknown, token),
        (GameMode.pvp, 'tt_synthetic'),
        (GameMode.pvp, 'PVE_synthetic'),
        (GameMode.pvp, 'PVP_'),
      ]) {
        await expectLater(
          c.fetch(mode: pair.$1, token: pair.$2, credentialSession: 1),
          throwsA(isA<TrackerException>()),
        );
      }
      expect(requests, 0);
    },
  );
  final tokenMutations = <String, void Function(Map<String, Object?>)>{
    'GP absent': (j) => j['permissions'] = ['WP'],
    'wrong echo': (j) => j['token'] = 'PVP_other-synthetic',
    'wrong mode': (j) => j['gameMode'] = 'pve',
    'owner missing': (j) => j.remove('owner'),
    'success false': (j) => j['success'] = false,
    'calls malformed': (j) => j['calls'] = -1,
  };
  for (final mutation in tokenMutations.entries) {
    test('${mutation.key} does not authorize', () async {
      final j = tokenWire(token);
      mutation.value(j);
      await expectLater(
        fetch(client(tokenInfo: j)),
        throwsA(isA<TrackerException>()),
      );
    });
  }
  final progressMutations = <String, void Function(Map<String, dynamic>)>{
    'owner mismatch': (j) => j['data']['userId'] = 'synthetic-other',
    'self mismatch': (j) => j['meta']['self'] = 'synthetic-other',
    'mode mismatch': (j) => j['meta']['gameMode'] = 'pve',
    'player missing': (j) => (j['data'] as Map).remove('playerLevel'),
    'player wrong range': (j) => j['data']['playerLevel'] = 80,
    'player fractional': (j) => j['data']['playerLevel'] = 1.5,
    'faction malformed': (j) => j['data']['pmcFaction'] = 'SCAV',
    'edition missing': (j) => (j['data'] as Map).remove('gameEdition'),
    'duplicate task': (j) =>
        (j['data']['tasksProgress'] as List).add(j['data']['tasksProgress'][0]),
    'duplicate objective': (j) => (j['data']['taskObjectivesProgress'] as List)
        .add(j['data']['taskObjectivesProgress'][0]),
    'duplicate module': (j) => (j['data']['hideoutModulesProgress'] as List)
        .add(j['data']['hideoutModulesProgress'][0]),
    'duplicate part': (j) => (j['data']['hideoutPartsProgress'] as List).add(
      j['data']['hideoutPartsProgress'][0],
    ),
    'complete omitted': (j) =>
        (j['data']['tasksProgress'][0] as Map).remove('complete'),
    'complete malformed': (j) => j['data']['tasksProgress'][0]['complete'] = 0,
    'failed malformed': (j) =>
        j['data']['tasksProgress'][0]['failed'] = 'false',
    'invalid malformed': (j) =>
        j['data']['taskObjectivesProgress'][0]['invalid'] = 0,
    'count negative': (j) => j['data']['hideoutPartsProgress'][0]['count'] = -1,
    'count malformed': (j) =>
        j['data']['taskObjectivesProgress'][0]['count'] = 'NaN',
    for (final key in [
      'tasksProgress',
      'taskObjectivesProgress',
      'hideoutModulesProgress',
      'hideoutPartsProgress',
    ])
      'missing $key': (j) => (j['data'] as Map).remove(key),
  };
  for (final mutation in progressMutations.entries) {
    test('${mutation.key} invalidates progress', () async {
      final j = progressWire();
      mutation.value(j);
      await expectLater(
        fetch(client(progress: j)),
        throwsA(isA<TrackerException>()),
      );
    });
  }
  test('empty arrays valid but absent entity unknown; omitted count remains nullable', () async {
    final j = progressWire();
    for (final key in [
      'tasksProgress',
      'taskObjectivesProgress',
      'hideoutModulesProgress',
      'hideoutPartsProgress',
    ]) {
      j['data'][key] = [];
    }
    final p = await fetch(client(progress: j));
    expect(p.tasks['task-a'], isNull);
    expect(p.objectives, isEmpty);
    final omitted = progressWire();
    (omitted['data']['hideoutPartsProgress'][0] as Map).remove('count');
    expect(
      (await fetch(client(progress: omitted))).parts['part-a']!.count,
      isNull,
    );
  });
  for (final status in [401, 403, 302]) {
    test('$status safe error contains no credential/body/owner', () async {
      try {
        await fetch(client(tokenStatus: status));
        fail('Expected error');
      } on TrackerException catch (e) {
        expect(e.toString(), isNot(contains(token)));
        expect(e.toString(), isNot(contains('synthetic-owner')));
      }
    });
  }
  test(
    'same session ETag 304 renews observation only after matching token owner',
    () async {
      final previous = await fetch(client(headers: {'etag': 'W/"synthetic"'}));
      final requests = <http.Request>[];
      final renewed = await fetch(
        client(progressStatus: 304, requests: requests),
        previous: previous,
      );
      expect(renewed.tasks, previous.tasks);
      expect(requests.last.headers['If-None-Match'], previous.etag);
    },
  );
  test(
    '304 without same credential/session snapshot cannot create authority',
    () async {
      await expectLater(
        fetch(client(progressStatus: 304)),
        throwsA(isA<TrackerException>()),
      );
      final previous = await fetch(client(headers: {'etag': 'W/"synthetic"'}));
      await expectLater(
        client(progressStatus: 304).fetch(
          mode: GameMode.pvp,
          token: token,
          credentialSession: 2,
          previous: previous,
        ),
        throwsA(isA<TrackerException>()),
      );
    },
  );
  test(
    'changed verified account invalidates prior same-session result',
    () async {
      final p = await fetch(client(headers: {'etag': 'W/"synthetic"'}));
      final t = tokenWire(token)..['owner'] = 'synthetic-other';
      await expectLater(
        fetch(client(tokenInfo: t), previous: p),
        throwsA(
          isA<TrackerException>().having(
            (e) => e.failure,
            'failure',
            TrackerFailure.identity,
          ),
        ),
      );
    },
  );
  for (final value in <String?>[
    null,
    'not-a-date',
    '0',
    '-1',
    'Tue, 06 Oct 2026 00:01:30 GMT',
    'Mon, 05 Oct 2026 00:00:00 GMT',
  ]) {
    test(
      'review 4 Retry-After $value has a finite recoverable deadline',
      () async {
        final expected = switch (value) {
          '0' => fixtureNow,
          'Tue, 06 Oct 2026 00:01:30 GMT' => fixtureNow.add(
            const Duration(seconds: 90),
          ),
          'Mon, 05 Oct 2026 00:00:00 GMT' => DateTime.utc(2026, 10, 5),
          _ => fixtureNow.add(const Duration(seconds: 60)),
        };
        await expectLater(
          fetch(client(tokenStatus: 429, headers: {'retry-after': ?value})),
          throwsA(
            isA<TrackerException>().having(
              (e) => e.cooldownUntil,
              'finite deadline',
              expected,
            ),
          ),
        );
      },
    );
  }
  test('429 exposes Retry-After without body diagnostic', () async {
    await expectLater(
      fetch(client(tokenStatus: 429, headers: {'retry-after': '90'})),
      throwsA(
        isA<TrackerException>().having(
          (e) => e.cooldownUntil,
          'cooldown',
          fixtureNow.add(const Duration(seconds: 90)),
        ),
      ),
    );
  });
  test('duplicate wire fields cannot overwrite identity checks', () async {
    final c = TrackerClient(
      client: MockClient(
        (r) async => http.Response(
          r.url.path == '/token'
              ? jsonEncode(tokenWire(token)).replaceFirst(
                  '"owner":"synthetic-owner"',
                  '"owner":"synthetic-other","owner":"synthetic-owner"',
                )
              : jsonEncode(progressWire()),
          200,
        ),
      ),
    );
    await expectLater(
      fetch(c),
      throwsA(
        isA<TrackerException>().having(
          (e) => e.failure,
          'failure',
          TrackerFailure.malformed,
        ),
      ),
    );
  });
  test('transport failure is safe typed unavailable', () async {
    final c = TrackerClient(
      client: MockClient(
        (r) async => throw Exception('private $token synthetic-owner'),
      ),
    );
    await expectLater(
      fetch(c),
      throwsA(
        isA<TrackerException>().having(
          (e) => e.toString(),
          'safe message',
          'Tracker transport unavailable',
        ),
      ),
    );
  });
}
