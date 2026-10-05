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
  if (value is! String || value.trim().isEmpty) {
    _invalid('$where must be nonempty text');
  }
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
  if (!choices.contains(value)) {
    _invalid('$where must be one of ${choices.join(', ')}');
  }
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
      if (entry.value == null) {
        _text(value['${key}_reason'], '$where.$key reason');
      }
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
      if (item == null) {
        _invalid(
          '$where: unavailable array entries require an object with a null field and reason',
        );
      }
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
  final filesByPath = <String, Map<String, dynamic>>{};
  String? previous;
  for (final file in files) {
    final row = _map(file, 'file');
    _sourcePath(row['path'], 'file.path');
    final path = row['path'] as String;
    if (!paths.add(path.toLowerCase())) {
      _invalid('Duplicate/case-aliased closure path $path');
    }
    if (previous != null && previous.compareTo(path) >= 0) {
      _invalid('File closure must be sorted by ordinal path');
    }
    previous = path;
    _hash(row['sha256'], 'file.sha256');
    _number(row['size_bytes'], 'file.size_bytes', integer: true);
    _text(row['role'], 'file.role');
    filesByPath[path] = row;
  }
  _boolean(record['closure_complete'], 'closure_complete');
  if (complete && record['closure_complete'] != true) {
    _invalid('Final lock requires a declared complete closure');
  }
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
        final file = filesByPath[row['path']];
        if (file == null || file['sha256'] != row['sha256']) {
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
    if (record['freeze_id'] != sourceFreezeId(record)) {
      _invalid('freeze_id does not match effective inputs');
    }
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
  for (final path in scope) {
    _sourcePath(path, 'permission.scope_paths');
  }
  if (!scope.cast<String>().toSet().containsAll(paths)) {
    _invalid('Permission scope must cover every closure file');
  }
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
      if (gate['status'] == 'not_applicable') {
        _invalid('Required gates cannot be not_applicable');
      }
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
    for (final key in ['required', 'applicable', 'attempted']) {
      _boolean(row[key], 'check.$key');
    }
    for (final key in ['owner', 'scope', 'stratum_id', 'reason']) {
      _text(row[key], 'check.$key');
    }
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
    if (!row.containsKey('freeze_id')) {
      _invalid(
        'Planned checks must explicitly declare freeze_id or null with reason',
      );
    }
    if (row['required'] == true && row['applicable'] == false) {
      _invalid('Required scope cannot be made inapplicable');
    }
    if (row['attempted'] == false &&
        (row['freeze_id'] != null ||
            (row['evidence_ids'] as List).isNotEmpty ||
            row['disposition'] == 'observed')) {
      _invalid('Unattempted checks cannot fabricate a freeze or observation');
    }
    if (row['attempted'] == true &&
        row['disposition'] == 'observed' &&
        (row['evidence_ids'] as List).isEmpty) {
      _invalid('Observed check requires evidence');
    }
    if (row['freeze_id'] != null) _hash(row['freeze_id'], 'check.freeze_id');
    if (row['disposition'] == 'skipped') {
      _text(row['skip_decision_id'], 'check.skip_decision_id');
    }
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
  _texts(record['provenance_ids'], 'provenance_ids', nonempty: true);
  for (final key in ['freeze_id', 'fixture_manifest_sha256']) {
    _hash(record[key], key);
  }
  for (final key in ['run_id', 'environment_id']) {
    _text(record[key], key);
  }
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
    if (!seen.add('${row['case_id']}/${row['profile']}')) {
      _invalid('Duplicate observation case/profile');
    }
    _choice(row['status'], [
      'observed',
      'unverified',
      'error',
    ], 'observation.status');
    _list(row['stage_timings'], 'observation.stage_timings');
    _list(row['errors'], 'observation.errors');
    if (row['status'] == 'unverified') {
      if (row['result'] != null || row['comparison'] != null) {
        _invalid('Unverified observation cannot supply measured results');
      }
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
        if (!result.containsKey(field)) {
          _invalid(
            'Observed ${row['profile']} requires $field (null with reason if unavailable)',
          );
        }
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
    for (final key in ['kind', 'purpose']) {
      _text(row[key], 'artifact.$key');
    }
    _map(row['source'], 'artifact.source');
    if (!row.containsKey('sha256')) {
      _invalid('Artifact must explicitly declare sha256 or null with reason');
    }
    if (row['sha256'] != null) _hash(row['sha256'], 'artifact.sha256');
    for (final key in [
      'depends_on',
      'derived_from',
      'build_inputs',
      'notices',
      'modifications',
    ]) {
      _texts(row[key], 'artifact.$key');
    }
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
      for (final key in ['scope', 'reason']) {
        _text(disposition[key], '$use.$key');
      }
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
  ]) {
    _text(record[key], key);
  }
  final cases = _list(record['cases'], 'cases');
  _ids(cases, 'cases');
  for (final value in cases) {
    final row = _map(value, 'case');
    _choice(row['role'], [
      'reference_characterization',
      'expectation_only',
      'both',
    ], 'case.role');
    for (final key in ['source_id', 'display_cell_id']) {
      _text(row[key], 'case.$key');
    }
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
      for (final key in ['width', 'height']) {
        _number(input[key], 'case.input.$key', integer: true, minimum: 1);
      }
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
    ]) {
      _text(row[key], 'control.$key');
    }
    for (final key in ['artwork_sha256', 'config_sha256']) {
      _hash(row[key], 'control.$key');
    }
    final xyz = _map(row['game_xyz'], 'control.game_xyz');
    for (final key in ['x', 'z']) {
      if (xyz[key] is! num || !(xyz[key] as num).isFinite) {
        _invalid('game_xyz.$key must be finite');
      }
    }
    if (!xyz.containsKey('y')) {
      _invalid('game_xyz must explicitly state y or y:null with reason');
    }
    if (xyz['y'] != null && (xyz['y'] is! num || !(xyz['y'] as num).isFinite)) {
      _invalid('game_xyz.y must be finite or unavailable');
    }
    for (final key in ['artwork_pixel', 'normalized']) {
      _point(row[key], 'control.$key');
    }
    _number(row['tolerance'], 'control.tolerance');
    _number(row['uncertainty'], 'control.uncertainty');
    _texts(row['source_ids'], 'control.source_ids', nonempty: true);
    _texts(row['review_ids'], 'control.review_ids', nonempty: true);
  }
  if (record.containsKey('anchors')) _anchors(record['anchors']);
}

