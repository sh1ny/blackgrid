import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class ContractException implements Exception {
  const ContractException(this.message);
  final String message;
  @override
  String toString() => 'ContractException: $message';
}

Never _invalid(String message) => throw ContractException(message);

String canonicalJson(Object? value) {
  Object? ordered(Object? input) {
    if (input is Map) {
      if (input.keys.any((key) => key is! String)) {
        _invalid('JSON object keys must be strings');
      }
      final keys = input.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: ordered(input[key])};
    }
    if (input is List) return input.map(ordered).toList();
    if (input == null || input is String || input is bool || input is int) {
      return input;
    }
    if (input is double && input.isFinite) return input;
    _invalid('Only finite JSON values are supported');
  }

  return jsonEncode(ordered(value));
}

String sha256Json(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

String sourceFreezeId(Map<String, dynamic> lock) {
  if (lock['record_type'] != 'source_lock') {
    _invalid('Only a final source_lock has a freeze identity');
  }
  final payload = Map<String, dynamic>.from(lock)
    ..remove('freeze_id')
    ..remove('collected_at')
    ..remove('local_locators');
  return sha256Json(payload);
}

Map<String, dynamic> _map(Object? value, String where) {
  if (value is! Map<String, dynamic>) _invalid('$where must be an object');
  return value;
}

List<dynamic> _list(Object? value, String where, {bool nonempty = false}) {
  if (value is! List || (nonempty && value.isEmpty)) {
    _invalid('$where must be ${nonempty ? 'a nonempty' : 'an'} array');
  }
  return value;
}

String _text(Object? value, String where) {
  if (value is! String || value.trim().isEmpty)
    _invalid('$where must be nonempty text');
  return value;
}

void _boolean(Object? value, String where) {
  if (value is! bool) _invalid('$where must be a boolean');
}

void _hash(Object? value, String where) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    _invalid('$where must be a lowercase SHA-256');
  }
}

void _choice(Object? value, List<String> choices, String where) {
  if (!choices.contains(value))
    _invalid('$where must be one of ${choices.join(', ')}');
}

void _number(
  Object? value,
  String where, {
  bool integer = false,
  num minimum = 0,
}) {
  if (value is! num ||
      !value.isFinite ||
      value < minimum ||
      (integer && value is! int)) {
    _invalid(
      '$where must be a finite ${integer ? 'integer' : 'number'} >= $minimum',
    );
  }
}

void _texts(Object? value, String where, {bool nonempty = false}) {
  for (final item in _list(value, where, nonempty: nonempty)) {
    _text(item, where);
  }
}

void _nullReasons(Object? value, String where) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key as String;
      if (entry.value == null)
        _text(value['${key}_reason'], '$where.$key reason');
      if (key.endsWith('_reason')) {
        final field = key.substring(0, key.length - 7);
        if (!value.containsKey(field) || value[field] != null) {
          _invalid('$where.$key is only allowed beside a null $field');
        }
      }
      _nullReasons(entry.value, '$where.$key');
    }
  } else if (value is List) {
    for (final item in value) {
      if (item == null)
        _invalid(
          '$where: unavailable array entries require an object with a null field and reason',
        );
      _nullReasons(item, where);
    }
  }
}

void _portablePath(Object? value, String where) {
  final path = _text(value, where);
  final segments = path.split('/');
  if (path.contains('\\') ||
      path.contains(':') ||
      path.startsWith('/') ||
      segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
    _invalid('$where must be a portable relative path');
  }
}

