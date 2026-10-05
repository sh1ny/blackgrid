import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/contracts.dart';
import '../../tool/qualification/statistics.dart';

// Original synthetic metadata only: none of these rows records a real trial.
Map<String, dynamic> video(String name, {num lower = 0, num upper = 0}) => {
  'type': 'video',
  'name': name,
  'recording_id': 'synthetic-recording',
  'clock_domain': 'video-1',
  'lower_ms': lower,
  'upper_ms': upper,
  'request_id': 'request-1',
  'generation': 'generation-1',
  'ordinal': 1,
  'case_id': 'variant-1',
  'observable': true,
  'linkage_valid': true,
  if (name != 'physical_actuation') 'visibility': 'visible',
  if (name == 'actionable_visible') 'correctness': 'identified_correct',
  if (name == 'fallback_visible') 'phase': 'fallback_running',
};

Map<String, dynamic> attempt(
  String id, {
  String outcome = 'correct',
  String route = 'automatic',
  num delay = 20,
}) => {
  'id': id,
  'request_id': 'request-1',
  'generation': 'generation-1',
  'ordinal': 1,
  'executor': 'synthetic-developer',
  'evidence_mode': 'synthetic',
  'intended_path': 'targeted',
  'actual_path': 'targeted',
  'terminal_outcome': outcome,
  'trigger_kind': route,
  'clock_domain': 'qpc-1',
  'qpc_frequency': 1000,
  'warm_state': 'warm',
  'profile': 'host_resolution',
  'display_cell': {'width': 1920, 'height': 1080, 'os_scale_percent': 100},
  'acquisition_class': 'synthetic',
  'case_id': 'variant-1',
  'master_case_id': 'master-1',
  'source_id': 'source-1',
  'stages': [
    {'name': 'capture', 'start_tick': 10, 'end_tick': 15},
  ],
  'missing_stage_reasons': {
    'fallback_work': 'Targeted route; no fallback work.',
  },
  'trigger': video('physical_actuation'),
  'endpoint': video('actionable_visible', lower: delay, upper: delay),
  'observer': {'method': 'synthetic-video-annotation'},
  'external_data_age_ms': null,
  'external_data_age_ms_reason':
      'No external timestamp in this synthetic case.',
};

Map<String, dynamic> bundle(List<Map<String, dynamic>> rows) => {
  'schema_version': 1,
  'record_type': 'attempt_bundle',
  'id': 'synthetic-attempts',
  'provenance_ids': ['synthetic-author'],
  'freeze_id': 'a' * 64,
  'run_id': 'synthetic-run',
  'environment_id': 'synthetic-environment',
  'attempts': rows,
};

Map<String, dynamic> stratum(
  Map<String, dynamic> summary,
  String outcome, {
  String route = 'automatic',
}) => (summary['strata'] as List).cast<Map<String, dynamic>>().singleWhere(
  (row) =>
      row['stratum']['terminal_outcome'] == outcome &&
      row['stratum']['trigger_kind'] == route,
);

