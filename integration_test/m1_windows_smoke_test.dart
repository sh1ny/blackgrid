import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/data/credential_store.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/local_paths.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

class MissingReplacementSource implements CredentialProtector {
  const MissingReplacementSource();
  final native = const WindowsCredentialProtector();
  @override
  Future<Uint8List> protect(Uint8List value) => native.protect(value);
  @override
  Future<Uint8List> unprotect(Uint8List value) => native.unprotect(value);
  @override
  Future<void> replace(File source, File target) =>
      native.replace(File('${source.path}.missing'), target);
}

Future<void> requireGameClosed() async {
  // Query only process identity. No game window, pixels, hooks or memory.
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    r'Get-Process | Where-Object { $_.ProcessName -match "^(EscapeFromTarkov(?:_BE)?|EFT)$" } | Select-Object -ExpandProperty ProcessName',
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'Game-closure identity check unavailable.',
  );
  expect(
    (result.stdout as String).trim(),
    isEmpty,
    reason: 'Escape from Tarkov must be closed before native verification.',
  );
}

Future<void> awaitNativeCompletion(bool Function() completed) async {
  final elapsed = Stopwatch()..start();
  while (!completed()) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError(
        'Native durable action did not complete within 10 seconds.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows native DPAPI real catalog UI and close reopen preserve only durable records',
    (tester) async {
      await requireGameClosed();
      final paths = await LocalPaths.resolve();
      final directory = await Directory('${paths.root.path}/verification')
          .create(recursive: true);
      final run = await directory.createTemp('m1-native-');
      AppServices? active;
      addTearDown(() async {
        await active?.dispose();
        if (await run.exists()) await run.delete(recursive: true);
      });
      final credentialsDirectory = await Directory('${run.path}/credentials')
          .create();
      final credentials = DpapiCredentialStore(credentialsDirectory);
      const synthetic = 'PVP_SYNTHETIC_DPAPI_ROUNDTRIP_NOT_A_REAL_TOKEN';
      await credentials.writeCredential(GameMode.pvp, synthetic);
      expect(await credentials.readCredential(GameMode.pvp), synthetic);
      final file = File('${credentialsDirectory.path}/pvp.dpapi');
      final before = await file.readAsBytes();
      expect(
        utf8.decode(before, allowMalformed: true),
        isNot(contains(synthetic)),
      );
      final failureStore = DpapiCredentialStore(
        credentialsDirectory,
        protector: const MissingReplacementSource(),
      );
      await expectLater(
        failureStore.writeCredential(GameMode.pvp, 'PVP_SYNTHETIC_REPLACEMENT'),
        throwsA(isA<CredentialUnavailable>()),
      );
      expect(await file.readAsBytes(), orderedEquals(before));
      await credentials.removeCredential(GameMode.pvp);
      final databaseFile = File('${run.path}/blackgrid.sqlite');
      var services = AppServices(
        database: BlackgridDatabase.open(databaseFile),
        credentials: credentials,
        client: http.Client(),
      );
      active = services;
      await services.initialize();
      expect(services.catalog.mode, GameMode.unknown);
      await services.setMode(GameMode.pvp);
      await services.catalog.refresh();
      expect(services.catalog.snapshot, isNotNull);
      await requireGameClosed();
      await tester.pumpWidget(BlackgridApp(services: services));
      await tester.pumpAndSettle();
      await requireGameClosed();
      await tester.tap(find.byKey(const Key('nav-scanner')));
      await tester.pumpAndSettle();
      final item = services.catalog.snapshot!.items.values.firstWhere(
        (i) => i.name.isNotEmpty,
      );
      await requireGameClosed();
      await tester.enterText(find.byType(TextField), item.id);
      await tester.pumpAndSettle();
      await requireGameClosed();
      await tester.tap(find.widgetWithText(ListTile, item.name));
      await awaitNativeCompletion(() => services.history.rows.isNotEmpty);
      await tester.pumpAndSettle();
      expect(services.selection.item!.id, item.id);
      expect(services.history.rows.single.itemId, item.id);
      await requireGameClosed();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Yes'));
      await tester.pumpAndSettle();
      expect(services.selection.fir, FirState.yes);
      await requireGameClosed();
      await tester.tap(find.byKey(const Key('nav-map')));
      await tester.pumpAndSettle();
      expect(find.text('No accepted scan this session'), findsOneWidget);
      await services.settings.savePin(
        CustomPin(
          id: 'native-synthetic-pin',
          mapId: 'shoreline',
          x: -.2,
          y: 1.3,
          frame: 'legacy-normalized',
          frameRevision: 0,
          label: 'Native smoke pin',
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Native smoke pin'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await services.dispose();
      await requireGameClosed();
      services = AppServices(
        database: BlackgridDatabase.open(databaseFile),
        credentials: credentials,
        client: http.Client(),
      );
      active = services;
      await services.initialize();
      expect(services.catalog.mode, GameMode.pvp);
      expect(services.history.rows.single.itemId, item.id);
      expect(services.settings.pins.single.id, 'native-synthetic-pin');
      expect(services.selection.fir, FirState.unknown);
      expect(services.selection.selectedId, isNull);
      expect(services.progress.snapshot, isNull);
      expect(services.scans.hasAcceptedScan, isFalse);
      await requireGameClosed();
      await tester.pumpWidget(BlackgridApp(services: services));
      await tester.pumpAndSettle();
      expect(find.text('Native smoke pin'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await services.dispose();
      await run.delete(recursive: true);
    },
  );
}