void _anchors(Object? value) {
  final anchors = _list(value, 'anchors');
  _ids(anchors, 'anchors');
  for (final value in anchors) {
    final row = _map(value, 'anchor');
    for (final key in ['map_id', 'source_key', 'frame_revision']) {
      _text(row[key], 'anchor.$key');
    }
    _choice(row['kind'], [
      'floor_artwork',
      'tile_seam',
      'raster_extent',
    ], 'anchor.kind');
    _portablePath(row['artwork_path'], 'anchor.artwork_path');
    for (final key in ['artwork_sha256', 'config_sha256']) {
      _hash(row[key], 'anchor.$key');
    }
    if (!row.containsKey('floor_group_id')) {
      _invalid('Anchor requires an explicit floor group or null with reason');
    }
    if (row['kind'] == 'floor_artwork' || row['floor_group_id'] != null) {
      _text(row['floor_group_id'], 'anchor.floor_group_id');
    }
    for (final key in ['width', 'height']) {
      _number(row[key], 'anchor.$key', integer: true, minimum: 1);
    }
    _number(row['uncertainty'], 'anchor.uncertainty');
    _boolean(
      row['independent_of_reference_output'],
      'anchor.independent_of_reference_output',
    );
    _texts(row['source_ids'], 'anchor.source_ids', nonempty: true);
    _texts(row['review_ids'], 'anchor.review_ids', nonempty: true);
    final points = _list(row['points'], 'anchor.points', nonempty: true);
    if (row['kind'] != 'floor_artwork' && points.length < 2) {
      _invalid('Seam/extent anchors require at least two independent points');
    }
    for (final point in points) {
      _point(point, 'anchor.point');
    }
  }
}

void _display(Map<String, dynamic> record) {
  final cells = _list(record['cells'], 'cells');
  _ids(cells, 'cells');
  final combinations = <String>{};
  for (final value in cells) {
    final row = _map(value, 'cell');
    for (final key in ['width', 'height', 'os_scale_percent']) {
      _number(row[key], 'cell.$key', integer: true, minimum: 1);
    }
    if (!combinations.add(
      '${row['width']}x${row['height']}@${row['os_scale_percent']}',
    )) {
      _invalid('Duplicate display combination');
    }
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
        (row['evidence_ids'] as List).isNotEmpty) {
      _invalid('Planned display cells cannot claim observations');
    }
    _text(row['limitations'], 'cell.limitations');
  }
}

