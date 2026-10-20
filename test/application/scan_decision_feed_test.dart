import 'package:blackgrid/application/scan_decision_feed.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/application/selection_controller.dart';
import 'package:blackgrid/application/session_scan_state.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/domain/title_matching.dart';
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
  late SessionScanState scans;
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
    scans = SessionScanState();
    feed = ScanDecisionFeed(
      source: source,
      scans: scans,
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
    scans.dispose();
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
    // AppServices retires the scan itself; the test feed is not called.
    await h.services.setMode(GameMode.pve);

    expect(selection.scan, isNull);
    expect(selection.scanRetired, isTrue);
    expect(h.services.history.rows.map((row) => row.mode), [GameMode.pvp]);
  });

  group('latest scan', () {
    test('accepted scan advances the latest scan without a pump', () {
      expect(scans.latest, isNull);

      acceptScan(1, 'item-b');

      final latest = scans.latest;
      expect(latest, isNotNull);
      expect(latest!.itemId, 'item-b');
      expect(latest, same(h.services.selection.scan));
      expect(latest.acceptedAt, fixtureNow.toUtc());
    });

    test('manual, history and correction leave the latest scan', () async {
      // AppServices' selection checks picks against the app's own epoch, so
      // this test drives a selection that reads the test epoch instead.
      feed.dispose();
      final selection = SelectionController(
        database: h.db,
        catalog: h.services.catalog,
        progress: h.services.progress,
        history: h.services.history,
        clock: () => now,
        epoch: epoch.call,
      );
      addTearDown(selection.dispose);
      final localFeed = ScanDecisionFeed(
        source: source,
        selection: selection,
        catalog: h.services.catalog,
        scans: scans,
        epoch: epoch.call,
      );
      addTearDown(localFeed.dispose);
      acceptScan(1, 'item-b');
      await scanLanded('item-b');
      final latest = scans.latest!;
      expect(latest, same(selection.scan));
      var notified = 0;
      scans.addListener(() => notified++);

      now = now.add(const Duration(minutes: 1));
      await selection.selectManual(
        h.services.catalog.snapshot!.items['item-a']!,
      );
      expect(scans.latest, same(latest));

      await selection.openHistory(h.services.history.rows.first);
      expect(selection.isHistory, isTrue);
      expect(scans.latest, same(latest));

      // A later scan is rejected and offers a correction to another item.
      source.publish(
        rejectedScanReport(
          id: 2,
          epoch: e0,
          candidates: const [TitleCandidate('item-a', 0.9)],
        ),
      );
      expect(selection.correctionOffer, isNotNull);
      expect(scans.latest, same(latest));
      await selection.selectCorrection(2, 'item-a');
      expect(selection.correction?.itemId, 'item-a');

      expect(scans.latest, same(latest));
      expect(scans.latest!.acceptedAt, latest.acceptedAt);
      expect(notified, 0);
    });

    test('refresh and age tick leave the latest scan', () async {
      acceptScan(1, 'item-b');
      await scanLanded('item-b');
      final latest = scans.latest!;
      var notified = 0;
      scans.addListener(() => notified++);

      now = now.add(const Duration(minutes: 5));
      await h.services.catalog.refresh();
      await h.services.progress.refresh();
      h.services.catalog.updateAge();
      h.services.progress.updateAge();

      expect(scans.latest, same(latest));
      expect(notified, 0);
    });

    test('fenced scans do not advance the latest scan', () async {
      acceptScan(1, 'item-b');
      await scanLanded('item-b');
      final latest = scans.latest!;

      acceptScan(2, 'item-missing');
      acceptScan(3, 'item-a', mode: GameMode.pve);
      epoch.value = const ScanEpoch(1, 2);
      acceptScan(4, 'item-a');

      expect(scans.latest, same(latest));
    });

    test('rejected scan does not advance the latest scan', () async {
      acceptScan(1, 'item-b');
      await scanLanded('item-b');
      final latest = scans.latest!;

      source.publish(
        rejectedScanReport(
          id: 2,
          epoch: e0,
          candidates: const [TitleCandidate('item-a', 0.9)],
        ),
      );

      expect(scans.latest, same(latest));
    });

    test('repeated notification keeps the first acceptance time', () async {
      final report = acceptedScanReport(id: 1, itemId: 'item-b', epoch: e0);
      source.accept(report);
      await scanLanded('item-b');
      final first = scans.latest!.acceptedAt;

      now = now.add(const Duration(minutes: 5));
      source.accept(report);
      source.notify();

      expect(scans.latest?.itemId, 'item-b');
      expect(scans.latest?.acceptedAt, first);
    });

    test('same item scanned again takes the second acceptance time', () async {
      acceptScan(1, 'item-b');
      await scanLanded('item-b');
      final first = scans.latest!.acceptedAt;

      now = now.add(const Duration(minutes: 5));
      acceptScan(2, 'item-b');

      expect(scans.latest?.itemId, 'item-b');
      expect(scans.latest?.reportId, 2);
      expect(scans.latest?.acceptedAt, isNot(first));
      expect(scans.latest?.acceptedAt, now.toUtc());
    });

    test('epochChanged clears the latest scan', () async {
      acceptScan(1, 'item-b');
      await scanLanded('item-b');
      expect(scans.latest, isNotNull);

      epoch.value = const ScanEpoch(2, 1);
      feed.epochChanged();

      expect(scans.latest, isNull);
      expect(scans.hasAcceptedScan, isFalse);
    });
  });
}
