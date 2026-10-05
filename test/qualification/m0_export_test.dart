import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/contracts.dart';
import '../../tool/qualification/export.dart';

const uses = [
  'private_reference',
  'repository_fixture',
  'report_export',
  'release',
];

Map<String, dynamic> artifact(
  String id, {
  List<String> dependencies = const [],
  List<String> parents = const [],
}) => {
  'id': id,
  'kind': 'synthetic_json',
  'purpose': 'Original developer test data, not personal data.',
  'source': {'id': 'synthetic-author'},
  'sha256': null,
  'sha256_reason': 'In-memory synthetic test data.',
  'declared_terms': {'expression': 'LicenseRef-Synthetic-Test'},
  'depends_on': dependencies,
  'derived_from': parents,
  'build_inputs': <String>[],
  'notices': <String>[],
  'modifications': <String>[],
  'uses': {
    for (final use in uses)
      use: {
        'status': 'cleared',
        'scope': 'This exact synthetic artifact for $use.',
        'reason': 'Original test authorship only; no real permission grant.',
        'evidence_ids': ['synthetic-authorship'],
        'reviewer': 'synthetic-author',
        'reviewed_at': '2026-10-05',
      },
  },
};

Map<String, dynamic> ledger(List<Map<String, dynamic>> rows) => {
  'schema_version': 1,
  'record_type': 'provenance',
  'id': 'synthetic-ledger',
  'artifacts': rows,
};

Map<String, dynamic> payload() => {
  'schema_version': 1,
  'record_type': 'fixture_manifest',
  'id': 'synthetic-corpus',
  'data_class': 'synthetic',
  'corpus_version': '1',
  'annotation_version': '1',
  'catalog_version': '1',
  'config_version': '1',
  'cases': [
    {
      'id': 'case-1',
      'source_id': 'original-json',
      'display_cell_id': 'semantic-only',
      'role': 'expectation_only',
      'provenance_ids': ['original-json'],
      'adjudication_ids': ['synthetic-author'],
      'truth': {'decision': 'Check'},
      'initial_context': {
        'progression': {'level': 1, 'completed_task_ids': <String>[]},
      },
      'ordered_inputs': [
        {'event': 'inspect', 'item_id': 'synthetic-item'},
      ],
      'expected_effects': {'decision': 'Check', 'progression_changed': false},
    },
  ],
};

void unresolved(Map<String, dynamic> row, String use) {
  row['uses'][use] = {
    'status': 'unresolved',
    'scope': 'This artifact for $use.',
    'reason': 'Missing reviewed evidence.',
    'evidence_ids': <String>[],
  };
}