void _attempts(Map<String, dynamic> record) {
  _texts(record['provenance_ids'], 'provenance_ids', nonempty: true);
  for (final key in ['run_id', 'environment_id']) {
    _text(record[key], key);
  }
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
    ]) {
      _text(row[key], 'attempt.$key');
    }
    _number(row['ordinal'], 'attempt.ordinal', integer: true, minimum: 1);
    _list(row['stages'], 'attempt.stages');
    _map(row['missing_stage_reasons'], 'attempt.missing_stage_reasons');
    if (row.containsKey('measurements') && row['measurements'] != null) {
      final measurements = _map(row['measurements'], 'attempt.measurements');
      for (final key in [
        'initialization_ms',
        'map_load_ms',
        'map_switch_ms',
        'pan_ms',
        'zoom_ms',
        'floor_switch_ms',
        'process_cpu_ms',
        'process_memory_bytes',
      ]) {
        if (measurements[key] != null) {
          _number(
            measurements[key],
            'measurements.$key',
            integer: key == 'process_memory_bytes',
          );
        }
      }
      if (measurements['interaction_path_id'] != null) {
        _text(
          measurements['interaction_path_id'],
          'measurements.interaction_path_id',
        );
      }
      for (final key in ['startup', 'first_scan']) {
        if (measurements[key] == null) continue;
        final elapsed = _map(measurements[key], 'measurements.$key');
        for (final boundary in ['start', 'end']) {
          if (elapsed[boundary] == null) continue;
          final stamp = _map(elapsed[boundary], '$key.$boundary');
          if (stamp['type'] != null) {
            _choice(stamp['type'], ['video'], '$key.$boundary.type');
          }
          for (final text in ['name', 'recording_id', 'clock_domain']) {
            if (stamp[text] != null) _text(stamp[text], '$key.$boundary.$text');
          }
          for (final bound in ['lower_ms', 'upper_ms']) {
            if (!stamp.containsKey(bound)) {
              _invalid(
                'Measurement boundary requires $bound or null with reason',
              );
            }
            if (stamp[bound] != null) {
              _number(stamp[bound], '$key.$boundary.$bound');
            }
          }
          if (stamp['lower_ms'] is num &&
              stamp['upper_ms'] is num &&
              (stamp['lower_ms'] as num) > (stamp['upper_ms'] as num)) {
            _invalid('Measurement boundary frame interval runs backwards');
          }
        }
      }
    }
    if (!row.containsKey('qpc_frequency')) {
      _invalid(
        'Attempt must explicitly declare qpc_frequency or null with reason',
      );
    }
    if (row['qpc_frequency'] != null) {
      _number(
        row['qpc_frequency'],
        'attempt.qpc_frequency',
        integer: true,
        minimum: 1,
      );
    }
    for (final stage in row['stages'] as List) {
      final ticks = _map(stage, 'stage');
      _text(ticks['name'], 'stage.name');
      for (final key in ['start_tick', 'end_tick']) {
        _number(ticks[key], 'stage.$key', integer: true);
      }
      if ((ticks['end_tick'] as int) < (ticks['start_tick'] as int)) {
        _invalid('Stage ticks run backwards');
      }
      if (row['qpc_frequency'] == null) {
        _invalid('Tick stages require frequency');
      }
    }
    if (!row.containsKey('endpoint') ||
        !row.containsKey('trigger') ||
        !row.containsKey('observer') ||
        !row.containsKey('external_data_age_ms')) {
      _invalid(
        'Attempts must explicitly state endpoint/trigger/observer/external-data availability',
      );
    }
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
    if (!record.containsKey(key)) {
      _invalid('environment requires $key or null with reason');
    }
    if (record[key] != null) {
      final value = _map(record[key], key);
      final numeric = switch (key) {
        'hardware' => ['ram_bytes'],
        'viewport' => [
          'width',
          'height',
          'client_width',
          'client_height',
          'ui_scale',
        ],
        'display' => ['width', 'height', 'os_scale_percent'],
        'observer' => ['uncertainty_ms'],
        _ => <String>[],
      };
      for (final field in numeric) {
        if (value[field] != null) {
          _number(
            value[field],
            '$key.$field',
            integer: field != 'ui_scale' && field != 'uncertainty_ms',
            minimum: field == 'uncertainty_ms' || field == 'ui_scale' ? 0 : 1,
          );
          if (field == 'ui_scale' && (value[field] as num) == 0) {
            _invalid('viewport.ui_scale must be positive');
          }
        }
      }
      final textual = switch (key) {
        'hardware' => ['cpu', 'gpu'],
        'windows' => ['version', 'architecture'],
        'runtime' => ['sdk'],
        'app_build' => ['id', 'version'],
        'display' => ['topology'],
        'observer' => ['method', 'recording_id', 'clock_domain'],
        _ => <String>[],
      };
      for (final field in textual) {
        if (value[field] != null) _text(value[field], '$key.$field');
      }
      if (key == 'display' && value['origin'] != null) {
        final origin = _map(value['origin'], 'display.origin');
        for (final axis in ['x', 'y']) {
          if (origin[axis] != null &&
              (origin[axis] is! num || !(origin[axis] as num).isFinite)) {
            _invalid('display.origin.$axis must be finite');
          }
        }
      }
    }
  }
  for (final key in ['locale', 'display_mode', 'warm_state']) {
    if (!record.containsKey(key)) {
      _invalid('environment requires $key or null with reason');
    }
    if (record[key] != null) _text(record[key], key);
  }
}