void _sourcePath(Object? value, String where) {
  _portablePath(value, where);
  final path = value as String;
  const excluded = {
    '.git',
    'build',
    'bin',
    'obj',
    '.dart_tool',
    '.pub-cache',
    '.qualification',
    'node_modules',
    'cache',
    'caches',
    'logs',
    'log',
    'settings',
    'credentials',
    'secrets',
    'appdata',
    '.vs',
    '.idea',
  };
  if (path.split('/').any((part) => excluded.contains(part.toLowerCase())) ||
      RegExp(
        r'(^|/)(\.env(\..*)?|.*\.(log|pfx|p12|key)|credentials\..*|secrets\..*|user\.config|.*\.csproj\.user)$',
        caseSensitive: false,
      ).hasMatch(path)) {
    _invalid('$where is an excluded private/build/cache path');
  }
}

void _ids(List<dynamic> rows, String where) {
  final seen = <String>{};
  for (final row in rows) {
    final id = _text(_map(row, where)['id'], '$where.id');
    if (!seen.add(id)) _invalid('$where has duplicate id $id');
  }
}

void _reference(
  Map<String, dynamic> row,
  String where, {
  required bool complete,
}) {
  for (final key in ['commit', 'dirty', 'closure_status']) {
    if (!row.containsKey(key)) _invalid('$where must explicitly declare $key');
  }
  if (row['commit'] == null && !complete) {
    // Null reason is checked centrally; an unborn or non-Git source is intake only.
  } else if (row['commit'] is! String ||
      !RegExp(r'^[a-f0-9]{40,64}$').hasMatch(row['commit'] as String)) {
    _invalid('$where.commit must be an immutable Git commit');
  }
  if (row['dirty'] != null || complete) _boolean(row['dirty'], '$where.dirty');
  for (final status in _list(row['closure_status'], '$where.closure_status')) {
    final item = _map(status, where);
    _sourcePath(item['path'], '$where.path');
    _text(item['status'], '$where.status');
  }
}

const _inputCategories = [
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
];

void _source(Map<String, dynamic> record, {required bool complete}) {
  _reference(
    _map(record['reference'], 'reference'),
    'reference',
    complete: complete,
  );
  for (final submodule in _list(record['submodules'], 'submodules')) {
    final row = _map(submodule, 'submodule');
    _sourcePath(row['path'], 'submodule.path');
    _reference(row, 'submodule', complete: complete);
  }
  final files = _list(record['files'], 'files', nonempty: complete);
  final paths = <String>{};
  String? previous;
  for (final file in files) {
    final row = _map(file, 'file');
    _sourcePath(row['path'], 'file.path');
    final path = row['path'] as String;
    if (!paths.add(path.toLowerCase()))
      _invalid('Duplicate/case-aliased closure path $path');
    if (previous != null && previous.compareTo(path) >= 0)
      _invalid('File closure must be sorted by ordinal path');
    previous = path;
    _hash(row['sha256'], 'file.sha256');
    _number(row['size_bytes'], 'file.size_bytes', integer: true);
    _text(row['role'], 'file.role');
  }
  _boolean(record['closure_complete'], 'closure_complete');
  if (complete && record['closure_complete'] != true)
    _invalid('Final lock requires a declared complete closure');
  _text(record['closure_declaration'], 'closure_declaration');
  final effective = _map(record['effective_inputs'], 'effective_inputs');
  for (final category in _inputCategories) {
    if (effective[category] == null && !complete) {
      _text(
        effective['${category}_reason'],
        'effective_inputs.$category reason',
      );
      continue;
    }
    final inputs = _list(
      effective[category],
      'effective_inputs.$category',
      nonempty: true,
    );
    _ids(inputs, category);
    for (final input in inputs) {
      final row = _map(input, category);
      _hash(row['sha256'], '$category.sha256');
      _text(row['version'], '$category.version');
      _portablePath(row['locator'], '$category.locator');
      if (row.containsKey('path')) {
        _sourcePath(row['path'], '$category.path');
        final matches = files
            .where((file) => (file as Map)['path'] == row['path'])
            .toList();
        if (matches.length != 1 ||
            (matches.single as Map)['sha256'] != row['sha256']) {
          _invalid('$category input does not bind its closure file hash');
        }
      }
    }
  }
  if (complete) {
    _permission(
      _map(record['permission'], 'permission'),
      files.map((file) => (file as Map)['path'] as String).toSet(),
    );
    _hash(record['freeze_id'], 'freeze_id');
    if (record['freeze_id'] != sourceFreezeId(record))
      _invalid('freeze_id does not match effective inputs');
  } else {
    if (!record.containsKey('freeze_id') || record['freeze_id'] != null) {
      _invalid(
        'Metadata-only source_intake must explicitly declare freeze_id:null',
      );
    }
    _text(record['freeze_id_reason'], 'freeze_id_reason');
  }
}

