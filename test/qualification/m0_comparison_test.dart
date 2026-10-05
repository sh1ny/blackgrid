import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/compare.dart';
import '../../tool/qualification/contracts.dart';

const freeze =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const inputHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, dynamic> identity(String label, [String? id]) => {
  'label': label,
  'item_id': id,
  if (id == null) 'item_id_reason': 'Independent label has no unique identity.',
};

Map<String, dynamic> outcome(String disposition, [String? id]) => {
  'disposition': disposition,
  'item_id': id,
  if (id == null) 'item_id_reason': 'Reference did not select an identity.',
};

Map<String, dynamic> roi(num x) => {'x': x, 'y': 20, 'width': 80, 'height': 24};

Map<String, dynamic> fixture(
  String id,
  String profile,
  Map<String, dynamic> truth,
) => {
  'id': id,
  'source_id': 'authored-$id',
  'display_cell_id': '1920-100',
  'role': 'reference_characterization',
  'profile': profile,
  'seam': 'synthetic-serialized-$profile',
  'reference_eligible': true,
  'input': {
    'path': 'synthetic/$id.json',
    'sha256': inputHash,
    'width': 1920,
    'height': 1080,
  },
  'acquisition': 'synthetic',
  'provenance_ids': ['synthetic-author'],
  'adjudication_ids': ['independent-review'],
  'truth': truth,
};

Map<String, dynamic> manifest(List<Map<String, dynamic>> cases) => {
  'schema_version': 1,
  'record_type': 'fixture_manifest',
  'id': 'synthetic-manifest',
  'corpus_version': 'corpus-1',
  'annotation_version': 'labels-1',
  'catalog_version': 'catalog-1',
  'config_version': 'host-settings-1',
  'mode': 'pve',
  'freeze_id': freeze,
  'cases': cases,
};

Map<String, dynamic> observation(
  String id,
  String profile,
  Map<String, dynamic> result,
) => {
  'case_id': id,
  'input_sha256': inputHash,
  'profile': profile,
  'status': 'observed',
  'result': result,
  // A reference-supplied claim must never replace independent truth.
  'comparison': {'claim': 'correct'},
  'stage_timings': <dynamic>[],
  'errors': <dynamic>[],
};

Map<String, dynamic> results(
  Map<String, dynamic> m,
  List<Map<String, dynamic>> rows,
) => {
  'schema_version': 1,
  'record_type': 'oracle_results',
  'id': 'synthetic-results',
  'provenance_ids': ['synthetic-author'],
  'freeze_id': m['freeze_id'],
  'run_id': 'serialized-run',
  'environment_id': 'synthetic-environment',
  'fixture_manifest_sha256': sha256Json(m),
  'comparison_basis': {
    for (final key in [
      'corpus_version',
      'annotation_version',
      'catalog_version',
      'config_version',
      'mode',
      'freeze_id',
    ])
      key: m[key],
  },
  'observations': rows,
};

Map<String, dynamic> inspectionTruth(String label, [String? id]) => {
  ...identity(label, id),
  'title_roi': roi(10),
  'geometry_tolerance': 2,
};

Map<String, dynamic> engine(String disposition, [String? id]) => {
  'marker': {'x': 10, 'y': 20, 'score': .9},
  'title_roi': roi(10),
  'ocr_text': 'Synthetic title',
  'candidates': <dynamic>[],
  'outcome': outcome(disposition, id),
};

Map<String, dynamic> policyTruth(String expected, {bool divergence = false}) =>
    {
      ...identity('readable_positive', 'item-a'),
      'target_policy': <String, dynamic>{
        'id': 'conservative-1',
        'decision': expected,
        'inputs': {
          'instance_fir': null,
          'instance_fir_reason': 'Critical instance fact unavailable.',
          'keep_need': false,
        },
        'rationale': 'Unknown critical FIR requires Check, not an unsafe sale.',
        'intentional_divergence': divergence,
      },
    };

