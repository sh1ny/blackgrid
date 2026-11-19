import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/decision_engine.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/local_progress.dart' show ProgressTaskStatus;
import 'package:blackgrid/domain/price_freshness.dart';
import 'package:blackgrid/domain/progress_facts.dart';
import 'package:blackgrid_progress/blackgrid_progress.dart'
    show CatalogTask, ProgressCatalog;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/m1/catalog/fixture.dart';

const engine = DecisionEngine();
const _started = ProgressTaskStatus.started;
const _finished = ProgressTaskStatus.finished;
const _failed = ProgressTaskStatus.failed;

ProgressCatalog _taskCatalog({bool? restartable}) => ProgressCatalog(
  tasks: [CatalogTask(id: 'task-a', name: 'Task A', restartable: restartable)],
  stations: const [],
);

/// A task need with an explicit gate, so a test can pick which gates apply.
ItemRequirement _task({
  String sourceId = 'task-a',
  String objective = 'objective-a',
  num count = 3,
  int? minLevel = 1,
  String faction = 'Any',
  List<int> editions = const [],
  List<String> editionIds = const [],
  Map<String, List<String>> statuses = const {},
  Map<String, int> stations = const {},
}) => ItemRequirement(
  kind: RequirementKind.task,
  sourceId: sourceId,
  sourceName: 'Synthetic $sourceId',
  id: objective,
  itemIds: const ['item-a'],
  progressIds: [objective],
  count: count,
  foundInRaid: false,
  gate: RequirementGate(
    minPlayerLevel: minLevel,
    faction: faction,
    editions: editions,
    editionIds: editionIds,
    taskStatuses: statuses,
    stations: stations,
  ),
);

ItemRequirement _hideout({num count = 2, int level = 2}) => ItemRequirement(
  kind: RequirementKind.hideout,
  sourceId: 'station-a-$level',
  sourceName: 'Station',
  id: 'part',
  itemIds: const ['item-a'],
  progressIds: const ['part'],
  count: count,
  foundInRaid: false,
  gate: RequirementGate(),
  stationId: 'station-a',
  stationLevel: level,
);