void _permission(Map<String, dynamic> row, Set<String> paths) {
  if (row['use'] != 'private_reference' || row['status'] != 'cleared') {
    _invalid(
      'A final lock/materialization requires reviewed private_reference permission',
    );
  }
  _text(row['reviewer'], 'permission.reviewer');
  _text(row['reviewed_at'], 'permission.reviewed_at');
  _texts(row['evidence_ids'], 'permission.evidence_ids', nonempty: true);
  final scope = _list(row['scope_paths'], 'permission.scope_paths');
  for (final path in scope) _sourcePath(path, 'permission.scope_paths');
  if (!scope.cast<String>().toSet().containsAll(paths))
    _invalid('Permission scope must cover every closure file');
}

String qualificationStatus(List<Map<String, dynamic>> gates) {
  _ids(gates, 'gates');
  var requiredCount = 0;
  var missing = false;
  var failed = false;
  for (final gate in gates) {
    _boolean(gate['required'], 'gate.required');
    _choice(gate['status'], [
      'pass',
      'fail',
      'unverified',
      'not_applicable',
    ], 'gate.status');
    _text(gate['owner'], 'gate.owner');
    _text(gate['reason'], 'gate.reason');
    _texts(
      gate['evidence_ids'],
      'gate.evidence_ids',
      nonempty: gate['status'] == 'pass',
    );
    if (gate['required'] == true) {
      requiredCount++;
      if (gate['status'] == 'not_applicable')
        _invalid('Required gates cannot be not_applicable');
      failed |= gate['status'] == 'fail';
      missing |= gate['status'] != 'pass';
    }
  }
  if (failed) return 'not_qualified';
  if (missing || requiredCount == 0) return 'incomplete';
  return 'qualified';
}

void _planned(Map<String, dynamic> record) {
  final checks = _list(record['checks'], 'checks');
  _ids(checks, 'checks');
  for (final check in checks) {
    final row = _map(check, 'check');
    for (final key in ['required', 'applicable', 'attempted'])
      _boolean(row[key], 'check.$key');
    for (final key in ['owner', 'scope', 'stratum_id', 'reason'])
      _text(row[key], 'check.$key');
    _texts(row['case_ids'], 'check.case_ids');
    _texts(row['evidence_ids'], 'check.evidence_ids');
    _number(row['allocation'], 'check.allocation', integer: true);
    _choice(row['disposition'], [
      'planned',
      'observed',
      'blocked',
      'missing',
      'skipped',
      'excluded',
    ], 'check.disposition');
    if (!row.containsKey('freeze_id'))
      _invalid(
        'Planned checks must explicitly declare freeze_id or null with reason',
      );
    if (row['required'] == true && row['applicable'] == false)
      _invalid('Required scope cannot be made inapplicable');
    if (row['attempted'] == false &&
        (row['freeze_id'] != null ||
            (row['evidence_ids'] as List).isNotEmpty ||
            row['disposition'] == 'observed')) {
      _invalid('Unattempted checks cannot fabricate a freeze or observation');
    }
    if (row['attempted'] == true &&
        row['disposition'] == 'observed' &&
        (row['evidence_ids'] as List).isEmpty)
      _invalid('Observed check requires evidence');
    if (row['freeze_id'] != null) _hash(row['freeze_id'], 'check.freeze_id');
    if (row['disposition'] == 'skipped')
      _text(row['skip_decision_id'], 'check.skip_decision_id');
  }
}

