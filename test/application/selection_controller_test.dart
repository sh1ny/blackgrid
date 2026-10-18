import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/application/selection_controller.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/m1_harness.dart';

void main() {
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
        expect(s.error, contains('Accepted scan was not recorded'));
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
}