void main() {
  ItemDecision decide({
    CatalogItem? item,
    Iterable<ItemRequirement> needs = const [],
    ProgressFacts? progress,
    bool noProgress = false,
    FirState fir = FirState.yes,
    CatalogSnapshot? catalog,
    ProgressCatalog? progressCatalog,
    bool catalogStale = false,
  }) {
    final i = item ?? saleItem();
    return engine.evaluate(
      i,
      InspectionContext(
        mode: GameMode.pvp,
        now: fixtureNow,
        catalog:
            catalog ??
            decisionCatalog(
              item: i,
              requirements: needs,
              progressCatalog: progressCatalog,
            ),
        progress: noProgress ? null : progress ?? decisionFacts(),
        fir: fir,
        catalogStale: catalogStale,
      ),
    );
  }

  NeedReason only(ItemDecision d) => d.reasons.single;

  /// The task started with one of its three items counted.
  ProgressFacts active() => decisionFacts(
    tasks: const {'task-a': _started},
    objectiveCounts: const {'objective-a': 1},
  );

  /// The task not started, one of its three items counted.
  ProgressFacts unstarted({int? level = 30}) =>
      decisionFacts(objectiveCounts: const {'objective-a': 1}, level: level);

  group('progress-authority', () {
    test('progress-authority: Finished task from the logs', () {
      final r = only(
        decide(
          needs: [_task()],
          progress: decisionFacts(tasks: const {'task-a': _finished}),
        ),
      );
      expect(r.state, NeedState.satisfied);
      expect(r.detail, 'task completed');
    });
    test('progress-authority: Empty wipe with level set', () {
      final r = only(
        decide(
          needs: [_task(count: 2, minLevel: 10)],
          progress: decisionFacts(level: 20),
        ),
      );
      expect(r.state, NeedState.actionable);
      expect(r.detail, 'needed now');
      expect(r.remaining, 2);
    });
    test('progress-authority: Level unset', () {
      final d = decide(
        needs: [
          _task(minLevel: 10),
          _task(sourceId: 'task-b', objective: 'objective-b', minLevel: 2),
          _task(sourceId: 'task-c', objective: 'objective-c', minLevel: 1),
        ],
        progress: decisionFacts(level: null),
      );
      expect(d.reasons.map((r) => r.state), [
        NeedState.unresolved,
        NeedState.unresolved,
        NeedState.actionable,
      ]);
      expect(
        d.reasons.first.detail,
        'not known yet whether you can do this (level, trader, skill or another requirement)',
      );
      expect(d.reasons.last.remaining, 3);
    });
    test('progress-authority: Counted objective', () {
      final r = only(decide(needs: [_task()], progress: active()));
      expect(r.state, NeedState.actionable);
      expect(r.remaining, 2);
    });
    test('progress-authority: Started task skips its gates', () {
      final r = only(
        decide(
          needs: [
            _task(
              count: 2,
              minLevel: 40,
              faction: 'BEAR',
              statuses: const {
                'prior': ['complete'],
              },
              stations: const {'station-a': 3},
            ),
          ],
          progress: decisionFacts(
            tasks: const {'task-a': _started},
            level: null,
            faction: null,
          ),
        ),
      );
      expect(r.state, NeedState.actionable);
      expect(r.detail, 'needed now');
      expect(r.remaining, 2);
    });
    test(
      'progress-authority: Started task with an unrecorded prerequisite',
      () {
        final need = _task(
          statuses: const {
            'prior': ['complete'],
          },
        );
        final started = only(
          decide(
            needs: [need],
            progress: decisionFacts(tasks: const {'task-a': _started}),
          ),
        );
        expect(started.state, NeedState.actionable);
        expect(started.detail, 'needed now');
        final unstartedTask = only(decide(needs: [need]));
        expect(unstartedTask.state, NeedState.future);
        expect(unstartedTask.detail, 'needed later');
      },
    );
    test('progress-authority: Restartable failed task', () {
      final r = only(
        decide(
          needs: [_task()],
          progress: decisionFacts(tasks: const {'task-a': _failed}),
          progressCatalog: _taskCatalog(restartable: true),
        ),
      );
      expect(r.state, NeedState.actionable);
      expect(r.remaining, 3);
    });
    test('progress-authority: Non-restartable failed task', () {
      for (final catalog in [
        _taskCatalog(restartable: false),
        _taskCatalog(),
        null,
      ]) {
        final r = only(
          decide(
            needs: [_task()],
            progress: decisionFacts(tasks: const {'task-a': _failed}),
            progressCatalog: catalog,
          ),
        );
        expect(r.state, NeedState.satisfied);
        expect(r.detail, 'task failed; no active obligation');
      }
    });
    test('progress-authority: Level 1 minimum with no level', () {
      final r = only(
        decide(
          needs: [_task(minLevel: 1)],
          progress: decisionFacts(level: null),
        ),
      );
      expect(r.state, NeedState.actionable);
    });
    test('progress-authority: Unset faction', () {
      final r = only(
        decide(
          needs: [_task(faction: 'USEC')],
          progress: decisionFacts(faction: null),
        ),
      );
      expect(r.state, NeedState.unresolved);
      final other = only(
        decide(
          needs: [_task(faction: 'USEC')],
          progress: decisionFacts(faction: 'BEAR'),
        ),
      );
      expect(other.state, NeedState.irrelevant);
    });
    test('progress-authority: Level built', () {
      final r = only(
        decide(
          needs: [_hideout()],
          progress: decisionFacts(stations: const {'station-a': 2}),
        ),
      );
      expect(r.state, NeedState.satisfied);
    });
    test('progress-authority: Next level', () {
      final r = only(
        decide(
          needs: [_hideout()],
          progress: decisionFacts(stations: const {'station-a': 1}),
        ),
      );
      expect(r.state, NeedState.actionable);
      expect(r.detail, 'needed now');
      expect(r.remaining, 2);
    });
    test('progress-authority: Later level', () {
      final r = only(decide(needs: [_hideout()]));
      expect(r.state, NeedState.future);
      expect(r.detail, 'needed later');
      expect(r.remaining, 2);
    });
    test('progress-authority: Edition-gated task', () {
      for (final need in [
        _task(editions: const [2]),
        _task(editionIds: const ['edge_of_darkness']),
      ]) {
        final r = only(
          decide(
            needs: [need],
            progress: decisionFacts(edition: 'edge_of_darkness'),
          ),
        );
        expect(r.state, NeedState.unresolved);
      }
    });
    test('progress-authority: No edition list', () {
      final r = only(
        decide(needs: [_task()], progress: decisionFacts(edition: null)),
      );
      expect(r.state, NeedState.actionable);
    });
  });

  group('task-catalog', () {
    test('task-catalog: Task catalog unavailable', () {
      final needs = [_task(), _hideout()];
      final scenarios = [
        decisionFacts(),
        active(),
        unstarted(),
        decisionFacts(tasks: const {'task-a': _finished}),
        decisionFacts(tasks: const {'task-a': _failed}),
        decisionFacts(stations: const {'station-a': 1}, level: null),
      ];
      List<Object?> view(ItemDecision d) => [
        d.recommendation,
        d.firNeed,
        d.nonFirNeed,
        d.unknownFirNeed,
        d.openInputs,
        for (final r in d.reasons)
          (r.requirement.id, r.state, r.remaining, r.message),
      ];
      for (final facts in scenarios) {
        expect(
          view(
            decide(
              needs: needs,
              progress: facts,
              progressCatalog: _taskCatalog(restartable: false),
            ),
          ),
          view(decide(needs: needs, progress: facts)),
        );
      }
      final failed = decisionFacts(tasks: const {'task-a': _failed});
      final restartable = decide(
        needs: [_task()],
        progress: failed,
        progressCatalog: _taskCatalog(restartable: true),
      );
      final without = decide(needs: [_task()], progress: failed);
      expect(restartable.reasons.single.state, NeedState.actionable);
      expect(without.reasons.single.state, NeedState.satisfied);
    });
  });

  test('Keep outranks high price, future needs and unrelated uncertainty', () {
    final d = decide(
      needs: [taskNeed(fir: false)],
      progress: active(),
      fir: FirState.unknown,
    );
    expect(d.recommendation, Recommendation.keep);
    expect(d.nonFirNeed, 2);
    expect(d.warnings, contains('Found in raid unknown for this item'));
  });
  test('warnings use plain wording for stale data and unknown flea rules', () {
    final stale = decide(catalogStale: true);
    expect(stale.warnings, contains('Item data missing or out of date'));
    final unknownRule = decide(item: saleItem(noFlea: null, minimum: 0));
    expect(
      unknownRule.warnings,
      contains('Not known whether this item can be sold on the flea market'),
    );
    final noProgress = decide(noProgress: true);
    expect(noProgress.warnings, contains('Progress unavailable'));
  });
  test('FIR unknown is Check, Yes is Keep, No cannot satisfy FIR need', () {
    for (final fir in FirState.values) {
      final d = decide(needs: [taskNeed()], progress: active(), fir: fir);
      expect(d.recommendation, switch (fir) {
        FirState.unknown => Recommendation.check,
        FirState.yes => Recommendation.keep,
        FirState.no => Recommendation.trader,
      });
      expect(d.firNeed, 2);
    }
  });
  test('known future level need wins later', () {
    final d = decide(
      needs: [
        taskNeed(
          gate: RequirementGate(
            minPlayerLevel: 40,
            faction: 'Any',
            editions: const [],
            taskStatuses: const {},
          ),
        ),
      ],
      progress: unstarted(),
    );
    expect(d.recommendation, Recommendation.keepForLater);
  });
  test('an unmet complete-only prerequisite gives later, a met one now', () {
    final need = taskNeed(
      gate: RequirementGate(
        minPlayerLevel: 1,
        faction: 'Any',
        editions: const [],
        taskStatuses: const {
          'prior': ['complete'],
        },
      ),
    );
    ProgressFacts withPrior(ProgressTaskStatus? prior) => decisionFacts(
      tasks: {'prior': ?prior},
      objectiveCounts: const {'objective-a': 1},
    );
    for (final prior in [null, _started]) {
      expect(
        decide(needs: [need], progress: withPrior(prior)).recommendation,
        Recommendation.keepForLater,
      );
    }
    expect(
      decide(needs: [need], progress: withPrior(_finished)).recommendation,
      Recommendation.keep,
    );
    expect(
      only(decide(needs: [need], progress: withPrior(_failed))).state,
      NeedState.irrelevant,
    );
  });
  for (final gate in [
    RequirementGate(unknownTraderOrSkill: true),
    RequirementGate(incomplete: true),
  ]) {
    test('unknown gate stays Check ${gate.toJson()}', () {
      expect(
        decide(
          needs: [taskNeed(gate: gate)],
          progress: unstarted(),
        ).recommendation,
        Recommendation.check,
      );
    });
  }
  test('a station gate is met at the level and later below it', () {
    final need = taskNeed(
      gate: RequirementGate(
        minPlayerLevel: 1,
        faction: 'Any',
        editions: const [],
        taskStatuses: const {},
        stations: const {'station-a': 2},
      ),
    );
    ProgressFacts at(int level) => decisionFacts(
      stations: {'station-a': level},
      objectiveCounts: const {'objective-a': 1},
    );
    expect(
      decide(needs: [need], progress: at(2)).recommendation,
      Recommendation.keep,
    );
    expect(
      decide(needs: [need], progress: at(1)).recommendation,
      Recommendation.keepForLater,
    );
  });
  test('catalog string edition IDs always leave the gate unknown', () {
    expect(
      decide(
        needs: [
          taskNeed(
            gate: RequirementGate(editionIds: const ['edge_of_darkness']),
          ),
        ],
        progress: unstarted(),
      ).recommendation,
      Recommendation.check,
    );
  });
  test(
    'omitted task level/faction/prerequisite/edition gate facts stay unknown',
    () {
      expect(
        decide(
          needs: [taskNeed(gate: RequirementGate())],
          progress: unstarted(),
        ).recommendation,
        Recommendation.check,
      );
    },
  );
  test('known future plus unknown trader gate does not claim later', () {
    expect(
      decide(
        needs: [
          taskNeed(
            gate: RequirementGate(
              minPlayerLevel: 40,
              unknownTraderOrSkill: true,
            ),
          ),
        ],
        progress: unstarted(),
      ).recommendation,
      Recommendation.check,
    );
  });
  test('finished and failed tasks do not retain an obligation', () {
    for (final task in [_finished, _failed]) {
      final d = decide(
        needs: [taskNeed()],
        progress: decisionFacts(tasks: {'task-a': task}),
      );
      expect(d.recommendation, Recommendation.flea);
    }
  });
  test('an empty wipe counts as not started with nothing handed in', () {
    final d = decide(needs: [taskNeed()], progress: decisionFacts());
    expect(d.recommendation, Recommendation.keep);
    expect(d.firNeed, 3);
  });
  test('missing counts and missing FIR remain unresolved', () {
    expect(
      decide(needs: [taskNeed(count: null)], progress: active()).recommendation,
      Recommendation.check,
    );
    final unknownFir = decide(needs: [taskNeed(fir: null)], progress: active());
    expect(unknownFir.recommendation, Recommendation.check);
    expect(unknownFir.firNeed, isNull);
    expect(unknownFir.nonFirNeed, isNull);
    expect(unknownFir.unknownFirNeed, 2);
  });
  test('completed paired requirement satisfied once and alternatives quantity stays nullable', () {
    final need = taskNeed(
      items: const ['item-a', 'item-b'],
      ids: const ['objective-a', 'give-a'],
    );
    final d = decide(
      needs: [need],
      progress: decisionFacts(
        tasks: const {'task-a': _started},
        objectiveCounts: const {'objective-a': 1, 'give-a': 1},
      ),
    );
    expect(d.reasons.single.remaining, 2);
    expect(d.firNeed, isNull);
    expect(d.recommendation, Recommendation.keep);
    final done = decide(
      needs: [need],
      progress: decisionFacts(
        tasks: const {'task-a': _started},
        objectivesComplete: const {'give-a'},
      ),
    );
    expect(done.recommendation, Recommendation.flea);
  });
  test('hideout level built, next level and later level', () {
    final need = _hideout();
    for (final (level, expected) in [
      (2, Recommendation.flea),
      (3, Recommendation.flea),
      (1, Recommendation.keep),
      (0, Recommendation.keepForLater),
    ]) {
      expect(
        decide(
          needs: [need],
          progress: decisionFacts(stations: {'station-a': level}),
        ).recommendation,
        expected,
        reason: 'station level $level',
      );
    }
  });
  test('hideout parts count zero whatever the objective ids hold', () {
    final r = only(
      decide(
        needs: [_hideout()],
        progress: decisionFacts(
          stations: const {'station-a': 1},
          objectiveCounts: const {'part': 5},
          objectivesComplete: const {'part'},
        ),
      ),
    );
    expect(r.state, NeedState.actionable);
    expect(r.remaining, 2);
  });
  test(
    'faction mismatch is irrelevant and a missing player level is unresolved',
    () {
      expect(
        decide(
          needs: [_task(faction: 'BEAR')],
          progress: unstarted(),
        ).recommendation,
        Recommendation.flea,
      );
      expect(
        decide(
          needs: [_task(minLevel: 10)],
          progress: unstarted(level: null),
        ).recommendation,
        Recommendation.check,
      );
    },
  );
  test('craft/barter optional uses do not become obligations', () {
    final c = fixtureCatalog();
    final uses = c.requirements.where(
      (r) =>
          r.kind == RequirementKind.craft || r.kind == RequirementKind.barter,
    );
    final d = decide(needs: uses);
    expect(d.recommendation, Recommendation.flea);
    expect(d.reasons.every((r) => r.state == NeedState.irrelevant), isTrue);
  });
  test('reason detail is the message without the source name prefix', () {
    final hideout = ItemRequirement(
      kind: RequirementKind.hideout,
      sourceId: 'station-a-2',
      sourceName: 'Defective Wall',
      id: 'part',
      itemIds: const ['item-a'],
      progressIds: const ['part'],
      count: 2,
      foundInRaid: false,
      gate: RequirementGate(),
      stationId: 'station-a',
      stationLevel: 2,
    );
    final craft = fixtureCatalog().requirements.firstWhere(
      (r) => r.kind == RequirementKind.craft,
    );
    final d = decide(needs: [taskNeed(), hideout, craft], progress: active());
    expect(d.reasons, hasLength(3));
    for (final r in d.reasons) {
      expect(r.detail, isNotEmpty);
      expect(r.message, '${r.requirement.sourceName}: ${r.detail}');
    }
  });
  test(
    'a craft tool stays an optional use and leaves the totals unchanged',
    () {
      final craft = fixtureCatalog().requirements.firstWhere(
        (r) => r.kind == RequirementKind.craft,
      );
      ItemRequirement withTool(bool? tool) => ItemRequirement(
        kind: craft.kind,
        sourceId: craft.sourceId,
        sourceName: craft.sourceName,
        id: craft.id,
        itemIds: craft.itemIds,
        progressIds: craft.progressIds,
        count: craft.count,
        foundInRaid: craft.foundInRaid,
        gate: craft.gate,
        optional: craft.optional,
        stationId: craft.stationId,
        stationLevel: craft.stationLevel,
        productItemId: craft.productItemId,
        productCount: craft.productCount,
        tool: tool,
      );
      final plain = decide(
        needs: [taskNeed(), withTool(null)],
        progress: active(),
      );
      final tool = decide(
        needs: [taskNeed(), withTool(true)],
        progress: active(),
      );
      expect(tool.recommendation, plain.recommendation);
      expect(tool.firNeed, plain.firNeed);
      expect(tool.nonFirNeed, plain.nonFirNeed);
      expect(tool.unknownFirNeed, plain.unknownFirNeed);
      expect(
        [for (final r in tool.reasons) (r.state, r.remaining)],
        [for (final r in plain.reasons) (r.state, r.remaining)],
      );
      expect(
        tool.reasons.singleWhere((r) => r.requirement.tool == true).state,
        NeedState.irrelevant,
      );
    },
  );
  test('stale catalog, no progress and mismatched mode block sale and confirmed need', () {
    expect(decide(catalogStale: true).recommendation, Recommendation.check);
    expect(decide(noProgress: true).recommendation, Recommendation.check);
    expect(
      decide(progress: decisionFacts(mode: GameMode.pve)).recommendation,
      Recommendation.check,
    );
    expect(
      decide(
        catalog: decisionCatalog(
          observedAt: fixtureNow.subtract(const Duration(hours: 25)),
        ),
      ).recommendation,
      Recommendation.check,
    );
    // Source times are evidence only: a fresh download without them is
    // not forced to Check by the catalog.
    expect(
      decide(catalog: decisionCatalog(times: const {})).recommendation,
      Recommendation.flea,
    );
  });
  test('noFlea is independent of zero minimum and unknown restriction is not clearance', () {
    expect(
      decide(item: saleItem(noFlea: true, minimum: 0)).recommendation,
      Recommendation.trader,
    );
    expect(
      decide(item: saleItem(noFlea: null, minimum: 0)).recommendation,
      Recommendation.check,
    );
    expect(
      decide(item: saleItem(minimum: null)).recommendation,
      Recommendation.check,
    );
    expect(
      decide(item: saleItem(minimum: 40)).recommendation,
      Recommendation.trader,
    );
  });
  for (final age in [const Duration(hours: 2), const Duration(seconds: -1)]) {
    test('old/future quote Check retains gross values $age', () {
      final d = decide(item: saleItem(quoteAt: fixtureNow.subtract(age)));
      expect(d.recommendation, Recommendation.check);
      expect(d.fleaGross, 400);
      expect(d.traderGross, 120);
    });
  }
  test('absent quote is not renewed by fresh catalog envelope', () {
    final i = CatalogItem(
      id: 'item-a',
      name: 'Synthetic',
      normalizedName: 'synthetic',
      noFlea: false,
      minLevelForFlea: 0,
      fleaPrice: 400,
    );
    final d = decide(item: i);
    expect(d.recommendation, Recommendation.check);
    expect(d.fleaGross, 400);
  });
  test('best named positive cash RUB sale tie ignores USD/EUR/barter/unnamed/nonpositive', () {
    final offers = [
      const CashOffer(traderId: 'trader-b', currency: 'RUB', price: 120),
      const CashOffer(traderId: 'trader-a', currency: 'RUB', price: 120),
      const CashOffer(traderId: 'trader-a', currency: 'USD', price: 500),
      const CashOffer(traderId: 'trader-a', currency: 'EUR', price: 900),
      const CashOffer(
        traderId: 'trader-a',
        currency: 'RUB',
        price: 1000,
        barter: true,
      ),
      const CashOffer(traderId: 'trader-unnamed', currency: 'RUB', price: 2000),
      const CashOffer(traderId: 'trader-a', currency: 'RUB', price: 0),
      const CashOffer(traderId: 'trader-a', currency: 'RUB', price: -1),
      CashOffer(traderId: 'trader-a', currency: 'RUB', price: double.nan),
    ];
    for (final order in [offers, offers.reversed]) {
      final d = decide(item: saleItem(price: 120, offers: order));
      expect(d.recommendation, Recommendation.trader);
      expect(d.traderId, 'trader-a');
      expect(d.traderGross, 120);
      expect(d.traderPerSlot, 30);
    }
  });
  for (final price in [100, 120, 400]) {
    test(
      'fresh positive Flea gross $price beats usable RUB trader only when greater',
      () {
        final d = decide(item: saleItem(price: price));
        expect(
          d.recommendation,
          price > 120 ? Recommendation.flea : Recommendation.trader,
        );
        expect(d.fleaEligible, isTrue);
        expect(d.fleaGross, price);
        expect(d.traderGross, 120);
        expect(d.traderId, 'trader-a');
      },
    );
  }
  test('no positive sale destination is price unavailable', () {
    expect(
      decide(item: saleItem(price: 0, offers: const [])).recommendation,
      Recommendation.priceUnavailable,
    );
  });
  for (final dimensions in [
    (null, 2),
    (0, 2),
    (-1, 2),
    (2, null),
    (double.infinity, 2),
  ]) {
    test('invalid dimensions retain gross without per slot $dimensions', () {
      final d = decide(
        item: saleItem(width: dimensions.$1, height: dimensions.$2),
      );
      expect(d.fleaGross, 400);
      expect(d.fleaPerSlot, isNull);
      expect(d.traderPerSlot, isNull);
    });
  }
  test('invalid/nonpositive quote cannot become a gross zero', () {
    for (final price in [null, 0, -1, double.nan, double.infinity]) {
      expect(decide(item: saleItem(price: price)).fleaGross, isNull);
    }
  });
  test(
    'missing progress/catalog and Unknown mode cannot sell high-price item',
    () {
      final i = saleItem();
      for (final context in [
        InspectionContext(
          mode: GameMode.pvp,
          now: fixtureNow,
          catalog: decisionCatalog(),
          fir: FirState.yes,
        ),
        InspectionContext(
          mode: GameMode.pvp,
          now: fixtureNow,
          progress: decisionFacts(),
          fir: FirState.yes,
        ),
        InspectionContext(
          mode: GameMode.unknown,
          now: fixtureNow,
          catalog: decisionCatalog(),
          progress: decisionFacts(),
          fir: FirState.yes,
        ),
      ]) {
        expect(
          engine.evaluate(i, context).recommendation,
          Recommendation.check,
        );
      }
    },
  );
  test('flat shared-objective completion never resolves distinct active task owners', () {
    final needs = fixtureCatalog(wire: sharedObjectiveWireFixture())
        .requirements
        .where((r) => r.kind == RequirementKind.task)
        .toList();
    for (final (count, complete) in [(1, true), (1, false), (0, false)]) {
      final d = decide(
        needs: needs,
        progress: decisionFacts(
          tasks: const {
            'task-a': _started,
            'task-b': _started,
            'task-c': _started,
          },
          objectiveCounts: {'shared-find-item': count},
          objectivesComplete: {if (complete) 'shared-find-item'},
        ),
      );
      expect(d.recommendation, Recommendation.check);
      expect(d.reasons.length, 3);
      expect(d.reasons.every((r) => r.state == NeedState.unresolved), isTrue);
      expect(d.reasons.every((r) => r.remaining == null), isTrue);
      expect(d.firNeed, isNull);
    }
  });
  test('owning task completion or failure resolves only that shared-objective owner', () {
    final needs = fixtureCatalog(wire: sharedObjectiveWireFixture())
        .requirements
        .where((r) => r.kind == RequirementKind.task)
        .toList();
    final d = decide(
      needs: needs,
      progress: decisionFacts(
        tasks: const {
          'task-a': _finished,
          'task-b': _failed,
          'task-c': _started,
        },
        objectiveCounts: const {'shared-find-item': 1},
        objectivesComplete: const {'shared-find-item'},
      ),
    );
    expect(d.recommendation, Recommendation.check);
    expect(d.reasons.map((r) => (r.requirement.sourceId, r.state)), [
      ('task-a', NeedState.satisfied),
      ('task-b', NeedState.satisfied),
      ('task-c', NeedState.unresolved),
    ]);
    final resolved = decide(
      needs: needs,
      progress: decisionFacts(
        tasks: const {
          'task-a': _finished,
          'task-b': _finished,
          'task-c': _finished,
        },
      ),
    );
    expect(resolved.recommendation, Recommendation.flea);
    expect(
      resolved.reasons.every((r) => r.state == NeedState.satisfied),
      isTrue,
    );
  });
  test('completed find alone does not release unfulfilled paired handover', () {
    final c = fixtureCatalog();
    final need = c.requirements
        .where((r) => r.kind == RequirementKind.task)
        .single;
    final p = decisionFacts(
      tasks: const {'task-a': _started},
      objectiveCounts: const {'find-a': 3, 'give-a': 1},
      objectivesComplete: const {'find-a'},
    );
    final d = decide(needs: [need], progress: p);
    expect(d.recommendation, Recommendation.keep);
    expect(d.reasons.single.remaining, 2);
  });
  test(
    'zero count satisfied and finite invalid requirement quantities unresolved',
    () {
      expect(
        decide(needs: [taskNeed(count: 0)], progress: active()).recommendation,
        Recommendation.flea,
      );
      for (final count in [-1, double.nan, double.infinity]) {
        expect(
          decide(
            needs: [taskNeed(count: count)],
            progress: active(),
          ).recommendation,
          Recommendation.check,
        );
      }
    },
  );
  test('reordered input and identical surface contexts produce same values and reasons', () {
    final needs = [
      taskNeed(),
      ItemRequirement(
        kind: RequirementKind.barter,
        sourceId: 'barter-z',
        sourceName: 'Use',
        id: 'use',
        itemIds: const ['item-a'],
        progressIds: const [],
        count: 1.5,
        foundInRaid: false,
        gate: RequirementGate(),
        optional: true,
      ),
    ];
    final a = decide(needs: needs, progress: active());
    final b = decide(needs: needs.reversed, progress: active());
    expect(a.recommendation, b.recommendation);
    expect(a.fleaGross, b.fleaGross);
    expect(a.traderGross, b.traderGross);
    expect(
      a.reasons.map((r) => (r.requirement.id, r.state, r.remaining, r.message)),
      b.reasons.map((r) => (r.requirement.id, r.state, r.remaining, r.message)),
    );
  });
  group('open inputs', () {
    test('openInputs is empty when nothing is open', () {
      expect(decide().openInputs, isEmpty);
    });
    test('openInputs lists every open input in the fixed order', () {
      final d = decide(
        item: saleItem(quoteAt: fixtureNow.subtract(const Duration(hours: 2))),
        needs: [taskNeed()],
        catalogStale: true,
        noProgress: true,
        fir: FirState.unknown,
      );
      expect(d.openInputs, [
        OpenInput.itemData,
        OpenInput.progress,
        OpenInput.foundInRaid,
        OpenInput.unresolvedNeed,
        OpenInput.fleaEligibility,
        OpenInput.priceTimeStale,
      ]);
    });
    test('a missing or future price time is priceTimeUnknown', () {
      final missing = CatalogItem(
        id: 'item-a',
        name: 'Synthetic',
        normalizedName: 'synthetic',
        noFlea: false,
        minLevelForFlea: 0,
        fleaPrice: 400,
      );
      expect(decide(item: missing).openInputs, [OpenInput.priceTimeUnknown]);
      final future = decide(
        item: saleItem(quoteAt: fixtureNow.add(const Duration(seconds: 1))),
      );
      expect(future.openInputs, [OpenInput.priceTimeUnknown]);
    });
    test('an item that cannot be sold on the Flea ignores its price time', () {
      final d = decide(
        item: saleItem(
          noFlea: true,
          quoteAt: fixtureNow.subtract(const Duration(hours: 2)),
        ),
      );
      expect(d.openInputs, isEmpty);
    });
    test('an unresolved need alone is recorded', () {
      final d = decide(needs: [taskNeed(fir: null)], progress: active());
      expect(d.openInputs, [OpenInput.unresolvedNeed]);
    });
    test('the Flea eligibility input is recorded when the rule is unknown', () {
      final d = decide(item: saleItem(noFlea: null, minimum: 0));
      expect(d.openInputs, [OpenInput.fleaEligibility]);
    });
    test('the price freshness limit is one hour', () {
      expect(priceFreshnessLimit, const Duration(hours: 1));
    });
  });
  test('outputs are immutable', () {
    final d = decide();
    expect(() => d.warnings.clear(), throwsUnsupportedError);
    expect(() => d.reasons.clear(), throwsUnsupportedError);
  });
}