const _profiles = [
  'engine_inspection',
  'engine_multi',
  'host_resolution',
  'map_geometry',
  'exfil_panel',
];

void _oracle(Map<String, dynamic> record) {
  for (final key in ['freeze_id', 'fixture_manifest_sha256'])
    _hash(record[key], key);
  for (final key in ['run_id', 'environment_id']) _text(record[key], key);
  final seen = <String>{};
  for (final observation in _list(
    record['observations'],
    'observations',
    nonempty: true,
  )) {
    final row = _map(observation, 'observation');
    _text(row['case_id'], 'observation.case_id');
    _hash(row['input_sha256'], 'observation.input_sha256');
    _choice(row['profile'], _profiles, 'observation.profile');
    if (!seen.add('${row['case_id']}/${row['profile']}'))
      _invalid('Duplicate observation case/profile');
    _choice(row['status'], [
      'observed',
      'unverified',
      'error',
    ], 'observation.status');
    _list(row['stage_timings'], 'observation.stage_timings');
    _list(row['errors'], 'observation.errors');
    if (row['status'] == 'unverified') {
      if (row['result'] != null || row['comparison'] != null)
        _invalid('Unverified observation cannot supply measured results');
      _text(row['result_reason'], 'observation.result_reason');
      _text(row['comparison_reason'], 'observation.comparison_reason');
    } else if (row['status'] == 'observed') {
      final result = _map(row['result'], 'observation.result');
      final fields = switch (row['profile']) {
        'engine_inspection' => [
          'marker',
          'title_roi',
          'ocr_text',
          'candidates',
          'outcome',
        ],
        'engine_multi' => ['detections', 'unmatched', 'duplicates'],
        'host_resolution' => [
          'selected_evidence_ids',
          'outcome',
          'decision',
          'reasons',
          'facts',
          'snapshot_ids',
          'target_policy_id',
        ],
        'map_geometry' => [
          'frame_revision',
          'artwork_pixel',
          'normalized',
          'game_xyz',
          'floor_group_id',
          'heading',
        ],
        'exfil_panel' => [
          'disposition',
          'extract_text',
          'transit_text',
          'matched_ids',
          'ocr_spans',
        ],
        _ => <String>[],
      };
      for (final field in fields) {
        if (!result.containsKey(field))
          _invalid(
            'Observed ${row['profile']} requires $field (null with reason if unavailable)',
          );
      }
      _map(row['comparison'], 'observation.comparison');
    } else if ((row['errors'] as List).isEmpty) {
      _invalid('Error observation requires recorded errors');
    }
  }
}

void _provenance(Map<String, dynamic> record) {
  final artifacts = _list(record['artifacts'], 'artifacts');
  _ids(artifacts, 'artifacts');
  for (final artifact in artifacts) {
    final row = _map(artifact, 'artifact');
    for (final key in ['kind', 'purpose']) _text(row[key], 'artifact.$key');
    _map(row['source'], 'artifact.source');
    if (!row.containsKey('sha256'))
      _invalid('Artifact must explicitly declare sha256 or null with reason');
    if (row['sha256'] != null) _hash(row['sha256'], 'artifact.sha256');
    for (final key in [
      'depends_on',
      'derived_from',
      'build_inputs',
      'notices',
      'modifications',
    ])
      _texts(row[key], 'artifact.$key');
    _map(row['declared_terms'], 'artifact.declared_terms');
    final uses = _map(row['uses'], 'artifact.uses');
    for (final use in [
      'private_reference',
      'repository_fixture',
      'report_export',
      'release',
    ]) {
      final disposition = _map(uses[use], 'artifact.uses.$use');
      _choice(disposition['status'], [
        'cleared',
        'unresolved',
        'excluded',
      ], '$use.status');
      for (final key in ['scope', 'reason'])
        _text(disposition[key], '$use.$key');
      _texts(
        disposition['evidence_ids'],
        '$use.evidence_ids',
        nonempty: disposition['status'] == 'cleared',
      );
      if (disposition['status'] == 'cleared') {
        _text(disposition['reviewer'], '$use.reviewer');
        _text(disposition['reviewed_at'], '$use.reviewed_at');
      }
    }
  }
}

