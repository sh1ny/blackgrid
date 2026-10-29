import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/decision.dart';
import 'package:blackgrid/domain/decision_engine.dart';
import 'package:blackgrid/domain/inspection_context.dart';
import 'package:blackgrid/domain/progress.dart';

import '../fixtures/m1/catalog/fixture.dart';

const engine = DecisionEngine();
const activeTask = EntityProgress(
  complete: false,
  failed: false,
  invalid: false,
);
const remainingObjective = EntityProgress(
  complete: false,
  count: 1,
  invalid: false,
);

void main() {
  ItemDecision decide({
    CatalogItem? item,
    Iterable<ItemRequirement> needs = const [],
    ProgressSnapshot? progress,
    FirState fir = FirState.yes,
    CatalogSnapshot? catalog,
    bool catalogStale = false,
    bool progressStale = false,
  }) {
    final i = item ?? saleItem();
    return engine.evaluate(
      i,
      InspectionContext(
        mode: GameMode.pvp,
        now: fixtureNow,
        catalog: catalog ?? decisionCatalog(item: i, requirements: needs),
        progress: progress ?? decisionProgress(),
        fir: fir,
        catalogStale: catalogStale,
        progressStale: progressStale,
      ),
    );
  }

  ProgressSnapshot active({RequirementGate? gate}) => decisionProgress(
    tasks: const {'task-a': activeTask},
    objectives: const {'objective-a': remainingObjective},
  );
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
      progress: active(),
    );
    expect(d.recommendation, Recommendation.keepForLater);
  });
  test(
    'known unmet prerequisite gives later; absent prerequisite stays Check',
    () {
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
      expect(
        decide(
          needs: [need],
          progress: decisionProgress(
            tasks: const {'task-a': activeTask, 'prior': activeTask},
            objectives: const {'objective-a': remainingObjective},
          ),
        ).recommendation,
        Recommendation.keepForLater,
      );
      expect(
        decide(needs: [need], progress: active()).recommendation,
        Recommendation.check,
      );
    },
  );
  for (final gate in [
    RequirementGate(unknownTraderOrSkill: true),
    RequirementGate(incomplete: true),
    RequirementGate(stations: const {'missing': 1}),
  ]) {
    test('unknown gate stays Check ${gate.toJson()}', () {
      expect(
        decide(
          needs: [taskNeed(gate: gate)],
          progress: active(),
        ).recommendation,
        Recommendation.check,
      );
    });
  }
  test('catalog string edition lacks documented Tracker numeric mapping', () {
    expect(
      decide(
        needs: [
          taskNeed(
            gate: RequirementGate(editionIds: const ['edge_of_darkness']),
          ),
        ],
        progress: active(),
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
          progress: active(),
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
        progress: active(),
      ).recommendation,
      Recommendation.check,
    );
  });
  test('completed/failed tasks do not retain and invalid task stays Check', () {
    for (final task in [
      const EntityProgress(complete: true),
      const EntityProgress(complete: false, failed: true),
      const EntityProgress(complete: false, invalid: true),
    ]) {
      final d = decide(
        needs: [taskNeed()],
        progress: decisionProgress(tasks: {'task-a': task}),
      );
      expect(
        d.recommendation,
        task.invalid == true ? Recommendation.check : Recommendation.flea,
      );
    }
  });
  test('missing task and valid empty arrays mean unknown entity, not zero', () {
    final d = decide(needs: [taskNeed()], progress: decisionProgress());
    expect(d.recommendation, Recommendation.check);
    expect(d.firNeed, isNull);
  });
  test(
    'missing counts, missing FIR and missing objective remain unresolved',
    () {
      expect(
        decide(
          needs: [taskNeed(count: null)],
          progress: active(),
        ).recommendation,
        Recommendation.check,
      );
      final unknownFir = decide(
        needs: [taskNeed(fir: null)],
        progress: active(),
      );
      expect(unknownFir.recommendation, Recommendation.check);
      expect(unknownFir.firNeed, isNull);
      expect(unknownFir.nonFirNeed, isNull);
      expect(unknownFir.unknownFirNeed, 2);
      expect(
        decide(
          needs: [taskNeed()],
          progress: decisionProgress(
            tasks: const {'task-a': activeTask},
            objectives: const {'objective-a': EntityProgress(complete: false)},
          ),
        ).recommendation,
        Recommendation.check,
      );
    },
  );
  test('completed paired requirement satisfied once and alternatives quantity stays nullable', () {
    final need = taskNeed(
      items: const ['item-a', 'item-b'],
      ids: const ['objective-a', 'give-a'],
    );
    final d = decide(
      needs: [need],
      progress: decisionProgress(
        tasks: const {'task-a': activeTask},
        objectives: const {
          'objective-a': remainingObjective,
          'give-a': remainingObjective,
        },
      ),
    );
    expect(d.reasons.single.remaining, 2);
    expect(d.firNeed, isNull);
    expect(d.recommendation, Recommendation.keep);
    final done = decide(
      needs: [need],
      progress: decisionProgress(
        tasks: const {'task-a': activeTask},
        objectives: const {'give-a': EntityProgress(complete: true)},
      ),
    );
    expect(done.recommendation, Recommendation.flea);
  });
  test('hideout module/part completion and previous station level gates', () {
    final need = ItemRequirement(
      kind: RequirementKind.hideout,
      sourceId: 'station-a-2',
      sourceName: 'Station',
      id: 'part',
      itemIds: const ['item-a'],
      progressIds: const ['part'],
      count: 2,
      foundInRaid: false,
      gate: RequirementGate(),
      stationId: 'station-a',
      stationLevel: 2,
    );
    for (final completed in [true, false]) {
      final p = decisionProgress(
        modules: {
          'station-a-2': const EntityProgress(complete: false),
          'station-a-1': EntityProgress(complete: completed),
        },
        parts: const {'part': EntityProgress(complete: false, count: 1)},
      );
      expect(
        decide(needs: [need], progress: p).recommendation,
        completed ? Recommendation.keep : Recommendation.keepForLater,
      );
    }
    expect(
      decide(
        needs: [need],
        progress: decisionProgress(
          modules: const {'station-a-2': EntityProgress(complete: true)},
        ),
      ).recommendation,
      Recommendation.flea,
    );
    expect(
      decide(
        needs: [need],
        progress: decisionProgress(
          modules: const {'station-a-2': EntityProgress(complete: false)},
          parts: const {'part': EntityProgress(complete: true)},
        ),
      ).recommendation,
      Recommendation.flea,
    );
  });
  test(
    'faction/edition mismatch irrelevant; missing player gates unresolved',
    () {
      expect(
        decide(
          needs: [taskNeed(gate: RequirementGate(faction: 'BEAR'))],
          progress: active(),
        ).recommendation,
        Recommendation.flea,
      );
      expect(
        decide(
          needs: [
            taskNeed(gate: RequirementGate(editions: const [2])),
          ],
          progress: active(),
        ).recommendation,
        Recommendation.flea,
      );
      final p = decisionProgress(
        playerLevel: null,
        tasks: const {'task-a': activeTask},
        objectives: const {'objective-a': remainingObjective},
      );
      expect(
        decide(needs: [taskNeed()], progress: p).recommendation,
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
  test(
    'stale catalog/progress and mismatched mode block sale and confirmed need',
    () {
      expect(decide(catalogStale: true).recommendation, Recommendation.check);
      expect(decide(progressStale: true).recommendation, Recommendation.check);
      expect(
        decide(progress: decisionProgress(mode: GameMode.pve)).recommendation,
        Recommendation.check,
      );
      expect(
        decide(
          progress: decisionProgress(
            observedAt: fixtureNow.subtract(const Duration(minutes: 15)),
          ),
        ).recommendation,
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
    },
  );
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
          progress: decisionProgress(),
          fir: FirState.yes,
        ),
        InspectionContext(
          mode: GameMode.unknown,
          now: fixtureNow,
          catalog: decisionCatalog(),
          progress: decisionProgress(),
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
    for (final objective in [
      const EntityProgress(complete: true, count: 1, invalid: false),
      const EntityProgress(complete: false, count: 1, invalid: false),
      const EntityProgress(complete: false, count: 0, invalid: false),
    ]) {
      final d = decide(
        needs: needs,
        progress: decisionProgress(
          tasks: const {
            'task-a': activeTask,
            'task-b': activeTask,
            'task-c': activeTask,
          },
          objectives: {'shared-find-item': objective},
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
      progress: decisionProgress(
        tasks: const {
          'task-a': EntityProgress(complete: true, invalid: false),
          'task-b': EntityProgress(
            complete: false,
            failed: true,
            invalid: false,
          ),
          'task-c': activeTask,
        },
        objectives: const {
          'shared-find-item': EntityProgress(
            complete: true,
            count: 1,
            invalid: false,
          ),
        },
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
      progress: decisionProgress(
        tasks: const {
          'task-a': EntityProgress(complete: true, invalid: false),
          'task-b': EntityProgress(complete: true, invalid: false),
          'task-c': EntityProgress(complete: true, invalid: false),
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
    final p = decisionProgress(
      tasks: const {'task-a': activeTask},
      objectives: const {
        'find-a': EntityProgress(complete: true, count: 3, invalid: false),
        'give-a': EntityProgress(complete: false, count: 1, invalid: false),
      },
    );
    final d = decide(needs: [need], progress: p);
    expect(d.recommendation, Recommendation.keep);
    expect(d.reasons.single.remaining, 2);
  });
  test('invalid completion cannot erase unresolved task evidence', () {
    expect(
      decide(
        needs: [taskNeed()],
        progress: decisionProgress(
          tasks: const {
            'task-a': EntityProgress(complete: true, invalid: true),
          },
        ),
      ).recommendation,
      Recommendation.check,
    );
    expect(
      decide(
        needs: [taskNeed()],
        progress: decisionProgress(
          tasks: const {'task-a': activeTask},
          objectives: const {
            'objective-a': EntityProgress(complete: true, invalid: true),
          },
        ),
      ).recommendation,
      Recommendation.check,
    );
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
  test('outputs are immutable', () {
    final d = decide();
    expect(() => d.warnings.clear(), throwsUnsupportedError);
    expect(() => d.reasons.clear(), throwsUnsupportedError);
  });
}
