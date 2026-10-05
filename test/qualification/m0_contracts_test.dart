import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/contracts.dart';

Map<String, dynamic> lock() {
  final record = <String, dynamic>{
    'schema_version': 1,
    'record_type': 'source_lock',
    'id': 'synthetic-lock',
    'collected_at': '2026-10-05T00:00:00Z',
    'local_locators': {'source_root': 'Z:/private/reference'},
    'reference': {
      'commit': 'a'.padLeft(40, 'a'),
      'dirty': true,
      'closure_status': [
        {'path': 'config.json', 'status': ' M'},
      ],
    },
    'submodules': <dynamic>[],
    'files': [
      {
        'path': 'config.json',
        'sha256': sha256Json({'scale': 1}),
        'size_bytes': 11,
        'role': 'config',
      },
    ],
    'effective_inputs': {
      for (final category in [
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
        category: [
          {
            'id': '$category-v1',
            'sha256': 'b'.padLeft(64, 'b'),
            'version': '1',
            'locator': '$category/input',
          },
        ],
    },
    'closure_complete': true,
    'closure_declaration':
        'All effective inputs for the declared recipe are listed.',
    'permission': {
      'use': 'private_reference',
      'status': 'cleared',
      'reviewer': 'synthetic-reviewer',
      'reviewed_at': '2026-10-05',
      'evidence_ids': ['synthetic-grant'],
      'scope_paths': ['config.json'],
    },
  };
  record['freeze_id'] = sourceFreezeId(record);
  return jsonDecode(jsonEncode(record)) as Map<String, dynamic>;
}

Map<String, dynamic> gate(String id, String status, {bool required = true}) => {
  'id': id,
  'required': required,
  'status': status,
  'owner': 'user',
  'evidence_ids': status == 'pass' ? ['evidence-1'] : <String>[],
  'reason': status == 'pass' ? 'Observed.' : 'Not established.',
};

Map<String, dynamic> oracle(String freezeId) => {
  'schema_version': 1,
  'record_type': 'oracle_results',
  'id': 'result-1',
  'provenance_ids': ['synthetic-author'],
  'freeze_id': freezeId,
  'run_id': 'run-1',
  'environment_id': 'env-1',
  'fixture_manifest_sha256': 'c'.padLeft(64, 'c'),
  'observations': [
    {
      'case_id': 'case-1',
      'input_sha256': 'd'.padLeft(64, 'd'),
      'profile': 'engine_inspection',
      'status': 'unverified',
      'result': null,
      'result_reason': 'Native reference was not executed.',
      'stage_timings': <dynamic>[],
      'errors': <dynamic>[],
      'comparison': null,
      'comparison_reason': 'No observed result.',
    },
  ],
};

void main() {
  test('oracle contract requires explicit observation provenance linkage', () {
    final value = oracle('a' * 64)..remove('provenance_ids');
    expect(() => validateRecord(value), throwsA(isA<ContractException>()));
    value['provenance_ids'] = <String>[];
    expect(() => validateRecord(value), throwsA(isA<ContractException>()));
    value['provenance_ids'] = ['synthetic-observations'];
    expect(() => validateRecord(value), returnsNormally);
  });

  test(
    'concrete environment rejects malformed supplied display measurements',
    () {
      final value = <String, dynamic>{
        'schema_version': 1,
        'record_type': 'environment',
        'id': 'setup',
        'setup_alias': 'synthetic',
        for (final key in [
          'hardware',
          'windows',
          'runtime',
          'app_build',
          'viewport',
          'observer',
        ]) ...{key: null, '${key}_reason': 'Not collected.'},
        'display': {'width': '1920', 'height': 1080, 'os_scale_percent': 100},
        'locale': null,
        'locale_reason': 'Not collected.',
        'display_mode': null,
        'display_mode_reason': 'Not collected.',
        'warm_state': null,
        'warm_state_reason': 'Not collected.',
      };
      expect(() => validateRecord(value), throwsA(isA<ContractException>()));
    },
  );

  test(
    'source integrity refuses linked root and declared junction child',
    () async {
      final temp = await Directory.systemTemp.createTemp('m0-source-link-');
      addTearDown(() => temp.delete(recursive: true));
      final real = await Directory('${temp.path}/real').create();
      final file = File('${real.path}/config.json');
      await file.writeAsString(canonicalJson({'scale': 1}));
      Future<void> junction(String path) async {
        if (Platform.isWindows) {
          final result = await Process.run(
            'powershell.exe',
            [
              '-NoProfile',
              '-Command',
              r'$ErrorActionPreference = "Stop"; New-Item -ItemType Junction -Path $env:M0_LINK_PATH -Target $env:M0_LINK_TARGET | Out-Null',
            ],
            environment: {'M0_LINK_PATH': path, 'M0_LINK_TARGET': real.path},
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
        } else {
          await Link(path).create(real.path);
        }
        addTearDown(() => Link(path).delete());
      }

      final linked = '${temp.path}/linked';
      await junction(linked);
      await expectLater(
        verifySourceIntegrity(lock(), linked),
        throwsA(isA<ContractException>()),
      );
      final child = '${real.path}/child';
      await junction(child);
      final value = lock();
      value['files'][0]['path'] = 'child/config.json';
      value['freeze_id'] = sourceFreezeId(value);
      await expectLater(
        verifySourceIntegrity(value, real.path),
        throwsA(isA<ContractException>()),
      );
      expect(await file.readAsString(), canonicalJson({'scale': 1}));
    },
  );
  group('effective input identity', () {
    test(
      'canonical JSON ignores map insertion order but preserves array order',
      () {
        expect(canonicalJson({'b': 2, 'a': 1}), '{"a":1,"b":2}');
        expect(sha256Json({'b': 2, 'a': 1}), sha256Json({'a': 1, 'b': 2}));
        expect(sha256Json([1, 2]), isNot(sha256Json([2, 1])));
        expect(
          sha256Json({'a': 1}),
          '015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862',
        );
      },
    );

    test('same HEAD with changed effective config changes freeze and rejects stale linkage', () {
      final before = lock();
      validateRecord(before);
      final after = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
      (after['files'] as List).first['sha256'] = sha256Json({'scale': 2});
      after['freeze_id'] = sourceFreezeId(after);
      expect(after['reference']['commit'], before['reference']['commit']);
      expect(after['freeze_id'], isNot(before['freeze_id']));
      expect(
        () => validateRecord(
          oracle(before['freeze_id'] as String),
          expectedFreezeId: after['freeze_id'] as String,
        ),
        throwsA(isA<ContractException>()),
      );
    });

    test('timestamps and private local roots do not alter portable freeze', () {
      final record = lock();
      final identity = record['freeze_id'];
      record['collected_at'] = '2027-01-01T00:00:00Z';
      record['local_locators'] = {'source_root': 'Q:/other/private'};
      expect(sourceFreezeId(record), identity);
      validateRecord(record);
    });

    test('each declared effective input participates in the freeze', () {
      for (final category in (lock()['effective_inputs'] as Map).keys) {
        final record = lock();
        final old = record['freeze_id'];
        record['effective_inputs'][category][0]['sha256'] = 'e'.padLeft(
          64,
          'e',
        );
        expect(
          sourceFreezeId(record),
          isNot(old),
          reason: '$category must be frozen',
        );
      }
    });

    test('missing source/model/catalog hashes and forged identity cannot be complete', () {
      for (final category in ['model', 'catalog']) {
        final record = lock();
        record['effective_inputs'][category][0].remove('sha256');
        record['freeze_id'] = sourceFreezeId(record);
        expect(() => validateRecord(record), throwsA(isA<ContractException>()));
      }
      final missingSource = lock();
      missingSource['files'][0].remove('sha256');
      missingSource['freeze_id'] = sourceFreezeId(missingSource);
      expect(
        () => validateRecord(missingSource),
        throwsA(isA<ContractException>()),
      );
      final forged = lock()..['freeze_id'] = '0'.padLeft(64, '0');
      expect(() => validateRecord(forged), throwsA(isA<ContractException>()));
    });

    test('copied bytes drift invalidates integrity without any reference invocation', () async {
      final directory = await Directory.systemTemp.createTemp('blackgrid-m0-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/config.json');
      await file.writeAsString(canonicalJson({'scale': 1}));
      final record = lock();
      await verifySourceIntegrity(record, directory.path);
      await file.writeAsString(canonicalJson({'scale': 2}));
      await expectLater(
        verifySourceIntegrity(record, directory.path),
        throwsA(isA<ContractException>()),
      );
    });

    test('unsafe or repeated closure paths cannot be used for integrity', () {
      for (final path in [
        '../secret',
        'C:/secret',
        '.git/config',
        'logs/session.txt',
        'settings/private.json',
      ]) {
        final record = lock();
        record['files'][0]['path'] = path;
        record['freeze_id'] = sourceFreezeId(record);
        expect(() => validateRecord(record), throwsA(isA<ContractException>()));
      }
      final repeated = lock();
      repeated['files'].add(
        Map<String, dynamic>.from(repeated['files'][0] as Map),
      );
      repeated['freeze_id'] = sourceFreezeId(repeated);
      expect(() => validateRecord(repeated), throwsA(isA<ContractException>()));
    });
  });

  group('evidence honesty', () {
    test('unknown versions are rejected rather than guessed', () {
      final record = oracle('a'.padLeft(64, 'a'))..['schema_version'] = 2;
      expect(() => validateRecord(record), throwsA(isA<ContractException>()));
    });

    test(
      'unavailable observations stay null with reasons, not measured zeros',
      () {
        final record = oracle('a'.padLeft(64, 'a'));
        validateRecord(record);
        record['observations'][0]['result'] = {'elapsed_ms': 0};
        expect(() => validateRecord(record), throwsA(isA<ContractException>()));
        record['observations'][0]['result'] = null;
        record['observations'][0].remove('result_reason');
        expect(() => validateRecord(record), throwsA(isA<ContractException>()));
      },
    );

    test('intake remains usable but cannot claim final reproducibility', () {
      final record = lock()
        ..['record_type'] = 'source_intake'
        ..['freeze_id'] = null
        ..['freeze_id_reason'] = 'Not permission-cleared or complete.'
        ..['closure_complete'] = false;
      record['effective_inputs']['model'] = null;
      record['effective_inputs']['model_reason'] = 'Missing model identity.';
      validateRecord(record);
      expect(() => sourceFreezeId(record), throwsA(isA<ContractException>()));
      record['record_type'] = 'source_lock';
      expect(() => validateRecord(record), throwsA(isA<ContractException>()));
    });

    test(
      'required missing and skipped gates preserve incomplete classification',
      () {
        expect(
          qualificationStatus([
            gate('offline', 'pass'),
            gate('live', 'unverified'),
          ]),
          'incomplete',
        );
        expect(
          qualificationStatus([
            gate('offline', 'fail'),
            gate('live', 'unverified'),
          ]),
          'not_qualified',
        );
        expect(
          qualificationStatus([
            gate('offline', 'pass'),
            gate('future-release', 'unverified', required: false),
          ]),
          'qualified',
        );
        expect(qualificationStatus([]), 'incomplete');
        expect(
          () => qualificationStatus([gate('live', 'not_applicable')]),
          throwsA(isA<ContractException>()),
        );
        expect(
          () => qualificationStatus([
            gate('offline', 'pass')..['evidence_ids'] = <String>[],
          ]),
          throwsA(isA<ContractException>()),
        );
      },
    );

    test('real expectation-only cases need ordered semantics, not invented screenshot bytes', () {
      final record = <String, dynamic>{
        'schema_version': 1,
        'record_type': 'fixture_manifest',
        'id': 'synthetic-sequences',
        'corpus_version': '1',
        'annotation_version': 'independent-1',
        'catalog_version': 'synthetic-1',
        'config_version': 'synthetic-1',
        'cases': [
          {
            'id': 'correction-history',
            'role': 'expectation_only',
            'source_id': 'independent-synthetic',
            'display_cell_id': '1080-100',
            'provenance_ids': ['synthetic-author'],
            'adjudication_ids': ['independent-review'],
            'truth': {'identity': 'corrected-item'},
            'initial_context': {'identity': 'wrong-item'},
            'ordered_inputs': [
              {'action': 'correct', 'identity': 'corrected-item'},
            ],
            'expected_effects': {
              'identity': 'corrected-item',
              'progress_changed': false,
            },
          },
        ],
      };
      validateRecord(record);
      record['cases'][0]['ordered_inputs'] = <dynamic>[];
      expect(() => validateRecord(record), throwsA(isA<ContractException>()));
    });

    test('planned display coverage cannot become a qualified report', () {
      final record = <String, dynamic>{
        'schema_version': 1,
        'record_type': 'qualification_report',
        'id': 'report-1',
        'status': 'incomplete',
        'inputs': [
          {'id': 'plan', 'version': '1', 'sha256': 'a'.padLeft(64, 'a')},
        ],
        'planned_checks_id': 'checks-1',
        'coverage': {'observed': 0, 'planned': 16},
        'denominators': {'attempted': 0, 'planned': 16},
        'timing': {'samples': 0},
        'strata': <dynamic>[],
        'divergences': <dynamic>[],
        'exports': <dynamic>[],
        'gates': [gate('display-coverage', 'unverified')],
        'display_matrix': {
          'cells': [
            for (final width in [1280, 1920, 2560, 3840])
              for (final scale in [100, 125, 150, 200])
                {
                  'id': '$width-$scale',
                  'width': width,
                  'height': width * 9 ~/ 16,
                  'os_scale_percent': scale,
                  'evidence_class': 'planned',
                  'case_ids': <String>[],
                  'evidence_ids': <String>[],
                  'limitations': 'Independent captures unavailable.',
                },
          ],
        },
      };
      validateRecord(record);
      record['status'] = 'qualified';
      record['gates'] = [gate('display-coverage', 'pass')];
      expect(() => validateRecord(record), throwsA(isA<ContractException>()));
    });

    test('unknown provenance cannot silently become cleared permission', () {
      final unresolved = <String, dynamic>{
        'status': 'unresolved',
        'scope': 'declared-use',
        'reason': 'Terms unreviewed.',
        'evidence_ids': <String>[],
        'reviewer': null,
        'reviewer_reason': 'No review.',
        'reviewed_at': null,
        'reviewed_at_reason': 'No review.',
      };
      final record = <String, dynamic>{
        'schema_version': 1,
        'record_type': 'provenance',
        'id': 'ledger',
        'artifacts': [
          {
            'id': 'private-reference',
            'kind': 'source',
            'purpose': 'characterization',
            'source': {'revision': 'declared'},
            'sha256': null,
            'sha256_reason': 'Effective closure incomplete.',
            'depends_on': <String>[],
            'derived_from': <String>[],
            'build_inputs': <String>[],
            'notices': <String>[],
            'modifications': <String>[],
            'declared_terms': {'text_locator': 'terms/reference-license'},
            'uses': {
              for (final use in [
                'private_reference',
                'repository_fixture',
                'report_export',
                'release',
              ])
                use: Map<String, dynamic>.from(unresolved),
            },
          },
        ],
      };
      validateRecord(record);
      record['artifacts'][0]['uses']['private_reference']['status'] = 'cleared';
      expect(() => validateRecord(record), throwsA(isA<ContractException>()));
    });

    test(
      'unattempted planned checks cannot fabricate a freeze or evidence',
      () {
        final record = <String, dynamic>{
          'schema_version': 1,
          'record_type': 'planned_checks',
          'id': 'plan-1',
          'checks': [
            {
              'id': 'live-1',
              'required': true,
              'applicable': true,
              'owner': 'user',
              'scope': 'live-baseline',
              'case_ids': <String>[],
              'stratum_id': 'native-1080-100',
              'allocation': 30,
              'attempted': false,
              'disposition': 'blocked',
              'reason': 'User measurements unavailable.',
              'evidence_ids': <String>[],
              'freeze_id': null,
              'freeze_id_reason': 'No permitted run.',
            },
          ],
        };
        validateRecord(record);
        record['checks'][0]['freeze_id'] = 'a'.padLeft(64, 'a');
        expect(() => validateRecord(record), throwsA(isA<ContractException>()));
      },
    );
  });
}