void _fixtures(Map<String, dynamic> record) {
  for (final key in [
    'corpus_version',
    'annotation_version',
    'catalog_version',
    'config_version',
  ])
    _text(record[key], key);
  final cases = _list(record['cases'], 'cases');
  _ids(cases, 'cases');
  for (final value in cases) {
    final row = _map(value, 'case');
    _choice(row['role'], [
      'reference_characterization',
      'expectation_only',
      'both',
    ], 'case.role');
    for (final key in ['source_id', 'display_cell_id'])
      _text(row[key], 'case.$key');
    _texts(row['provenance_ids'], 'case.provenance_ids', nonempty: true);
    _texts(row['adjudication_ids'], 'case.adjudication_ids', nonempty: true);
    _map(row['truth'], 'case.truth');
    if (row['role'] == 'expectation_only') {
      _map(row['initial_context'], 'case.initial_context');
      _list(row['ordered_inputs'], 'case.ordered_inputs', nonempty: true);
      _map(row['expected_effects'], 'case.expected_effects');
    } else {
      _choice(row['profile'], _profiles, 'case.profile');
      _text(row['seam'], 'case.seam');
      final input = _map(row['input'], 'case.input');
      _portablePath(input['path'], 'case.input.path');
      _hash(input['sha256'], 'case.input.sha256');
      for (final key in ['width', 'height'])
        _number(input[key], 'case.input.$key', integer: true, minimum: 1);
      _choice(row['acquisition'], [
        'actual',
        'derived',
        'synthetic',
      ], 'case.acquisition');
      if (row['acquisition'] == 'derived') {
        _text(row['parent_id'], 'case.parent_id');
        _map(row['transform'], 'case.transform');
      }
    }
  }
}

void _point(Object? value, String where) {
  final point = _map(value, where);
  for (final key in ['x', 'y']) {
    if (point[key] is! num || !(point[key] as num).isFinite) {
      _invalid('$where.$key must be finite');
    }
  }
}

void _maps(Map<String, dynamic> record) {
  final controls = _list(record['controls'], 'controls');
  _ids(controls, 'controls');
  for (final value in controls) {
    final row = _map(value, 'control');
    for (final key in [
      'map_id',
      'source_key',
      'frame_revision',
      'floor_group_id',
      'heading_convention',
    ])
      _text(row[key], 'control.$key');
    for (final key in ['artwork_sha256', 'config_sha256'])
      _hash(row[key], 'control.$key');
    final xyz = _map(row['game_xyz'], 'control.game_xyz');
    for (final key in ['x', 'z']) {
      if (xyz[key] is! num || !(xyz[key] as num).isFinite)
        _invalid('game_xyz.$key must be finite');
    }
    if (!xyz.containsKey('y'))
      _invalid('game_xyz must explicitly state y or y:null with reason');
    if (xyz['y'] != null && (xyz['y'] is! num || !(xyz['y'] as num).isFinite))
      _invalid('game_xyz.y must be finite or unavailable');
    for (final key in ['artwork_pixel', 'normalized'])
      _point(row[key], 'control.$key');
    _number(row['tolerance'], 'control.tolerance');
    _number(row['uncertainty'], 'control.uncertainty');
    _texts(row['source_ids'], 'control.source_ids', nonempty: true);
    _texts(row['review_ids'], 'control.review_ids', nonempty: true);
  }
}