void main() {
  test('private permission cannot authorize repository or report export', () {
    final row = artifact('original-json');
    unresolved(row, 'repository_fixture');
    unresolved(row, 'report_export');
    final provenance = ledger([row]);
    expect(
      inspectExport(
        payload(),
        ['original-json'],
        provenance,
        use: 'private_reference',
      ).allowed,
      isTrue,
    );
    for (final use in ['repository_fixture', 'report_export']) {
      final decision = inspectExport(
        payload(),
        ['original-json'],
        provenance,
        use: use,
      );
      expect(decision.allowed, isFalse);
      expect(decision.blockers.single, contains('original-json'));
      expect(decision.blockers.single, contains(use));
      expect(
        () =>
            sanitizedExport(payload(), ['original-json'], provenance, use: use),
        throwsA(isA<ContractException>()),
      );
      expect(row['uses'][use]['status'], 'unresolved');
    }
  });

  test(
    'derived artifacts need their own use decision even with a cleared parent',
    () {
      final child = artifact('original-json', parents: ['parent']);
      unresolved(child, 'release');
      final decision = inspectExport(
        payload(),
        ['original-json'],
        ledger([artifact('parent'), child]),
        use: 'release',
      );
      expect(decision.allowed, isFalse);
      expect(decision.blockers.single, contains('original-json'));
    },
  );

  test(
    'unresolved nested dependencies and missing build inputs block the use',
    () {
      final nested = artifact('tile');
      unresolved(nested, 'report_export');
      final parent = artifact('original-json', dependencies: ['svg']);
      final svg = artifact('svg', dependencies: ['tile']);
      final decision = inspectExport(payload(), [
        'original-json',
      ], ledger([parent, svg, nested]));
      expect(decision.allowed, isFalse);
      expect(decision.blockers.single, contains('tile'));
      parent['build_inputs'] = ['missing-build'];
      expect(
        inspectExport(payload(), [
          'original-json',
        ], ledger([parent, svg, nested])).blockers,
        contains(contains('missing-build')),
      );
    },
  );

  test('SDK slash separators remain exportable environment metadata', () {
    final provenance = ledger([artifact('original-json')]);
    for (final sdk in [
      'Flutter 3.47.6 / Dart >=3.13.5 <4.0.0',
      'Flutter SDK / Dart SDK',
    ]) {
      final record = <String, dynamic>{
        'schema_version': 1,
        'record_type': 'environment',
        'id': 'synthetic-environment',
        'setup_alias': 'synthetic-only',
        'hardware': <String, dynamic>{},
        'windows': <String, dynamic>{},
        'runtime': {'sdk': sdk},
        'app_build': <String, dynamic>{},
        'viewport': <String, dynamic>{},
        'display': <String, dynamic>{},
        'observer': <String, dynamic>{},
        'locale': 'en',
        'display_mode': 'synthetic',
        'warm_state': 'unmeasured',
      };
      expect(
        sanitizedExport(record, ['original-json'], provenance),
        same(record),
        reason: sdk,
      );
      expect(record['runtime']['sdk'], sdk);
    }
  });

  test('space-delimited arithmetic remains exportable without redaction', () {
    final provenance = ledger([artifact('original-json')]);
    for (final formula in [
      '(pin_x - map_left) / map_width',
      '(pin_y - map_top) / map_height',
      'scale = client_width / logical_width',
      'separator /',
      'quoted separator "/"',
    ]) {
      final record = payload();
      record['cases'][0]['truth'] = {'method': formula};
      expect(
        sanitizedExport(record, ['original-json'], provenance),
        same(record),
        reason: formula,
      );
      expect(record['cases'][0]['truth']['method'], formula);
    }
  });

  test(
    'rooted and embedded absolute paths remain refused in ordinary text',
    () {
      final provenance = ledger([artifact('original-json')]);
      for (final text in [
        '/',
        '/ private',
        '/home/example/private.json',
        'source /home/example/private.json',
        'source "/home/example/private.json"',
        "source '/home/example/private.json'",
        'source C:/Users/example/private.json',
        r'source C:\Users\example\private.json',
        r'source \\server\share\private.json',
        'source file:///home/example/private.json',
        'source=C:/Users/example/private.json',
        'source=/home/example/private.json',
        r'source=\\server\share\private.json',
        'source=file:///home/example/private.json',
        '(C:/Users/example/private.json)',
        '(/home/example/private.json)',
        r'(\\server\share\private.json)',
        '(file:///home/example/private.json)',
      ]) {
        final record = payload();
        record['cases'][0]['truth'] = {'method': text};
        final decision = inspectExport(record, ['original-json'], provenance);
        expect(decision.allowed, isFalse, reason: text);
        expect(
          decision.blockers,
          contains(contains('absolute/private locator')),
          reason: text,
        );
        expect(
          () => sanitizedExport(record, ['original-json'], provenance),
          throwsA(isA<ContractException>()),
        );
        expect(record['cases'][0]['truth']['method'], text);
      }
    },
  );

  test('rooted slash dictionary keys remain refused', () {
    final provenance = ledger([artifact('original-json')]);
    for (final key in ['/', '/ private']) {
      final record = payload();
      record['cases'][0]['truth'] = {
        'missing_stage_reasons': {key: 'Unavailable.'},
      };
      expect(
        inspectExport(record, ['original-json'], provenance).blockers,
        contains(contains('is not allowlisted')),
        reason: key,
      );
      expect(
        () => sanitizedExport(record, ['original-json'], provenance),
        throwsA(isA<ContractException>()),
      );
    }
  });

  test(
    'fixture root authoring source is allowed without opening extension bags',
    () {
      final provenance = ledger([artifact('original-json')]);
      final record = payload()..['authoring_source_id'] = 'original-json';
      expect(
        sanitizedExport(record, ['original-json'], provenance),
        same(record),
      );
      expect(record['authoring_source_id'], 'original-json');
      record['extensions'] = {'authoring_source_id': 'original-json'};
      expect(
        inspectExport(record, ['original-json'], provenance).blockers,
        contains(contains('payload.extensions is not allowlisted')),
      );
      expect(
        () => sanitizedExport(record, ['original-json'], provenance),
        throwsA(isA<ContractException>()),
      );
    },
  );

  test('nested secrets, identities, private locators and attachments are refused, never redacted', () {
    final provenance = ledger([artifact('original-json')]);
    for (final forbidden in [
      {'token': 'synthetic-not-a-secret'},
      {'account_id': 'synthetic-not-an-account'},
      {'accessToken': 'synthetic-not-a-secret'},
      {'chat': 'synthetic-not-a-message'},
      {
        'local_locators': {'source_root': 'private'},
      },
      {'path': 'C:/Users/example/private.json'},
      {'path': '/'},
      {'path': '/ private'},
      {'path': '/home/example/private.json'},
      {'path': '../private.json'},
      {'locator': 'https://example.invalid/evidence?token=synthetic'},
      {
        'attachments': [
          {'path': 'recording.mp4'},
        ],
      },
      {'path': 'private/oracle.dll'},
      {
        'source': {'path': 'private/oracle.dll'},
      },
      {
        'unexpected_extension': {'token': 'synthetic'},
      },
    ]) {
      final record = payload();
      record['cases'][0]['truth'] = forbidden;
      expect(
        inspectExport(record, ['original-json'], provenance).allowed,
        isFalse,
        reason: '$forbidden',
      );
      expect(
        () => sanitizedExport(record, ['original-json'], provenance),
        throwsA(isA<ContractException>()),
      );
      expect(record['cases'][0]['truth'], forbidden);
    }
  });

  test('original synthetic semantic progression is exportable, real progression is not', () {
    final provenance = ledger([artifact('original-json')]);
    final record = payload();
    expect(
      sanitizedExport(record, ['original-json'], provenance),
      same(record),
    );
    record.remove('data_class');
    expect(
      inspectExport(record, ['original-json'], provenance).allowed,
      isFalse,
    );
  });

  test('nested synthetic acquisition markers cannot authorize personal progression', () {
    final provenance = ledger([artifact('original-json')]);
    final record = payload()..remove('data_class');
    record['cases'][0]['initial_context'] = {
      'acquisition': 'synthetic',
      'progression': {'level': 1},
    };
    record['cases'][0]['expected_effects'] = {'decision': 'Check'};
    validateRecord(record);
    expect(
      inspectExport(record, ['original-json'], provenance).allowed,
      isFalse,
    );
    expect(
      () => sanitizedExport(record, ['original-json'], provenance),
      throwsA(isA<ContractException>()),
    );
  });

  test('synthetic state dictionaries retain semantic keys but cannot hide credentials', () {
    final provenance = ledger([artifact('original-json')]);
    final record = payload();
    record['cases'][0]['initial_context'] = {
      'state': {
        'synthetic_item_qty': 2,
        'progression': {'level': 1},
      },
    };
    expect(
      sanitizedExport(record, ['original-json'], provenance),
      same(record),
    );
    record['cases'][0]['initial_context']['state']['extensions'] = {
      'account': {'accessToken': 'synthetic-not-a-secret'},
    };
    expect(
      inspectExport(record, ['original-json'], provenance).allowed,
      isFalse,
    );
    expect(
      () => sanitizedExport(record, ['original-json'], provenance),
      throwsA(isA<ContractException>()),
    );
  });

  test(
    'hyphenated sensitive keys cannot hide in synthetic state dictionaries',
    () {
      final provenance = ledger([artifact('original-json')]);
      for (final key in [
        'access-token',
        'account-id',
        'api-key',
        'access-tokens',
        'accounts',
      ]) {
        final record = payload();
        record['cases'][0]['initial_context'] = {
          'state': {key: 'synthetic'},
        };
        validateRecord(record);
        expect(
          inspectExport(record, ['original-json'], provenance).allowed,
          isFalse,
        );
        expect(
          () => sanitizedExport(record, ['original-json'], provenance),
          throwsA(isA<ContractException>()),
        );
      }
    },
  );

  test('path and locator arrays cannot bypass portable-path and attachment refusal', () {
    final provenance = ledger([artifact('original-json')]);
    for (final key in ['path', 'locator']) {
      final record = payload();
      record['cases'][0]['truth'] = {
        key: ['../private/oracle.dll'],
      };
      validateRecord(record);
      expect(
        inspectExport(record, ['original-json'], provenance).allowed,
        isFalse,
      );
      expect(
        () => sanitizedExport(record, ['original-json'], provenance),
        throwsA(isA<ContractException>()),
      );
    }
  });

  test('payload linkage cannot evade clearance by omitting an artifact from arguments', () {
    final record = payload();
    record['cases'][0]['provenance_ids'] = ['uncleared'];
    final blocked = artifact('uncleared');
    unresolved(blocked, 'report_export');
    expect(
      inspectExport(record, [
        'original-json',
      ], ledger([artifact('original-json'), blocked])).blockers,
      contains(contains('uncleared')),
    );
  });

  test(
    'schema-unsafe records and unknown extensions fail despite cleared rights',
    () {
      final provenance = ledger([artifact('original-json')]);
      final record = payload()..['schema_version'] = 2;
      expect(
        inspectExport(record, ['original-json'], provenance).allowed,
        isFalse,
      );
      final extension = payload()..['extensions'] = {'harmless': true};
      expect(
        inspectExport(extension, ['original-json'], provenance).allowed,
        isFalse,
      );
    },
  );
}
