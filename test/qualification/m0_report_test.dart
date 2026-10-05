import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/contracts.dart';
import '../../tool/qualification/export.dart';
import '../../tool/qualification/report.dart';
import 'm0_contracts_test.dart' as source_examples;
import 'm0_comparison_test.dart' as comparison_examples;
import 'm0_export_test.dart' as export_examples;
import 'm0_statistics_test.dart' as statistics_examples;

Map<String, dynamic> record(
  String type,
  String id,
  Map<String, dynamic> data,
) => {'schema_version': 1, 'record_type': type, 'id': id, ...data};

Map<String, Map<String, dynamic>> inputs() {
  final source = source_examples.lock()
    ..remove('local_locators')
    ..remove('permission')
    ..['record_type'] = 'source_intake'
    ..['freeze_id'] = null
    ..['freeze_id_reason'] = 'Metadata intake is not a final freeze.';
  final environment = record('environment', 'setup', {
    'setup_alias': 'synthetic-setup',
    for (final key in [
      'hardware',
      'windows',
      'runtime',
      'app_build',
      'viewport',
      'display',
      'observer',
      'locale',
      'display_mode',
      'warm_state',
    ]) ...{key: null, '${key}_reason': 'Not collected in this synthetic test.'},
  });
  final provenance = export_examples.ledger([
    for (final id in [
      'synthetic-author',
      'm0-reference-intake-metadata',
      'm0-provenance-metadata',
      'm0-planned-checks-metadata',
      'm0-display-matrix-metadata',
      'm0-original-synthetic-fixtures',
      'm0-authored-report-metadata',
      'm0-setup-metadata',
    ])
      export_examples.artifact(id),
  ]);
  return {
    'source_intake': source,
    'environment': environment,
    'provenance': provenance,
    'fixture_manifest': record('fixture_manifest', 'manifest', {
      'data_class': 'synthetic',
      'corpus_version': '1',
      'annotation_version': '1',
      'catalog_version': '1',
      'config_version': '1',
      'cases': <dynamic>[],
    }),
    'map_controls': record('map_controls', 'maps', {'controls': <dynamic>[]}),
    'display_matrix': record('display_matrix', 'display', {
      'cells': <dynamic>[],
    }),
    'planned_checks': record('planned_checks', 'planned', {
      'checks': [
        {
          'id': 'live-baseline',
          'required': true,
          'applicable': true,
          'attempted': false,
          'owner': 'user',
          'scope': 'live-warm',
          'stratum_id': 'targeted',
          'reason': 'User has not collected live evidence.',
          'case_ids': <String>[],
          'allocation': 100,
          'evidence_ids': <String>[],
          'disposition': 'blocked',
          'freeze_id': null,
          'freeze_id_reason': 'No final reference freeze.',
        },
      ],
    }),
  };
}

// Original synthetic metadata models the consumer's live record shape only.
// These tests do not collect or assert any real native/user observations.
Map<String, Map<String, dynamic>> finiteLiveInputs() {
  final records = inputs();
  final lock = source_examples.lock()..remove('local_locators');
  records.remove('source_intake');
  records['source_lock'] = lock;
  final fixture = comparison_examples.fixture(
    'variant-1',
    'host_resolution',
    comparison_examples.policyTruth('Check'),
  );
  records['fixture_manifest'] = comparison_examples.manifest([fixture])
    ..['freeze_id'] = lock['freeze_id'];
  final setup = <String, dynamic>{
    'hardware': {
      'cpu': 'synthetic-cpu',
      'gpu': 'synthetic-gpu',
      'ram_bytes': 8192,
    },
    'windows': {'version': 'synthetic-windows', 'architecture': 'x64'},
    'runtime': {'sdk': 'synthetic-sdk'},
    'app_build': {'id': 'synthetic-build', 'version': '1'},
    'viewport': {
      'width': 1920,
      'height': 1080,
      'client_width': 1920,
      'client_height': 1080,
      'ui_scale': 1,
    },
    'display': {
      'width': 1920,
      'height': 1080,
      'os_scale_percent': 100,
      'origin': {'x': 0, 'y': 0},
      'topology': 'single',
    },
    'observer': {
      'method': 'synthetic-video-annotation',
      'recording_id': 'synthetic-recording',
      'clock_domain': 'video-1',
      'uncertainty_ms': 1,
    },
    'locale': 'en',
    'display_mode': 'synthetic-borderless',
    'warm_state': 'warm',
  };
  for (final entry in setup.entries) {
    records['environment']![entry.key] = entry.value;
    records['environment']!.remove('${entry.key}_reason');
  }
  const paths = ['intended-targeted', 'fallback-required'];
  const allocation = [
    {'automatic': 17, 'manual': 17},
    {'automatic': 17, 'manual': 16},
    {'automatic': 16, 'manual': 17},
  ];
  final attempts = <Map<String, dynamic>>[];
  for (final path in paths) {
    for (var batch = 0; batch < allocation.length; batch++) {
      for (final trigger in allocation[batch].entries) {
        for (var index = 0; index < trigger.value; index++) {
          final ordinal = attempts.length + 1;
          final row =
              statistics_examples.attempt('live-$ordinal', route: trigger.key)
                ..['ordinal'] = ordinal
                ..['request_id'] = 'request-$ordinal'
                ..['generation'] = 'generation-$ordinal'
                ..['scope'] = 'live-warm'
                ..['stratum_id'] = path
                ..['intended_path'] = path
                ..['actual_path'] = path
                ..['batch_ordinal'] = batch + 1
                ..['executor'] = 'user'
                ..['evidence_mode'] = 'live_user'
                ..['acquisition_class'] = 'actual'
                ..['input_sha256'] = fixture['input']['sha256']
                ..['viewport'] = setup['viewport'];
          for (final field in ['trigger', 'endpoint']) {
            for (final key in ['ordinal', 'request_id', 'generation']) {
              row[field][key] = row[key];
            }
          }
          attempts.add(row);
        }
      }
    }
  }
  records['attempt_bundle'] = statistics_examples.bundle(attempts)
    ..['freeze_id'] = lock['freeze_id']
    ..['run_id'] = 'test-run'
    ..['environment_id'] = records['environment']!['id']
    ..['collection_status'] = 'observed';
  records['planned_checks']!['checks'] = [
    for (final path in paths)
      {
        'id': 'live-warm-$path',
        'required': true,
        'applicable': true,
        'attempted': true,
        'owner': 'user',
        'scope': 'live-warm',
        'stratum_id': path,
        'reason': 'Finite live collection remains incomplete.',
        'case_ids': ['variant-1'],
        'allocation': 100,
        'evidence_ids': [records['attempt_bundle']!['id']],
        'disposition': 'observed',
        'freeze_id': lock['freeze_id'],
      },
  ];
  return records;
}

Map<String, dynamic> gate(Map<String, dynamic> dossier, String id) =>
    (dossier['qualification']['gates'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['id'] == id);

Map<String, Map<String, dynamic>> measuredInputs(String scope) {
  final records = finiteLiveInputs();
  final row = jsonDecode(
    jsonEncode(records['attempt_bundle']!['attempts'][0]),
  ) as Map<String, dynamic>;
  row['scope'] = scope;
  row['stratum_id'] = 'measurement';
  row['warm_state'] = scope.endsWith('cold') ? 'cold' : 'warm';
  records['environment']!['warm_state'] = row['warm_state'];
  if (scope.startsWith('offline') || scope == 'map-startup-memory') {
    row['executor'] = 'developer';
    row['evidence_mode'] = 'offline';
  }
  row['measurements'] = <String, dynamic>{
    'initialization_ms': 10,
    'map_load_ms': 20,
    'map_switch_ms': 10,
    'pan_ms': 1,
    'zoom_ms': 1,
    'floor_switch_ms': 1,
    'process_cpu_ms': 3,
    'process_memory_bytes': 1024,
    'interaction_path_id': 'synthetic-fixed-path',
    for (final name in ['startup', 'first_scan'])
      name: {
        'start': statistics_examples.video(
          name == 'startup' ? 'process_launch' : 'physical_actuation',
        ),
        'end': statistics_examples.video(
          name == 'startup' ? 'first_usable' : 'actionable_visible',
          lower: 20,
          upper: 21,
        ),
      },
  };
  records['attempt_bundle']!['attempts'] = [row];
  records['planned_checks']!['checks'] = [
    {
      'id': 'measurement',
      'required': true,
      'applicable': true,
      'attempted': true,
      'owner': scope.startsWith('live') ? 'user' : 'developer',
      'scope': scope,
      'stratum_id': 'measurement',
      'reason': 'Applicable observations remain required.',
      'case_ids': ['variant-1'],
      'allocation': 1,
      'evidence_ids': [records['attempt_bundle']!['id']],
      'disposition': 'observed',
      'freeze_id': records['source_lock']!['freeze_id'],
    },
  ];
  return records;
}

Map<String, Map<String, dynamic>> observedPolicyInputs({bool denied = false}) {
  final records = finiteLiveInputs()..remove('attempt_bundle');
  final fixture = comparison_examples.fixture(
    'policy',
    'host_resolution',
    comparison_examples.policyTruth('Check', divergence: true),
  );
  records['fixture_manifest'] = comparison_examples.manifest([fixture])
    ..['freeze_id'] = records['source_lock']!['freeze_id'];
  records['oracle_results'] =
      comparison_examples.results(records['fixture_manifest']!, [
          comparison_examples.observation(
            'policy',
            'host_resolution',
            comparison_examples.host('Sell'),
          ),
        ])
        ..['run_id'] = 'test-run'
        ..['environment_id'] = records['environment']!['id']
        ..['provenance_ids'] = ['synthetic-observations'];
  final artifact = export_examples.artifact('synthetic-observations');
  if (denied) export_examples.unresolved(artifact, 'report_export');
  records['provenance']!['artifacts'].add(artifact);
  return records;
}

Future<File> writeRequest(
  Directory root,
  Map<String, Map<String, dynamic>> records, {
  String attemptReason = 'No actual collection.',
}) async {
  for (final entry in records.entries) {
    await File('${root.path}/${entry.key}.json')
        .writeAsString(jsonEncode(entry.value));
  }
  final request = File('${root.path}/request.json');
  await request.writeAsString(
    jsonEncode(
      record('dossier_request', 'request', {
        'run_id': 'test-run',
        'records': {for (final key in records.keys) key: '$key.json'},
        if (!records.containsKey('oracle_results')) ...{
          'oracle_results': null,
          'oracle_results_reason': 'No native replay.',
        },
        if (!records.containsKey('attempt_bundle')) ...{
          'attempt_bundle': null,
          'attempt_bundle_reason': attemptReason,
        },
      }),
    ),
  );
  return request;
}

Future<void> linkDirectory(String path, String target) async {
  if (Platform.isWindows) {
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-Command',
        r'$ErrorActionPreference = "Stop"; New-Item -ItemType Junction -Path $env:M0_LINK_PATH -Target $env:M0_LINK_TARGET | Out-Null',
      ],
      environment: {'M0_LINK_PATH': path, 'M0_LINK_TARGET': target},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
  } else {
    await Link(path).create(target);
  }
}