void _display(Map<String, dynamic> record) {
  final cells = _list(record['cells'], 'cells');
  _ids(cells, 'cells');
  final combinations = <String>{};
  for (final value in cells) {
    final row = _map(value, 'cell');
    for (final key in ['width', 'height', 'os_scale_percent'])
      _number(row[key], 'cell.$key', integer: true, minimum: 1);
    if (!combinations.add(
      '${row['width']}x${row['height']}@${row['os_scale_percent']}',
    ))
      _invalid('Duplicate display combination');
    _choice(row['evidence_class'], [
      'planned',
      'synthetic',
      'derived',
      'offline',
      'live_user',
    ], 'cell.evidence_class');
    _texts(row['case_ids'], 'cell.case_ids');
    _texts(
      row['evidence_ids'],
      'cell.evidence_ids',
      nonempty:
          row['evidence_class'] == 'live_user' ||
          row['evidence_class'] == 'offline',
    );
    if (row['evidence_class'] == 'planned' &&
        (row['evidence_ids'] as List).isNotEmpty)
      _invalid('Planned display cells cannot claim observations');
    _text(row['limitations'], 'cell.limitations');
  }
}

void _attempts(Map<String, dynamic> record) {
  for (final key in ['run_id', 'environment_id']) _text(record[key], key);
  _hash(record['freeze_id'], 'freeze_id');
  final attempts = _list(record['attempts'], 'attempts');
  _ids(attempts, 'attempts');
  for (final value in attempts) {
    final row = _map(value, 'attempt');
    for (final key in [
      'request_id',
      'generation',
      'intended_path',
      'actual_path',
      'terminal_outcome',
      'executor',
      'evidence_mode',
      'trigger_kind',
      'clock_domain',
    ])
      _text(row[key], 'attempt.$key');
    _number(row['ordinal'], 'attempt.ordinal', integer: true, minimum: 1);
    _list(row['stages'], 'attempt.stages');
    _map(row['missing_stage_reasons'], 'attempt.missing_stage_reasons');
    if (!row.containsKey('qpc_frequency'))
      _invalid(
        'Attempt must explicitly declare qpc_frequency or null with reason',
      );
    if (row['qpc_frequency'] != null)
      _number(
        row['qpc_frequency'],
        'attempt.qpc_frequency',
        integer: true,
        minimum: 1,
      );
    for (final stage in row['stages'] as List) {
      final ticks = _map(stage, 'stage');
      _text(ticks['name'], 'stage.name');
      for (final key in ['start_tick', 'end_tick'])
        _number(ticks[key], 'stage.$key', integer: true);
      if ((ticks['end_tick'] as int) < (ticks['start_tick'] as int))
        _invalid('Stage ticks run backwards');
      if (row['qpc_frequency'] == null)
        _invalid('Tick stages require frequency');
    }
    if (!row.containsKey('endpoint') ||
        !row.containsKey('trigger') ||
        !row.containsKey('observer') ||
        !row.containsKey('external_data_age_ms'))
      _invalid(
        'Attempts must explicitly state endpoint/trigger/observer/external-data availability',
      );
  }
}

void _environment(Map<String, dynamic> record) {
  _text(record['setup_alias'], 'setup_alias');
  for (final key in [
    'hardware',
    'windows',
    'runtime',
    'app_build',
    'viewport',
    'display',
    'observer',
  ]) {
    if (!record.containsKey(key))
      _invalid('environment requires $key or null with reason');
    if (record[key] != null) _map(record[key], key);
  }
  for (final key in ['locale', 'display_mode', 'warm_state']) {
    if (!record.containsKey(key))
      _invalid('environment requires $key or null with reason');
    if (record[key] != null) _text(record[key], key);
  }
}

