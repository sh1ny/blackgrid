import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
