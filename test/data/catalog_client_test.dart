import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/domain/catalog.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/stalling_http_client.dart';

void main() {
  for (final path in ['items', 'items_en']) {
    for (final body in [false, true]) {
      testWidgets(
        'review 2 catalog $path ${body ? 'body' : 'headers'} stall releases and next fetch works',
        (tester) async {
          final transport = StallingHttpClient(
            stallPath: path,
            body: body,
            responses: wireFixture(),
          );
          addTearDown(transport.close);
          final client = CatalogClient(
            client: transport,
            clock: () => fixtureNow,
          );
          var finished = false;
          Object? failure;
          final fetch = client
              .fetch(GameMode.pvp)
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
          // Dictionary failure continues normalization outside FakeAsync.
          if (path.endsWith('_en')) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 200)),
            );
            await tester.pump();
          }
          expect(finished, isTrue);
          expect(transport.aborts, 1);
          if (path == 'items') expect(failure, isA<CatalogException>());
          await fetch;
          transport.stall = false;
          final next = await tester.runAsync(() => client.fetch(GameMode.pvp));
          expect(next!.items, isNotEmpty);
        },
      );
    }
  }
  for (final mode in [GameMode.pvp, GameMode.pve, GameMode.seasonal]) {
    test(
      'GET-only fixed-host six datasets and four dictionaries for ${mode.name}',
      () async {
        final requests = <http.Request>[];
        final j = wireFixture();
        final client = CatalogClient(
          client: MockClient((r) async {
            requests.add(r);
            return http.Response(jsonEncode(j[r.url.pathSegments.last]), 200);
          }),
          clock: () => fixtureNow,
        );
        final result = await client.fetch(mode);
        expect(result.mode, mode);
        expect(requests.length, 10);
        expect(requests.map((r) => r.url.pathSegments.first).toSet(), {
          mode.catalogRoute,
        });
        for (final r in requests) {
          expect(r.method, 'GET');
          expect(r.url.host, 'json.tarkov.dev');
          expect(r.url.scheme, 'https');
          expect(r.followRedirects, isFalse);
          expect(r.headers.containsKey('Authorization'), isFalse);
        }
      },
    );
  }
  for (final mode in [GameMode.pvp, GameMode.pve, GameMode.seasonal]) {
    test(
      'production isolate accepts shared-objective wire in ${mode.name}',
      () async {
        final j = sharedObjectiveWireFixture();
        final client = CatalogClient(
          client: MockClient(
            (r) async =>
                http.Response(jsonEncode(j[r.url.pathSegments.last]), 200),
          ),
          clock: () => fixtureNow,
        );
        final c = await client.fetch(mode);
        expect(c.mode, mode);
        expect(c.datasetCounts['tasks'], 3);
        expect(
          c.requirements.where((r) => r.kind == RequirementKind.task).length,
          3,
        );
        expect(c.sourceFreshAt(fixtureNow), isNull);
        expect(c.authoritativeAt(fixtureNow), isFalse);
      },
    );
  }
  test('Unknown performs zero requests', () async {
    var calls = 0;
    final client = CatalogClient(
      client: MockClient((r) async {
        calls++;
        return http.Response('', 200);
      }),
    );
    await expectLater(
      client.fetch(GameMode.unknown),
      throwsA(isA<CatalogException>()),
    );
    expect(calls, 0);
  });
  test(
    'localization HTTP failures do not publish partial six dataset failure',
    () async {
      final j = wireFixture();
      final client = CatalogClient(
        client: MockClient(
          (r) async => r.url.path.endsWith('_en')
              ? http.Response('private body', 503)
              : http.Response(jsonEncode(j[r.url.pathSegments.last]), 200),
        ),
        clock: () => fixtureNow,
      );
      expect((await client.fetch(GameMode.pvp)).localizationErrors.length, 4);
    },
  );
  for (final status in [302, 500]) {
    test('required download $status rejects safely', () async {
      final client = CatalogClient(
        client: MockClient((r) async => http.Response('private body', status)),
      );
      try {
        await client.fetch(GameMode.pvp);
        fail('Expected rejection');
      } on CatalogException catch (e) {
        expect(e.toString(), isNot(contains('private body')));
      }
    });
  }
  test(
    'malformed sixth dataset rejects entire candidate off isolate',
    () async {
      final j = wireFixture();
      final client = CatalogClient(
        client: MockClient(
          (r) async => http.Response(
            r.url.path.endsWith('hideout')
                ? '{invalid'
                : jsonEncode(j[r.url.pathSegments.last]),
            200,
          ),
        ),
      );
      await expectLater(
        client.fetch(GameMode.pvp),
        throwsA(isA<CatalogException>()),
      );
    },
  );
}
