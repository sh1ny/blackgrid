import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/history_controller.dart';
import 'package:blackgrid/application/progress_controller.dart';
import 'package:blackgrid/application/scan_coordinator.dart';
import 'package:blackgrid/application/scan_decision_feed.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/application/selection_controller.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/catalog_normalizer.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/tracker_client.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/catalog_store.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/m1_harness.dart';
import 'support/fake_accepted_scan_source.dart';
import 'support/history_wait.dart';

class _NoStore implements CatalogStore {
  @override
  Future<CatalogSnapshot?> loadCatalog(GameMode mode) async => null;

  @override
  Future<void> commitCatalog(CatalogSnapshot snapshot) async {}
}

const _failingWrite =
    "CREATE TRIGGER activity_failure BEFORE INSERT ON activity_records "
    "BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END";

const _names = {
  'ana-od': 'ANA Tactical M1 plate carrier (OD Green)',
  'ana-black': 'ANA Tactical M1 plate carrier (Black)',
  'ana-m2': 'ANA Tactical M2 plate carrier',
  'flea': 'Flea sample',
  'f1': 'Filler one',
  'f2': 'Filler two',
  'f3': 'Filler three',
  'f4': 'Filler four',
  'f5': 'Filler five',
  'f6': 'Filler six',
  'f7': 'Filler seven',
};

CatalogItem _item(String id) => CatalogItem(
  id: id,
  name: _names[id]!,
  normalizedName: id,
  width: 2,
  height: 2,
  noFlea: false,
  minLevelForFlea: 0,
  fleaPrice: 400,
  quoteAt: fixtureNow,
  sellOffers: const [
    CashOffer(traderId: 'trader-a', currency: 'RUB', price: 120),
  ],
);

CatalogSnapshot _snapshot({Iterable<String>? ids, GameMode? mode}) =>
    CatalogSnapshot(
      mode: mode ?? GameMode.pvp,
      revision: 'correction-revision',
      observedAt: fixtureNow,
      items: {for (final id in ids ?? _names.keys) id: _item(id)},
      traders: const {
        'trader-a': CatalogTrader(id: 'trader-a', name: 'Synthetic Alpha'),
      },
      requirements: const [],
      sourceTimestamps: {for (final key in catalogDatasets) key: fixtureNow},
    );

