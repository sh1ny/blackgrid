import 'dart:async';

import 'package:blackgrid/application/accepted_scan.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/application/scan_correction.dart';
import 'package:blackgrid/application/selection_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';


import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:drift/native.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/m1_harness.dart';

class _HeldActivityDatabase extends BlackgridDatabase {
  _HeldActivityDatabase() : super(NativeDatabase.memory());
  Completer<void>? gate;
  final entered = Completer<void>();

  @override
  Future<ItemActivity> recordActivity(
    String itemId,
    GameMode mode,
    DateTime time, {
    ActivitySource source = ActivitySource.manual,
    Recommendation? verdict,
  }) async {
    if (gate case final hold?) {
      gate = null;
      entered.complete();
      await hold.future;
    }
    return super.recordActivity(
      itemId,
      mode,
      time,
      source: source,
      verdict: verdict,
    );
  }
}

void main() {
  test('local-data-durability: Each source records its verdict', () async {
    final h = M1Harness();
    addTearDown(h.dispose);
    await h.initialize();
    final s = SelectionController(
      database: h.db,
      catalog: h.services.catalog,
      progress: h.services.progress,
      history: h.services.history,
      clock: () => fixtureNow,
    );
    addTearDown(s.dispose);
    await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
    expect(h.services.history.rows.single.verdict, s.decision!.recommendation);
    await s.selectScan(
      reportId: 1,
      itemId: 'item-b',
      mode: GameMode.pvp,
      catalogRevision: s.catalog.snapshot!.revision,
      epoch: const ScanEpoch(0, 0),
    );
    expect(
      h.services.history.rows.firstWhere((r) => r.itemId == 'item-b').verdict,
      s.decision!.recommendation,
    );
    s.offerCorrection(
      ScanCorrectionOffer(
        reportId: 2,
        epoch: const ScanEpoch(0, 0),
        mode: GameMode.pvp,
        catalogRevision: s.catalog.snapshot!.revision,
        ocrText: '',
        candidates: const [],
        query: '',
      ),
    );
    await s.selectCorrection(2, 'item-a');
    expect(s.correction, isNotNull);
    expect(
      h.services.history.rows.firstWhere((r) => r.itemId == 'item-a').verdict,
      s.decision!.recommendation,
    );
  });

  test('local-data-durability: Later data changes', () async {
    const token = 'PVP_synthetic-fixture-only';
    final h = M1Harness(
      shapeWire: (wire) {
        (wire['tasks']['data']['tasks'] as Map).clear();
        (wire['hideout']['data'] as Map).clear();
        wire['crafts']['data'] = [];
        wire['barters']['data'] = [];
        wire['token'] = {
          'success': true,
          'permissions': ['GP'],
          'token': token,
          'owner': 'synthetic-owner',
          'note': 'Synthetic',
          'calls': 0,
          'gameMode': 'pvp',
        };
        wire['progress'] = progressWire();
      },
    );
    addTearDown(h.dispose);
    h.credentials.values[GameMode.pvp] = token;
    await h.initialize();
    await h.services.progress.refresh();
    final s = h.services.selection;
    await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
    final recorded = h.services.history.rows.single;
    expect(recorded.verdict, isNotNull);
    s.setFir(FirState.yes);
    expect(s.decision!.recommendation, Recommendation.flea);
    expect(s.decision!.recommendation, isNot(recorded.verdict));
    await h.services.catalog.refresh();
    await s.openHistory(recorded);
    expect((await h.db.readActivity()).rows.single.verdict, recorded.verdict);
    expect((await h.db.readActivity()).rows.single.revision, recorded.revision);
  });

  test(
    'pending activity retains its item mode and projected verdict',
    () async {
      final db = _HeldActivityDatabase();
      final h = M1Harness(database: db);
      addTearDown(h.dispose);
      await h.initialize();
      final s = h.services.selection;
      final gate = db.gate = Completer<void>();
      final first = s.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      );
      final verdict = s.decision!.recommendation;
      await db.entered.future;
      await s.selectManual(h.services.catalog.snapshot!.items['item-b']!);
      gate.complete();
      await first;
      final rows = (await db.readActivity()).rows;
      final saved = rows.firstWhere((r) => r.itemId == 'item-a');
      expect(saved.mode, GameMode.pvp);
      expect(saved.verdict, verdict);
      expect(s.selectedId, 'item-b');
    },
  );

  test(
    'local-data-durability: No available decision or failed write',
    () async {
      final h = M1Harness();
      addTearDown(h.dispose);
      await h.initialize();
      final s = h.services.selection;
      await s.selectManual(
        CatalogItem(id: 'missing', name: 'Missing', normalizedName: 'missing'),
      );
      expect(s.decision, isNull);
      expect(h.services.history.rows.single.verdict, isNull);
      await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
      final previous = h.services.history.rows.firstWhere(
        (r) => r.itemId == 'item-a',
      );
      expect(previous.verdict, isNotNull);
      await h.db.customStatement(
        "CREATE TRIGGER activity_failure BEFORE INSERT ON activity_records BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
      expect(s.error, contains('not recorded'));
      final retained = (await h.db.readActivity()).rows.firstWhere(
        (r) => r.itemId == 'item-a',
      );
      expect(retained.verdict, previous.verdict);
      expect(retained.revision, previous.revision);
    },
  );
  test('manual identity activity persists and FIR resets only on new context, never accepted scan', () async {
    final h = M1Harness();
    await h.initialize();
    final s = h.services.selection;
    s.setQuery('item-a');
    expect(s.results.single.id, 'item-a');
    await s.selectManual(s.results.single);
    expect(h.services.history.rows.single.itemId, 'item-a');
    s.setFir(FirState.yes);
    s.setQuery('item');
    expect(s.fir, FirState.yes);
    expect(h.services.scans.hasAcceptedScan, isFalse);
    final same = s.item!;
    await s.selectManual(same);
    expect(s.fir, FirState.unknown);
    s.setFir(FirState.no);
    await h.services.catalog.refresh();
    expect(s.fir, FirState.unknown);
    s.setFir(FirState.yes);
    await h.services.setMode(GameMode.pve);
    expect(s.fir, FirState.unknown);
    expect(h.services.scans.hasAcceptedScan, isFalse);
    await h.dispose();
  });
  test('stored PvE history is separate from live PvP and close returns live selection', () async {
    final h = M1Harness();
    await h.initialize(mode: GameMode.pve);
    await h.services.selection.selectManual(
      h.services.catalog.snapshot!.items['item-a']!,
    );
    final row = h.services.history.rows.single;
    await h.services.setMode(GameMode.pvp);
    await h.services.catalog.refresh();
    await h.services.selection.selectManual(
      h.services.catalog.snapshot!.items['item-b']!,
    );
    await h.services.selection.openHistory(row);
    expect(h.services.selection.inspectionMode, GameMode.pve);
    expect(h.services.catalog.mode, GameMode.pvp);
    expect(h.services.progress.mode, GameMode.pvp);
    expect(h.services.selection.item!.id, 'item-a');
    h.services.selection.setFir(FirState.yes);
    h.services.selection.closeHistory();
    expect(h.services.selection.item!.id, 'item-b');
    expect(h.services.selection.fir, FirState.unknown);
    expect(h.services.scans.hasAcceptedScan, isFalse);
    await h.dispose();
  });
  test('same-mode history follows refreshed authority and clears FIR without creating a scan', () async {
    final h = M1Harness();
    addTearDown(h.dispose);
    await h.initialize();
    final s = h.services.selection;
    await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
    await s.openHistory(h.services.history.rows.single);
    s.setFir(FirState.yes);
    await h.services.catalog.refresh();
    expect(s.fir, FirState.unknown);
    expect(s.inspectionCatalog, same(h.services.catalog.snapshot));
    expect(s.inspectionMode, GameMode.pvp);
    expect(s.historyRow, isNotNull);
    expect(h.services.scans.hasAcceptedScan, isFalse);
  });
  test(
    'unrelated refresh preserves stored-mode FIR but a new live mode clears it',
    () async {
      final h = M1Harness();
      addTearDown(h.dispose);
      await h.initialize(mode: GameMode.pve);
      final s = h.services.selection;
      await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
      final row = h.services.history.rows.single;
      await h.services.setMode(GameMode.pvp);
      await h.services.catalog.refresh();
      await s.openHistory(row);
      final stored = s.inspectionCatalog;
      s.setFir(FirState.yes);
      await h.services.catalog.refresh();
      expect(s.fir, FirState.yes);
      expect(s.inspectionCatalog, same(stored));
      await h.services.setMode(GameMode.seasonal);
      expect(s.fir, FirState.unknown);
      expect(s.inspectionMode, GameMode.pve);
      expect(h.services.catalog.mode, GameMode.seasonal);
      expect(h.services.scans.hasAcceptedScan, isFalse);
    },
  );
  test(
    'failed activity write shows error without fake successful history',
    () async {
      final h = M1Harness();
      await h.initialize();
      await h.db.customStatement(
        "CREATE TRIGGER activity_failure BEFORE INSERT ON activity_records BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      await h.services.selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      );
      expect(h.services.selection.item!.id, 'item-a');
      expect(h.services.selection.error, contains('not recorded'));
      expect(h.services.history.rows, isEmpty);
      expect(h.services.scans.hasAcceptedScan, isFalse);
      await h.dispose();
    },
  );

  group('selectScan', () {
    const epoch = ScanEpoch(0, 0);
    var nextReportId = 0;
    Future<void> scan(SelectionController s, String id) => s.selectScan(
      reportId: ++nextReportId,
      itemId: id,
      mode: GameMode.pvp,
      catalogRevision: s.catalog.snapshot!.revision,
      epoch: epoch,
    );

    test('scan of an item missing from the catalog changes nothing', () async {
      final h = M1Harness();
      addTearDown(h.dispose);
      await h.initialize();
      final s = h.services.selection;
      await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
      var notified = 0;
      s.addListener(() => notified++);

      await scan(s, 'item-missing');

      expect(notified, 0);
      expect(s.selectedId, 'item-a');
      expect(s.scan, isNull);
      expect(h.services.history.rows.map((row) => row.itemId), ['item-a']);
    });

    test('manual selection after a scan stays after refresh', () async {
      final h = M1Harness();
      addTearDown(h.dispose);
      await h.initialize();
      final s = h.services.selection;
      await scan(s, 'item-b');
      expect(s.item!.id, 'item-b');
      expect(s.scan, isNotNull);
      await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
      expect(s.scan, isNull);
      await h.services.catalog.refresh();
      expect(s.selectedId, 'item-a');
      expect(s.scan, isNull);
    });

    test(
      'accepted scan closes an open history row into the live mode',
      () async {
        final h = M1Harness();
        addTearDown(h.dispose);
        await h.initialize();
        final s = h.services.selection;
        await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
        final opening = s.openHistory(h.services.history.rows.single);
        expect(s.loadingHistory, isTrue);
        await scan(s, 'item-b');
        expect(s.loadingHistory, isFalse);
        expect(s.isHistory, isFalse);
        expect(s.item!.id, 'item-b');
        expect(s.inspectionMode, h.services.catalog.mode);
        await opening;
        expect(s.isHistory, isFalse);
        expect(s.loadingHistory, isFalse);
        expect(s.item!.id, 'item-b');
      },
    );

    test(
      'failed scan history write keeps the decision with an error',
      () async {
        final h = M1Harness();
        addTearDown(h.dispose);
        await h.initialize();
        await h.db.customStatement(
          "CREATE TRIGGER activity_failure BEFORE INSERT ON activity_records BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
        );
        final s = h.services.selection;
        await scan(s, 'item-b');
        expect(s.item!.id, 'item-b');
        expect(s.decision, isNotNull);
        expect(s.error, contains('accepted scan was not recorded'));
        expect(h.services.history.rows, isEmpty);
      },
    );

    test('FIR resets when the same item is scanned again', () async {
      final h = M1Harness();
      addTearDown(h.dispose);
      await h.initialize();
      final s = h.services.selection;
      await scan(s, 'item-b');
      s.setFir(FirState.yes);
      await scan(s, 'item-b');
      expect(s.fir, FirState.unknown);
      expect(
        s.decision!.recommendation,
        s.scan!.decisionAtAcceptance.recommendation,
      );
    });

    test(
      'stale Flea quote downgrades the scan to Check, acceptance unchanged',
      () async {
        var now = fixtureNow;
        const token = 'PVP_synthetic-fixture-only';
        final h = M1Harness(
          clock: () => now,
          shapeWire: (wire) {
            // Item-a has no requirements, so a Flea outcome depends on facts only.
            (wire['tasks']['data']['tasks'] as Map).clear();
            (wire['hideout']['data'] as Map).clear();
            wire['crafts']['data'] = [];
            wire['barters']['data'] = [];
            wire['token'] = {
              'success': true,
              'permissions': ['GP'],
              'token': token,
              'owner': 'synthetic-owner',
              'note': 'Synthetic',
              'calls': 0,
              'gameMode': 'pvp',
            };
            wire['progress'] = progressWire();
          },
        );
        addTearDown(h.dispose);
        h.credentials.values[GameMode.pvp] = token;
        await h.initialize();
        await h.services.progress.refresh();
        final s = h.services.selection;
        await scan(s, 'item-a');
        final accepted = s.scan!;
        expect(accepted.acceptedAt, fixtureNow);
        s.setFir(FirState.yes);
        expect(s.decision!.recommendation, Recommendation.flea);
        now = fixtureNow.add(const Duration(hours: 1, minutes: 1));
        s.setFir(FirState.yes);
        expect(s.decision!.recommendation, Recommendation.check);
        expect(s.scan, same(accepted));
        expect(s.scan!.acceptedAt, fixtureNow);
        expect(
          s.scan!.decisionAtAcceptance.recommendation,
          isNot(Recommendation.flea),
        );
        expect(s.fir, FirState.yes);
      },
    );

    test('retiring a non-scan source keeps a history load alive', () async {
      final h = M1Harness();
      addTearDown(h.dispose);
      await h.initialize();
      final s = h.services.selection;
      await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
      final opening = s.openHistory(h.services.history.rows.single);
      expect(s.loadingHistory, isTrue);
      s.retireScan();
      expect(s.scanRetired, isFalse);
      expect(s.loadingHistory, isTrue);
      await opening;
      expect(s.loadingHistory, isFalse);
      expect(s.historyRow, isNotNull);
      expect(s.item!.id, 'item-a');
    });
  });

  group('showScan', () {
    late M1Harness h;
    late SelectionController s;
    late ScanEpoch epoch;
    late List<String> debugLines;
    late DebugPrintCallback originalDebugPrint;

    setUp(() async {
      h = M1Harness();
      await h.initialize();
      epoch = const ScanEpoch(0, 0);
      s = SelectionController(
        database: h.services.database,
        catalog: h.services.catalog,
        progress: h.services.progress,
        history: h.services.history,
        epoch: () => epoch,
      );
      debugLines = [];
      originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => debugLines.add(message ?? '');
    });

    tearDown(() async {
      debugPrint = originalDebugPrint;
      s.dispose();
      await h.dispose();
    });

    Future<AcceptedScan> accept(String id) async {
      await s.selectScan(
        reportId: 1,
        itemId: id,
        mode: GameMode.pvp,
        catalogRevision: s.catalog.snapshot!.revision,
        epoch: epoch,
      );
      return s.scan!;
    }

    AcceptedScan variant(
      AcceptedScan of, {
      String? itemId,
      GameMode? mode,
      ScanEpoch? epoch,
    }) => AcceptedScan(
      reportId: of.reportId,
      itemId: itemId ?? of.itemId,
      mode: mode ?? of.mode,
      catalogRevision: of.catalogRevision,
      acceptedAt: of.acceptedAt,
      epoch: epoch ?? of.epoch,
      decisionAtAcceptance: of.decisionAtAcceptance,
    );

    test('showScan restores the scan without recording', () async {
      final accepted = await accept('item-b');
      await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
      await s.openHistory(h.services.history.rows.first);
      expect(s.isHistory, isTrue);
      final rowsBefore = h.services.history.rows.length;

      s.showScan(accepted);

      expect(s.selectedId, 'item-b');
      expect(s.item!.id, 'item-b');
      expect(s.decision, isNotNull);
      expect(s.scan, same(accepted));
      expect(s.scan!.acceptedAt, accepted.acceptedAt);
      expect(s.isHistory, isFalse);
      expect(s.historyRow, isNull);
      expect(s.scanRetired, isFalse);
      expect(s.correction, isNull);
      expect(s.correctionOffer, isNull);
      expect(h.services.history.rows.length, rowsBefore);
      expect(debugLines, isEmpty);
    });

    test('showScan resets FIR', () async {
      final accepted = await accept('item-b');
      await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
      s.setFir(FirState.yes);

      s.showScan(accepted);

      expect(s.fir, FirState.unknown);
      expect(
        s.decision!.recommendation,
        accepted.decisionAtAcceptance.recommendation,
      );
    });

    test('showScan refuses a stale epoch, mode or missing item', () async {
      final accepted = await accept('item-b');
      await s.selectManual(h.services.catalog.snapshot!.items['item-a']!);
      s.setFir(FirState.yes);
      final rows = h.services.history.rows.map((row) => row.itemId).toList();
      final stale = [
        variant(accepted, epoch: const ScanEpoch(99, 99)),
        variant(accepted, mode: GameMode.pve),
        variant(accepted, itemId: 'item-missing'),
      ];

      var refused = 0;
      for (final record in stale) {
        s.showScan(record);
        refused++;
        expect(debugLines, hasLength(refused));
        expect(s.selectedId, 'item-a');
        expect(s.item!.id, 'item-a');
        expect(s.scan, isNull);
        expect(s.fir, FirState.yes);
        expect(h.services.history.rows.map((row) => row.itemId), rows);
      }
    });
  });
}