void _report(Map<String, dynamic> record) {
  final gates = _list(
    record['gates'],
    'gates',
  ).map((value) => _map(value, 'gate')).toList();
  if (record['status'] != qualificationStatus(gates))
    _invalid('Report status must equal its required-gate classification');
  final manifests = _list(record['inputs'], 'inputs', nonempty: true);
  for (final input in manifests) {
    final row = _map(input, 'report.input');
    for (final key in ['id', 'version']) _text(row[key], 'report.input.$key');
    _hash(row['sha256'], 'report.input.sha256');
  }
  _text(record['planned_checks_id'], 'planned_checks_id');
  for (final key in ['coverage', 'denominators', 'timing'])
    _map(record[key], key);
  _list(record['strata'], 'strata');
  _list(record['divergences'], 'divergences');
  final display = _map(record['display_matrix'], 'display_matrix');
  _display(display);
  if ((display['cells'] as List).length != 16)
    _invalid('Qualification reports must retain all 16 display cells');
  if (record['status'] == 'qualified' &&
      (display['cells'] as List).any(
        (value) => (value as Map)['evidence_class'] == 'planned',
      )) {
    _invalid('Planned display coverage cannot qualify M0');
  }
  for (final export in _list(record['exports'], 'exports')) {
    final row = _map(export, 'export');
    _portablePath(row['path'], 'export.path');
    _hash(row['sha256'], 'export.sha256');
    _texts(row['provenance_ids'], 'export.provenance_ids', nonempty: true);
  }
}

void validateRecord(Map<String, dynamic> record, {String? expectedFreezeId}) {
  if (record['schema_version'] != 1)
    _invalid('Unsupported schema_version; expected 1');
  _text(record['id'], 'id');
  canonicalJson(record);
  _nullReasons(record, 'record');
  if (expectedFreezeId != null) {
    _hash(expectedFreezeId, 'expectedFreezeId');
    if (record['freeze_id'] != expectedFreezeId)
      _invalid('Record is bound to a different or unavailable freeze');
  }
  switch (record['record_type']) {
    case 'source_intake':
      _source(record, complete: false);
    case 'source_lock':
      _source(record, complete: true);
    case 'environment':
      _environment(record);
    case 'provenance':
      _provenance(record);
    case 'fixture_manifest':
      _fixtures(record);
    case 'map_controls':
      _maps(record);
    case 'display_matrix':
      _display(record);
    case 'oracle_results':
      _oracle(record);
    case 'attempt_bundle':
      _attempts(record);
    case 'planned_checks':
      _planned(record);
    case 'qualification_report':
      _report(record);
    default:
      _invalid('Unsupported record_type ${record['record_type']}');
  }
}

/// Checks exactly the declared closure, never discovering files or invoking a reference.
Future<void> verifySourceIntegrity(
  Map<String, dynamic> record,
  String sourceRoot,
) async {
  validateRecord(record);
  if (record['record_type'] != 'source_lock' &&
      record['record_type'] != 'source_intake')
    _invalid('Integrity verification requires a source record');
  final root = Directory(sourceRoot).absolute;
  var ancestor = root;
  while (true) {
    final kind = await FileSystemEntity.type(ancestor.path, followLinks: false);
    if (kind != FileSystemEntityType.directory)
      _invalid('Source root ancestry must contain real directories, not links');
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) break;
    ancestor = parent;
  }
  for (final entry in record['files'] as List) {
    final row = entry as Map<String, dynamic>;
    final segments = (row['path'] as String).split('/');
    var current = root.path;
    for (var index = 0; index < segments.length; index++) {
      current = '$current${Platform.pathSeparator}${segments[index]}';
      final kind = await FileSystemEntity.type(current, followLinks: false);
      final expected = index == segments.length - 1
          ? FileSystemEntityType.file
          : FileSystemEntityType.directory;
      if (kind != expected)
        _invalid('Missing, linked or wrong-kind closure path ${row['path']}');
    }
    final file = File(current);
    final hash = await sha256.bind(file.openRead()).first;
    if (hash.toString() != row['sha256'] ||
        await file.length() != row['size_bytes'])
      _invalid('Integrity drift for ${row['path']}');
  }
}
