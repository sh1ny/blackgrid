import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/history_controller.dart';
import 'package:blackgrid/application/progress_controller.dart';
import 'package:blackgrid/application/scan_correction.dart';
import 'package:blackgrid/application/scan_decision_feed.dart';
import 'package:blackgrid/application/session_scan_state.dart';
import 'package:blackgrid/application/scan_epoch.dart';
import 'package:blackgrid/application/selection_controller.dart';
import 'package:blackgrid/data/catalog_client.dart';
import 'package:blackgrid/data/catalog_normalizer.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/vision/inspection_fir.dart';
import 'package:blackgrid/data/tracker_client.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/catalog_store.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/progress.dart';
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

const _activeTask = EntityProgress(
  complete: false,
  failed: false,
  invalid: false,
);
const _remainingObjective = EntityProgress(
  complete: false,
  count: 1,
  invalid: false,
);

/// One item per precedence rule, and what the engine must answer for it.
class _Fixture {
  const _Fixture(
    this.id,
    this.expected, {
    this.firYes = false,
    this.price = 400,
    this.gate,
    this.needed = false,
  });

  final String id;
  final Recommendation expected;
  final bool firYes;
  final num price;
  final RequirementGate? gate;
  final bool needed;
}

final _fixtures = [
  _Fixture('keep', Recommendation.keep, needed: true, gate: _openGate()),
  _Fixture(
    'later',
    Recommendation.keepForLater,
    needed: true,
    gate: RequirementGate(
      minPlayerLevel: 40,
      faction: 'Any',
      editions: const [],
      taskStatuses: const {},
    ),
  ),
  _Fixture(
    'check',
    Recommendation.check,
    needed: true,
    gate: RequirementGate(incomplete: true),
  ),
  const _Fixture('flea', Recommendation.flea, firYes: true),
  const _Fixture('trader', Recommendation.trader, firYes: true, price: 100),
  const _Fixture(
    'unpriced',
    Recommendation.priceUnavailable,
    firYes: true,
    price: 0,
  ),
];

RequirementGate _openGate() => RequirementGate(
  minPlayerLevel: 1,
  faction: 'Any',
  editions: const [],
  taskStatuses: const {},
  stations: const {},
);

CatalogItem _item(_Fixture f) => CatalogItem(
  id: f.id,
  name: 'Item ${f.id}',
  normalizedName: 'item-${f.id}',
  width: 2,
  height: 2,
  noFlea: false,
  minLevelForFlea: 0,
  fleaPrice: f.price,
  quoteAt: fixtureNow,
  sellOffers: f.price == 0
      ? const []
      : const [CashOffer(traderId: 'trader-a', currency: 'RUB', price: 120)],
);

ItemRequirement _need(_Fixture f) => ItemRequirement(
  kind: RequirementKind.task,
  sourceId: 'task-${f.id}',
  sourceName: 'Task ${f.id}',
  id: 'objective-${f.id}',
  itemIds: [f.id],
  progressIds: ['objective-${f.id}'],
  count: 3,
  foundInRaid: false,
  gate: f.gate!,
);

CatalogSnapshot _catalogSnapshot() => CatalogSnapshot(
  mode: GameMode.pvp,
  revision: 'precedence-revision',
  observedAt: fixtureNow,
  items: {
    for (final f in _fixtures) f.id: _item(f),
    'fir-only': CatalogItem(
      id: 'fir-only',
      name: 'FIR only',
      normalizedName: 'fir only',
      noFlea: true,
      sellOffers: const [
        CashOffer(traderId: 'trader-a', currency: 'RUB', price: 120),
      ],
    ),
  },
  traders: const {
    'trader-a': CatalogTrader(id: 'trader-a', name: 'Synthetic Alpha'),
  },
  requirements: [
    for (final f in _fixtures)
      if (f.needed) _need(f),
    ItemRequirement(
      kind: RequirementKind.task,
      sourceId: 'task-fir-only',
      sourceName: 'FIR task',
      id: 'objective-fir-only',
      itemIds: const ['fir-only'],
      progressIds: const ['objective-fir-only'],
      count: 3,
      foundInRaid: true,
      gate: _openGate(),
    ),
  ],
  sourceTimestamps: {for (final key in catalogDatasets) key: fixtureNow},
);

ProgressSnapshot _progressSnapshot() => decisionProgress(
  tasks: {
    for (final f in _fixtures)
      if (f.needed) 'task-${f.id}': _activeTask,
    'task-fir-only': _activeTask,
  },
  objectives: {
    for (final f in _fixtures)
      if (f.needed) 'objective-${f.id}': _remainingObjective,
    'objective-fir-only': _remainingObjective,
  },
);