void _dossierRequest(Map<String, dynamic> record) {
  _text(record['run_id'], 'run_id');
  const required = {
    'provenance',
    'fixture_manifest',
    'map_controls',
    'display_matrix',
    'planned_checks',
    'environment',
  };
  const optional = {'oracle_results', 'attempt_bundle'};
  const source = {'source_intake', 'source_lock'};
  const fields = {
    'schema_version',
    'record_type',
    'id',
    'run_id',
    'records',
    'oracle_results',
    'oracle_results_reason',
    'attempt_bundle',
    'attempt_bundle_reason',
  };
  if (record.keys.any((key) => !fields.contains(key))) {
    _invalid('Unexpected dossier request field');
  }
  final records = _map(record['records'], 'records');
  if (required.any((key) => !records.containsKey(key)) ||
      source.where(records.containsKey).length != 1) {
    _invalid(
      'Dossier requires every metadata role and exactly one source role',
    );
  }
  for (final entry in records.entries) {
    if (!required.contains(entry.key) &&
        !optional.contains(entry.key) &&
        !source.contains(entry.key)) {
      _invalid('Unknown dossier record role ${entry.key}');
    }
    _portablePath(entry.value, 'records.${entry.key}');
  }
  for (final role in optional) {
    if (records.containsKey(role)) {
      if (record.containsKey(role) || record.containsKey('${role}_reason')) {
        _invalid('Supplied $role cannot also be declared unavailable');
      }
    } else if (!record.containsKey(role) || record[role] != null) {
      _invalid('Missing $role requires explicit null with a reason');
    }
  }
}

void _attemptCounts(Map<String, dynamic> record, String where) {
  _number(record['attempt_n'], '$where.attempt_n', integer: true);
  _texts(record['attempt_ids'], '$where.attempt_ids');
  final ids = record['attempt_ids'] as List;
  if (ids.toSet().length != ids.length || ids.length != record['attempt_n']) {
    _invalid('$where attempt IDs must be unique and match the denominator');
  }
  var total = 0;
  final counts = _map(record['outcome_counts'], '$where.outcome_counts');
  for (final entry in counts.entries) {
    _text(entry.key, '$where.outcome');
    _number(entry.value, '$where.outcome count', integer: true);
    total += entry.value as int;
  }
  if (total != record['attempt_n']) {
    _invalid('$where outcomes must retain every attempted disposition');
  }
}