void main() {
  const e0 = ScanEpoch(1, 1);
  late BlackgridDatabase database;
  late CatalogController catalog;
  late ProgressController progress;
  late HistoryController history;
  late SelectionController selection;
  late FakeAcceptedScanSource source;
  late FakeScanEpochReader epoch;
  late ScanDecisionFeed feed;
  late DateTime now;

  setUp(() {
    now = fixtureNow;
    database = BlackgridDatabase(NativeDatabase.memory());
    catalog =
        CatalogController(
            store: _NoStore(),
            client: CatalogClient(
              client: MockClient((_) async => http.Response('', 500)),
            ),
          )
          ..mode = GameMode.pvp
          ..snapshot = _snapshot()
          ..status = CatalogStatus.current;
    progress =
        ProgressController(
            store: MemoryCredentials(),
            client: TrackerClient(
              client: MockClient((_) async => http.Response('', 500)),
            ),
          )
          ..mode = GameMode.pvp
          ..snapshot = decisionProgress()
          ..status = ProgressStatus.current;
    history = HistoryController(database);
    epoch = FakeScanEpochReader(e0);
    selection = SelectionController(
      database: database,
      catalog: catalog,
      progress: progress,
      history: history,
      clock: () => now,
      epoch: epoch.call,
    );
    source = FakeAcceptedScanSource();
    feed = ScanDecisionFeed(
      source: source,
      selection: selection,
      catalog: catalog,
      epoch: epoch.call,
    );
  });

  tearDown(() async {
    feed.dispose();
    selection.dispose();
    history.dispose();
    catalog.dispose();
    progress.dispose();
    await database.close();
  });

  /// Publishes a rejected report and returns its id.
  int reject(
    int id, {
    ScanRejectReason reason = ScanRejectReason.ambiguous,
    String? text = 'ANA M1 OD GREEN',
    List<TitleCandidate>? candidates = const [
      TitleCandidate('ana-od', 1.0),
      TitleCandidate('ana-black', 0.974),
    ],
    ScanEpoch? stamped = e0,
    GameMode? mode = GameMode.pvp,
  }) {
    source.publish(
      rejectedScanReport(
        id: id,
        epoch: stamped,
        reason: reason,
        text: text,
        candidates: candidates,
        mode: mode,
      ),
    );
    return id;
  }

  Future<void> accept(int id, String itemId) {
    source.publish(acceptedScanReport(id: id, itemId: itemId, epoch: e0));
    return untilRow(
      history,
      (row) => row.itemId == itemId && row.source == ActivitySource.scan,
    );
  }

  Future<void> manual(String id) =>
      selection.selectManual(catalog.snapshot!.items[id]!);

  List<String> candidateIds() => [
    for (final c in selection.correctionCandidates) c.item.id,
  ];

  group('offers', () {
    test(
      'ambiguous scan offers a correction and keeps the selection',
      () async {
        await manual('f1');
        final decision = selection.decision;

        reject(2);

        final offer = selection.correctionOffer!;
        expect(offer.reportId, 2);
        expect(offer.ocrText, 'ANA M1 OD GREEN');
        expect(selection.selectedId, 'f1');
        expect(selection.decision, same(decision));
        expect(history.rows.map((r) => r.itemId), ['f1']);
      },
    );

    test(
      'below-similarity scan offers a correction with no recommendation',
      () {
        reject(
          2,
          reason: ScanRejectReason.belowSimilarity,
          text: 'FILTRBY',
          candidates: const [TitleCandidate('f1', 0.31)],
        );

        expect(selection.correctionOffer, isNotNull);
        expect(selection.correctionOffer!.candidates, isEmpty);
        expect(selection.selectedId, isNull);
        expect(selection.decision, isNull);
        expect(selection.correction, isNull);
      },
    );

    test('other rejection reasons offer nothing', () {
      final others = ScanRejectReason.values.where(
        (r) =>
            r != ScanRejectReason.ambiguous &&
            r != ScanRejectReason.belowSimilarity,
      );
      var id = 1;
      for (final reason in others) {
        reject(++id, reason: reason);
        expect(selection.correctionOffer, isNull, reason: reason.name);
      }
    });

    test('failed scan offers nothing', () {
      source.publish(failedScanReport(id: 2, epoch: e0));

      expect(selection.correctionOffer, isNull);
    });

    test('empty OCR text offers nothing', () {
      reject(2, reason: ScanRejectReason.belowSimilarity, text: '');
      expect(selection.correctionOffer, isNull);

      // No evidence or no match in the outcome offers nothing either.
      reject(3, text: null);
      expect(selection.correctionOffer, isNull);
      reject(4, candidates: null);
      expect(selection.correctionOffer, isNull);
    });

    test('scan from an older mode offers nothing', () {
      // Triggered before the mode transition: the epoch differs.
      epoch.value = const ScanEpoch(2, 1);
      reject(2);
      expect(selection.correctionOffer, isNull);

      // Same epoch, but matched against another mode's index.
      reject(3, stamped: epoch.value, mode: GameMode.pve);
      expect(selection.correctionOffer, isNull);
    });

    test('offer lists close variants in rank order with scores', () {
      reject(2);

      final listed = selection.correctionCandidates;
      expect(listed.map((c) => c.item.name), [
        'ANA Tactical M1 plate carrier (OD Green)',
        'ANA Tactical M1 plate carrier (Black)',
      ]);
      expect(listed.map((c) => c.score), [1.0, 0.974]);
      expect(selection.decision, isNull);
    });

    test('offer lists at most five candidates', () {
      reject(
        2,
        candidates: const [
          TitleCandidate('f1', 0.9),
          TitleCandidate('f2', 0.8),
          TitleCandidate('f3', 0.7),
          TitleCandidate('f4', 0.6),
          TitleCandidate('f5', 0.5),
          TitleCandidate('f6', 0.45),
          TitleCandidate('f7', 0.41),
        ],
      );

      expect(candidateIds(), ['f1', 'f2', 'f3', 'f4', 'f5']);
      expect(selection.correctionOffer!.candidates, hasLength(5));
    });

    test('candidates below .40 are left out', () {
      reject(
        2,
        candidates: const [
          TitleCandidate('f1', 0.9),
          TitleCandidate('f2', 0.39),
          TitleCandidate('f3', 0.31),
        ],
      );

      expect(candidateIds(), ['f1']);
    });

    test('candidate missing from the live catalog is left out', () {
      catalog.snapshot = _snapshot(ids: _names.keys.where((k) => k != 'f2'));

      reject(
        2,
        candidates: const [
          TitleCandidate('f1', 0.9),
          TitleCandidate('f2', 0.8),
          TitleCandidate('f3', 0.7),
        ],
      );

      expect(candidateIds(), ['f1', 'f3']);
    });
  });

  group('search', () {
    test(
      'editing the offer text searches without changing the selection',
      () async {
        await manual('f1');
        final decision = selection.decision;
        reject(2);
        expect(
          selection.correctionResults.map((i) => i.id),
          contains('ana-od'),
        );

        selection.setCorrectionQuery('ANA M1');
        expect(selection.correctionResults.map((i) => i.id), [
          'ana-black',
          'ana-od',
        ]);

        selection.setCorrectionQuery('ANA M1 black');
        expect(selection.correctionResults.map((i) => i.id), ['ana-black']);
        expect(selection.correctionOffer!.query, 'ANA M1 black');
        expect(selection.query, '');
        expect(selection.selectedId, 'f1');
        expect(selection.decision, same(decision));
      },
    );

    test('offer search with no match leaves the selection', () async {
      await manual('f1');
      reject(2);

      selection.setCorrectionQuery('zzz qqq');

      expect(selection.correctionResults, isEmpty);
      expect(selection.correctionOffer, isNotNull);
      expect(selection.selectedId, 'f1');
    });
  });

  group('picks', () {
    test('picking the runner-up selects it as a correction', () async {
      reject(2);

      await selection.selectCorrection(2, 'ana-black');

      expect(selection.selectedId, 'ana-black');
      expect(selection.correction?.reportId, 2);
      expect(selection.correction?.itemId, 'ana-black');
      expect(selection.correction?.correctedAt, fixtureNow);
      expect(selection.decision, isNotNull);
      expect(selection.correctionOffer, isNull);
      expect(selection.scan, isNull);
    });

    test('picking a search result selects it as a correction', () async {
      reject(2);
      selection.setCorrectionQuery('ana m1 black');
      final result = selection.correctionResults.single;

      await selection.selectCorrection(2, result.id);

      expect(selection.selectedId, 'ana-black');
      expect(selection.correction?.reportId, 2);
      expect(selection.correctionOffer, isNull);
    });

    test('correcting to the scanned item resets FIR', () async {
      await accept(1, 'ana-od');
      selection.setFir(FirState.yes);
      reject(2);

      await selection.selectCorrection(2, 'ana-od');

      expect(selection.selectedId, 'ana-od');
      expect(selection.correction?.itemId, 'ana-od');
      expect(selection.fir, FirState.unknown);
    });

    test('accepted scan after a correction replaces it', () async {
      reject(1);
      await selection.selectCorrection(1, 'ana-black');
      expect(selection.correction?.itemId, 'ana-black');

      await accept(2, 'f2');

      expect(selection.selectedId, 'f2');
      expect(selection.scan?.reportId, 2);
      expect(selection.correction, isNull);
    });

    test('a pick resets FIR', () async {
      await manual('f1');
      selection.setFir(FirState.yes);
      reject(2);

      await selection.selectCorrection(2, 'ana-black');

      expect(selection.fir, FirState.unknown);
    });

    test('a pick closes an open history view', () async {
      await manual('f1');
      await selection.openHistory(history.rows.single);
      expect(selection.isHistory, isTrue);
      reject(2);

      await selection.selectCorrection(2, 'ana-black');

      expect(selection.isHistory, isFalse);
      expect(selection.selectedId, 'ana-black');
      expect(selection.inspectionMode, catalog.mode);
    });

    test(
      'failed correction write keeps the correction with an error',
      () async {
        await database.customStatement(_failingWrite);
        reject(2);

        await selection.selectCorrection(2, 'ana-black');

        expect(selection.selectedId, 'ana-black');
        expect(selection.correction, isNotNull);
        expect(selection.decision, isNotNull);
        expect(
          selection.error,
          'Correction was not recorded: local persistence failed.',
        );
        expect(history.rows, isEmpty);
      },
    );

    test('a correction records manual activity at the pick time', () async {
      reject(2);
      now = fixtureNow.add(const Duration(minutes: 7));

      await selection.selectCorrection(2, 'ana-black');

      final row = history.rows.single;
      expect(row.itemId, 'ana-black');
      expect(row.mode, GameMode.pvp);
      expect(row.source, ActivitySource.manual);
      expect(row.observedAt, now);
      expect(selection.correction?.correctedAt, now);
    });
  });

  group('after a pick', () {
    test('session change retires a correction', () async {
      reject(2);
      await selection.selectCorrection(2, 'ana-black');
      selection.setFir(FirState.yes);

      epoch.value = const ScanEpoch(1, 2);
      feed.epochChanged();

      expect(selection.correction, isNull);
      expect(selection.selectedId, isNull);
      expect(selection.decision, isNull);
      expect(selection.scanRetired, isTrue);
      expect(selection.fir, FirState.unknown);
    });

    test('stale Flea quote downgrades a correction to Check', () async {
      reject(2, candidates: const [TitleCandidate('flea', 0.9)]);
      await selection.selectCorrection(2, 'flea');
      selection.setFir(FirState.yes);
      expect(selection.decision!.recommendation, Recommendation.flea);

      now = fixtureNow.add(const Duration(hours: 1, minutes: 1));
      selection.setFir(FirState.yes);

      expect(selection.decision!.recommendation, Recommendation.check);
      expect(selection.correction?.itemId, 'flea');
      expect(selection.selectedId, 'flea');
    });

    test('a correction is never an accepted scan', () async {
      await accept(1, 'f1');
      final accepted = source.lastAccepted;
      reject(2);

      await selection.selectCorrection(2, 'ana-black');
      source.notify();

      expect(source.lastAccepted, same(accepted));
      expect(source.lastAccepted!.id, 1);
      expect(source.latest!.id, 2);
      expect(selection.scan, isNull);
      expect(selection.selectedId, 'ana-black');
      expect(
        history.rows
            .where((r) => r.source == ActivitySource.scan)
            .map((r) => r.itemId),
        ['f1'],
      );
      expect(
        history.rows.singleWhere((r) => r.itemId == 'ana-black').source,
        ActivitySource.manual,
      );
    });

    test('refresh after a correction records nothing new', () async {
      // The real catalog and progress controllers refresh over the fixture.
      final h = M1Harness(database: database, clock: () => now);
      addTearDown(h.dispose);
      await h.initialize();
      final s = SelectionController(
        database: database,
        catalog: h.services.catalog,
        progress: h.services.progress,
        history: history,
        clock: () => now,
        epoch: epoch.call,
      );
      addTearDown(s.dispose);
      final localSource = FakeAcceptedScanSource();
      final localFeed = ScanDecisionFeed(
        source: localSource,
        selection: s,
        catalog: h.services.catalog,
        epoch: epoch.call,
      );
      addTearDown(localFeed.dispose);
      localSource.publish(
        rejectedScanReport(
          id: 2,
          epoch: e0,
          candidates: const [TitleCandidate('item-b', 0.9)],
        ),
      );
      await s.selectCorrection(2, 'item-b');
      final recorded = history.rows.single;

      now = now.add(const Duration(minutes: 5));
      await h.services.catalog.refresh();
      await h.services.progress.refresh();

      expect(s.correction?.itemId, 'item-b');
      expect(s.selectedId, 'item-b');
      expect(s.scan, isNull);
      final rows = history.rows;
      expect(rows, hasLength(1));
      expect(rows.single.observedAt, recorded.observedAt);
      expect(rows.single.revision, recorded.revision);
      expect(localSource.lastAccepted, isNull);
    });
  });

  group('lifecycle', () {
    test('a newer offer replaces the older one', () {
      reject(2);
      reject(3, text: 'ANA M1 BLACK');

      expect(selection.correctionOffer!.reportId, 3);
      expect(selection.correctionOffer!.ocrText, 'ANA M1 BLACK');
    });

    test('an accepted scan clears the offer', () async {
      reject(2);

      await accept(3, 'f2');

      expect(selection.correctionOffer, isNull);
      expect(selection.selectedId, 'f2');
    });

    test('a later failure keeps the offer', () {
      reject(2);

      source.publish(failedScanReport(id: 3, epoch: e0));

      expect(selection.correctionOffer?.reportId, 2);
    });

    test('manual selection clears the offer', () async {
      reject(2);

      await manual('f3');

      expect(selection.correctionOffer, isNull);
      expect(selection.selectedId, 'f3');
      expect(selection.correction, isNull);
    });

    test('closing a history view keeps the offer', () async {
      await manual('f1');
      await selection.openHistory(history.rows.single);
      reject(2);
      expect(selection.correctionOffer, isNotNull);

      selection.closeHistory();

      expect(selection.correctionOffer?.reportId, 2);
      expect(selection.isHistory, isFalse);
      expect(selection.selectedId, 'f1');
    });

    test('dismiss clears only the offer', () async {
      await manual('f1');
      selection.setFir(FirState.yes);
      final decision = selection.decision;
      reject(2);

      selection.dismissCorrection();

      expect(selection.correctionOffer, isNull);
      expect(selection.selectedId, 'f1');
      expect(selection.fir, FirState.yes);
      expect(selection.decision, same(decision));
      expect(history.rows.map((r) => r.itemId), ['f1']);
    });

    test('session change clears the offer', () {
      reject(2);

      epoch.value = const ScanEpoch(1, 2);
      feed.epochChanged();

      expect(selection.correctionOffer, isNull);
    });

    test('a dismissed offer is not offered again', () {
      reject(2);
      selection.dismissCorrection();

      source.notify();

      expect(selection.correctionOffer, isNull);
    });
  });

  group('stale picks', () {
    test('a pick from a replaced offer changes nothing', () async {
      reject(2);
      await accept(3, 'f2');

      await selection.selectCorrection(2, 'ana-black');

      expect(selection.selectedId, 'f2');
      expect(selection.correction, isNull);
      expect(history.rows.map((r) => r.itemId), ['f2']);
    });

    test(
      'a pick of an item no longer in the catalog changes nothing',
      () async {
        await manual('f1');
        reject(2);
        catalog.snapshot = _snapshot(
          ids: _names.keys.where((k) => k != 'ana-black'),
        );

        await selection.selectCorrection(2, 'ana-black');

        expect(selection.selectedId, 'f1');
        expect(selection.correction, isNull);
        expect(selection.correctionOffer?.reportId, 2);
        expect(history.rows.map((r) => r.itemId), ['f1']);
      },
    );

    test('a pick after a session change changes nothing', () async {
      await manual('f1');
      reject(2);
      // The session moved on without the feed retiring the offer.
      epoch.value = const ScanEpoch(1, 2);

      await selection.selectCorrection(2, 'ana-black');

      expect(selection.correction, isNull);
      expect(selection.selectedId, 'f1');
      expect(history.rows.map((r) => r.itemId), ['f1']);
    });

    test('a pick after a mode change changes nothing', () async {
      await manual('f1');
      reject(2);
      catalog.mode = GameMode.pve;
      catalog.snapshot = _snapshot(mode: GameMode.pve);

      await selection.selectCorrection(2, 'ana-black');

      expect(selection.correction, isNull);
      expect(selection.correctionOffer?.reportId, 2);
      expect(history.rows.map((r) => r.itemId), ['f1']);
    });
  });
}