Map<String, dynamic> host(String decision, {String id = 'item-a'}) => {
  'selected_evidence_ids': ['inspection-1'],
  'outcome': outcome('accepted', id),
  'decision': decision,
  'reasons': ['Reference chose its legacy sale rule.'],
  'facts': {
    'instance_fir': null,
    'instance_fir_reason': 'Unknown to reference.',
  },
  'snapshot_ids': ['catalog-1', 'progress-1'],
  'target_policy_id': 'conservative-1',
};

Map<String, dynamic> mapTruth() => {
  'frame_revision': 1,
  'artwork_pixel': {'x': 960, 'y': 2720},
  'normalized': {'x': .234375, 'y': .6640625},
  'game_xyz': {'x': 10, 'y': null, 'y_reason': 'Altitude unknown.', 'z': 20},
  'floor_group_id': 'floor-main',
  'heading': {'degrees': 359, 'convention': 'clockwise-north'},
  'tolerances': {
    'artwork_pixel': 2,
    'normalized': .0005,
    'game_xyz': .01,
    'heading': 2,
  },
};

Map<String, dynamic> mapResult() => {
  'frame_revision': 1,
  'artwork_pixel': {'x': 960, 'y': 2720},
  'normalized': {'x': .234375, 'y': .6640625},
  'game_xyz': {'x': 10, 'y': null, 'y_reason': 'Altitude unknown.', 'z': 20},
  'floor_group_id': 'floor-main',
  'heading': {'degrees': 0, 'convention': 'clockwise-north'},
};

Map<String, dynamic> panelTruth(
  String disposition, {
  List<String> ids = const [],
}) => {
  'map_id': 'customs',
  'disposition': disposition,
  'extract_text': '',
  'transit_text': '',
  'matched_ids': ids,
};

Map<String, dynamic> panel(
  String disposition, {
  String map = 'customs',
  List<String> ids = const [],
}) => {
  ...panelTruth(disposition, ids: ids),
  'map_id': map,
  'ocr_spans': <dynamic>[],
};

Map<String, dynamic> multiTruth() => {
  'geometry_tolerance': 2,
  'inspections': [
    {
      'id': 'left',
      ...identity('readable_positive', 'item-a'),
      'title_roi': roi(10),
    },
    {
      'id': 'right',
      ...identity('readable_positive', 'item-b'),
      'title_roi': roi(300),
    },
  ],
};

Map<String, dynamic> detection(String id, num x, String item) => {
  'id': id,
  ...engine('recognized', item),
  'title_roi': roi(x),
};

Map<String, dynamic> multi(List<Map<String, dynamic>> detections) => {
  'detections': detections,
  'unmatched': <dynamic>[],
  'duplicates': <dynamic>[],
};

Map<String, dynamic> compareOne(
  String profile,
  Map<String, dynamic> truth,
  Map<String, dynamic> actual,
) {
  final m = manifest([fixture('case', profile, truth)]);
  return compareReferenceResults(
    m,
    results(m, [observation('case', profile, actual)]),
  );
}

