import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:blackgrid/application/progress_controller.dart';
import 'package:blackgrid/data/tracker_client.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/credential_store.dart';
import 'package:blackgrid/domain/progress.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/stalling_http_client.dart';
import '../data/tracker_client_test.dart' show tokenWire;

class MemoryCredentials implements CredentialStore {
  final Map<GameMode, String> credentials = {};
  Object? writeFailure, removalFailure;
  Completer<void>? writeBarrier;
  int reads = 0, writes = 0, removals = 0;
  @override
  Future<String?> readCredential(GameMode mode) async {
    reads++;
    return credentials[mode];
  }

  @override
  Future<void> writeCredential(GameMode mode, String token) async {
    writes++;
    await writeBarrier?.future;
    if (writeFailure != null) throw writeFailure!;
    credentials[mode] = token;
  }

  @override
  Future<void> removeCredential(GameMode mode) async {
    removals++;
    if (removalFailure != null) throw removalFailure!;
    credentials.remove(mode);
  }
}

class ControlledTracker extends TrackerClient {
  ControlledTracker(this.handler)
    : super(client: MockClient((r) async => http.Response('', 500)));
  final Future<ProgressSnapshot> Function(
    GameMode,
    String,
    int,
    ProgressSnapshot?,
  )
  handler;
  int calls = 0;
  @override
  Future<ProgressSnapshot> fetch({
    required GameMode mode,
    required String token,
    required int credentialSession,
    ProgressSnapshot? previous,
  }) {
    calls++;
    return handler(mode, token, credentialSession, previous);
  }
}

ProgressSnapshot response(GameMode mode, int session, {DateTime? at}) =>
    ProgressSnapshot(
      mode: mode,
      credentialSession: session,
      owner: 'synthetic-owner',
      observedAt: at ?? fixtureNow,
      tasks: const {},
      objectives: const {},
      modules: const {},
      parts: const {},
      playerLevel: 30,
      gameEdition: 1,
      faction: 'USEC',
      etag: 'W/"synthetic"',
    );