void _metric(Object? value, int denominator, {required bool interval}) {
  final metric = _map(value, 'metric');
  for (final key in ['n', 'missing_n']) {
    _number(metric[key], 'metric.$key', integer: true);
  }
  if ((metric['n'] as int) + (metric['missing_n'] as int) != denominator) {
    _invalid('Metric eligible and missing counts must retain the denominator');
  }
  final reasons = _map(metric['missing_reasons'], 'metric.missing_reasons');
  var missing = 0;
  for (final entry in reasons.entries) {
    _text(entry.key, 'metric.missing reason');
    _number(entry.value, 'metric.missing count', integer: true);
    missing += entry.value as int;
  }
  if (missing != metric['missing_n']) {
    _invalid('Metric missing reasons must account for every missing sample');
  }
  final fields = interval ? ['p95_lower_ms', 'p95_upper_ms'] : ['p95_ms'];
  for (final field in fields) {
    if (!metric.containsKey(field)) _invalid('Metric requires $field');
    if (metric['n'] == 0) {
      if (metric[field] != null) {
        _invalid(
          'Zero eligible samples require null latency, not a measured zero',
        );
      }
    } else {
      _number(metric[field], 'metric.$field');
    }
  }
  final lower = metric[fields.first] as num?;
  final upper = metric[fields.last] as num?;
  if (lower != null && upper != null && lower > upper) {
    _invalid('Metric uncertainty bounds run backwards');
  }
  if (!metric.containsKey('target_ms')) {
    _invalid('Metric requires an explicit target or null with reason');
  }
  final target = metric['target_ms'];
  if (target != null) _number(target, 'metric.target_ms');
  final expected = lower == null || upper == null || target == null
      ? 'unverified'
      : upper <= (target as num)
      ? 'pass'
      : lower > target
      ? 'fail'
      : 'indeterminate';
  if (metric['threshold_status'] != expected) {
    _invalid(
      'Metric threshold status must follow its measured bounds and target',
    );
  }
}

void _baseline(Map<String, dynamic> record) {
  for (final key in ['run_id', 'environment_id']) {
    _text(record[key], key);
  }
  if (record['quantile_method'] != 'nearest_rank' ||
      record['quantile'] != 0.95) {
    _invalid('Version-1 baseline uses nearest-rank p95');
  }
  _choice(record['status'], ['incomplete', 'descriptive'], 'status');
  _choice(record['visible_evidence_status'], [
    'unverified',
    'observed',
  ], 'visible_evidence_status');
  _attemptCounts(record, 'baseline');
  final n = record['attempt_n'] as int;
  final attemptIds = (record['attempt_ids'] as List).cast<String>().toSet();
  for (final key in ['actionable_sample_n', 'fallback_visible_sample_n']) {
    _number(record[key], key, integer: true);
    if ((record[key] as int) > n) {
      _invalid('$key exceeds attempted denominator');
    }
  }
  final actionable = record['actionable_sample_n'] as int;
  if ((record['visible_evidence_status'] == 'observed') != (actionable > 0)) {
    _invalid('Visible evidence status must match eligible actionable samples');
  }
  if (actionable == 0 && record['status'] != 'incomplete') {
    _invalid('No actionable samples cannot establish a descriptive baseline');
  }
  for (final key in [
    'attempt_bundle_id',
    'attempt_bundle_sha256',
    'freeze_id',
    'collection_status',
  ]) {
    if (!record.containsKey(key)) _invalid('Baseline requires explicit $key');
  }
  if (record['collection_status'] != null) {
    _text(record['collection_status'], 'collection_status');
  }
  final invalid = record['collection_status'] == 'invalid_evidence';
  if (record['attempt_bundle_id'] == null) {
    if (record['attempt_bundle_sha256'] != null ||
        record['freeze_id'] != null ||
        record['status'] != 'incomplete' ||
        actionable != 0 ||
        record['fallback_visible_sample_n'] != 0 ||
        (!invalid && n != 0)) {
      _invalid('Unavailable measurement input cannot establish frozen samples');
    }
  } else {
    _text(record['attempt_bundle_id'], 'attempt_bundle_id');
    _hash(record['attempt_bundle_sha256'], 'attempt_bundle_sha256');
    _hash(record['freeze_id'], 'freeze_id');
  }
  _map(record['coverage'], 'coverage');
  _map(record['external_data_ages'], 'external_data_ages');
  final summaries = _list(record['attempt_summaries'], 'attempt_summaries');
  _ids(summaries, 'attempt_summaries');
  if (!invalid &&
      (summaries.length != n ||
          summaries.any((row) => !attemptIds.contains(row['id'])))) {
    _invalid('Baseline summaries must retain exactly the attempted IDs');
  }
  var stratumN = 0;
  var actionableN = 0;
  var fallbackN = 0;
  final stratumIds = <String>{};
  final stratumAttempts = <String>{};
  for (final value in _list(record['strata'], 'strata')) {
    final row = _map(value, 'stratum');
    final identity = canonicalJson(_map(row['stratum'], 'stratum.identity'));
    if (!stratumIds.add(identity)) _invalid('Duplicate baseline stratum');
    _attemptCounts(row, 'stratum');
    for (final id in (row['attempt_ids'] as List).cast<String>()) {
      if (!attemptIds.contains(id) || !stratumAttempts.add(id)) {
        _invalid('Baseline strata must partition the actual attempted IDs');
      }
    }
    final count = row['attempt_n'] as int;
    stratumN += count;
    for (final metric in _map(
      row['internal_stages'],
      'internal_stages',
    ).values) {
      _metric(metric, count, interval: false);
    }
    _metric(row['physical_to_actionable_visible'], count, interval: true);
    _metric(row['physical_to_fallback_visible'], count, interval: true);
    actionableN += row['physical_to_actionable_visible']['n'] as int;
    fallbackN += row['physical_to_fallback_visible']['n'] as int;
  }
  if (!invalid &&
      (stratumN != n ||
          actionableN != actionable ||
          fallbackN != record['fallback_visible_sample_n'])) {
    _invalid('Strata must preserve global attempt and eligible-sample counts');
  }
  if (record.containsKey('physical_to_actionable_visible')) {
    _metric(record['physical_to_actionable_visible'], n, interval: true);
    if (record['physical_to_actionable_visible']['n'] != 0) {
      _invalid(
        'Visible quantiles must be stratified, never a pooled root metric',
      );
    }
  }
}