void main() {
  test(
    'observation export uses its explicit artifact and denies copied payloads',
    () {
      final records = observedPolicyInputs(denied: true);
      final dossier = buildDossier(records, runId: 'test-run');
      expect(gate(dossier, 'oracle-evidence-linkage')['status'], 'pass');
      expect(gate(dossier, 'report-export')['status'], 'unverified');
      expect(
        dossier['qualification']['exports'],
        isNot(contains(containsPair('path', 'reference-results.json'))),
      );
      final indexed = (dossier['evidence_index'] as List).singleWhere(
        (row) => row['id'] == records['oracle_results']!['id'],
      );
      expect(indexed['sha256'], sha256Json(records['oracle_results']));
      expect(indexed.containsKey('provenance_ids'), isFalse);
      expect(indexed['status'], 'unverified');
      expect(
        dossier['qualification']['coverage']['recognition']['status'],
        'unverified',
      );
      expect(
        dossier['qualification']['coverage']['recognition']['metrics'],
        isNull,
      );
      expect(dossier['divergence_register']['observed'], isEmpty);
      final portable = canonicalJson(dossier);
      expect(
        portable,
        isNot(contains('Reference chose its legacy sale rule.')),
      );
      expect(portable, isNot(contains('"decision":"Sell"')));
    },
  );

  test(
    'intentional Sell observation is observed rather than expectation only',
    () {
      final dossier = buildDossier(observedPolicyInputs(), runId: 'test-run');
      final register = dossier['divergence_register'];
      expect(register['observed'], hasLength(1));
      final row = register['observed'].single;
      expect(row['case_id'], 'policy');
      expect(row['profile'], 'host_resolution');
      expect(row['kind'], 'intentional_target_policy');
      expect(row['status'], 'observed');
      expect(row['expected']['decision'], 'Check');
      expect(row['observed']['decision'], 'Sell');
      expect(row['rationale'], contains('FIR'));
      expect(row['defects'], isEmpty);
      expect(register['expectation_only'], isEmpty);
      expect(dossier['qualification']['divergences'], register['observed']);
    },
  );

  test('denied timing bundle retains only indexed identity without derived observations', () {
    final records = finiteLiveInputs();
    records['attempt_bundle']!['provenance_ids'] = ['synthetic-timing'];
    final artifact = export_examples.artifact('synthetic-timing');
    export_examples.unresolved(artifact, 'report_export');
    records['provenance']!['artifacts'].add(artifact);
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'attempt-evidence-linkage')['status'], 'pass');
    expect(
      gate(dossier, 'user-native-visible-baseline')['status'],
      'unverified',
    );
    expect(gate(dossier, 'report-export')['status'], 'unverified');
    expect(dossier['baseline_summary']['attempt_n'], 0);
    expect(dossier['baseline_summary']['strata'], isEmpty);
    expect(dossier['baseline_summary']['attempt_summaries'], isEmpty);
    expect(dossier['qualification']['timing']['internal_stages'], isNull);
    expect(
      dossier['qualification']['coverage']['checks'][0]['actual_attempt_n'],
      0,
    );
    expect(
      dossier['evidence_index'],
      contains(
        allOf(
          containsPair('id', records['attempt_bundle']!['id']),
          containsPair('sha256', sha256Json(records['attempt_bundle'])),
          containsPair('status', 'unverified'),
        ),
      ),
    );
  });

  test('invalid attempt fallback respects denied nested row provenance', () {
    final records = measuredInputs('live-cold');
    final bundle = records['attempt_bundle']!;
    final row = bundle['attempts'][0];
    row['id'] = 'denied-nested-attempt-identity';
    row['provenance_ids'] = ['denied-nested-observation'];
    final artifact = export_examples.artifact('denied-nested-observation');
    export_examples.unresolved(artifact, 'report_export');
    records['provenance']!['artifacts'].add(artifact);
    bundle['run_id'] = 'different-run';
    final decision = inspectExport(
      bundle,
      (bundle['provenance_ids'] as List).cast<String>(),
      records['provenance']!,
    );
    expect(decision.allowed, isFalse, reason: decision.blockers.join(' | '));
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'attempt-evidence-linkage')['status'], 'fail');
    expect(gate(dossier, 'report-export')['status'], 'unverified');
    final baseline = dossier['baseline_summary'];
    expect(baseline['attempt_n'], 0);
    expect(baseline['attempt_ids'], isEmpty);
    expect(baseline['outcome_counts'], isEmpty);
    expect(baseline['attempt_summaries'], isEmpty);
    expect(baseline['strata'], isEmpty);
    expect(dossier['qualification']['timing']['internal_stages'], isNull);
    expect(
      dossier['evidence_index'],
      contains(
        allOf(
          containsPair('id', bundle['id']),
          containsPair('sha256', sha256Json(bundle)),
          containsPair('status', 'unverified'),
        ),
      ),
    );
    expect(canonicalJson(dossier), isNot(contains(row['id'] as String)));
  });

  test('invalid attempt fallback refuses forbidden row payload despite cleared artifact uses', () {
    final records = measuredInputs('live-cold');
    final bundle = records['attempt_bundle']!;
    final row = bundle['attempts'][0];
    row['id'] = 'forbidden-payload-private-attempt-identity';
    row['viewport']['width'] = 1280;
    row['personal_progress'] = {'level': 1};
    expect(() => validateRecord(bundle), returnsNormally);
    expect(
      records['provenance']!['artifacts'][0]['uses']['report_export']['status'],
      'cleared',
    );
    final decision = inspectExport(bundle, [
      'synthetic-author',
    ], records['provenance']!);
    expect(decision.allowed, isFalse, reason: decision.blockers.join(' | '));
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'attempt-evidence-linkage')['status'], 'fail');
    expect(dossier['baseline_summary']['attempt_n'], 0);
    expect(dossier['baseline_summary']['attempt_ids'], isEmpty);
    expect(dossier['baseline_summary']['outcome_counts'], isEmpty);
    expect(dossier['baseline_summary']['attempt_summaries'], isEmpty);
    expect(dossier['qualification']['timing']['internal_stages'], isNull);
    expect(
      dossier['evidence_index'],
      contains(
        allOf(
          containsPair('id', bundle['id']),
          containsPair('sha256', sha256Json(bundle)),
          containsPair('status', 'unverified'),
        ),
      ),
    );
    expect(canonicalJson(dossier), isNot(contains(row['id'] as String)));
  });

  test('privacy-safe schema-invalid timing retains counts but cannot export raw source', () {
    final records = measuredInputs('live-cold');
    final bundle = records['attempt_bundle']!;
    bundle['attempts'][0]['measurements']['startup']['end']['upper_ms'] = -1;
    final decision = inspectExport(bundle, [
      'synthetic-author',
    ], records['provenance']!);
    expect(decision.allowed, isFalse);
    expect(decision.privacyBlockers, isEmpty);
    expect(
      () =>
          sanitizedExport(bundle, ['synthetic-author'], records['provenance']!),
      throwsA(isA<ContractException>()),
    );
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'attempt-evidence-linkage')['status'], 'fail');
    expect(
      dossier['baseline_summary']['collection_status'],
      'invalid_evidence',
    );
    expect(dossier['baseline_summary']['attempt_n'], 1);
    expect(dossier['baseline_summary']['outcome_counts'], {'correct': 1});
    expect(dossier['baseline_summary']['actionable_sample_n'], 0);
    expect(dossier['baseline_summary']['attempt_summaries'], isEmpty);
    expect(dossier['baseline_summary']['strata'], isEmpty);
  });

  test('invalid cleared nested attempt provenance retains authorized denominators and linkage', () {
    final records = measuredInputs('live-cold');
    final bundle = records['attempt_bundle']!;
    bundle['attempts'][0]['provenance_ids'] = ['cleared-nested-observation'];
    records['provenance']!['artifacts'].add(
      export_examples.artifact('cleared-nested-observation'),
    );
    bundle['run_id'] = 'different-run';
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'attempt-evidence-linkage')['status'], 'fail');
    expect(
      dossier['baseline_summary']['collection_status'],
      'invalid_evidence',
    );
    expect(dossier['baseline_summary']['attempt_n'], 1);
    expect(dossier['baseline_summary']['outcome_counts'], {'correct': 1});
    expect(dossier['baseline_summary']['actionable_sample_n'], 0);
    expect(dossier['baseline_summary']['provenance_ids'], [
      'synthetic-author',
      'cleared-nested-observation',
    ]);
    expect(
      dossier['qualification']['exports'],
      contains(
        allOf(
          containsPair('path', 'baseline-summary.json'),
          containsPair('provenance_ids', [
            'm0-authored-report-metadata',
            'synthetic-author',
            'cleared-nested-observation',
          ]),
        ),
      ),
    );
  });

  test('invalid attempt fallback checks denied nested dependency closure', () {
    for (final relation in ['depends_on', 'derived_from', 'build_inputs']) {
      final records = measuredInputs('live-cold');
      final bundle = records['attempt_bundle']!;
      final row = bundle['attempts'][0];
      row['id'] = 'denied-derived-private-attempt';
      row['provenance_ids'] = ['nested-derived-observation'];
      final derived = export_examples.artifact('nested-derived-observation')
        ..[relation] = ['denied-observation-input'];
      final denied = export_examples.artifact('denied-observation-input');
      export_examples.unresolved(denied, 'report_export');
      records['provenance']!['artifacts'].addAll([derived, denied]);
      bundle['run_id'] = 'different-run';
      final dossier = buildDossier(records, runId: 'test-run');
      expect(
        gate(dossier, 'attempt-evidence-linkage')['status'],
        'fail',
        reason: relation,
      );
      expect(dossier['baseline_summary']['attempt_n'], 0, reason: relation);
      expect(
        dossier['baseline_summary']['attempt_ids'],
        isEmpty,
        reason: relation,
      );
      expect(
        dossier['baseline_summary']['outcome_counts'],
        isEmpty,
        reason: relation,
      );
      expect(
        dossier['qualification']['denominators']['actual_attempt_n'],
        0,
        reason: relation,
      );
      expect(
        dossier['qualification']['timing']['attempt_n'],
        0,
        reason: relation,
      );
      expect(
        canonicalJson(dossier),
        isNot(contains(row['id'] as String)),
        reason: relation,
      );
    }
  });

  test(
    'denied setup conflict diagnostics do not publish private attempt identity',
    () {
      final records = measuredInputs('live-cold');
      final bundle = records['attempt_bundle']!;
      final row = bundle['attempts'][0];
      row['id'] = 'denied-setup-private-attempt-identity';
      row['viewport']['width'] = 1280;
      bundle['provenance_ids'] = ['denied-setup-observation'];
      final artifact = export_examples.artifact('denied-setup-observation');
      export_examples.unresolved(artifact, 'report_export');
      records['provenance']!['artifacts'].add(artifact);
      final decision = inspectExport(bundle, [
        'denied-setup-observation',
      ], records['provenance']!);
      expect(decision.allowed, isFalse, reason: decision.blockers.join(' | '));
      final dossier = buildDossier(records, runId: 'test-run');
      expect(gate(dossier, 'attempt-evidence-linkage')['status'], 'fail');
      expect(gate(dossier, 'report-export')['status'], 'unverified');
      expect(dossier['baseline_summary']['attempt_n'], 0);
      expect(dossier['baseline_summary']['attempt_summaries'], isEmpty);
      expect(dossier['qualification']['timing']['internal_stages'], isNull);
      expect(
        dossier['evidence_index'],
        contains(
          allOf(
            containsPair('id', bundle['id']),
            containsPair('sha256', sha256Json(bundle)),
            containsPair('status', 'unverified'),
          ),
        ),
      );
      expect(canonicalJson(dossier), isNot(contains(row['id'] as String)));
    },
  );

  test('scope measurements cannot pass on allocated null observations', () {
    for (final scope in [
      'offline-warm',
      'offline-cold',
      'live-cold',
      'live-burst',
      'map-startup-memory',
    ]) {
      final records = measuredInputs(scope);
      final row = records['attempt_bundle']!['attempts'][0];
      row['stages'] = <dynamic>[];
      row['missing_stage_reasons'] = {'capture': 'Not measured.'};
      row['trigger'] = null;
      row['trigger_reason'] = 'Not measured.';
      row['endpoint'] = null;
      row['endpoint_reason'] = 'Not measured.';
      for (final key in (row['measurements'] as Map).keys.toList()) {
        row['measurements'][key] = null;
        row['measurements']['${key}_reason'] = 'Not measured.';
      }
      row['terminal_outcome'] = 'error';
      final decision = inspectExport(
        records['attempt_bundle']!,
        (records['attempt_bundle']!['provenance_ids'] as List).cast<String>(),
        records['provenance']!,
      );
      expect(
        decision.blockers,
        isEmpty,
        reason: '$scope: ${decision.blockers.join(' | ')}',
      );
      final dossier = buildDossier(records, runId: 'test-run');
      expect(
        gate(dossier, 'attempt-evidence-linkage')['status'],
        'pass',
        reason: scope,
      );
      expect(
        gate(dossier, 'planned-measurement')['status'],
        'unverified',
        reason: scope,
      );
      expect(dossier['baseline_summary']['attempt_n'], 1, reason: scope);
      expect(dossier['baseline_summary']['outcome_counts'], {
        'error': 1,
      }, reason: scope);
      expect(
        dossier['baseline_summary']['attempt_summaries'][0]['measurements']['initialization_ms'],
        isNull,
      );
      expect(
        dossier['baseline_summary']['attempt_summaries'][0]['measurements']['initialization_ms_reason'],
        'Not measured.',
      );
      expect(
        dossier['baseline_summary']['attempt_summaries'][0]['measurements'],
        row['measurements'],
        reason: scope,
      );
    }
  });

  test('nullable byte measurements do not authorize private reason fields', () {
    for (final key in [
      'bytes',
      'raw_bytes',
      'personal_progress',
      'account_id',
      'access_token',
    ]) {
      final records = measuredInputs('map-startup-memory');
      final measurements =
          records['attempt_bundle']!['attempts'][0]['measurements'];
      measurements[key] = null;
      measurements['${key}_reason'] = 'Not measured.';
      final decision = inspectExport(records['attempt_bundle']!, [
        'synthetic-author',
      ], records['provenance']!);
      expect(decision.allowed, isFalse, reason: key);
      expect(
        decision.blockers,
        contains(
          'payload.attempts[0].measurements.${key}_reason is forbidden.',
        ),
        reason: key,
      );
    }
  });

  test('scope measurements retain observed failure denominators without success quotas', () {
    for (final scope in [
      'offline-warm',
      'offline-cold',
      'map-startup-memory',
    ]) {
      final records = measuredInputs(scope);
      records['attempt_bundle']!['attempts'][0]['terminal_outcome'] = 'error';
      final dossier = buildDossier(records, runId: 'test-run');
      expect(
        gate(dossier, 'planned-measurement')['status'],
        'pass',
        reason: scope,
      );
      expect(dossier['baseline_summary']['attempt_n'], 1);
      expect(dossier['baseline_summary']['outcome_counts'], {'error': 1});
      expect(dossier['baseline_summary']['actionable_sample_n'], 0);
      expect(
        dossier['baseline_summary']['attempt_summaries'][0]['measurements'],
        records['attempt_bundle']!['attempts'][0]['measurements'],
      );
      expect(dossier['baseline_summary']['provenance_ids'], [
        'synthetic-author',
      ]);
      records['attempt_bundle']!['collection_status'] = 'incomplete';
      final incomplete = buildDossier(records, runId: 'test-run');
      expect(
        gate(incomplete, 'planned-measurement')['status'],
        'unverified',
        reason: scope,
      );
      expect(incomplete['baseline_summary']['attempt_n'], 1);
    }
  });

  test('honest missing cold boundary bounds remain null and unverified', () {
    final records = measuredInputs('live-cold');
    final row = records['attempt_bundle']!['attempts'][0];
    row['measurements']['startup']['end']['upper_ms'] = null;
    row['measurements']['startup']['end']['upper_ms_reason'] =
        'Frame interval unavailable.';
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'attempt-evidence-linkage')['status'], 'pass');
    expect(gate(dossier, 'planned-measurement')['status'], 'unverified');
    expect(
      dossier['baseline_summary']['attempt_summaries'][0]['measurements']['startup']['end']['upper_ms'],
      isNull,
    );
    expect(
      dossier['baseline_summary']['attempt_summaries'][0]['measurements']['startup']['end']['upper_ms_reason'],
      'Frame interval unavailable.',
    );
  });

  test(
    'scope measurement qualification rejects wrong cache state or executor',
    () {
      for (final scope in [
        'offline-warm',
        'offline-cold',
        'live-cold',
        'live-burst',
        'map-startup-memory',
      ]) {
        for (final defect in ['warm-state', 'executor']) {
          final records = measuredInputs(scope);
          final row = records['attempt_bundle']!['attempts'][0];
          if (defect == 'warm-state') {
            row['warm_state'] = scope == 'map-startup-memory'
                ? 'unknown'
                : scope.endsWith('cold')
                ? 'warm'
                : 'cold';
          } else {
            row['executor'] = scope.startsWith('live') ? 'developer' : 'user';
          }
          final dossier = buildDossier(records, runId: 'test-run');
          expect(
            gate(dossier, 'planned-measurement')['status'],
            'unverified',
            reason: '$scope $defect',
          );
          expect(dossier['baseline_summary']['attempt_n'], 1);
        }
      }
    },
  );

  test('missing native setup fields stay unverified but conflicting cell is invalid', () {
    final missing = finiteLiveInputs();
    missing['environment']!['display'] = {'name': 'unspecified'};
    final incomplete = buildDossier(missing, runId: 'test-run');
    expect(
      gate(incomplete, 'user-native-visible-baseline')['status'],
      'unverified',
    );
    final conflict = finiteLiveInputs();
    conflict['environment']!['display'] = {
      'width': 2560,
      'height': 1440,
      'os_scale_percent': 125,
      'origin': {'x': 0, 'y': 0},
      'topology': 'single',
    };
    final invalid = buildDossier(conflict, runId: 'test-run');
    expect(gate(invalid, 'attempt-evidence-linkage')['status'], 'fail');
    expect(invalid['baseline_summary']['attempt_n'], 200);
    expect(invalid['qualification']['status'], 'not_qualified');
  });

  test('denied observation generator writes index but no raw or derived observation payload', () async {
    final temp = await Directory.systemTemp.createTemp(
      'm0-denied-observation-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final records = observedPolicyInputs(denied: true);
    final fixtureDecision = inspectExport(records['fixture_manifest']!, [
      'm0-original-synthetic-fixtures',
    ], records['provenance']!);
    expect(
      fixtureDecision.blockers,
      isEmpty,
      reason: fixtureDecision.blockers.join(' | '),
    );
    final observationDecision = inspectExport(records['oracle_results']!, [
      'synthetic-observations',
    ], records['provenance']!);
    expect(
      observationDecision.allowed,
      isFalse,
      reason: observationDecision.blockers.join(' | '),
    );
    final fixture = records['fixture_manifest']!['cases'][0];
    final bytes = utf8.encode('original synthetic offline input');
    await Directory('${temp.path}/synthetic').create();
    await File('${temp.path}/synthetic/policy.json').writeAsBytes(bytes);
    fixture['input']['sha256'] = sha256.convert(bytes).toString();
    records['oracle_results']!['fixture_manifest_sha256'] = sha256Json(
      records['fixture_manifest'],
    );
    records['oracle_results']!['observations'][0]['input_sha256'] =
        fixture['input']['sha256'];
    final request = await writeRequest(temp, records);
    final output = '${temp.path}/output';
    expect(await Directory(output).exists(), isFalse);
    await generateDossier(
      request.path,
      inputRoot: temp.path,
      outputRoot: output,
    );
    expect(await File('$output/reference-results.json').exists(), isFalse);
    final report = jsonDecode(
      await File('$output/qualification.json').readAsString(),
    );
    expect(
      report['evidence_index'],
      contains(
        allOf(
          containsPair('id', records['oracle_results']!['id']),
          containsPair('status', 'unverified'),
        ),
      ),
    );
    expect(report['coverage']['recognition']['metrics'], isNull);
    final indexed = (report['evidence_index'] as List).singleWhere(
      (row) => row['id'] == records['oracle_results']!['id'],
    );
    expect(indexed['sha256'], sha256Json(records['oracle_results']));
    expect(indexed.containsKey('provenance_ids'), isFalse);
    expect(
      report['rights_blockers'],
      contains(
        allOf(
          containsPair('id', 'synthetic-observations'),
          containsPair('use', 'report_export'),
          containsPair('status', 'unresolved'),
        ),
      ),
    );
    for (final path in ['qualification.json', 'divergences.json']) {
      expect(
        await File('$output/$path').readAsString(),
        isNot(contains('"decision":"Sell"')),
      );
    }
  });

  test(
    'denied timing generator excludes raw and derived measured values',
    () async {
      final temp = await Directory.systemTemp.createTemp('m0-denied-timing-');
      addTearDown(() => temp.delete(recursive: true));
      final records = measuredInputs('map-startup-memory');
      records['attempt_bundle']!['provenance_ids'] = ['synthetic-timing'];
      final artifact = export_examples.artifact('synthetic-timing');
      export_examples.unresolved(artifact, 'report_export');
      records['provenance']!['artifacts'].add(artifact);
      final fixtureDecision = inspectExport(records['fixture_manifest']!, [
        'm0-original-synthetic-fixtures',
      ], records['provenance']!);
      expect(
        fixtureDecision.blockers,
        isEmpty,
        reason: fixtureDecision.blockers.join(' | '),
      );
      final attemptDecision = inspectExport(records['attempt_bundle']!, [
        'synthetic-timing',
      ], records['provenance']!);
      expect(
        attemptDecision.allowed,
        isFalse,
        reason: attemptDecision.blockers.join(' | '),
      );
      final fixture = records['fixture_manifest']!['cases'][0];
      final bytes = utf8.encode('original synthetic map measurement input');
      await Directory('${temp.path}/synthetic').create();
      await File('${temp.path}/synthetic/variant-1.json').writeAsBytes(bytes);
      fixture['input']['sha256'] = sha256.convert(bytes).toString();
      records['attempt_bundle']!['attempts'][0]['input_sha256'] =
          fixture['input']['sha256'];
      final request = await writeRequest(temp, records);
      final output = '${temp.path}/output';
      expect(await Directory(output).exists(), isFalse);
      await generateDossier(
        request.path,
        inputRoot: temp.path,
        outputRoot: output,
      );
      final baseline = jsonDecode(
        await File('$output/baseline-summary.json').readAsString(),
      );
      expect(baseline['attempt_n'], 0);
      expect(baseline['attempt_summaries'], isEmpty);
      expect(baseline['strata'], isEmpty);
      final report = jsonDecode(
        await File('$output/qualification.json').readAsString(),
      );
      expect(report['timing']['internal_stages'], isNull);
      expect(
        report['evidence_index'],
        contains(
          allOf(
            containsPair('id', records['attempt_bundle']!['id']),
            containsPair('status', 'unverified'),
          ),
        ),
      );
      final indexed = (report['evidence_index'] as List).singleWhere(
        (row) => row['id'] == records['attempt_bundle']!['id'],
      );
      expect(indexed['sha256'], sha256Json(records['attempt_bundle']));
      expect(indexed.containsKey('provenance_ids'), isFalse);
      expect(
        report['rights_blockers'],
        contains(
          allOf(
            containsPair('id', 'synthetic-timing'),
            containsPair('use', 'report_export'),
            containsPair('status', 'unresolved'),
          ),
        ),
      );
      expect(await File('$output/attempt-bundle.json').exists(), isFalse);
      expect(
        await File('$output/baseline-summary.json').readAsString(),
        isNot(contains('process_memory_bytes')),
      );
    },
  );

  test('generator and canonical request validator both require explicit optional null', () async {
    final temp = await Directory.systemTemp.createTemp('m0-request-null-');
    addTearDown(() => temp.delete(recursive: true));
    final request = await writeRequest(temp, inputs());
    final value =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>
          ..remove('oracle_results');
    expect(() => validateRecord(value), throwsA(isA<ContractException>()));
    await request.writeAsString(jsonEncode(value));
    final output = '${temp.path}/output';
    await expectLater(
      generateDossier(request.path, inputRoot: temp.path, outputRoot: output),
      throwsA(isA<ContractException>()),
    );
    expect(await Directory(output).exists(), isFalse);
  });

  test('generator refuses punctuation-prefixed private reasons before creating output', () async {
    final temp = await Directory.systemTemp.createTemp('m0-private-reason-');
    addTearDown(() => temp.delete(recursive: true));
    for (final reason in [
      'source=C:/Users/example/reference',
      'source=/home/example/reference',
      r'source=\\server\share\reference',
      'source=file:///home/example/reference',
      '(C:/Users/example/reference)',
      '(/home/example/reference)',
    ]) {
      final request = await writeRequest(temp, inputs(), attemptReason: reason);
      final output = '${temp.path}/output';
      await expectLater(
        generateDossier(request.path, inputRoot: temp.path, outputRoot: output),
        throwsA(isA<ContractException>()),
        reason: reason,
      );
      expect(await Directory(output).exists(), isFalse, reason: reason);
    }
  });

  test(
    'linked input roots declared children and output parents preserve evidence',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'm0-linked-boundaries-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final real = await Directory('${temp.path}/real').create();
      final request = await writeRequest(real, inputs());
      final sentinel = File('${real.path}/sentinel');
      await sentinel.writeAsString('preexisting evidence');
      final linked = '${temp.path}/linked';
      await linkDirectory(linked, real.path);
      addTearDown(() => Link(linked).delete());
      await expectLater(
        generateDossier(
          '$linked/request.json',
          inputRoot: linked,
          outputRoot: '${temp.path}/root-output',
        ),
        throwsA(isA<ContractException>()),
      );
      final child = '${real.path}/linked-child';
      await linkDirectory(child, real.path);
      addTearDown(() => Link(child).delete());
      final value = jsonDecode(await request.readAsString());
      value['records']['environment'] = 'linked-child/environment.json';
      await request.writeAsString(jsonEncode(value));
      await expectLater(
        generateDossier(
          request.path,
          inputRoot: real.path,
          outputRoot: '${temp.path}/child-output',
        ),
        throwsA(isA<ContractException>()),
      );
      await writeRequest(real, inputs());
      await expectLater(
        generateDossier(
          request.path,
          inputRoot: real.path,
          outputRoot: '$linked/output',
        ),
        throwsA(isA<ContractException>()),
      );
      expect(await sentinel.readAsString(), 'preexisting evidence');
      expect(await Directory('${temp.path}/root-output').exists(), isFalse);
      expect(await Directory('${temp.path}/child-output').exists(), isFalse);
      expect(await Directory('${real.path}/output').exists(), isFalse);
    },
  );

  test(
    'existing output evidence is refused without replacing any bytes',
    () async {
      final temp = await Directory.systemTemp.createTemp('m0-existing-output-');
      addTearDown(() => temp.delete(recursive: true));
      final request = await writeRequest(temp, inputs());
      final output = await Directory('${temp.path}/output').create();
      final sentinel = File('${output.path}/qualification.json');
      await sentinel.writeAsString('original evidence bytes');
      await expectLater(
        generateDossier(
          request.path,
          inputRoot: temp.path,
          outputRoot: output.path,
        ),
        throwsA(isA<ContractException>()),
      );
      expect(await sentinel.readAsString(), 'original evidence bytes');
      expect(await Directory('${output.path}/inputs').exists(), isFalse);
    },
  );

  test(
    'original record byte hash binds consumed noncanonical JSON bytes',
    () async {
      final temp = await Directory.systemTemp.createTemp('m0-original-bytes-');
      addTearDown(() => temp.delete(recursive: true));
      final records = inputs();
      final request = await writeRequest(temp, records);
      final original = ' ${jsonEncode(records['environment'])}\r\n';
      await File('${temp.path}/environment.json').writeAsString(original);
      final output = '${temp.path}/output';
      await generateDossier(
        request.path,
        inputRoot: temp.path,
        outputRoot: output,
      );
      final report = jsonDecode(
        await File('$output/qualification.json').readAsString(),
      );
      expect(
        report['inputs'],
        contains(
          containsPair(
            'sha256',
            sha256.convert(utf8.encode(original)).toString(),
          ),
        ),
      );
      expect(
        await File('$output/inputs/environment.json').readAsString(),
        canonicalJson(records['environment']),
      );
    },
  );
  test('missing live and blocked export retain incompleteness without fake observations', () {
    final records = inputs();
    final row = (records['provenance']!['artifacts'] as List).singleWhere(
      (row) => row['id'] == 'm0-authored-report-metadata',
    ) as Map<String, dynamic>;
    export_examples.unresolved(row, 'report_export');
    final dossier = buildDossier(records, runId: 'test-run');
    expect(dossier['qualification']['status'], 'incomplete');
    expect(dossier['baseline_summary']['attempt_n'], 0);
    expect(dossier['baseline_summary']['actionable_sample_n'], 0);
    expect(dossier['baseline_summary']['freeze_id'], isNull);
    expect(dossier['divergence_register']['observed'], isEmpty);
    expect(gate(dossier, 'planned-live-baseline')['status'], 'unverified');
    expect(gate(dossier, 'report-export')['status'], 'unverified');
    expect(dossier['qualification']['rights_blockers'], isNotEmpty);
  });

  test('source intake cannot satisfy a final reference freeze even with complete hashes', () {
    final dossier = buildDossier(inputs(), runId: 'test-run');
    expect(gate(dossier, 'effective-reference-freeze')['status'], 'unverified');
    expect(dossier['qualification']['status'], 'incomplete');
    expect(
      dossier['qualification']['inputs'],
      contains(containsPair('id', 'synthetic-lock')),
    );
  });

  test('omitted maps cells masters and semantic cases remain in required denominators', () {
    final dossier = buildDossier(inputs(), runId: 'test-run');
    final report = dossier['qualification'] as Map<String, dynamic>;
    expect(report['display_matrix']['cells'], hasLength(16));
    expect(report['coverage']['maps'], hasLength(13));
    expect(report['coverage']['scanner_masters']['planned_allocation'], 36);
    expect(report['coverage']['scanner_masters']['actual_master_n'], 0);
    expect(
      gate(dossier, 'scanner-independent-masters')['status'],
      'unverified',
    );
    expect(gate(dossier, 'map-independent-controls')['status'], 'unverified');
    expect(gate(dossier, 'semantic-roster')['status'], 'unverified');
    expect(report['coverage']['cells'].first['missing_variants'], hasLength(4));
  });

  test('synthetic masters and asserted pass checks cannot substitute for real missing cases', () {
    final records = inputs();
    final fixtures = <Map<String, dynamic>>[];
    for (final width in [1920, 2560, 3440, 3840]) {
      for (var index = 0; index < 9; index++) {
        final fixture = comparison_examples.fixture(
          '$width-$index',
          'engine_inspection',
          comparison_examples.inspectionTruth(
            'readable_positive',
            'item-$index',
          ),
        );
        fixture['master_slot'] = [
          'ordinary-positive-a',
          'ordinary-positive-b',
          'quantity-positive-a',
          'quantity-positive-b',
          'empty-no-marker',
          'ui-chrome',
          'ambiguous',
          'occluded',
          'multi',
        ][index];
        fixture['truth']['independent_of_reference_output'] = true;
        fixture['review'] = {'status': 'adjudicated'};
        fixture['adjudication_ids'] = ['first-reviewer', 'second-reviewer'];
        fixture['input']['width'] = width;
        fixture['input']['height'] = width == 1920
            ? 1080
            : width == 3840
            ? 2160
            : 1440;
        fixtures.add(fixture);
      }
    }
    records['fixture_manifest']!['cases'] = fixtures;
    records['planned_checks']!['checks'][0]['case_ids'] = [
      'required-real-case-not-acquired',
    ];
    records['planned_checks']!['checks'][0]['status'] = 'pass';
    final dossier = buildDossier(records, runId: 'test-run');
    expect(
      dossier['qualification']['coverage']['scanner_masters']['actual_master_n'],
      0,
    );
    expect(
      gate(dossier, 'scanner-independent-masters')['status'],
      'unverified',
    );
    expect(gate(dossier, 'declared-case-roster')['status'], 'unverified');
    expect(gate(dossier, 'planned-live-baseline')['status'], 'unverified');
    expect(
      dossier['qualification']['denominators']['missing_case_ids'],
      contains('required-real-case-not-acquired'),
    );
  });

  test(
    'collinear map landmarks cannot satisfy the independent map geometry gate',
    () {
      final records = inputs();
      final hash =
          records['source_intake']!['effective_inputs']['maps'][0]['sha256'];
      records['map_controls']!['expected_roster'] = [
        {
          'map_id': 'factory',
          'source_key': 'factory',
          'frame_revision': '0',
          'artwork_path': 'maps/input',
          'floor_group_ids': <String>[],
          'required_control_count': 3,
        },
      ];
      records['map_controls']!['controls'] = [
        for (var index = 0; index < 3; index++)
          {
            'id': 'factory-control-$index',
            'map_id': 'factory',
            'source_key': 'factory',
            'frame_revision': '0',
            'artwork_sha256': hash,
            'config_sha256': hash,
            'game_xyz': {'x': index, 'y': 0, 'z': index},
            'artwork_pixel': {'x': index * 10, 'y': index * 10},
            'normalized': {'x': index / 100, 'y': index / 100},
            'floor_group_id': 'floor',
            'heading_convention': 'clockwise-north',
            'tolerance': 1,
            'uncertainty': 1,
            'source_ids': ['landmark-$index'],
            'review_ids': ['first-reviewer', 'second-reviewer'],
            'independent_of_reference_output': true,
          },
      ];
      final dossier = buildDossier(records, runId: 'test-run');
      final factory = (dossier['qualification']['coverage']['maps'] as List)
          .singleWhere((row) => row['map_id'] == 'factory');
      expect(factory['actual'], 3);
      expect(factory['noncollinear'], isFalse);
      expect(factory['status'], 'unverified');
      expect(gate(dossier, 'map-independent-controls')['status'], 'unverified');
    },
  );

  test('an independent anchor for another configured floor cannot complete a missing floor check', () {
    final records = inputs();
    final lock = source_examples.lock()..remove('local_locators');
    records.remove('source_intake');
    records['source_lock'] = lock;
    final hash = lock['effective_inputs']['maps'][0]['sha256'];
    records['map_controls']!['expected_roster'] = [
      {
        'map_id': 'factory',
        'source_key': 'factory',
        'frame_revision': '0',
        'artwork_path': 'maps/input',
        'floor_group_ids': ['Ground_Floor', 'Second_Floor'],
        'required_control_count': 3,
      },
    ];
    records['map_controls']!['anchors'] = [
      {
        'id': 'factory-second-floor',
        'map_id': 'factory',
        'source_key': 'factory',
        'frame_revision': '0',
        'kind': 'floor_artwork',
        'floor_group_id': 'Second_Floor',
        'artwork_path': 'maps/input',
        'artwork_sha256': hash,
        'config_sha256': hash,
        'width': 100,
        'height': 100,
        'points': [
          {'x': 20, 'y': 30},
        ],
        'uncertainty': 1,
        'independent_of_reference_output': true,
        'source_ids': ['survey-second-floor'],
        'review_ids': ['first-reviewer', 'second-reviewer'],
      },
    ];
    records['planned_checks']!['checks'] = [
      {
        'id': 'floor-ground',
        'required': true,
        'applicable': true,
        'attempted': true,
        'owner': 'independent-map-annotators',
        'scope': 'floor-artwork-anchor',
        'stratum_id': 'factory',
        'map_id': 'factory',
        'source_key': 'factory',
        'frame_revision': '0',
        'floor_group_id': 'Ground_Floor',
        'reason': 'The required ground-floor anchor is still missing.',
        'case_ids': <String>[],
        'allocation': 1,
        'evidence_ids': ['factory-second-floor'],
        'disposition': 'observed',
        'freeze_id': lock['freeze_id'],
      },
    ];
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'planned-floor-ground')['status'], 'unverified');
    expect(gate(dossier, 'map-floor-raster-anchors')['status'], 'unverified');
    final factory = (dossier['qualification']['coverage']['maps'] as List)
        .singleWhere((row) => row['map_id'] == 'factory');
    expect(factory['missing_case_ids'], ['Ground_Floor']);
  });

  test('invalid oracle linkage fails validity instead of becoming a reference defect', () {
    final records = inputs();
    final lock = source_examples.lock()..remove('local_locators');
    records.remove('source_intake');
    records['source_lock'] = lock;
    records['oracle_results'] = source_examples.oracle(
      lock['freeze_id'] as String,
    )..['run_id'] = 'wrong-run';
    final dossier = buildDossier(records, runId: 'test-run');
    expect(dossier['qualification']['status'], 'not_qualified');
    expect(gate(dossier, 'oracle-evidence-linkage')['status'], 'fail');
    expect(dossier['divergence_register']['observed'], isEmpty);
    expect(
      dossier['qualification']['exports'].any(
        (row) => row['path'] == 'reference-results.json',
      ),
      isFalse,
    );
  });

  test('faithfully recorded wrong identity is a counted defect, not invalid evidence', () {
    final records = inputs();
    final lock = source_examples.lock()..remove('local_locators');
    records.remove('source_intake');
    records['source_lock'] = lock;
    final fixture = comparison_examples.fixture(
      'positive',
      'engine_inspection',
      comparison_examples.inspectionTruth('readable_positive', 'right-id'),
    );
    final manifest = comparison_examples.manifest([fixture])
      ..['freeze_id'] = lock['freeze_id'];
    records['fixture_manifest'] = manifest;
    records['oracle_results'] =
        comparison_examples.results(manifest, [
            comparison_examples.observation(
              'positive',
              'engine_inspection',
              comparison_examples.engine('recognized', 'wrong-id'),
            ),
          ])
          ..['run_id'] = 'test-run'
          ..['environment_id'] = records['environment']!['id'];
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'oracle-evidence-linkage')['status'], 'pass');
    expect(
      gate(dossier, 'offline-reference-characterization')['status'],
      'pass',
    );
    expect(dossier['qualification']['status'], 'incomplete');
    expect(
      dossier['qualification']['coverage']['recognition']['metrics']['wrong_positive_ids'],
      1,
    );
    expect(
      dossier['qualification']['coverage']['recognition']['metrics']['wrong_identities'],
      1,
    );
    expect(dossier['divergence_register']['observed'], hasLength(1));
    expect(
      dossier['divergence_register']['observed']
          .single['observed']['outcome']['item_id'],
      'wrong-id',
    );
  });

  test('faithful slow stages and error outcomes remain defects and counts, not invalid linkage', () {
    final records = inputs();
    final lock = source_examples.lock()..remove('local_locators');
    records.remove('source_intake');
    records['source_lock'] = lock;
    final fixture = comparison_examples.fixture(
      'variant-1',
      'host_resolution',
      comparison_examples.policyTruth('Check'),
    );
    records['fixture_manifest'] = comparison_examples.manifest([fixture])
      ..['freeze_id'] = lock['freeze_id'];
    final attempt = statistics_examples.attempt(
      'error-attempt',
      outcome: 'error',
    )..['input_sha256'] = fixture['input']['sha256'];
    records['attempt_bundle'] = statistics_examples.bundle([attempt])
      ..['freeze_id'] = lock['freeze_id']
      ..['run_id'] = 'test-run'
      ..['environment_id'] = records['environment']!['id']
      ..['targets_ms'] = {'capture': 1};
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'attempt-evidence-linkage')['status'], 'pass');
    expect(dossier['qualification']['status'], 'incomplete');
    expect(dossier['baseline_summary']['attempt_n'], 1);
    expect(dossier['baseline_summary']['outcome_counts'], {'error': 1});
    expect(dossier['baseline_summary']['actionable_sample_n'], 0);
    final speed = (dossier['divergence_register']['observed'] as List)
        .singleWhere((row) => row['kind'] == 'reference_speed');
    expect(speed['observed'], {'name': 'capture', 'n': 1, 'p95_ms': 5.0});
    expect(speed['expected'], {'target_ms': 1});
    expect(speed['case_ids'], ['variant-1']);
    expect(speed.containsKey('case_id'), isFalse);
    expect(speed.containsKey('profile'), isFalse);
    expect(speed['evidence_ids'], [records['attempt_bundle']!['id']]);
    expect(
      () => validateRecord(
        dossier['divergence_register'] as Map<String, dynamic>,
      ),
      returnsNormally,
    );
    expect(
      dossier['qualification']['exports'],
      contains(containsPair('path', 'divergences.json')),
    );
  });

  test('finite warm live allocation counts one wrong identity without a success quota', () {
    final records = finiteLiveInputs();
    final rows = records['attempt_bundle']!['attempts'] as List;
    rows.first['terminal_outcome'] = 'wrong_id';
    rows.first['endpoint'] = null;
    rows.first['endpoint_reason'] =
        'Wrong identity is not a correct actionable endpoint.';
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'attempt-evidence-linkage')['status'], 'pass');
    expect(gate(dossier, 'user-native-visible-baseline')['status'], 'pass');
    for (final path in ['intended-targeted', 'fallback-required']) {
      expect(gate(dossier, 'planned-live-warm-$path')['status'], 'pass');
    }
    expect(dossier['baseline_summary']['attempt_n'], 200);
    expect(dossier['baseline_summary']['actionable_sample_n'], 199);
    expect(dossier['baseline_summary']['outcome_counts'], {
      'wrong_id': 1,
      'correct': 199,
    });
    expect(
      dossier['qualification']['coverage']['checks'].first['completed_n'],
      99,
    );
    expect(
      dossier['qualification']['coverage']['checks'].first['actual_attempt_n'],
      100,
    );
  });

  test('known completed noncorrect live outcomes retain finite attempt eligibility', () {
    final records = finiteLiveInputs();
    final rows = records['attempt_bundle']!['attempts'] as List;
    const outcomes = [
      'wrong_id',
      'rejected',
      'error',
      'canceled',
      'superseded',
    ];
    for (var index = 0; index < outcomes.length; index++) {
      rows[index]['terminal_outcome'] = outcomes[index];
      rows[index]['endpoint'] = null;
      rows[index]['endpoint_reason'] =
          'Completed noncorrect result has no success endpoint.';
    }
    final dossier = buildDossier(records, runId: 'test-run');
    expect(gate(dossier, 'user-native-visible-baseline')['status'], 'pass');
    expect(
      gate(dossier, 'planned-live-warm-intended-targeted')['status'],
      'pass',
    );
    expect(dossier['baseline_summary']['attempt_n'], 200);
    expect(dossier['baseline_summary']['actionable_sample_n'], 195);
  });

  test('missing or uncorrelated physical actuation cannot complete a noncorrect attempt', () {
    for (final defect in [
      'missing',
      'unobservable',
      'uncorrelated',
      'wrong-boundary',
    ]) {
      final records = finiteLiveInputs();
      final row = (records['attempt_bundle']!['attempts'] as List).first;
      row['terminal_outcome'] = 'wrong_id';
      row['endpoint'] = null;
      row['endpoint_reason'] =
          'Wrong identity has no eligible success endpoint.';
      switch (defect) {
        case 'missing':
          row['trigger'] = null;
          row['trigger_reason'] = 'Physical actuation was not observed.';
        case 'unobservable':
          row['trigger']['observable'] = false;
        case 'uncorrelated':
          row['trigger']['request_id'] = 'another-request';
        case 'wrong-boundary':
          row['trigger']['name'] = 'hook_receipt';
      }
      final dossier = buildDossier(records, runId: 'test-run');
      expect(
        gate(dossier, 'attempt-evidence-linkage')['status'],
        'pass',
        reason: defect,
      );
      expect(
        gate(dossier, 'user-native-visible-baseline')['status'],
        'unverified',
        reason: defect,
      );
      expect(
        gate(dossier, 'planned-live-warm-intended-targeted')['status'],
        'unverified',
        reason: defect,
      );
      expect(dossier['baseline_summary']['attempt_n'], 200, reason: defect);
    }
  });

  test('missing or incorrect correct-result endpoint keeps live allocation unverified', () {
    for (final defect in ['missing', 'wrong-identity', 'occluded']) {
      final records = finiteLiveInputs();
      final row = (records['attempt_bundle']!['attempts'] as List).first;
      if (defect == 'missing') {
        row['endpoint'] = null;
        row['endpoint_reason'] = 'No actionable frame was observed.';
      } else if (defect == 'wrong-identity') {
        row['endpoint']['correctness'] = 'wrong_identity';
      } else {
        row['endpoint']['visibility'] = 'occluded';
      }
      final dossier = buildDossier(records, runId: 'test-run');
      expect(
        gate(dossier, 'attempt-evidence-linkage')['status'],
        'pass',
        reason: defect,
      );
      expect(
        gate(dossier, 'user-native-visible-baseline')['status'],
        'unverified',
        reason: defect,
      );
      expect(
        gate(dossier, 'planned-live-warm-intended-targeted')['status'],
        'unverified',
        reason: defect,
      );
      expect(
        dossier['baseline_summary']['actionable_sample_n'],
        199,
        reason: defect,
      );
      expect(dossier['baseline_summary']['attempt_n'], 200, reason: defect);
    }
  });

  test(
    'invalid physical timing or changed input bytes remain invalid evidence',
    () {
      for (final defect in ['physical-timing', 'input-hash']) {
        final records = finiteLiveInputs();
        final row = (records['attempt_bundle']!['attempts'] as List).first;
        if (defect == 'physical-timing') {
          row['terminal_outcome'] = 'wrong_id';
          row['endpoint'] = null;
          row['endpoint_reason'] = 'No correct endpoint for wrong identity.';
          row['trigger']['lower_ms'] = 1;
          row['trigger']['upper_ms'] = 0;
        } else {
          row['input_sha256'] = 'f' * 64;
        }
        final dossier = buildDossier(records, runId: 'test-run');
        expect(
          gate(dossier, 'attempt-evidence-linkage')['status'],
          'fail',
          reason: defect,
        );
        expect(
          gate(dossier, 'user-native-visible-baseline')['status'],
          'unverified',
          reason: defect,
        );
        expect(
          dossier['baseline_summary']['collection_status'],
          'invalid_evidence',
          reason: defect,
        );
        expect(dossier['baseline_summary']['attempt_n'], 200, reason: defect);
        expect(
          dossier['baseline_summary']['actionable_sample_n'],
          0,
          reason: defect,
        );
        expect(
          dossier['qualification']['status'],
          'not_qualified',
          reason: defect,
        );
      }
    },
  );

  test(
    'balanced route totals cannot hide the wrong finite per-batch allocation',
    () {
      final records = finiteLiveInputs();
      final rows = records['attempt_bundle']!['attempts'] as List;
      rows.first['batch_ordinal'] = 2;
      final dossier = buildDossier(records, runId: 'test-run');
      expect(gate(dossier, 'attempt-evidence-linkage')['status'], 'pass');
      expect(dossier['baseline_summary']['attempt_n'], 200);
      expect(dossier['baseline_summary']['actionable_sample_n'], 200);
      expect(
        gate(dossier, 'user-native-visible-baseline')['status'],
        'unverified',
      );
      expect(
        gate(dossier, 'planned-live-warm-intended-targeted')['status'],
        'unverified',
      );
    },
  );

  test('incomplete and unknown timeout outcomes are retained but cannot complete live gates', () {
    for (final outcome in ['incomplete', 'timeout']) {
      final records = finiteLiveInputs();
      final row = (records['attempt_bundle']!['attempts'] as List).first;
      row['terminal_outcome'] = outcome;
      final dossier = buildDossier(records, runId: 'test-run');
      expect(
        gate(dossier, 'attempt-evidence-linkage')['status'],
        'pass',
        reason: outcome,
      );
      expect(
        gate(dossier, 'user-native-visible-baseline')['status'],
        'unverified',
        reason: outcome,
      );
      expect(
        gate(dossier, 'planned-live-warm-intended-targeted')['status'],
        'unverified',
        reason: outcome,
      );
      expect(dossier['baseline_summary']['outcome_counts'][outcome], 1);
      expect(dossier['baseline_summary']['attempt_n'], 200);
    }
  });

  test('incomplete collection dispositions apply to both planned warm gates and baseline', () {
    for (final disposition in ['incomplete', 'skipped', 'unattempted']) {
      final records = finiteLiveInputs();
      records['attempt_bundle']!['collection_status'] = disposition;
      records['attempt_bundle']!['collection_rationale'] =
          'Collection is not complete.';
      final dossier = buildDossier(records, runId: 'test-run');
      for (final id in [
        'user-native-visible-baseline',
        'planned-live-warm-intended-targeted',
        'planned-live-warm-fallback-required',
      ]) {
        expect(gate(dossier, id)['status'], 'unverified', reason: disposition);
      }
      expect(dossier['baseline_summary']['attempt_n'], 200);
    }
  });

  test(
    'extra warm attempts remain retained instead of satisfying a success quota',
    () {
      final records = finiteLiveInputs();
      final rows = records['attempt_bundle']!['attempts'] as List;
      final extra = jsonDecode(jsonEncode(rows.first)) as Map<String, dynamic>
        ..['id'] = 'extra-warm-attempt';
      rows.add(extra);
      final dossier = buildDossier(records, runId: 'test-run');
      expect(dossier['baseline_summary']['attempt_n'], 201);
      expect(
        gate(dossier, 'user-native-visible-baseline')['status'],
        'unverified',
      );
      expect(
        gate(dossier, 'planned-live-warm-intended-targeted')['status'],
        'unverified',
      );
    },
  );

  test('genuine visible speed divergence validates interval metrics and actual evidence', () {
    final records = finiteLiveInputs();
    records['attempt_bundle']!['targets_ms'] = {
      'physical_to_actionable_visible': 1,
    };
    final dossier = buildDossier(records, runId: 'test-run');
    final register = dossier['divergence_register'] as Map<String, dynamic>;
    expect(() => validateRecord(register), returnsNormally);
    expect(
      dossier['qualification']['exports'],
      contains(containsPair('path', 'divergences.json')),
    );
    expect(register['observed'], hasLength(4));
    for (final speed in register['observed'] as List) {
      expect(speed['kind'], 'reference_speed');
      expect(speed['case_ids'], ['variant-1']);
      expect(speed.containsKey('case_id'), isFalse);
      expect(speed.containsKey('profile'), isFalse);
      expect(speed['evidence_ids'], [records['attempt_bundle']!['id']]);
      expect(speed['observed']['p95_lower_ms'], 20);
      expect(speed['observed']['p95_upper_ms'], 20);
      expect(speed['observed']['n'], 50);
      expect(speed['observed']['name'], 'physical_to_actionable_visible');
    }
    for (final defect in [
      'missing-cases',
      'fake-case',
      'missing-evidence',
      'backwards-bounds',
      'no-exceedance',
      'mixed-metrics',
    ]) {
      final invalid = jsonDecode(jsonEncode(register)) as Map<String, dynamic>;
      final speed = (invalid['observed'] as List).first;
      switch (defect) {
        case 'missing-cases':
          speed['case_ids'] = [];
        case 'fake-case':
          speed['case_id'] = 'fabricated';
        case 'missing-evidence':
          speed['evidence_ids'] = [];
        case 'backwards-bounds':
          speed['observed']['p95_lower_ms'] = 21;
        case 'no-exceedance':
          speed['expected']['target_ms'] = 20;
        case 'mixed-metrics':
          speed['observed']['p95_ms'] = 20;
      }
      expect(
        () => validateRecord(invalid),
        throwsA(isA<ContractException>()),
        reason: defect,
      );
    }
  });

  test('unattempted planned allocation is not lost or converted to failed synthetic attempts', () {
    final dossier = buildDossier(inputs(), runId: 'test-run');
    final checks = dossier['qualification']['coverage']['checks'] as List;
    expect(checks.single['allocation'], 100);
    expect(checks.single['attempted'], isFalse);
    expect(checks.single['disposition'], 'blocked');
    expect(gate(dossier, 'planned-live-baseline')['owner'], 'user');
    expect(
      gate(dossier, 'planned-live-baseline')['reason'],
      contains('not collected'),
    );
    expect(dossier['baseline_summary']['attempt_ids'], isEmpty);
  });

  test('explicit file generator refuses forbidden attachments before any output is written', () async {
    final temp = await Directory.systemTemp.createTemp('m0-report-test-');
    addTearDown(() => temp.delete(recursive: true));
    final records = inputs();
    records['fixture_manifest']!['attachments'] = [
      {'path': 'private/recording.mp4'},
    ];
    for (final entry in records.entries) {
      await File('${temp.path}/${entry.key}.json')
          .writeAsString(jsonEncode(entry.value));
    }
    final request = File('${temp.path}/request.json');
    await request.writeAsString(
      jsonEncode(
        record('dossier_request', 'request', {
          'run_id': 'test-run',
          'records': {for (final key in records.keys) key: '$key.json'},
          'oracle_results': null,
          'oracle_results_reason': 'No native replay.',
          'attempt_bundle': null,
          'attempt_bundle_reason': 'No actual collection.',
        }),
      ),
    );
    final output = '${temp.path}/output';
    await expectLater(
      generateDossier(request.path, inputRoot: temp.path, outputRoot: output),
      throwsA(isA<ContractException>()),
    );
    expect(await Directory(output).exists(), isFalse);
  });

  test('fixture file hashes rooted at inputRoot detect changed bytes before exporting', () async {
    final temp = await Directory.systemTemp.createTemp('m0-report-integrity-');
    addTearDown(() => temp.delete(recursive: true));
    final records = inputs();
    await Directory('${temp.path}/payloads').create();
    final original = jsonEncode(
      record('fixture_manifest', 'local-corpus', {
        'corpus_version': '1',
        'annotation_version': '1',
        'catalog_version': '1',
        'config_version': '1',
        'cases': <dynamic>[],
      }),
    );
    await File('${temp.path}/payloads/corpus.json').writeAsString('$original ');
    records['fixture_manifest']!['files'] = [
      {
        'id': 'local-corpus',
        'path': 'payloads/corpus.json',
        'sha256': sha256.convert(utf8.encode(original)).toString(),
        'size_bytes': utf8.encode(original).length,
        'parent_ids': <String>[],
        'parent_bindings': <dynamic>[],
        'recipe': {
          'kind': 'original_authorship',
          'authoring_source_id': 'm0-original-synthetic-fixtures',
          'version': 1,
        },
        'recipe_sha256': sha256Json({
          'kind': 'original_authorship',
          'authoring_source_id': 'm0-original-synthetic-fixtures',
          'version': 1,
        }),
      },
    ];
    for (final entry in records.entries) {
      await File('${temp.path}/${entry.key}.json')
          .writeAsString(jsonEncode(entry.value));
    }
    final request = File('${temp.path}/request.json');
    await request.writeAsString(
      jsonEncode(
        record('dossier_request', 'request', {
          'run_id': 'test-run',
          'records': {for (final key in records.keys) key: '$key.json'},
          'oracle_results': null,
          'oracle_results_reason': 'No native replay.',
          'attempt_bundle': null,
          'attempt_bundle_reason': 'No actual collection.',
        }),
      ),
    );
    final output = '${temp.path}/output';
    await expectLater(
      generateDossier(request.path, inputRoot: temp.path, outputRoot: output),
      throwsA(isA<ContractException>()),
    );
    expect(await Directory(output).exists(), isFalse);
  });

  test('cleared synthetic oracle survives canonical public reconsume with exact frozen bytes', () async {
    final original = await Directory.systemTemp.createTemp(
      'm0-cleared-oracle-original-',
    );
    final consumer = await Directory.systemTemp.createTemp(
      'm0-cleared-oracle-consumer-',
    );
    addTearDown(() => original.delete(recursive: true));
    addTearDown(() => consumer.delete(recursive: true));
    // Authored serialized observations only: no native invocation or actual
    // user evidence is collected by either generator call.
    final records = observedPolicyInputs();
    final manifest = records['fixture_manifest']!;
    final fixture = manifest['cases'][0] as Map<String, dynamic>;
    final inputBytes = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert({'item_id': 'item-a', 'instance_fir': null, 'keep_need': false})}\r\n',
    );
    fixture['input']['sha256'] = sha256.convert(inputBytes).toString();
    final corpus = comparison_examples.manifest([fixture])
      ..['id'] = 'local-policy-corpus'
      ..['freeze_id'] = records['source_lock']!['freeze_id'];
    final displayBytes = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(records['display_matrix'])}\r\n',
    );
    final frozenBytes = <String, List<int>>{
      'payloads/policy-corpus.json': utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(corpus)}\r\n',
      ),
      'display_matrix.json': displayBytes,
      fixture['input']['path'] as String: inputBytes,
    };
    final frozenIds = {
      'payloads/policy-corpus.json': corpus['id'],
      'display_matrix.json': records['display_matrix']!['id'],
      fixture['input']['path'] as String: 'policy-input',
    };
    final recipe = {
      'kind': 'original_authorship',
      'authoring_source_id': 'm0-original-synthetic-fixtures',
      'version': 1,
    };
    manifest['files'] = [
      for (final entry in frozenBytes.entries)
        {
          'id': frozenIds[entry.key],
          'path': entry.key,
          'sha256': sha256.convert(entry.value).toString(),
          'size_bytes': entry.value.length,
          'parent_ids': <String>[],
          'parent_bindings': <dynamic>[],
          'recipe': recipe,
          'recipe_sha256': sha256Json(recipe),
        },
    ];
    final oracle = records['oracle_results']!;
    oracle['fixture_manifest_sha256'] = sha256Json(manifest);
    oracle['observations'][0]['input_sha256'] = fixture['input']['sha256'];
    final clearance = inspectExport(oracle, [
      'synthetic-observations',
    ], records['provenance']!);
    expect(clearance.allowed, isTrue, reason: clearance.blockers.join(' | '));
    final request = await writeRequest(original, records);
    for (final entry in frozenBytes.entries) {
      final file = File('${original.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
    }
    final prettyManifest = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\r\n',
    );
    final prettyOracle = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(oracle)}\r\n',
    );
    await File('${original.path}/fixture_manifest.json')
        .writeAsBytes(prettyManifest);
    await File('${original.path}/oracle_results.json')
        .writeAsBytes(prettyOracle);
    expect(
      sha256.convert(prettyManifest).toString(),
      isNot(oracle['fixture_manifest_sha256']),
    );
    final output = '${original.path}/output';
    await generateDossier(
      request.path,
      inputRoot: original.path,
      outputRoot: output,
    );
    final report = jsonDecode(
      await File('$output/qualification.json').readAsString(),
    ) as Map<String, dynamic>;
    final divergence = jsonDecode(
      await File('$output/divergences.json').readAsString(),
    ) as Map<String, dynamic>;
    final exportedOracleBytes = await File('$output/reference-results.json')
        .readAsBytes();
    expect(jsonDecode(utf8.decode(exportedOracleBytes)), oracle);
    expect(utf8.decode(exportedOracleBytes), canonicalJson(oracle));
    expect(exportedOracleBytes, isNot(prettyOracle));
    expect(
      (report['exports'] as List).singleWhere(
        (row) => row['path'] == 'reference-results.json',
      ),
      {
        'path': 'reference-results.json',
        'sha256': sha256Json(oracle),
        'provenance_ids': ['synthetic-observations'],
      },
    );
    expect(
      (report['exports'] as List).singleWhere(
        (row) => row['path'] == 'divergences.json',
      )['provenance_ids'],
      ['m0-authored-report-metadata', 'synthetic-observations'],
    );

    void expectObservedPolicy(
      Map<String, dynamic> qualification,
      Map<String, dynamic> register,
    ) {
      expect(
        (qualification['gates'] as List).singleWhere(
          (row) => row['id'] == 'oracle-evidence-linkage',
        )['status'],
        'pass',
      );
      expect(qualification['status'], isNot('qualified'));
      expect(qualification['denominators']['actual_attempt_n'], 0);
      expect(qualification['denominators']['observed_case_ids'], ['policy']);
      final recognition = qualification['coverage']['recognition'];
      expect(recognition['status'], 'pass');
      expect(
        recognition['reference_behavior'],
        'intentional_divergences_observed',
      );
      expect(recognition['denominators'], {
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
      expect(recognition['metrics']['correct_positive_ids'], 1);
      expect(recognition['metrics']['host_accepted_identities'], 1);
      expect(recognition['metrics']['actionable_advice'], 1);
      expect(recognition['metrics']['wrong_identities'], 0);
      expect(recognition['metrics']['policy_mismatches'], 0);
      expect(register['provenance_ids'], ['synthetic-observations']);
      expect(register['expectation_only'], isEmpty);
      expect(register['observed'], hasLength(1));
      final row = register['observed'].single;
      expect(row['case_id'], 'policy');
      expect(row['profile'], 'host_resolution');
      expect(row['kind'], 'intentional_target_policy');
      expect(row['status'], 'observed');
      expect(row['expected'], fixture['truth']['target_policy']);
      expect(row['observed'], oracle['observations'][0]['result']);
      expect(row['expected']['decision'], 'Check');
      expect(row['observed']['decision'], 'Sell');
      expect(row['rationale'], contains('FIR'));
      expect(row['defects'], isEmpty);
      expect(row['errors'], isEmpty);
      expect(row['evidence_ids'], [oracle['id']]);
      expect(qualification['divergences'], register['observed']);
      final indexed = (qualification['evidence_index'] as List).singleWhere(
        (row) => row['id'] == oracle['id'],
      );
      expect(indexed['status'], 'pass');
      expect(indexed['sha256'], sha256Json(oracle));
      expect(indexed['provenance_ids'], ['synthetic-observations']);
    }

    expectObservedPolicy(report, divergence);
    await Directory('${consumer.path}/public').create();
    final consumerPaths = <String, String>{};
    for (final key in records.keys) {
      final exportedPath = key == 'oracle_results'
          ? 'reference-results.json'
          : 'inputs/$key.json';
      consumerPaths[key] = 'public/$key.json';
      await File('$output/$exportedPath')
          .copy('${consumer.path}/${consumerPaths[key]}');
    }
    for (final entry in frozenBytes.entries) {
      final file = File('${consumer.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await File('${original.path}/${entry.key}').copy(file.path);
      final copied = await file.readAsBytes();
      expect(copied, entry.value);
      final declared = (manifest['files'] as List).singleWhere(
        (row) => row['path'] == entry.key,
      );
      expect(sha256.convert(copied).toString(), declared['sha256']);
      expect(copied.length, declared['size_bytes']);
    }
    final canonicalDisplay = await File(
      '${consumer.path}/${consumerPaths['display_matrix']}',
    ).readAsBytes();
    expect(
      utf8.decode(canonicalDisplay),
      canonicalJson(records['display_matrix']),
    );
    expect(canonicalDisplay, isNot(displayBytes));
    expect(
      sha256.convert(canonicalDisplay).toString(),
      isNot(sha256.convert(displayBytes).toString()),
    );
    final consumerRequest = File('${consumer.path}/request.json');
    await consumerRequest.writeAsString(
      jsonEncode(
        record('dossier_request', 'consumer-request', {
          'run_id': 'test-run',
          'records': consumerPaths,
          'attempt_bundle': null,
          'attempt_bundle_reason': 'No actual collection.',
        }),
      ),
    );
    final consumedOutput = '${consumer.path}/output';
    await generateDossier(
      consumerRequest.path,
      inputRoot: consumer.path,
      outputRoot: consumedOutput,
    );
    final consumedReport = jsonDecode(
      await File('$consumedOutput/qualification.json').readAsString(),
    ) as Map<String, dynamic>;
    final consumedDivergence = jsonDecode(
      await File('$consumedOutput/divergences.json').readAsString(),
    ) as Map<String, dynamic>;
    expectObservedPolicy(consumedReport, consumedDivergence);
    expect(consumedDivergence, divergence);
    expect(consumedReport['coverage'], report['coverage']);
    expect(consumedReport['denominators'], report['denominators']);
    expect(consumedReport['status'], report['status']);
    expect(consumedReport['exports'], report['exports']);
    expect(
      await File('$consumedOutput/reference-results.json').readAsBytes(),
      exportedOracleBytes,
    );
    for (final key in [
      'fixture_manifest',
      'display_matrix',
      'oracle_results',
    ]) {
      final originalBytes = await File('${original.path}/$key.json')
          .readAsBytes();
      final publicBytes = await File('${consumer.path}/${consumerPaths[key]}')
          .readAsBytes();
      expect(publicBytes, isNot(originalBytes));
      expect(utf8.decode(publicBytes), canonicalJson(records[key]));
      for (final pair in [
        (report, originalBytes),
        (consumedReport, publicBytes),
      ]) {
        expect(
          (pair.$1['inputs'] as List).singleWhere(
            (row) => row['id'] == '${records[key]!['id']}-original-json-bytes',
          )['sha256'],
          sha256.convert(pair.$2).toString(),
        );
      }
    }
    // Logical JSON equality cannot substitute for frozen byte identity.
    for (final entry in frozenBytes.entries) {
      final file = File('${consumer.path}/${entry.key}');
      await file.writeAsBytes([...entry.value, 32]);
      final rejectedOutput = '${consumer.path}/drift-${frozenIds[entry.key]}';
      await expectLater(
        generateDossier(
          consumerRequest.path,
          inputRoot: consumer.path,
          outputRoot: rejectedOutput,
        ),
        throwsA(
          isA<ContractException>().having(
            (error) => error.message,
            'message',
            contains(
              'Fixture payload hash/size drift: ${frozenIds[entry.key]}',
            ),
          ),
        ),
      );
      expect(await Directory(rejectedOutput).exists(), isFalse);
      await file.writeAsBytes(entry.value);
    }
  });

  test('portable generator consumes canonical exports with exact frozen payloads and rejects drift', () async {
    final temp = await Directory.systemTemp.createTemp('m0-report-output-');
    addTearDown(() => temp.delete(recursive: true));
    final records = inputs();
    records['display_matrix']!['cells'] = [
      {
        'id': '1920-100',
        'width': 1920,
        'height': 1080,
        'os_scale_percent': 100,
        'evidence_class': 'planned',
        'case_ids': <String>[],
        'evidence_ids': <String>[],
        'limitations': 'No actual display observation.',
      },
    ];
    final displayBytes = jsonEncode(records['display_matrix']);
    await Directory('${temp.path}/records').create();
    await Directory('${temp.path}/payloads').create();
    final corpusBytes = jsonEncode(
      record('fixture_manifest', 'local-corpus', {
        'corpus_version': '1',
        'annotation_version': '1',
        'catalog_version': '1',
        'config_version': '1',
        'cases': <dynamic>[],
      }),
    );
    await File('${temp.path}/payloads/corpus.json').writeAsString(corpusBytes);
    final recipe = {
      'kind': 'original_authorship',
      'authoring_source_id': 'm0-original-synthetic-fixtures',
      'version': 1,
    };
    records['fixture_manifest']!['files'] = [
      {
        'id': 'local-corpus',
        'path': 'payloads/corpus.json',
        'sha256': sha256.convert(utf8.encode(corpusBytes)).toString(),
        'size_bytes': utf8.encode(corpusBytes).length,
        'parent_ids': <String>[],
        'parent_bindings': <dynamic>[],
        'recipe': recipe,
        'recipe_sha256': sha256Json(recipe),
      },
      {
        'id': records['display_matrix']!['id'],
        'path': 'display_matrix.json',
        'sha256': sha256.convert(utf8.encode(displayBytes)).toString(),
        'size_bytes': utf8.encode(displayBytes).length,
        'parent_ids': <String>[],
        'parent_bindings': <dynamic>[],
        'recipe': recipe,
        'recipe_sha256': sha256Json(recipe),
      },
    ];
    final paths = {
      for (final key in records.keys)
        key: key == 'fixture_manifest' ? 'records/$key.json' : '$key.json',
    };
    for (final entry in records.entries) {
      await File('${temp.path}/${paths[entry.key]}')
          .writeAsString(jsonEncode(entry.value));
    }
    final request = File('${temp.path}/request.json');
    await request.writeAsString(
      jsonEncode(
        record('dossier_request', 'request', {
          'run_id': 'test-run',
          'records': paths,
          'oracle_results': null,
          'oracle_results_reason': 'No native replay.',
          'attempt_bundle': null,
          'attempt_bundle_reason': 'No actual collection.',
        }),
      ),
    );
    final output = '${temp.path}/output';
    await generateDossier(
      request.path,
      inputRoot: temp.path,
      outputRoot: output,
    );
    final report = jsonDecode(
      await File('$output/qualification.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(report['status'], 'incomplete');
    expect(await File('$output/reference-results.json').exists(), isFalse);
    expect(await File('$output/attempt-bundle.json').exists(), isFalse);
    expect(
      report['exports'].any((row) => row['path'] == 'qualification.json'),
      isFalse,
    );
    for (final entry in report['exports'] as List) {
      final bytes = await File('$output/${entry['path']}').readAsString();
      expect(entry['sha256'], sha256Json(jsonDecode(bytes)));
    }
    expect(
      await File('$output/README.md').readAsString(),
      contains('not user-approved skips'),
    );
    final exportedDisplay = File('$output/inputs/display_matrix.json');
    final canonicalDisplay = await exportedDisplay.readAsString();
    expect(canonicalDisplay, canonicalJson(records['display_matrix']));
    expect(canonicalDisplay, isNot(displayBytes));
    final consumerRequest = File('${temp.path}/consumer-request.json');
    await consumerRequest.writeAsString(
      jsonEncode(
        record('dossier_request', 'consumer-request', {
          'run_id': 'test-run',
          'records': {
            for (final key in records.keys) key: 'output/inputs/$key.json',
          },
          'oracle_results': null,
          'oracle_results_reason': 'No native replay.',
          'attempt_bundle': null,
          'attempt_bundle_reason': 'No actual collection.',
        }),
      ),
    );
    final consumedOutput = '${temp.path}/consumed-output';
    await generateDossier(
      consumerRequest.path,
      inputRoot: temp.path,
      outputRoot: consumedOutput,
    );
    final consumedReport = jsonDecode(
      await File('$consumedOutput/qualification.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(consumedReport['status'], report['status']);
    expect(
      {
        for (final row in consumedReport['gates'] as List)
          row['id']: row['status'],
      },
      {for (final row in report['gates'] as List) row['id']: row['status']},
    );
    expect(consumedReport['coverage'], report['coverage']);
    expect(consumedReport['denominators'], report['denominators']);
    for (final row in records['fixture_manifest']!['files'] as List) {
      final bytes = await File('${temp.path}/${row['path']}').readAsBytes();
      expect(sha256.convert(bytes).toString(), row['sha256']);
      expect(bytes.length, row['size_bytes']);
    }

    // Whitespace changes no logical JSON, but must still fail the frozen hash.
    final frozenDisplay = File('${temp.path}/display_matrix.json');
    await frozenDisplay.writeAsString('$displayBytes ');
    final tamperedOutput = '${temp.path}/tampered-output';
    await expectLater(
      generateDossier(
        consumerRequest.path,
        inputRoot: temp.path,
        outputRoot: tamperedOutput,
      ),
      throwsA(
        isA<ContractException>().having(
          (error) => error.message,
          'message',
          contains('Fixture payload hash/size drift: display'),
        ),
      ),
    );
    expect(await Directory(tamperedOutput).exists(), isFalse);
    await frozenDisplay.writeAsString(displayBytes);

    // A valid supplied role record must retain every field of the frozen one.
    final driftedDisplay = jsonDecode(canonicalDisplay) as Map<String, dynamic>;
    driftedDisplay['cells'][0]['limitations'] = 'Changed logical limitation.';
    await exportedDisplay.writeAsString(canonicalJson(driftedDisplay));
    final driftedOutput = '${temp.path}/drifted-output';
    await expectLater(
      generateDossier(
        consumerRequest.path,
        inputRoot: temp.path,
        outputRoot: driftedOutput,
      ),
      throwsA(
        isA<ContractException>().having(
          (error) => error.message,
          'message',
          contains(
            'Consumed record differs from its declared manifest file: display',
          ),
        ),
      ),
    );
    expect(await Directory(driftedOutput).exists(), isFalse);
  });
}
