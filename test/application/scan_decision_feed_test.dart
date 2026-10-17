import 'package:blackgrid/application/scan_decision_feed.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/m1_harness.dart';
import 'support/fake_accepted_scan_source.dart';
import 'support/history_wait.dart';

void main() {
  const e0 = ScanEpoch(1, 1);
  late M1Harness h;
  late FakeAcceptedScanSource source;
  late FakeScanEpochReader epoch;
  late ScanDecisionFeed feed;
  late DateTime now;
  late List<String> debugLines;
  late DebugPrintCallback originalDebugPrint;

  setUp(() async {
    now = fixtureNow;
    h = M1Harness(clock: () => now);
    await h.initialize();
    source = FakeAcceptedScanSource();
    epoch = FakeScanEpochReader(e0);
    feed = ScanDecisionFeed(
      source: source,
      selection: h.services.selection,
      catalog: h.services.catalog,
      epoch: epoch.call,
    );
    debugLines = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => debugLines.add(message ?? '');
  });

  tearDown(() async {
    debugPrint = originalDebugPrint;
    feed.dispose();
    await h.dispose();
  });

  void acceptScan(
    int id,
    String itemId, {
    ScanEpoch? stamped = e0,
    GameMode? mode = GameMode.pvp,
  }) {
    source.accept(
      acceptedScanReport(id: id, itemId: itemId, epoch: stamped, mode: mode),
    );
  }

  Future<void> scanLanded(String itemId) => untilRow(
    h.services.history,
    (row) => row.itemId == itemId && row.source == ActivitySource.scan,
  );

  test('accepted scan replaces a manual selection', () async {
    final selection = h.services.selection;
    await selection.selectManual(h.services.catalog.snapshot!.items['item-a']!);

    acceptScan(1, 'item-b');
    await scanLanded('item-b');

    expect(selection.selectedId, 'item-b');
    expect(selection.scan?.reportId, 1);
    expect(selection.scan?.epoch, e0);
    expect(selection.decision, isNotNull);
    expect(h.services.history.rows.map((row) => row.itemId).toSet(), {
      'item-a',
      'item-b',
    });
  });

  test('rejected scan with a candidate changes nothing', () async {
    final selection = h.services.selection;
    await selection.selectManual(h.services.catalog.snapshot!.items['item-a']!);
    final decision = selection.decision;

    // A rejected publish notifies but leaves lastAccepted alone.
    source.notify();

    expect(selection.selectedId, 'item-a');
    expect(selection.scan, isNull);
    expect(selection.decision, same(decision));
    expect(h.services.history.rows.map((row) => row.itemId), ['item-a']);
  });

  test('failed scan keeps the scanned item and its FIR', () async {
    final selection = h.services.selection;
    acceptScan(1, 'item-b');
    await scanLanded('item-b');
    selection.setFir(FirState.yes);

    // A failed publish notifies; the accepted scan is unchanged.
    source.notify();

    expect(selection.selectedId, 'item-b');
    expect(selection.scan?.reportId, 1);
    expect(selection.fir, FirState.yes);
  });

  test('refresh after an accepted scan records nothing new', () async {
    acceptScan(1, 'item-b');
    await scanLanded('item-b');
    final recorded = h.services.history.rows.single;
    final accepted = h.services.selection.scan!.acceptedAt;

    now = now.add(const Duration(minutes: 5));
    await h.services.catalog.refresh();
    await h.services.progress.refresh();

    final rows = h.services.history.rows;
    expect(rows, hasLength(1));
    expect(rows.single.observedAt, recorded.observedAt);
    expect(rows.single.revision, recorded.revision);
    expect(h.services.selection.scan?.acceptedAt, accepted);
    expect(h.services.selection.selectedId, 'item-b');
  });

  test(
    'notification without a new accepted scan keeps the manual item',
    () async {
      final selection = h.services.selection;
      acceptScan(1, 'item-b');
      await scanLanded('item-b');
      await selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      );

      source.notify();

      expect(selection.selectedId, 'item-a');
      expect(selection.scan, isNull);
    },
  );

  test('scan from an older mode is fenced', () async {
    final selection = h.services.selection;
    await selection.selectManual(h.services.catalog.snapshot!.items['item-a']!);

    // Began before a mode transition: the epoch differs.
    epoch.value = const ScanEpoch(2, 1);
    acceptScan(1, 'item-b');
    // Same epoch, but matched against another mode's index.
    acceptScan(2, 'item-b', stamped: epoch.value, mode: GameMode.pve);

    expect(selection.selectedId, 'item-a');
    expect(selection.scan, isNull);
    expect(h.services.history.rows.map((row) => row.itemId), ['item-a']);
    expect(debugLines.where((line) => line.contains('epoch')), hasLength(1));
    expect(debugLines.where((line) => line.contains('mode')), hasLength(1));
  });

  test('scan from an older session is fenced', () async {
    final selection = h.services.selection;
    await selection.selectManual(h.services.catalog.snapshot!.items['item-a']!);

    epoch.value = const ScanEpoch(1, 2);
    acceptScan(1, 'item-b');

    expect(selection.selectedId, 'item-a');
    expect(selection.scan, isNull);
    expect(h.services.history.rows.map((row) => row.itemId), ['item-a']);
    expect(debugLines.where((line) => line.contains('epoch')), hasLength(1));
  });

  test('scan of an item missing from the current catalog is fenced', () async {
    final selection = h.services.selection;
    await selection.selectManual(h.services.catalog.snapshot!.items['item-a']!);

    acceptScan(1, 'item-missing');

    expect(selection.selectedId, 'item-a');
    expect(selection.scan, isNull);
    expect(h.services.history.rows.map((row) => row.itemId), ['item-a']);
    expect(debugLines.where((line) => line.contains('catalog')), hasLength(1));

    // The fenced scan is never retried by a later notification.
    source.notify();
    expect(selection.selectedId, 'item-a');
    expect(debugLines.where((line) => line.contains('catalog')), hasLength(1));
  });

  test('session change retires the scan and resets FIR', () async {
    final selection = h.services.selection;
    acceptScan(1, 'item-b');
    await scanLanded('item-b');
    selection.setFir(FirState.yes);

    epoch.value = const ScanEpoch(1, 2);
    feed.epochChanged();

    expect(selection.scan, isNull);
    expect(selection.scanRetired, isTrue);
    expect(selection.fir, FirState.unknown);
  });

  test('mode change retires the scan and records nothing', () async {
    final selection = h.services.selection;
    acceptScan(1, 'item-b');
    await scanLanded('item-b');

    epoch.value = const ScanEpoch(2, 1);
    await h.services.setMode(GameMode.pve);
    feed.epochChanged();

    expect(selection.scan, isNull);
    expect(selection.scanRetired, isTrue);
    expect(h.services.history.rows.map((row) => row.mode), [GameMode.pvp]);
  });
}