void _divergences(Map<String, dynamic> record) {
  _text(record['run_id'], 'run_id');
  for (final value in _list(record['observed'], 'observed')) {
    final row = _map(value, 'divergence');
    if (row['kind'] == 'reference_speed') {
      if (row.containsKey('case_id') || row.containsKey('profile')) {
        _invalid(
          'Speed divergence uses actual case_ids and a stratum, not a fabricated case/profile',
        );
      }
      _choice(row['status'], ['observed'], 'speed divergence.status');
      _texts(row['case_ids'], 'speed divergence.case_ids', nonempty: true);
      _texts(
        row['evidence_ids'],
        'speed divergence.evidence_ids',
        nonempty: true,
      );
      final defects = _list(row['defects'], 'speed divergence.defects');
      final errors = _list(row['errors'], 'speed divergence.errors');
      if (defects.length != 1 ||
          defects.single != 'latency_target_exceeded' ||
          errors.isNotEmpty) {
        _invalid(
          'Observed speed divergence requires latency_target_exceeded and no evidence errors',
        );
      }
      _map(row['stratum'], 'speed divergence.stratum');
      final expected = _map(row['expected'], 'speed divergence.expected');
      _number(expected['target_ms'], 'speed divergence.target_ms');
      final observed = _map(row['observed'], 'speed divergence.observed');
      _text(observed['name'], 'speed divergence.metric name');
      _number(observed['n'], 'speed divergence.n', integer: true, minimum: 1);
      final scalar = observed.containsKey('p95_ms');
      final interval =
          observed.containsKey('p95_lower_ms') ||
          observed.containsKey('p95_upper_ms');
      if (scalar == interval) {
        _invalid(
          'Speed divergence requires exactly one scalar or bounded p95 metric',
        );
      }
      final lowerKey = scalar ? 'p95_ms' : 'p95_lower_ms';
      final upperKey = scalar ? 'p95_ms' : 'p95_upper_ms';
      _number(observed[lowerKey], 'speed divergence.$lowerKey');
      _number(observed[upperKey], 'speed divergence.$upperKey');
      if ((observed[lowerKey] as num) > (observed[upperKey] as num)) {
        _invalid('Speed divergence uncertainty bounds run backwards');
      }
      if ((observed[lowerKey] as num) <= (expected['target_ms'] as num)) {
        _invalid(
          'Observed speed divergence requires a p95 lower bound exceeding its target',
        );
      }
      continue;
    }
    _texts(
      record['provenance_ids'],
      'divergence provenance_ids',
      nonempty: true,
    );
    if (row['kind'] == 'intentional_target_policy') {
      _choice(row['status'], ['observed'], 'intentional divergence.status');
      _text(row['rationale'], 'intentional divergence.rationale');
      _texts(
        row['evidence_ids'],
        'intentional divergence.evidence_ids',
        nonempty: true,
      );
      if (_list(row['defects'], 'intentional divergence.defects').isNotEmpty ||
          _list(row['errors'], 'intentional divergence.errors').isNotEmpty) {
        _invalid(
          'Intentional policy difference is not a fabricated defect or evidence error',
        );
      }
    }
    _text(row['case_id'], 'divergence.case_id');
    _choice(row['profile'], _profiles, 'divergence.profile');
    _text(row['status'], 'divergence.status');
    _list(row['defects'], 'divergence.defects');
    _list(row['errors'], 'divergence.errors');
    _map(row['expected'], 'divergence.expected');
    if (!row.containsKey('observed')) {
      _invalid('Divergence must preserve observed value or null with reason');
    }
    if (row['observed'] != null) _map(row['observed'], 'divergence.observed');
  }
  for (final value in _list(record['expectation_only'], 'expectation_only')) {
    final row = _map(value, 'expected divergence');
    _text(row['case_id'], 'expected divergence.case_id');
    _choice(row['status'], ['expectation_only'], 'expected divergence.status');
    _map(row['expected'], 'expected divergence.expected');
    _texts(
      row['evidence_ids'],
      'expected divergence.evidence_ids',
      nonempty: true,
    );
    _text(row['reason'], 'expected divergence.reason');
  }
}