void main() {
  const epoch = ScanEpoch(0, 0);
  late BlackgridDatabase database;
  late CatalogController catalog;
  late ProgressController progress;
  late SelectionController selection;
  late CatalogSnapshot snapshot;
  late HistoryController history;
  late FakeAcceptedScanSource source;
  late SessionScanState scans;
  late ScanDecisionFeed feed;

  setUp(() {
    database = BlackgridDatabase(NativeDatabase.memory());
    snapshot = _catalogSnapshot();
    catalog =
        CatalogController(
            store: _NoStore(),
            client: CatalogClient(
              client: MockClient((_) async => http.Response('', 500)),
            ),
          )
          ..mode = GameMode.pvp
          ..snapshot = snapshot
          ..status = CatalogStatus.current;
    progress =
        ProgressController(
            store: MemoryCredentials(),
            client: TrackerClient(
              client: MockClient((_) async => http.Response('', 500)),
            ),
          )
          ..mode = GameMode.pvp
          ..snapshot = _progressSnapshot()
          ..status = ProgressStatus.current;
    history = HistoryController(database);
    selection = SelectionController(
      database: database,
      catalog: catalog,
      progress: progress,
      history: history,
      clock: () => fixtureNow,
    );
    source = FakeAcceptedScanSource();
    scans = SessionScanState();
    feed = ScanDecisionFeed(
      source: source,
      scans: scans,
      selection: selection,
      catalog: catalog,
      epoch: () => epoch,
    );
  });

  tearDown(() async {
    feed.dispose();
    scans.dispose();
    selection.dispose();
    history.dispose();
    catalog.dispose();
    progress.dispose();
    await database.close();
  });

  Future<void> scan(String id, {bool firYes = false}) => selection.selectScan(
    reportId: 1,
    itemId: id,
    mode: GameMode.pvp,
    catalogRevision: snapshot.revision,
    epoch: epoch,
    detectedFir: InspectionFirReading(
      reason: firYes
          ? InspectionFirReason.iconFound
          : InspectionFirReason.cornerUnreadable,
    ),
  );

  (Recommendation, List<(String, NeedState, num?, String)>) outcome() {
    final d = selection.decision!;
    return (
      d.recommendation,
      [
        for (final r in d.reasons)
          (r.requirement.id, r.state, r.remaining, r.message),
      ],
    );
  }

  test('scanned confirmed current need is Keep with the need', () async {
    await scan('keep');
    final d = selection.decision!;
    expect(d.recommendation, Recommendation.keep);
    expect(d.nonFirNeed, 2);
    expect(d.reasons.single.requirement.sourceId, 'task-keep');
    expect(d.reasons.single.remaining, 2);
  });

  test('scanned item with unknown progress is Check naming progress', () async {
    progress.snapshot = null;
    progress.status = ProgressStatus.missing;
    await scan('flea');
    selection.setFir(FirState.yes);
    final d = selection.decision!;
    expect(d.recommendation, Recommendation.check);
    expect(d.warnings, contains('Tracker progress missing or out of date'));
    expect(d.recommendation, isNot(Recommendation.flea));
    expect(d.recommendation, isNot(Recommendation.trader));
  });

  test(
    'FIR-only quest advice and recorded verdict follow detected Yes No Unknown',
    () async {
      final cases = [
        (
          InspectionFirReason.iconFound,
          Recommendation.keep,
          NeedState.actionable,
        ),
        (
          InspectionFirReason.iconAbsent,
          Recommendation.trader,
          NeedState.irrelevant,
        ),
        (
          InspectionFirReason.cornerUnreadable,
          Recommendation.check,
          NeedState.unresolved,
        ),
      ];
      var id = 0;
      for (final (reason, verdict, need) in cases) {
        source.accept(
          acceptedScanReport(
            id: ++id,
            itemId: 'fir-only',
            epoch: epoch,
            fir: InspectionFirReading(reason: reason),
          ),
        );
        final accepted = selection.scan!;
        expect(
          selection.decision!.recommendation,
          verdict,
          reason: reason.name,
        );
        expect(
          selection.decision!.reasons.single.state,
          need,
          reason: reason.name,
        );
        expect(
          accepted.decisionAtAcceptance.recommendation,
          verdict,
          reason: reason.name,
        );
        await untilRow(
          history,
          (row) => row.itemId == 'fir-only' && row.verdict == verdict,
        );
        expect(history.rows.single.verdict, verdict, reason: reason.name);
      }
    },
  );
  test('every precedence rule matches the hand-selected decision', () async {
    for (final f in _fixtures) {
      await scan(f.id, firYes: f.firYes);
      expect(selection.scan, isNotNull, reason: f.id);
      final scanned = outcome();

      await selection.selectManual(snapshot.items[f.id]!);
      expect(selection.scan, isNull, reason: f.id);
      if (f.firYes) selection.setFir(FirState.yes);
      final manual = outcome();

      expect(scanned.$1, f.expected, reason: f.id);
      expect(scanned.$1, manual.$1, reason: f.id);
      expect(scanned.$2, manual.$2, reason: f.id);
    }
  });

  test(
    'every precedence rule matches the hand-selected decision for a correction',
    () async {
      var reportId = 0;
      for (final f in _fixtures) {
        selection.offerCorrection(
          ScanCorrectionOffer(
            reportId: ++reportId,
            epoch: epoch,
            mode: GameMode.pvp,
            catalogRevision: snapshot.revision,
            ocrText: f.id,
            candidates: [TitleCandidate(f.id, 0.9)],
            query: f.id,
          ),
        );
        await selection.selectCorrection(reportId, f.id);
        expect(selection.correction, isNotNull, reason: f.id);
        expect(selection.scan, isNull, reason: f.id);
        if (f.firYes) selection.setFir(FirState.yes);
        final corrected = outcome();

        await selection.selectManual(snapshot.items[f.id]!);
        expect(selection.correction, isNull, reason: f.id);
        if (f.firYes) selection.setFir(FirState.yes);
        final manual = outcome();

        expect(corrected.$1, f.expected, reason: f.id);
        expect(corrected.$1, manual.$1, reason: f.id);
        expect(corrected.$2, manual.$2, reason: f.id);
      }
    },
  );
}
