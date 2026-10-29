import 'package:blackgrid/application/catalog_controller.dart';
import 'package:blackgrid/application/history_controller.dart';
import 'package:blackgrid/application/progress_controller.dart';
import 'package:blackgrid/application/scan_correction.dart';
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
import 'package:blackgrid/domain/progress.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../support/m1_harness.dart';

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
  items: {for (final f in _fixtures) f.id: _item(f)},
  traders: const {
    'trader-a': CatalogTrader(id: 'trader-a', name: 'Synthetic Alpha'),
  },
  requirements: [
    for (final f in _fixtures)
      if (f.needed) _need(f),
  ],
  sourceTimestamps: {for (final key in catalogDatasets) key: fixtureNow},
);

ProgressSnapshot _progressSnapshot() => decisionProgress(
  tasks: {
    for (final f in _fixtures)
      if (f.needed) 'task-${f.id}': _activeTask,
  },
  objectives: {
    for (final f in _fixtures)
      if (f.needed) 'objective-${f.id}': _remainingObjective,
  },
);

void main() {
  const epoch = ScanEpoch(0, 0);
  late BlackgridDatabase database;
  late CatalogController catalog;
  late ProgressController progress;
  late SelectionController selection;
  late CatalogSnapshot snapshot;

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
    selection = SelectionController(
      database: database,
      catalog: catalog,
      progress: progress,
      history: HistoryController(database),
      clock: () => fixtureNow,
    );
  });

  tearDown(() async {
    selection.dispose();
    catalog.dispose();
    progress.dispose();
    await database.close();
  });

  Future<void> scan(String id) => selection.selectScan(
    reportId: 1,
    itemId: id,
    mode: GameMode.pvp,
    catalogRevision: snapshot.revision,
    epoch: epoch,
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

  test('every precedence rule matches the hand-selected decision', () async {
    for (final f in _fixtures) {
      await scan(f.id);
      expect(selection.scan, isNotNull, reason: f.id);
      if (f.firYes) selection.setFir(FirState.yes);
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