void _report(Map<String, dynamic> record) {
  final gates = _list(
    record['gates'],
    'gates',
  ).map((value) => _map(value, 'gate')).toList();
  if (record['status'] != qualificationStatus(gates)) {
    _invalid('Report status must equal its required-gate classification');
  }
  final manifests = _list(record['inputs'], 'inputs', nonempty: true);
  for (final input in manifests) {
    final row = _map(input, 'report.input');
    for (final key in ['id', 'version']) {
      _text(row[key], 'report.input.$key');
    }
    _hash(row['sha256'], 'report.input.sha256');
  }
  final coverage = _map(record['coverage'], 'coverage');
  if (coverage['recognition'] is Map &&
      coverage['recognition']['metrics'] != null) {
    _texts(
      record['provenance_ids'],
      'report observation provenance_ids',
      nonempty: true,
    );
  }
  _text(record['planned_checks_id'], 'planned_checks_id');
  for (final key in ['coverage', 'denominators', 'timing']) {
    _map(record[key], key);
  }
  _list(record['strata'], 'strata');
  _list(record['divergences'], 'divergences');
  final display = _map(record['display_matrix'], 'display_matrix');
  _display(display);
  if ((display['cells'] as List).length != 16) {
    _invalid('Qualification reports must retain all 16 display cells');
  }
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
  if (record['schema_version'] != 1) {
    _invalid('Unsupported schema_version; expected 1');
  }
  _text(record['id'], 'id');
  canonicalJson(record);
  _nullReasons(record, 'record');
  if (expectedFreezeId != null) {
    _hash(expectedFreezeId, 'expectedFreezeId');
    if (record['freeze_id'] != expectedFreezeId) {
      _invalid('Record is bound to a different or unavailable freeze');
    }
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
    case 'dossier_request':
      _dossierRequest(record);
    case 'baseline_summary':
      _baseline(record);
    case 'divergence_register':
      _divergences(record);
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
      record['record_type'] != 'source_intake') {
    _invalid('Integrity verification requires a source record');
  }
  final root = Directory(sourceRoot).absolute;
  var ancestor = root;
  while (true) {
    final kind = await FileSystemEntity.type(ancestor.path, followLinks: false);
    if (kind != FileSystemEntityType.directory) {
      _invalid('Source root ancestry must contain real directories, not links');
    }
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
      if (kind != expected) {
        _invalid('Missing, linked or wrong-kind closure path ${row['path']}');
      }
    }
    final file = File(current);
    final hash = await sha256.bind(file.openRead()).first;
    if (hash.toString() != row['sha256'] ||
        await file.length() != row['size_bytes']) {
      _invalid('Integrity drift for ${row['path']}');
    }
  }
}