void main() {
  test('nearest rank uses ceil rather than interpolating the tail', () {
    expect(nearestRankQuantile([for (var i = 1; i <= 20; i++) i]), 19);
    expect(nearestRankQuantile([9, 2, 4]), 9);
    expect(nearestRankQuantile(<num>[]), isNull);
    expect(
      () => nearestRankQuantile([1], quantile: 0),
      throwsA(isA<ContractException>()),
    );
  });

  test(
    'mixed outcomes preserve every denominator but only correct actionable N',
    () {
      final rows = [
        attempt('ok-1', delay: 10),
        attempt('ok-2', delay: 30),
        attempt('reject', outcome: 'rejected'),
        attempt('wrong', outcome: 'wrong_id'),
        attempt('cancel', outcome: 'canceled'),
        attempt('supersede', outcome: 'superseded'),
        attempt('error', outcome: 'error'),
        attempt('incomplete', outcome: 'incomplete'),
      ];
      final result = summarizeAttempts(bundle(rows));
      expect(result['attempt_n'], 8);
      expect(result['attempt_ids'], rows.map((row) => row['id']).toList());
      expect(result['outcome_counts'], {
        'correct': 2,
        'rejected': 1,
        'wrong_id': 1,
        'canceled': 1,
        'superseded': 1,
        'error': 1,
        'incomplete': 1,
      });
      expect(result['actionable_sample_n'], 2);
      final correct = stratum(result, 'correct');
      expect(correct['physical_to_actionable_visible']['n'], 2);
      expect(correct['physical_to_actionable_visible']['p95_upper_ms'], 30);
      expect(correct['internal_stages']['capture']['n'], 2);
      expect(correct['internal_stages']['fallback_work']['n'], 0);
      expect(correct['internal_stages']['fallback_work']['p95_ms'], isNull);
      expect(correct['internal_stages']['fallback_work']['missing_n'], 2);
      expect(
        correct['physical_to_actionable_visible']['threshold_status'],
        'unverified',
      );
      expect(
        stratum(result, 'rejected')['physical_to_actionable_visible']['n'],
        0,
      );
      expect(result['coverage']['unique_master_n'], 1);
    },
  );

  test(
    'UI assignment and acceptance cannot substitute for an observed endpoint',
    () {
      final row = attempt('publication-only');
      row['endpoint'] = null;
      row['endpoint_reason'] = 'No actionable frame was observable.';
      row['stages'] = [
        {'name': 'acceptance', 'start_tick': 0, 'end_tick': 12},
        {'name': 'ui_assignment', 'start_tick': 12, 'end_tick': 13},
      ];
      final result = summarizeAttempts(bundle([row]));
      final visible = stratum(
        result,
        'correct',
      )['physical_to_actionable_visible'];
      expect(visible['n'], 0);
      expect(visible['p95_lower_ms'], isNull);
      expect(visible['p95_lower_ms_reason'], contains('No eligible'));
      expect(visible['threshold_status'], 'unverified');
      expect(result['visible_evidence_status'], 'unverified');
      expect(
        stratum(
          result,
          'correct',
        )['internal_stages']['ui_assignment']['p95_ms'],
        1,
      );
    },
  );

  test('declared missing custom stages keep the full attempt denominator', () {
    final row = attempt('missing-custom');
    row['missing_stage_reasons']['initialization'] =
        'Initialization was not traced.';
    final metric = stratum(
      summarizeAttempts(bundle([row])),
      'correct',
    )['internal_stages']['initialization'];
    expect(metric['n'], 0);
    expect(metric['missing_n'], 1);
    expect(metric['p95_ms'], isNull);
    expect(metric['missing_reasons'], {'Initialization was not traced.': 1});
  });

  test('automatic and manual distributions remain separate', () {
    final result = summarizeAttempts(
      bundle([
        for (var i = 0; i < 20; i++) attempt('auto-$i', delay: i + 1),
        for (var i = 0; i < 20; i++)
          attempt('manual-$i', route: 'manual', delay: 100 + i),
      ]),
    );
    expect(result['strata'], hasLength(2));
    final automatic = stratum(result, 'correct');
    final manual = stratum(result, 'correct', route: 'manual');
    expect(automatic['physical_to_actionable_visible']['p95_upper_ms'], 19);
    expect(manual['physical_to_actionable_visible']['p95_upper_ms'], 118);
    expect(automatic['outcome_counts'], {'correct': 20});
    expect(manual['outcome_counts'], {'correct': 20});
    expect(result.containsKey('pooled_p95'), isFalse);
  });

  test('actual paths retain separate quantiles and all-trigger sample denominators', () {
    final rows = <Map<String, dynamic>>[];
    for (final path in ['targeted', 'full_viewport']) {
      final offset = path == 'targeted' ? 0 : 100;
      for (var i = 1; i <= 20; i++) {
        rows.add(
          attempt('$path-$i', delay: offset + i)
            ..['actual_path'] = path
            ..['stages'] = [
              {'name': 'capture', 'start_tick': 0, 'end_tick': offset + i},
            ],
        );
      }
      rows.add(
        attempt('$path-unobserved')
          ..['actual_path'] = path
          ..['endpoint'] = null
          ..['endpoint_reason'] = 'Actionable frame was not observable.'
          ..['stages'] = <Map<String, dynamic>>[]
          ..['missing_stage_reasons'] = {
            'capture': 'Capture was not traced.',
            'fallback_work': 'Fallback work was not traced.',
          },
      );
    }
    final result = summarizeAttempts(bundle(rows));
    expect(result['strata'], hasLength(2));
    expect(result['attempt_n'], 42);
    expect(result['attempt_ids'], rows.map((row) => row['id']).toList());
    expect(result['actionable_sample_n'], 40);
    expect(result['outcome_counts'], {'correct': 42});
    expect(result['attempt_summaries'], hasLength(42));
    final cells = (result['strata'] as List).cast<Map<String, dynamic>>();
    expect(
      cells.expand((cell) => cell['attempt_ids'] as List),
      unorderedEquals(rows.map((row) => row['id'])),
    );
    for (final path in ['targeted', 'full_viewport']) {
      final cell = cells.singleWhere(
        (cell) => cell['stratum']['actual_path'] == path,
      );
      expect(cell['stratum']['intended_path'], 'targeted');
      expect(cell['stratum']['terminal_outcome'], 'correct');
      expect(cell['stratum']['trigger_kind'], 'automatic');
      expect(cell['attempt_n'], 21);
      expect(cell['outcome_counts'], {'correct': 21});
      expect(
        cell['attempt_ids'],
        rows.where((row) => row['actual_path'] == path).map((row) => row['id']),
      );
      final expected95 = path == 'targeted' ? 19 : 119;
      final visible = cell['physical_to_actionable_visible'];
      expect(visible['n'], 20);
      expect(visible['missing_n'], 1);
      expect(visible['n'] + visible['missing_n'], cell['attempt_n']);
      expect(visible['p95_lower_ms'], expected95);
      expect(visible['p95_upper_ms'], expected95);
      final capture = cell['internal_stages']['capture'];
      expect(capture['n'], 20);
      expect(capture['missing_n'], 1);
      expect(capture['n'] + capture['missing_n'], cell['attempt_n']);
      expect(capture['p95_ms'], expected95);
      expect(cell['physical_to_fallback_visible']['n'], 0);
      expect(cell['physical_to_fallback_visible']['missing_n'], 21);
    }
  });

  test(
    'cold profile display acquisition and environment cells cannot pool',
    () {
      final rows = [
        attempt('warm'),
        attempt('cold')..['warm_state'] = 'cold',
        attempt('profile')..['profile'] = 'engine_multi',
        attempt('display')
          ..['display_cell'] = {
            'width': 2560,
            'height': 1440,
            'os_scale_percent': 100,
          },
        attempt('derived')..['acquisition_class'] = 'derived',
      ];
      final result = summarizeAttempts(bundle(rows));
      expect(result['strata'], hasLength(5));
      for (final cell in result['strata'] as List) {
        expect(cell['attempt_n'], 1);
        expect(cell['stratum']['environment_id'], 'synthetic-environment');
      }
    },
  );

  test(
    'QPC rejects changed clocks or frequencies instead of computing a total',
    () {
      for (final change in [
        {'domain': 'qpc-other'},
        {'frequency': 2000},
      ]) {
        final row = attempt('mismatch');
        row['stages'] = [
          {
            'name': 'capture',
            'start_tick': 0,
            'end_tick': 10,
            'start': {
              'tick': 0,
              'frequency': 1000,
              'domain': 'qpc-1',
              'name': 'capture_start',
            },
            'end': {
              'tick': 10,
              'frequency': 1000,
              'domain': 'qpc-1',
              'name': 'capture_end',
              ...change,
            },
          },
        ];
        expect(
          () => summarizeAttempts(bundle([row])),
          throwsA(isA<ContractException>()),
        );
      }
    },
  );

  test('video cannot be subtracted from QPC or from a different recording', () {
    final qpc = attempt('qpc-trigger');
    qpc['trigger'] = {
      'type': 'qpc',
      'name': 'trigger',
      'tick': 0,
      'frequency': 1000,
      'domain': 'qpc-1',
    };
    expect(
      () => summarizeAttempts(bundle([qpc])),
      throwsA(isA<ContractException>()),
    );
    final other = attempt('different-video');
    other['endpoint']['recording_id'] = 'other-recording';
    expect(
      () => summarizeAttempts(bundle([other])),
      throwsA(isA<ContractException>()),
    );
    final domain = attempt('different-clock');
    domain['endpoint']['clock_domain'] = 'video-other';
    expect(
      () => summarizeAttempts(bundle([domain])),
      throwsA(isA<ContractException>()),
    );
  });

  test('frame intervals crossing a target cannot become a confident pass', () {
    final row = attempt('uncertain');
    row['trigger'] = video('physical_actuation', lower: 10, upper: 20);
    row['endpoint'] = video('actionable_visible', lower: 110, upper: 130);
    final input = bundle([row])
      ..['targets_ms'] = {'physical_to_actionable_visible': 100};
    final metric = stratum(
      summarizeAttempts(input),
      'correct',
    )['physical_to_actionable_visible'];
    expect(metric['p95_lower_ms'], 90);
    expect(metric['p95_upper_ms'], 120);
    expect(metric['threshold_status'], 'indeterminate');
    input['targets_ms']['physical_to_actionable_visible'] = 120;
    expect(
      stratum(
        summarizeAttempts(input),
        'correct',
      )['physical_to_actionable_visible']['threshold_status'],
      'pass',
    );
    input['targets_ms']['physical_to_actionable_visible'] = 80;
    expect(
      stratum(
        summarizeAttempts(input),
        'correct',
      )['physical_to_actionable_visible']['threshold_status'],
      'fail',
    );
  });

  test('wrong identity invalid linkage and invisible results never enter actionable N', () {
    final wrong = attempt('wrong-annotation')
      ..['endpoint']['correctness'] = 'wrong_identity';
    final stale = attempt('stale')
      ..['endpoint']['generation'] = 'stale-generation';
    final hidden = attempt('hidden')..['endpoint']['visibility'] = 'occluded';
    final unlink = attempt('unlinked')..['endpoint']['linkage_valid'] = false;
    final result = summarizeAttempts(bundle([wrong, stale, hidden, unlink]));
    expect(result['attempt_n'], 4);
    expect(result['actionable_sample_n'], 0);
    expect(
      stratum(result, 'correct')['physical_to_actionable_visible']['missing_n'],
      4,
    );
  });

  test(
    'stale ordinals cannot enter actionable or visible fallback samples',
    () {
      for (final field in ['trigger', 'endpoint', 'fallback_endpoint']) {
        final row = attempt('stale-$field');
        row['stages'] = [
          {'name': 'fallback_work', 'start_tick': 50, 'end_tick': 80},
        ];
        row['fallback_endpoint'] = video(
          'fallback_visible',
          lower: 60,
          upper: 70,
        );
        row[field]['ordinal'] = 2;
        final result = summarizeAttempts(bundle([row]));
        expect(result['attempt_n'], 1);
        expect(
          result['actionable_sample_n'],
          field == 'fallback_endpoint' ? 1 : 0,
        );
        expect(
          result['fallback_visible_sample_n'],
          field == 'endpoint' ? 1 : 0,
        );
        final metric =
            stratum(result, 'correct')[field == 'endpoint'
                ? 'physical_to_actionable_visible'
                : 'physical_to_fallback_visible'];
        expect(metric['missing_n'], 1);
        expect(metric['missing_reasons'], {
          'Boundary ordinal does not identify this attempt.': 1,
        });
      }
    },
  );

  test('replays and variants increase timing N but not unique master/source coverage', () {
    final rows = [for (var i = 0; i < 3; i++) attempt('variant-$i')];
    rows[1]['case_id'] = 'variant-2';
    rows[1]['trigger']['case_id'] = 'variant-2';
    rows[1]['endpoint']['case_id'] = 'variant-2';
    final result = summarizeAttempts(bundle(rows));
    expect(result['actionable_sample_n'], 3);
    expect(result['coverage']['unique_master_n'], 1);
    expect(result['coverage']['unique_source_n'], 1);
    expect(result['coverage']['unique_master_outcome_counts'], {'correct': 1});
  });

  test(
    'fallback running phase is distinct from work and the eventual rejection',
    () {
      final row = attempt('fallback', outcome: 'rejected')
        ..['actual_path'] = 'fallback';
      row['stages'] = [
        {'name': 'fallback_work', 'start_tick': 50, 'end_tick': 80},
      ];
      row['fallback_endpoint'] = video(
        'fallback_visible',
        lower: 60,
        upper: 70,
      );
      row['endpoint'] = null;
      row['endpoint_reason'] =
          'Fallback rejected; no correct actionable result.';
      final cell = stratum(summarizeAttempts(bundle([row])), 'rejected');
      expect(cell['internal_stages']['fallback_work']['p95_ms'], 30);
      expect(cell['physical_to_fallback_visible']['p95_lower_ms'], 60);
      expect(cell['physical_to_fallback_visible']['p95_upper_ms'], 70);
      expect(cell['physical_to_actionable_visible']['n'], 0);
      row.remove('fallback_endpoint');
      expect(
        stratum(
          summarizeAttempts(bundle([row])),
          'rejected',
        )['physical_to_fallback_visible']['n'],
        0,
      );
    },
  );

  test('fallback deadline or decorative label without actual work is not phase evidence', () {
    final row = attempt('fallback-label', outcome: 'canceled');
    row['stages'] = <dynamic>[];
    row['fallback_endpoint'] = video('fallback_visible', lower: 60, upper: 70);
    row['qpc_events'] = [
      {
        'name': 'fallback_deadline',
        'tick': 50,
        'frequency': 1000,
        'domain': 'qpc-1',
      },
    ];
    var result = summarizeAttempts(bundle([row]));
    expect(result['fallback_visible_sample_n'], 0);
    row['qpc_events'].add({
      'name': 'fallback_start',
      'tick': 55,
      'frequency': 1000,
      'domain': 'qpc-1',
    });
    result = summarizeAttempts(bundle([row]));
    expect(result['fallback_visible_sample_n'], 1);
    expect(result['actionable_sample_n'], 0);
    expect(result['attempt_summaries'][0]['qpc_events'], hasLength(2));
    row['fallback_endpoint']['phase'] = 'decorative_spinner';
    expect(summarizeAttempts(bundle([row]))['fallback_visible_sample_n'], 0);
  });

  test('absent future unsupported and measured external ages stay visible', () {
    final measured = attempt('age')..remove('external_data_age_ms_reason');
    measured['external_data_age_ms'] = 40;
    final future = attempt('future')..remove('external_data_age_ms_reason');
    future['external_data_age_ms'] = -10;
    final unsupported = attempt('unsupported')
      ..remove('external_data_age_ms_reason');
    unsupported['external_data_age_ms'] = {
      'status': 'unsupported',
      'reason': 'Clock basis is unsupported.',
    };
    final result = summarizeAttempts(
      bundle([attempt('absent'), measured, future, unsupported]),
    );
    expect(result['external_data_ages']['counts'], {
      'measured': 1,
      'absent': 1,
      'future': 1,
      'unsupported': 1,
    });
    expect(result['external_data_ages']['measured_ms']['n'], 1);
    expect(result['external_data_ages']['measured_ms']['p95_ms'], 40);
    expect(result['external_data_ages']['observations'], hasLength(4));
  });

  test(
    'skipped and unattempted collections never report a passed baseline',
    () {
      for (final disposition in ['skipped', 'unattempted']) {
        final input = bundle([])
          ..['collection_status'] = disposition
          ..['collection_rationale'] =
              'User evidence unavailable; no launch requested.'
          ..['targets_ms'] = {'physical_to_actionable_visible': 100};
        final result = summarizeAttempts(input);
        expect(result['attempt_n'], 0);
        expect(result['actionable_sample_n'], 0);
        expect(result['visible_evidence_status'], 'unverified');
        expect(result['status'], 'incomplete');
        expect(result['collection_status'], disposition);
        expect(result['collection_rationale'], input['collection_rationale']);
        expect(result['strata'], isEmpty);
      }
    },
  );
}