void main() {
  const token = 'PVP_synthetic-fixture-only';
  testWidgets(
    'review 2 Tracker deadline retains last-good and releases next refresh',
    (tester) async {
      final transport = StallingHttpClient(
        stallPath: 'progress',
        body: true,
        responses: {'token': tokenWire(token), 'progress': progressWire()},
      )..stall = false;
      addTearDown(transport.close);
      final c = ProgressController(
        store: MemoryCredentials()..credentials[GameMode.pvp] = token,
        client: TrackerClient(client: transport, clock: () => fixtureNow),
        clock: () => fixtureNow,
      );
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      await c.refresh();
      final old = c.snapshot;
      transport.stall = true;
      final pending = c.refresh();
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      await pending;
      expect(c.snapshot, same(old));
      expect(c.status, ProgressStatus.stale);
      transport.stall = false;
      await tester.runAsync(c.refresh);
      expect(c.status, ProgressStatus.current);
    },
  );
  test('Unknown sends no requests/credential reads; missing credentials remains unknown', () async {
    final store = MemoryCredentials();
    final client = ControlledTracker((m, t, s, p) async => response(m, s));
    final c = ProgressController(store: store, client: client);
    addTearDown(c.dispose);
    await c.setMode(GameMode.unknown);
    await c.refresh();
    expect(store.reads, 0);
    expect(client.calls, 0);
    expect(c.snapshot, isNull);
    await c.setMode(GameMode.pvp);
    await c.refresh();
    expect(c.status, ProgressStatus.missing);
    expect(client.calls, 0);
  });
  test(
    'restart reads protected credential but never hydrates progress authority',
    () async {
      final store = MemoryCredentials()..credentials[GameMode.pvp] = token;
      final client = ControlledTracker((m, t, s, p) async => response(m, s));
      final first = ProgressController(
        store: store,
        client: client,
        clock: () => fixtureNow,
      );
      await first.setMode(GameMode.pvp);
      await first.refresh();
      expect(first.snapshot, isNotNull);
      first.dispose();
      final second = ProgressController(store: store, client: client);
      addTearDown(second.dispose);
      await second.setMode(GameMode.pvp);
      expect(second.hasCredential, isTrue);
      expect(second.snapshot, isNull);
      expect(second.status, ProgressStatus.stale);
    },
  );
  test('credential replacement invalidates before protected write and publishes only after success', () async {
    final store = MemoryCredentials()..credentials[GameMode.pvp] = token;
    final client = ControlledTracker((m, t, s, p) async => response(m, s));
    final c = ProgressController(
      store: store,
      client: client,
      clock: () => fixtureNow,
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    await c.refresh();
    final version = c.authorityVersion;
    final barrier = Completer<void>();
    store.writeBarrier = barrier;
    final saving = c.saveCredential('PVP_synthetic-replacement');
    expect(c.snapshot, isNull);
    expect(c.authorityVersion, greaterThan(version));
    expect(c.hasCredential, isFalse);
    barrier.complete();
    await saving;
    expect(c.hasCredential, isTrue);
    expect(c.status, ProgressStatus.stale);
    expect(c.snapshot, isNull);
  });
  test('failed replacement preserves old protected bytes but not old progress authority', () async {
    final store = MemoryCredentials()
      ..credentials[GameMode.pvp] = token
      ..writeFailure = StateError('synthetic');
    final c = ProgressController(
      store: store,
      client: ControlledTracker((m, t, s, p) async => response(m, s)),
      clock: () => fixtureNow,
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    await c.refresh();
    await c.saveCredential('PVP_synthetic-replacement');
    expect(store.credentials[GameMode.pvp], token);
    expect(c.snapshot, isNull);
    expect(c.status, ProgressStatus.failed);
  });
  test('invalid credential prefix never writes/request and invalidates immediately', () async {
    final store = MemoryCredentials();
    final client = ControlledTracker((m, t, s, p) async => response(m, s));
    final c = ProgressController(store: store, client: client);
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    await c.saveCredential('PVE_synthetic');
    await c.refresh();
    expect(store.writes, 0);
    expect(client.calls, 0);
    expect(c.status, ProgressStatus.failed);
  });
  for (final failure in [
    TrackerFailure.authentication,
    TrackerFailure.permission,
    TrackerFailure.mode,
    TrackerFailure.identity,
    TrackerFailure.malformed,
  ]) {
    test('$failure invalidates authority, transport retains stale', () async {
      final store = MemoryCredentials()..credentials[GameMode.pvp] = token;
      TrackerFailure? next;
      final c = ProgressController(
        store: store,
        client: ControlledTracker((m, t, s, p) async {
          if (next != null) throw TrackerException(next);
          return response(m, s);
        }),
        clock: () => fixtureNow,
      );
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      await c.refresh();
      next = TrackerFailure.unavailable;
      await c.refresh();
      expect(c.snapshot, isNotNull);
      expect(c.status, ProgressStatus.stale);
      next = failure;
      await c.refresh();
      expect(c.snapshot, isNull);
      expect(c.status, ProgressStatus.failed);
    });
  }
  test(
    'late 200 fenced by token replacement, removal and mode switch',
    () async {
      for (final change in ['replace', 'remove', 'mode']) {
        final store = MemoryCredentials()..credentials[GameMode.pvp] = token;
        final completer = Completer<ProgressSnapshot>();
        var requestedSession = 0;
        final c = ProgressController(
          store: store,
          client: ControlledTracker((m, t, s, p) {
            requestedSession = s;
            return completer.future;
          }),
          clock: () => fixtureNow,
        );
        await c.setMode(GameMode.pvp);
        final pending = c.refresh();
        if (change == 'replace') {
          await c.saveCredential('PVP_synthetic-replacement');
        } else if (change == 'remove') {
          await c.removeCredential();
        } else {
          await c.setMode(GameMode.pve);
        }
        completer.complete(response(GameMode.pvp, requestedSession));
        await pending;
        expect(c.snapshot, isNull);
        expect(c.status, isNot(ProgressStatus.current));
        c.dispose();
      }
    },
  );
  test('late bodyless 304 real adapter fenced by token change', () async {
    final store = MemoryCredentials()..credentials[GameMode.pvp] = token;
    final pending304 = Completer<http.Response>();
    var progressCalls = 0;
    final started = Completer<void>();
    final client = TrackerClient(
      client: MockClient((r) async {
        if (r.url.path == '/token') {
          return http.Response(
            jsonEncode({
              'success': true,
              'permissions': ['GP'],
              'token': r.headers['Authorization']!.substring(7),
              'owner': 'synthetic-owner',
              'note': 'Synthetic',
              'calls': 0,
              'gameMode': 'pvp',
            }),
            200,
          );
        }
        progressCalls++;
        if (progressCalls == 1) {
          return http.Response(
            jsonEncode(progressWire()),
            200,
            headers: {'etag': 'W/"synthetic"'},
          );
        }
        started.complete();
        return pending304.future;
      }),
      clock: () => fixtureNow,
    );
    final c = ProgressController(
      store: store,
      client: client,
      clock: () => fixtureNow,
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    await c.refresh();
    final old = c.refresh();
    await started.future;
    await c.saveCredential('PVP_synthetic-replacement');
    pending304.complete(http.Response('', 304));
    await old;
    expect(c.snapshot, isNull);
    expect(c.status, ProgressStatus.stale);
  });
  test('removal invalidates even when protected deletion fails', () async {
    final store = MemoryCredentials()
      ..credentials[GameMode.pvp] = token
      ..removalFailure = StateError('synthetic');
    final c = ProgressController(
      store: store,
      client: ControlledTracker((m, t, s, p) async => response(m, s)),
      clock: () => fixtureNow,
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    await c.refresh();
    await c.removeCredential();
    expect(c.snapshot, isNull);
    expect(c.hasCredential, isFalse);
    expect(c.status, ProgressStatus.failed);
    expect(store.credentials[GameMode.pvp], token);
  });
  test(
    'mode switch establishes only mode credential and no old authority',
    () async {
      final store = MemoryCredentials()
        ..credentials[GameMode.pvp] = token
        ..credentials[GameMode.pve] = 'PVE_synthetic-only';
      final c = ProgressController(
        store: store,
        client: ControlledTracker((m, t, s, p) async => response(m, s)),
        clock: () => fixtureNow,
      );
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      await c.refresh();
      await c.setMode(GameMode.pve);
      expect(c.snapshot, isNull);
      await c.refresh();
      expect(c.snapshot!.mode, GameMode.pve);
    },
  );
  test('review 4 absent cooldown deadline permits explicit recovery after finite fallback', () async {
    var now = fixtureNow;
    var throttled = true;
    final client = ControlledTracker((m, t, s, p) async {
      if (throttled) throw const TrackerException(TrackerFailure.cooldown);
      return response(m, s, at: now);
    });
    final c = ProgressController(
      store: MemoryCredentials()..credentials[GameMode.pvp] = token,
      client: client,
      clock: () => now,
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    await c.refresh();
    expect(c.cooldown, const Duration(seconds: 60));
    await c.refresh();
    expect(client.calls, 1);
    now = now.add(const Duration(seconds: 60));
    throttled = false;
    await c.refresh();
    expect(client.calls, 2);
    expect(c.status, ProgressStatus.current);
  });
  test('429 cooldown emits no repeated requests; explicit refresh after deadline allowed', () async {
    var now = fixtureNow;
    final store = MemoryCredentials()..credentials[GameMode.pvp] = token;
    var throttled = true;
    final client = ControlledTracker((m, t, s, p) async {
      if (throttled) {
        throw TrackerException(
          TrackerFailure.cooldown,
          cooldownUntil: fixtureNow.add(const Duration(seconds: 90)),
        );
      }
      return response(m, s, at: now);
    });
    final c = ProgressController(
      store: store,
      client: client,
      clock: () => now,
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    await c.refresh();
    expect(c.status, ProgressStatus.cooldown);
    expect(c.cooldown, const Duration(seconds: 90));
    await c.refresh();
    await c.refresh();
    expect(client.calls, 1);
    now = now.add(const Duration(seconds: 90));
    throttled = false;
    await c.refresh();
    expect(client.calls, 2);
    expect(c.status, ProgressStatus.current);
  });
  test(
    'age expiry notifies authority version without network request',
    () async {
      var now = fixtureNow;
      final store = MemoryCredentials()..credentials[GameMode.pvp] = token;
      final client = ControlledTracker((m, t, s, p) async => response(m, s));
      final c = ProgressController(
        store: store,
        client: client,
        clock: () => now,
      );
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      await c.refresh();
      final version = c.authorityVersion;
      now = now.add(const Duration(minutes: 15));
      c.updateAge();
      expect(c.status, ProgressStatus.stale);
      expect(c.authorityVersion, greaterThan(version));
      expect(client.calls, 1);
    },
  );
  testWidgets(
    'session expiry timer notifies selection without manual request',
    (tester) async {
      var now = fixtureNow;
      final store = MemoryCredentials()..credentials[GameMode.pvp] = token;
      final client = ControlledTracker((m, t, s, p) async => response(m, s));
      final c = ProgressController(
        store: store,
        client: client,
        clock: () => now,
      );
      addTearDown(c.dispose);
      await c.setMode(GameMode.pvp);
      await c.refresh();
      final version = c.authorityVersion;
      now = now.add(const Duration(minutes: 15));
      await tester.pump(const Duration(minutes: 15));
      expect(c.status, ProgressStatus.stale);
      expect(c.authorityVersion, greaterThan(version));
      expect(client.calls, 1);
    },
  );
  test('duplicate manual refresh coalesces same credential request', () async {
    final store = MemoryCredentials()..credentials[GameMode.pvp] = token;
    final completer = Completer<ProgressSnapshot>();
    var session = 0;
    final client = ControlledTracker((m, t, s, p) {
      session = s;
      return completer.future;
    });
    final c = ProgressController(
      store: store,
      client: client,
      clock: () => fixtureNow,
    );
    addTearDown(c.dispose);
    await c.setMode(GameMode.pvp);
    final a = c.refresh();
    final b = c.refresh();
    completer.complete(response(GameMode.pvp, session));
    await Future.wait([a, b]);
    expect(client.calls, 1);
  });
}