void main() {
  test('catalog-valid swapped quantity identities remain wrong independent positives', () {
    final m = manifest([
      fixture(
        'quantity-5',
        'engine_inspection',
        inspectionTruth('readable_positive', 'item-5'),
      ),
      fixture(
        'quantity-50',
        'engine_inspection',
        inspectionTruth('readable_positive', 'item-50'),
      ),
    ]);
    m['catalog_item_ids'] = ['item-5', 'item-50'];
    final report = compareReferenceResults(
      m,
      results(m, [
        observation(
          'quantity-5',
          'engine_inspection',
          engine('recognized', 'item-50'),
        ),
        observation(
          'quantity-50',
          'engine_inspection',
          engine('recognized', 'item-5'),
        ),
      ]),
    );
    expect(report['metrics']['wrong_positive_ids'], 2);
    expect(report['metrics']['wrong_identities'], 2);
    expect(report['evidence_validity'], 'pass');
    expect(report['reference_behavior'], 'defects_observed');
  });

  test(
    'wrong host positive and accepted chrome are separate and aggregated',
    () {
      final negative = policyTruth('Check');
      negative.addAll(identity('chrome'));
      final m = manifest([
        fixture('positive', 'host_resolution', policyTruth('Check')),
        fixture('chrome', 'host_resolution', negative),
      ]);
      final report = compareReferenceResults(
        m,
        results(m, [
          observation(
            'positive',
            'host_resolution',
            host('Check', id: 'item-b'),
          ),
          observation('chrome', 'host_resolution', host('Check')),
        ]),
      );
      expect(report['metrics']['wrong_positive_ids'], 1);
      expect(report['metrics']['accepted_negatives'], 1);
      expect(report['metrics']['wrong_identities'], 2);
      expect(report['evidence_validity'], 'pass');
    },
  );

  test('genuine no-inspection negative retains null geometry rather than inventing a ROI', () {
    final truth = inspectionTruth('rejection');
    truth['title_roi'] = null;
    truth['title_roi_reason'] =
        'Independent annotation confirms no inspection window.';
    final actual = engine('rejected');
    actual['title_roi'] = null;
    actual['title_roi_reason'] = 'No inspection title found.';
    actual['marker'] = null;
    actual['marker_reason'] = 'No marker found.';
    final report = compareOne('engine_inspection', truth, actual);
    expect(report['evidence_validity'], 'pass');
    expect(report['reference_behavior'], 'matches_independent_truth');
    expect(report['metrics']['wrong_identities'], 0);
  });

  test(
    'recognized output missing applicable marker geometry is unverified',
    () {
      final actual = engine('recognized', 'item-a');
      actual['marker'] = null;
      actual['marker_reason'] = 'Marker position was not serialized.';
      final report = compareOne(
        'engine_inspection',
        inspectionTruth('readable_positive', 'item-a'),
        actual,
      );
      expect(report['evidence_validity'], 'unverified');
      expect(report['cases'][0]['unavailable'], contains('marker'));
    },
  );

  test('explicitly unavailable recognized identity stays unverified, not a wrong ID', () {
    final report = compareOne(
      'engine_inspection',
      inspectionTruth('readable_positive', 'item-a'),
      engine('recognized'),
    );
    expect(report['evidence_validity'], 'unverified');
    expect(report['metrics']['wrong_identities'], 0);
    expect(report['cases'][0]['unavailable'], contains('outcome.item_id'));
  });

  test(
    'all independent negative classes reject recognized false positives',
    () {
      for (final label in ['rejection', 'chrome', 'ambiguous', 'occluded']) {
        final report = compareOne(
          'engine_inspection',
          inspectionTruth(label),
          engine('recognized', 'item-a'),
        );
        expect(report['metrics']['recognized_negatives'], 1, reason: label);
        expect(report['metrics']['wrong_identities'], 1, reason: label);
      }
    },
  );

  test('engine recognition alone never establishes host acceptance or actionable advice', () {
    final report = compareOne(
      'engine_inspection',
      inspectionTruth('readable_positive', 'item-a'),
      engine('recognized', 'item-a'),
    );
    expect(report['metrics']['correct_positive_ids'], 1);
    expect(report['metrics']['host_accepted_identities'], 0);
    expect(report['metrics']['actionable_advice'], 0);
    expect(report['profiles']['host_resolution']['observed'], 0);
  });

  test('missing, error and unverified rows stay in planned denominator without fabricated attempts', () {
    final m = manifest([
      for (final id in ['missing', 'native-error', 'unverified'])
        fixture(
          id,
          'engine_inspection',
          inspectionTruth('readable_positive', 'item-a'),
        ),
    ]);
    final report = compareReferenceResults(
      m,
      results(m, [
        {
          'case_id': 'native-error',
          'profile': 'engine_inspection',
          'input_sha256': inputHash,
          'status': 'error',
          'result': null,
          'result_reason': 'Native model load failed.',
          'comparison': null,
          'comparison_reason': 'No recognized observation.',
          'stage_timings': <dynamic>[],
          'errors': ['Native model load failed.'],
        },
        {
          'case_id': 'unverified',
          'profile': 'engine_inspection',
          'input_sha256': inputHash,
          'status': 'unverified',
          'result': null,
          'result_reason': 'Observation unavailable.',
          'comparison': null,
          'comparison_reason': 'No observation.',
          'stage_timings': <dynamic>[],
          'errors': <dynamic>[],
        },
      ]),
    );
    expect(report['denominators']['eligible_cases'], 3);
    expect(report['denominators']['attempted_rows'], 2);
    expect(report['denominators']['missing_rows'], 1);
    expect(report['denominators']['errors'], 1);
    expect(report['denominators']['unverified'], 1);
    expect(report['evidence_validity'], 'unverified');
    expect(report['cases'][0]['status'], 'missing');
    expect(report['cases'][0]['attempted'], false);
  });

  test('genuine host rejection with explicitly inapplicable advice is valid evidence', () {
    final truth = policyTruth('Check');
    truth.addAll(identity('ambiguous'));
    truth['target_policy']['decision'] = null;
    truth['target_policy']['decision_reason'] =
        'No actionable advice for ambiguous identity.';
    final actual = host('Check');
    actual['outcome'] = outcome('rejected');
    actual['selected_evidence_ids'] = <String>[];
    actual['decision'] = null;
    actual['decision_reason'] =
        'Host rejected identity; advice is inapplicable.';
    final report = compareOne('host_resolution', truth, actual);
    expect(report['evidence_validity'], 'pass');
    expect(report['reference_behavior'], 'matches_independent_truth');
    expect(report['metrics']['actionable_advice'], 0);
    expect(report['metrics']['accepted_negatives'], 0);
  });

  test(
    'missing host acceptance never becomes actionable from engine-like data',
    () {
      final actual = host('Sell');
      actual['outcome'] = null;
      actual['outcome_reason'] =
          'Only engine recognition was recorded; host acceptance unavailable.';
      final report = compareOne(
        'host_resolution',
        policyTruth('Check', divergence: true),
        actual,
      );
      expect(report['evidence_validity'], 'unverified');
      expect(report['metrics']['host_accepted_identities'], 0);
      expect(report['metrics']['actionable_advice'], 0);
    },
  );

  test('readable-positive abstention is a miss, not wrong identity', () {
    final report = compareOne(
      'engine_inspection',
      inspectionTruth('readable_positive', 'item-a'),
      engine('abstained'),
    );
    expect(report['metrics']['abstentions'], 1);
    expect(report['metrics']['readable_positive_misses'], 1);
    expect(report['metrics']['wrong_identities'], 0);
  });

  test(
    'Sell versus Check keeps safety truth, facts and intentional divergence',
    () {
      final expected = policyTruth('Check', divergence: true);
      final report = compareOne('host_resolution', expected, host('Sell'));
      expect(expected['target_policy']['decision'], 'Check');
      expect(report['evidence_validity'], 'pass');
      expect(report['metrics']['policy_mismatches'], 0);
      expect(report['reference_behavior'], 'intentional_divergences_observed');
      expect(report['divergences'], hasLength(1));
      final divergence = report['divergences'][0];
      expect(divergence['expected_policy']['decision'], 'Check');
      expect(divergence['reference']['decision'], 'Sell');
      expect(divergence['expected_policy']['inputs']['instance_fir'], isNull);
      expect(divergence['reference']['facts']['instance_fir'], isNull);
      expect(divergence['rationale'], contains('FIR'));
    },
  );

  test('unregistered policy mismatch is a defect, not an evidence failure', () {
    final report = compareOne(
      'host_resolution',
      policyTruth('Check'),
      host('Sell'),
    );
    expect(report['metrics']['policy_mismatches'], 1);
    expect(report['divergences'], isEmpty);
    expect(report['evidence_validity'], 'pass');
  });

  test('changed corpus, annotations, catalog, configuration, mode or freeze is refused', () {
    for (final key in [
      'corpus_version',
      'annotation_version',
      'catalog_version',
      'config_version',
      'mode',
      'freeze_id',
    ]) {
      final m = manifest([
        fixture(
          'case',
          'engine_inspection',
          inspectionTruth('readable_positive', 'item-a'),
        ),
      ]);
      final r = results(m, [
        observation(
          'case',
          'engine_inspection',
          engine('recognized', 'item-a'),
        ),
      ]);
      r['comparison_basis'][key] = key == 'freeze_id' ? inputHash : 'changed';
      expect(
        () => compareReferenceResults(m, r),
        throwsA(isA<ContractException>()),
        reason: key,
      );
    }
  });

  test('changed per-case or per-observation snapshots cannot hide behind a matching bundle', () {
    final m = manifest([
      fixture(
        'case',
        'engine_inspection',
        inspectionTruth('readable_positive', 'item-a'),
      ),
    ]);
    final row = observation(
      'case',
      'engine_inspection',
      engine('recognized', 'item-a'),
    );
    row['freeze_id'] = inputHash;
    expect(
      () => compareReferenceResults(m, results(m, [row])),
      throwsA(isA<ContractException>()),
    );
    row.remove('freeze_id');
    row['catalog_version'] = 'catalog-2';
    expect(
      () => compareReferenceResults(m, results(m, [row])),
      throwsA(isA<ContractException>()),
    );
    row.remove('catalog_version');
    m['cases'][0]['config_version'] = 'benchmark-defaults';
    expect(
      () => compareReferenceResults(m, results(m, [row])),
      throwsA(isA<ContractException>()),
    );
  });

  test(
    'manifest hash, input hash, profile and eligible case roster cannot drift',
    () {
      final m = manifest([
        fixture(
          'case',
          'engine_inspection',
          inspectionTruth('readable_positive', 'item-a'),
        ),
      ]);
      for (final mutation in ['manifest', 'input', 'case', 'profile']) {
        final r = results(m, [
          observation(
            'case',
            'engine_inspection',
            engine('recognized', 'item-a'),
          ),
        ]);
        switch (mutation) {
          case 'manifest':
            r['fixture_manifest_sha256'] = inputHash;
          case 'input':
            r['observations'][0]['input_sha256'] = freeze;
          case 'case':
            r['observations'][0]['case_id'] = 'unplanned';
          case 'profile':
            r['observations'][0]['profile'] = 'host_resolution';
        }
        expect(
          () => compareReferenceResults(m, r),
          throwsA(isA<ContractException>()),
          reason: mutation,
        );
      }
    },
  );

  test(
    'expectation-only and ineligible cases never increase replay coverage',
    () {
      final m = manifest([
        fixture(
          'eligible',
          'engine_inspection',
          inspectionTruth('readable_positive', 'item-a'),
        ),
        {
          'id': 'expected-sequence',
          'source_id': 'authored-sequence',
          'display_cell_id': 'not-display-dependent',
          'role': 'expectation_only',
          'provenance_ids': ['synthetic-author'],
          'adjudication_ids': ['review'],
          'truth': {'policy': 'Check'},
          'initial_context': <String, dynamic>{},
          'ordered_inputs': [
            {'event': 'refresh'},
          ],
          'expected_effects': {'scan_count': 0},
        },
        {
          ...fixture(
            'blocked',
            'engine_inspection',
            inspectionTruth('readable_positive', 'item-a'),
          ),
          'reference_eligible': false,
          'eligibility_rationale': 'Missing permission.',
        },
      ]);
      final report = compareReferenceResults(
        m,
        results(m, [
          observation(
            'eligible',
            'engine_inspection',
            engine('recognized', 'item-a'),
          ),
        ]),
      );
      expect(report['denominators']['eligible_cases'], 1);
      expect(report['denominators']['expectation_only_cases'], 1);
      expect(report['denominators']['ineligible_cases'], 1);
      expect(report['expectation_only'][0]['id'], 'expected-sequence');
    },
  );

  test('map tolerance is fixed, heading wraps and unknown altitude differs from zero', () {
    final success = compareOne('map_geometry', mapTruth(), mapResult());
    expect(success['metrics']['geometry_mismatches'], 0);
    final actual = mapResult();
    actual['game_xyz']['y'] = 0;
    actual['game_xyz'].remove('y_reason');
    actual['artwork_pixel']['x'] = 963;
    final report = compareOne('map_geometry', mapTruth(), actual);
    expect(report['metrics']['geometry_mismatches'], 2);
    expect(report['cases'][0]['defects'], contains('game_xyz.y'));
    expect(report['cases'][0]['defects'], contains('artwork_pixel'));
    expect(report['cases'][0]['expected']['tolerances']['artwork_pixel'], 2);
  });

  test('missing map geometry is unverified and cannot pass as a zero', () {
    final actual = mapResult();
    actual['normalized'] = null;
    actual['normalized_reason'] = 'Reference omitted projection.';
    final report = compareOne('map_geometry', mapTruth(), actual);
    expect(report['evidence_validity'], 'unverified');
    expect(report['cases'][0]['unavailable'], contains('normalized'));
    actual.remove('normalized');
    actual.remove('normalized_reason');
    expect(
      () => compareOne('map_geometry', mapTruth(), actual),
      throwsA(isA<ContractException>()),
    );
  });

  test('map inverse, floor, frame and heading discrepancies stay visible', () {
    final actual = mapResult();
    actual['game_xyz']['x'] = 11;
    actual['floor_group_id'] = 'other-floor';
    actual['frame_revision'] = 0;
    actual['heading']['degrees'] = 180;
    final report = compareOne('map_geometry', mapTruth(), actual);
    expect(report['metrics']['geometry_mismatches'], 4);
    expect(report['evidence_validity'], 'pass');
  });

  test(
    'absent panel differs from authoritative present-empty and no-match',
    () {
      for (final disposition in ['present_empty', 'no_match']) {
        final report = compareOne(
          'exfil_panel',
          panelTruth('absent'),
          panel(disposition),
        );
        expect(report['metrics']['panel_mismatches'], 1, reason: disposition);
        expect(report['evidence_validity'], 'pass');
      }
    },
  );

  test(
    'panel map-local identities, ambiguity and required text cannot disappear',
    () {
      final report = compareOne(
        'exfil_panel',
        panelTruth('matched', ids: ['customs-zb1011']),
        panel('matched', map: 'woods', ids: ['woods-zb1011']),
      );
      expect(report['metrics']['panel_mismatches'], 2);
      final ambiguity = compareOne(
        'exfil_panel',
        panelTruth('ambiguous'),
        panel('no_match'),
      );
      expect(ambiguity['metrics']['panel_mismatches'], 1);
      final actual = panel('present_empty');
      actual.remove('extract_text');
      expect(
        () => compareOne('exfil_panel', panelTruth('present_empty'), actual),
        throwsA(isA<ContractException>()),
      );
    },
  );

  test(
    'panel output claiming matched with empty identities is a reference defect',
    () {
      final report = compareOne(
        'exfil_panel',
        panelTruth('matched', ids: ['customs-zb1011']),
        panel('matched'),
      );
      expect(report['metrics']['panel_mismatches'], 1);
      expect(report['reference_behavior'], 'defects_observed');
      expect(report['evidence_validity'], 'pass');
    },
  );

  test(
    'multi associations use geometry rather than observation list order',
    () {
      final report = compareOne(
        'engine_multi',
        multiTruth(),
        multi([
          detection('right-result', 300, 'item-b'),
          detection('left-result', 10, 'item-a'),
        ]),
      );
      expect(report['metrics']['correct_positive_ids'], 2);
      expect(report['metrics']['wrong_positive_ids'], 0);
      expect(report['metrics']['missing_detections'], 0);
      expect(report['cases'][0]['associations'], [
        {
          'inspection_id': 'left',
          'detection_ids': ['left-result'],
        },
        {
          'inspection_id': 'right',
          'detection_ids': ['right-result'],
        },
      ]);
    },
  );

  test('multi identity swaps are defects despite valid identities and reversed output', () {
    final report = compareOne(
      'engine_multi',
      multiTruth(),
      multi([
        detection('right-result', 300, 'item-a'),
        detection('left-result', 10, 'item-b'),
      ]),
    );
    expect(report['metrics']['wrong_positive_ids'], 2);
  });

  test('multi recognized chrome extra counts a false-positive selection without hiding correct windows', () {
    final truth = multiTruth();
    final report = compareOne(
      'engine_multi',
      truth,
      multi([
        detection('left-result', 10, 'item-a'),
        detection('right-result', 300, 'item-b'),
        detection('chrome-extra', 900, 'another-catalog-item'),
      ]),
    );
    expect(report['metrics']['correct_positive_ids'], 2);
    expect(report['metrics']['wrong_identities'], 1);
    expect(report['metrics']['extra_false_positive_selections'], 1);
    expect(report['metrics']['wrong_positive_ids'], 0);
    expect(report['metrics']['recognized_negatives'], 0);
    expect(report['metrics']['accepted_negatives'], 0);
    expect(report['metrics']['missing_detections'], 0);
    expect(report['metrics']['duplicate_detections'], 0);
    expect(report['metrics']['unmatched_detections'], 1);
    expect(report['profiles']['engine_multi']['wrong_identities'], 1);
    expect(
      report['profiles']['engine_multi']['extra_false_positive_selections'],
      1,
    );
    expect(report['denominators'], {
      'eligible_cases': 1,
      'attempted_rows': 1,
      'observed': 1,
      'missing_rows': 0,
      'errors': 0,
      'unverified': 0,
      'complete_comparisons': 1,
      'expectation_only_cases': 0,
      'ineligible_cases': 0,
    });
    expect(report['evidence_validity'], 'pass');
    expect(report['reference_behavior'], 'defects_observed');
    expect(report['cases'][0]['expected'], truth);
    expect(report['cases'][0]['unmatched_detection_ids'], ['chrome-extra']);
    expect(
      report['cases'][0]['defects'],
      contains('chrome-extra.extra_false_positive_selection'),
    );
    expect(report['cases'][0]['associations'], [
      {
        'inspection_id': 'left',
        'detection_ids': ['left-result'],
      },
      {
        'inspection_id': 'right',
        'detection_ids': ['right-result'],
      },
    ]);
  });

  test(
    'multi multiple-match ambiguity does not guess a false-positive identity',
    () {
      final truth = multiTruth();
      truth['inspections'][1]['title_roi'] = roi(11);
      final report = compareOne(
        'engine_multi',
        truth,
        multi([detection('ambiguous-match', 10, 'item-a')]),
      );
      expect(report['metrics']['wrong_identities'], 0);
      expect(report['metrics']['extra_false_positive_selections'], 0);
      expect(report['metrics']['correct_positive_ids'], 0);
      expect(report['metrics']['wrong_positive_ids'], 0);
      expect(report['metrics']['recognized_negatives'], 0);
      expect(report['metrics']['unmatched_detections'], 1);
      expect(report['metrics']['missing_detections'], 2);
      expect(report['cases'][0]['unmatched_detection_ids'], [
        'ambiguous-match',
      ]);
    },
  );

  test('multi unmatched outcomes without known recognized extra geometry retain their original accounting', () {
    for (final disposition in ['rejected', 'abstained', 'error']) {
      final extra = detection('unmatched-$disposition', 900, 'item-a');
      extra['outcome'] = outcome(disposition);
      final report = compareOne(
        'engine_multi',
        multiTruth(),
        multi([
          detection('left-result', 10, 'item-a'),
          detection('right-result', 300, 'item-b'),
          extra,
        ]),
      );
      expect(report['metrics']['wrong_identities'], 0, reason: disposition);
      expect(
        report['metrics']['extra_false_positive_selections'],
        0,
        reason: disposition,
      );
      expect(report['metrics']['unmatched_detections'], 1);
      expect(
        report['metrics']['abstentions'],
        disposition == 'abstained' ? 1 : 0,
      );
      expect(
        report['metrics']['outcome_errors'],
        disposition == 'error' ? 1 : 0,
      );
      expect(
        report['evidence_validity'],
        disposition == 'error' ? 'unverified' : 'pass',
      );
      expect(
        report['denominators']['complete_comparisons'],
        disposition == 'error' ? 0 : 1,
      );
    }
    final unlocated = detection('unlocated', 900, 'item-a');
    unlocated['title_roi'] = null;
    unlocated['title_roi_reason'] = 'Reference omitted detection geometry.';
    final report = compareOne(
      'engine_multi',
      multiTruth(),
      multi([
        detection('left-result', 10, 'item-a'),
        detection('right-result', 300, 'item-b'),
        unlocated,
      ]),
    );
    expect(report['metrics']['wrong_identities'], 0);
    expect(report['metrics']['extra_false_positive_selections'], 0);
    expect(report['metrics']['unmatched_detections'], 1);
    expect(report['evidence_validity'], 'unverified');
    expect(report['cases'][0]['unavailable'], contains('unlocated.title_roi'));
  });

  test(
    'multi missing, unmatched and duplicate detections cannot be hidden',
    () {
      final report = compareOne(
        'engine_multi',
        multiTruth(),
        multi([
          detection('left-a', 10, 'item-a'),
          detection('left-duplicate', 11, 'item-a'),
          detection('stray', 900, 'item-b'),
        ]),
      );
      expect(report['metrics']['duplicate_detections'], 1);
      expect(report['metrics']['correct_positive_ids'], 0);
      expect(report['metrics']['unmatched_detections'], 1);
      expect(report['metrics']['missing_detections'], 1);
      expect(report['reference_behavior'], 'defects_observed');
      expect(report['cases'][0]['unmatched_detection_ids'], ['stray']);
    },
  );

  test('unmatched multi errors stay recorded rather than disappearing behind association', () {
    final error = detection('unlocated-error', 900, 'item-a');
    error['outcome'] = outcome('error');
    error['errors'] = ['OCR native dependency failed.'];
    final report = compareOne('engine_multi', multiTruth(), multi([error]));
    expect(report['metrics']['outcome_errors'], 1);
    expect(report['metrics']['unmatched_detections'], 1);
    expect(report['metrics']['missing_detections'], 2);
    expect(report['evidence_validity'], 'unverified');
    expect(report['cases'][0]['reference']['detections'][0]['errors'], [
      'OCR native dependency failed.',
    ]);
  });

  test(
    'source lock remains optional, but a provided different freeze is refused',
    () {
      final m = manifest([
        fixture(
          'case',
          'engine_inspection',
          inspectionTruth('readable_positive', 'item-a'),
        ),
      ]);
      final r = results(m, [
        observation(
          'case',
          'engine_inspection',
          engine('recognized', 'item-a'),
        ),
      ]);
      expect(compareReferenceResults(m, r)['evidence_validity'], 'pass');
      final lock = <String, dynamic>{
        'schema_version': 1,
        'record_type': 'source_lock',
        'id': 'synthetic-lock',
        'reference': {
          'commit': 'a'.padLeft(40, 'a'),
          'dirty': false,
          'closure_status': <dynamic>[],
        },
        'submodules': <dynamic>[],
        'files': [
          {
            'path': 'config.json',
            'sha256': inputHash,
            'size_bytes': 1,
            'role': 'config',
          },
        ],
        'effective_inputs': {
          for (final key in [
            'config',
            'native',
            'model',
            'catalog',
            'build',
            'archive',
            'adapter',
            'instrumentation',
            'packages',
            'maps',
          ])
            key: [
              {
                'id': '$key-1',
                'sha256': inputHash,
                'version': '1',
                'locator': '$key/input',
              },
            ],
        },
        'closure_complete': true,
        'closure_declaration': 'Synthetic comparison lock.',
        'permission': {
          'use': 'private_reference',
          'status': 'cleared',
          'reviewer': 'synthetic-reviewer',
          'reviewed_at': '2026-10-05',
          'evidence_ids': ['synthetic-grant'],
          'scope_paths': ['config.json'],
        },
      };
      lock['freeze_id'] = sourceFreezeId(lock);
      expect(
        () => compareReferenceResults(m, r, sourceLock: lock),
        throwsA(isA<ContractException>()),
      );
      m['freeze_id'] = lock['freeze_id'];
      final linked = results(m, [
        observation(
          'case',
          'engine_inspection',
          engine('recognized', 'item-a'),
        ),
      ]);
      expect(
        compareReferenceResults(
          m,
          linked,
          sourceLock: lock,
        )['evidence_validity'],
        'pass',
      );
      lock['effective_inputs']['config'][0]['version'] = 'changed';
      expect(
        () => compareReferenceResults(m, linked, sourceLock: lock),
        throwsA(isA<ContractException>()),
      );
    },
  );
}
