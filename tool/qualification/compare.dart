import 'contracts.dart';

const _basisKeys = [
  'corpus_version',
  'annotation_version',
  'catalog_version',
  'config_version',
  'mode',
  'freeze_id',
];
const _profiles = [
  'engine_inspection',
  'engine_multi',
  'host_resolution',
  'map_geometry',
  'exfil_panel',
];
const _labels = [
  'readable_positive',
  'rejection',
  'chrome',
  'ambiguous',
  'occluded',
];
const _decisions = ['Keep', 'Sell', 'Check'];
const _panelDispositions = [
  'absent',
  'present_empty',
  'matched',
  'no_match',
  'ambiguous',
  'unreadable',
];
const _metricKeys = [
  'correct_positive_ids',
  'wrong_positive_ids',
  'accepted_negatives',
  'recognized_negatives',
  'extra_false_positive_selections',
  'wrong_identities',
  'abstentions',
  'readable_positive_misses',
  'host_accepted_identities',
  'actionable_advice',
  'outcome_errors',
  'geometry_mismatches',
  'policy_mismatches',
  'panel_mismatches',
  'missing_detections',
  'unmatched_detections',
  'duplicate_detections',
];

Never _invalid(String message) => throw ContractException(message);
Map<String, dynamic> _object(Object? value, String name) {
  if (value is! Map<String, dynamic>) _invalid('$name must be an object');
  return value;
}

List<dynamic> _array(Object? value, String name) {
  if (value is! List) _invalid('$name must be an array');
  return value;
}

String _text(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    _invalid('$name must be nonempty text');
  }
  return value;
}

num _number(Object? value, String name, {bool tolerance = false}) {
  if (value is! num || !value.isFinite || (tolerance && value < 0)) {
    _invalid(
      '$name must be ${tolerance ? 'nonnegative ' : ''}finite numeric data',
    );
  }
  return value;
}

void _choice(Object? value, List<String> choices, String name) {
  if (!choices.contains(value)) {
    _invalid('$name must be one of ${choices.join(', ')}');
  }
}

void _keys(Map<String, dynamic> value, List<String> keys, String name) {
  for (final key in keys) {
    if (!value.containsKey(key)) {
      _invalid('$name requires $key, or explicit null with reason');
    }
  }
}

List<String> _texts(Object? value, String name) =>
    _array(value, name).map((id) => _text(id, name)).toList();
List<String> _ids(Object? value, String name) {
  final ids = _texts(value, name);
  if (ids.toSet().length != ids.length) _invalid('$name contains duplicates');
  return ids;
}

void _point(Object? value, String name, {bool rectangle = false}) {
  final point = _object(value, name);
  for (final key in rectangle ? ['x', 'y', 'width', 'height'] : ['x', 'y']) {
    final number = _number(point[key], '$name.$key');
    if ((key == 'width' || key == 'height') && number <= 0) {
      _invalid('$name.$key must be positive');
    }
  }
}

bool _near(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
  List<String> axes,
  num tolerance,
) => axes.every(
  (axis) => ((a[axis] as num) - (b[axis] as num)).abs() <= tolerance,
);

void _identityTruth(Map<String, dynamic> truth) {
  _keys(truth, ['label', 'item_id'], 'identity truth');
  _choice(truth['label'], _labels, 'truth.label');
  if (truth['label'] == 'readable_positive') {
    _text(truth['item_id'], 'truth.item_id');
  } else if (truth['item_id'] != null) {
    _invalid(
      'Negative or unresolved independent truth must not select a unique item_id',
    );
  }
}

void _validateTruth(String profile, Map<String, dynamic> truth) {
  switch (profile) {
    case 'engine_inspection':
      _identityTruth(truth);
      _keys(truth, ['title_roi'], 'truth');
      if (truth['title_roi'] != null) {
        _point(truth['title_roi'], 'truth.title_roi', rectangle: true);
      } else if (truth['label'] == 'readable_positive') {
        _invalid(
          'Readable-positive truth requires independently labeled geometry',
        );
      }
      _number(
        truth['geometry_tolerance'],
        'truth.geometry_tolerance',
        tolerance: true,
      );
    case 'engine_multi':
      _number(
        truth['geometry_tolerance'],
        'truth.geometry_tolerance',
        tolerance: true,
      );
      final seen = <String>{};
      for (final value in _array(truth['inspections'], 'truth.inspections')) {
        final inspection = _object(value, 'truth.inspection');
        if (!seen.add(_text(inspection['id'], 'truth.inspection.id'))) {
          _invalid('Duplicate independent inspection ID');
        }
        _identityTruth(inspection);
        _point(
          inspection['title_roi'],
          'truth.inspection.title_roi',
          rectangle: true,
        );
      }
      if (seen.isEmpty) {
        _invalid('Multi truth requires independently labeled inspections');
      }
    case 'host_resolution':
      _identityTruth(truth);
      final policy = _object(truth['target_policy'], 'truth.target_policy');
      _text(policy['id'], 'target_policy.id');
      _keys(policy, ['decision'], 'target_policy');
      if (policy['decision'] != null || truth['label'] == 'readable_positive') {
        _choice(policy['decision'], _decisions, 'target_policy.decision');
      }
      _object(policy['inputs'], 'target_policy.inputs');
      _text(policy['rationale'], 'target_policy.rationale');
      if (policy['intentional_divergence'] is! bool) {
        _invalid('target_policy.intentional_divergence must be Boolean');
      }
    case 'map_geometry':
      _keys(truth, [
        'frame_revision',
        'artwork_pixel',
        'normalized',
        'game_xyz',
        'floor_group_id',
        'heading',
        'tolerances',
      ], 'map truth');
      _number(truth['frame_revision'], 'truth.frame_revision');
      _point(truth['artwork_pixel'], 'truth.artwork_pixel');
      _point(truth['normalized'], 'truth.normalized');
      _xyz(truth['game_xyz'], 'truth.game_xyz');
      _text(truth['floor_group_id'], 'truth.floor_group_id');
      _heading(truth['heading'], 'truth.heading');
      final tolerances = _object(truth['tolerances'], 'truth.tolerances');
      for (final field in [
        'artwork_pixel',
        'normalized',
        'game_xyz',
        'heading',
      ]) {
        _number(tolerances[field], 'truth.tolerances.$field', tolerance: true);
      }
    case 'exfil_panel':
      _keys(truth, [
        'map_id',
        'disposition',
        'extract_text',
        'transit_text',
        'matched_ids',
      ], 'panel truth');
      _text(truth['map_id'], 'truth.map_id');
      _choice(truth['disposition'], _panelDispositions, 'truth.disposition');
      for (final field in ['extract_text', 'transit_text']) {
        if (truth[field] != null && truth[field] is! String) {
          _invalid('truth.$field must be text or null with reason');
        }
      }
      final ids = _ids(truth['matched_ids'], 'truth.matched_ids');
      _panelIdentity(truth['disposition'], ids);
  }
}

void _xyz(Object? value, String name) {
  final xyz = _object(value, name);
  _keys(xyz, ['x', 'y', 'z'], name);
  for (final axis in ['x', 'z']) {
    _number(xyz[axis], '$name.$axis');
  }
  if (xyz['y'] != null) _number(xyz['y'], '$name.y');
}

void _heading(Object? value, String name) {
  final heading = _object(value, name);
  _number(heading['degrees'], '$name.degrees');
  _text(heading['convention'], '$name.convention');
}

void _panelIdentity(Object? disposition, List<String> ids) {
  if (disposition == 'matched' && ids.isEmpty) {
    _invalid('Matched panel requires map-local identities');
  }
  if ([
        'absent',
        'present_empty',
        'no_match',
        'unreadable',
      ].contains(disposition) &&
      ids.isNotEmpty) {
    _invalid('Panel disposition cannot claim matched identities');
  }
}

/// Consumes serialized U1 `fixture_manifest` and `oracle_results`, never a runtime.
///
/// Both inputs bind corpus/annotation/catalog/config/mode/freeze in
/// `comparison_basis` on results and the corresponding manifest fields. Reference
/// cases explicitly declare `reference_eligible`; false requires `eligibility_rationale`.
/// Independent identity truth is `{label,item_id}`, with readable_positive or
/// rejection/chrome/ambiguous/occluded. Outcomes are `{disposition,item_id}`:
/// recognized for engines, accepted for the host, or rejected/abstained/error.
/// ROI coordinates `{x,y,width,height}` use a fixed `geometry_tolerance`;
/// a genuine no-inspection negative explicitly has null ROI with reason.
/// Multi truth has `inspections:[{id,label,item_id,title_roi}]`; each actual
/// detection has `id,marker,title_roi,ocr_text,candidates,outcome`.
/// Host truth adds `target_policy:{id,decision,inputs,rationale,
/// intentional_divergence}`; its reference payload remains separate. A negative
/// may explicitly expect null decision with reason (no applicable advice).
/// Map truth has all U1 result fields, heading `{degrees,convention}`, and
/// `tolerances:{artwork_pixel,normalized,game_xyz,heading}`. Nullable game Y is
/// semantic unknown, not zero. Panel truth has `map_id,disposition,extract_text,
/// transit_text,matched_ids`; result also carries map_id, and disposition is
/// absent/present_empty/matched/no_match/ambiguous/unreadable.
///
/// The returned summary is computed comparison data, NOT a new U1 evidence record
/// or a qualification claim. Invalid linkage/shape throws [ContractException];
/// valid missing observations remain unverified, while faithful reference defects
/// do not fail evidence validity. Supplied observation.comparison is never truth.
/// Identity metrics count observed outcomes, but duplicate multi matches receive
/// no correct-positive credit. `actionable_advice` counts observed host-accepted
/// advice, not its safety or correctness; engine outputs cannot increment it.
Map<String, dynamic> compareReferenceResults(
  Map<String, dynamic> manifest,
  Map<String, dynamic> results, {
  Map<String, dynamic>? sourceLock,
}) {
  if (manifest['record_type'] != 'fixture_manifest' ||
      results['record_type'] != 'oracle_results') {
    _invalid('Comparison requires fixture_manifest and oracle_results');
  }
  validateRecord(manifest);
  validateRecord(results);
  final basis = <String, dynamic>{};
  final declared = _object(
    results['comparison_basis'],
    'results.comparison_basis',
  );
  for (final key in _basisKeys) {
    basis[key] = _text(manifest[key], 'manifest.$key');
    if (declared[key] != basis[key]) _invalid('Changed comparison basis: $key');
  }
  if (basis['freeze_id'] != results['freeze_id']) {
    _invalid('Results freeze differs from comparison basis');
  }
  final manifestHash = sha256Json(manifest);
  if (results['fixture_manifest_sha256'] != manifestHash) {
    _invalid('Results do not bind canonical manifest hash');
  }
  if (sourceLock != null) {
    if (sourceLock['record_type'] != 'source_lock') {
      _invalid('Provided sourceLock must be a final source_lock');
    }
    validateRecord(
      sourceLock,
      expectedFreezeId: results['freeze_id'] as String,
    );
  }

  final eligible = <String, Map<String, dynamic>>{};
  final expectationOnly = <Map<String, dynamic>>[];
  final ineligible = <Map<String, dynamic>>[];
  for (final value in manifest['cases'] as List) {
    final row = _object(value, 'case');
    if (row['role'] == 'expectation_only') {
      expectationOnly.add(row);
      continue;
    }
    for (final key in _basisKeys) {
      if (row.containsKey(key) && row[key] != basis[key]) {
        _invalid('Case ${row['id']} changes comparison basis: $key');
      }
    }
    if (row['reference_eligible'] is! bool) {
      _invalid(
        'Reference case ${row['id']} requires explicit reference_eligible',
      );
    }
    if (row['reference_eligible'] == false) {
      _text(row['eligibility_rationale'], 'case.eligibility_rationale');
      ineligible.add(row);
      continue;
    }
    _validateTruth(
      row['profile'] as String,
      _object(row['truth'], 'case.truth'),
    );
    eligible[row['id'] as String] = row;
  }
  final observed = <String, Map<String, dynamic>>{};
  for (final value in results['observations'] as List) {
    final row = _object(value, 'observation');
    _keys(row, ['result', 'comparison'], 'observation');
    for (final key in _basisKeys) {
      if (row.containsKey(key) && row[key] != basis[key]) {
        _invalid('Observation changes comparison basis: $key');
      }
    }
    for (final key in ['run_id', 'environment_id', 'fixture_manifest_sha256']) {
      if (row.containsKey(key) && row[key] != results[key]) {
        _invalid('Observation changes bundle linkage: $key');
      }
    }
    if (row.containsKey('comparison_basis')) {
      final rowBasis = _object(
        row['comparison_basis'],
        'observation.comparison_basis',
      );
      for (final key in _basisKeys) {
        if (rowBasis[key] != basis[key]) {
          _invalid('Observation changes comparison basis: $key');
        }
      }
    }
    final expected = eligible[row['case_id']];
    if (expected == null) {
      _invalid(
        'Observation is outside the explicit eligible reference case roster',
      );
    }
    if (row['profile'] != expected['profile']) {
      _invalid('Observation profile differs from case seam');
    }
    if (row['input_sha256'] != (expected['input'] as Map)['sha256']) {
      _invalid('Observation input hash differs from case');
    }
    // U1 refuses duplicate case/profile pairs; the single frozen case seam also
    // prevents pooling changed snapshots or multiple incompatible profiles.
    observed[row['case_id'] as String] = row;
  }

  final denominators = <String, int>{
    'eligible_cases': eligible.length,
    'attempted_rows': observed.length,
    'observed': 0,
    'missing_rows': 0,
    'errors': 0,
    'unverified': 0,
    'complete_comparisons': 0,
    'expectation_only_cases': expectationOnly.length,
    'ineligible_cases': ineligible.length,
  };
  final metrics = {for (final key in _metricKeys) key: 0};
  final profiles = <String, Map<String, int>>{
    for (final profile in _profiles)
      profile: {
        'eligible_cases': 0,
        'attempted_rows': 0,
        'observed': 0,
        'missing_rows': 0,
        'errors': 0,
        'unverified': 0,
        'complete_comparisons': 0,
        for (final key in _metricKeys) key: 0,
      },
  };
  final cases = <Map<String, dynamic>>[];
  final divergences = <Map<String, dynamic>>[];
  for (final fixture in eligible.values) {
    final id = fixture['id'] as String;
    final profile = fixture['profile'] as String;
    final counts = profiles[profile]!;
    counts['eligible_cases'] = counts['eligible_cases']! + 1;
    final actual = observed[id];
    final status = actual?['status'] as String? ?? 'missing';
    final row = <String, dynamic>{
      'case_id': id,
      'profile': profile,
      'status': status,
      'attempted': actual != null,
      'expected': fixture['truth'],
      'defects': <String>[],
      'unavailable': <String>[],
      'reference': actual?['result'],
      if (actual?['result'] == null)
        'reference_reason': actual == null
            ? 'No supplied result row; not an observed attempt.'
            : actual['result_reason'] ??
                  'Reference attempt did not yield a result.',
      'errors': actual?['errors'] ?? <dynamic>[],
    };
    cases.add(row);
    if (actual != null) {
      counts['attempted_rows'] = counts['attempted_rows']! + 1;
    }
    if (status != 'observed') {
      final counter = switch (status) {
        'missing' => 'missing_rows',
        'error' => 'errors',
        _ => 'unverified',
      };
      denominators[counter] = denominators[counter]! + 1;
      counts[counter] = counts[counter]! + 1;
      continue;
    }
    denominators['observed'] = denominators['observed']! + 1;
    counts['observed'] = counts['observed']! + 1;
    final comparison = _Comparison(row, metrics, counts);
    final truth = fixture['truth'] as Map<String, dynamic>;
    final result = actual!['result'] as Map<String, dynamic>;
    switch (profile) {
      case 'engine_inspection':
        comparison.inspection(truth, result);
      case 'engine_multi':
        comparison.multi(truth, result);
      case 'host_resolution':
        comparison.host(truth, result, divergences);
      case 'map_geometry':
        comparison.geometry(truth, result);
      case 'exfil_panel':
        comparison.panel(truth, result);
    }
    if ((row['unavailable'] as List).isEmpty && !comparison.hasOutcomeError) {
      denominators['complete_comparisons'] =
          denominators['complete_comparisons']! + 1;
      counts['complete_comparisons'] = counts['complete_comparisons']! + 1;
    }
  }
  final complete =
      denominators['complete_comparisons'] == eligible.length &&
      eligible.isNotEmpty;
  return {
    'schema_version': 1,
    'id': 'comparison-${results['id']}',
    'manifest_id': manifest['id'],
    'results_id': results['id'],
    'fixture_manifest_sha256': manifestHash,
    'oracle_results_sha256': sha256Json(results),
    'comparison_basis': basis,
    'evidence_validity': complete ? 'pass' : 'unverified',
    'reference_behavior':
        cases.any((row) => (row['defects'] as List).isNotEmpty)
        ? 'defects_observed'
        : divergences.isNotEmpty
        ? 'intentional_divergences_observed'
        : complete
        ? 'matches_independent_truth'
        : 'incomplete',
    'denominators': denominators,
    'metrics': metrics,
    'profiles': profiles,
    'cases': cases,
    'expectation_only': expectationOnly,
    'ineligible': ineligible,
    'divergences': divergences,
  };
}

class _Comparison {
  _Comparison(this.row, this.metrics, this.profileMetrics);
  final Map<String, dynamic> row;
  final Map<String, int> metrics;
  final Map<String, int> profileMetrics;
  bool hasOutcomeError = false;
  List<String> get defects => row['defects'] as List<String>;
  List<String> get unavailable => row['unavailable'] as List<String>;
  void count(String key, [int amount = 1]) {
    metrics[key] = metrics[key]! + amount;
    profileMetrics[key] = profileMetrics[key]! + amount;
  }

  void defect(String field, String metric) {
    defects.add(field);
    count(metric);
  }

  bool available(Map<String, dynamic> actual, String field, {String? path}) {
    _keys(actual, [field], 'result');
    if (actual[field] != null) return true;
    unavailable.add(path ?? field);
    return false;
  }

  Map<String, dynamic>? outcome(
    Map<String, dynamic> result, {
    bool host = false,
    String prefix = '',
  }) {
    if (!available(result, 'outcome', path: '${prefix}outcome')) return null;
    final value = _object(result['outcome'], 'result.outcome');
    _keys(value, ['disposition', 'item_id'], 'outcome');
    _choice(value['disposition'], [
      host ? 'accepted' : 'recognized',
      'rejected',
      'abstained',
      'error',
    ], 'outcome.disposition');
    if (value['disposition'] == (host ? 'accepted' : 'recognized')) {
      if (!available(value, 'item_id', path: '${prefix}outcome.item_id')) {
        return null;
      }
      _text(value['item_id'], 'outcome.item_id');
    } else if (value['item_id'] != null) {
      _invalid(
        'Rejected/abstained/error outcome cannot select an item identity',
      );
    }
    if (value['disposition'] == 'abstained') count('abstentions');
    if (value['disposition'] == 'error') {
      count('outcome_errors');
      hasOutcomeError = true;
      unavailable.add('${prefix}outcome_error');
    }
    return value;
  }

  bool identity(
    Map<String, dynamic> truth,
    Map<String, dynamic> result, {
    bool host = false,
    String prefix = '',
    bool creditCorrect = true,
  }) {
    final observedOutcome = outcome(result, host: host, prefix: prefix);
    if (observedOutcome == null) return false;
    final positive = truth['label'] == 'readable_positive';
    final selected =
        observedOutcome['disposition'] == (host ? 'accepted' : 'recognized');
    if (selected) {
      if (host) count('host_accepted_identities');
      if (positive && observedOutcome['item_id'] == truth['item_id']) {
        if (creditCorrect) count('correct_positive_ids');
      } else {
        defect(
          '${prefix}identity',
          positive
              ? 'wrong_positive_ids'
              : host
              ? 'accepted_negatives'
              : 'recognized_negatives',
        );
        count('wrong_identities');
      }
    } else if (positive && observedOutcome['disposition'] != 'error') {
      defect('${prefix}readable_positive_miss', 'readable_positive_misses');
    }
    return selected;
  }

  void inspection(Map<String, dynamic> truth, Map<String, dynamic> actual) {
    final selected = identity(truth, actual);
    _keys(actual, ['title_roi'], 'result');
    if (truth['title_roi'] == null) {
      if (actual['title_roi'] != null) {
        _point(actual['title_roi'], 'result.title_roi', rectangle: true);
        defect('unexpected_title_roi', 'geometry_mismatches');
      }
    } else if (available(actual, 'title_roi')) {
      _point(actual['title_roi'], 'result.title_roi', rectangle: true);
      if (!_near(
        truth['title_roi'] as Map<String, dynamic>,
        actual['title_roi'] as Map<String, dynamic>,
        ['x', 'y', 'width', 'height'],
        truth['geometry_tolerance'] as num,
      )) {
        defect('title_roi', 'geometry_mismatches');
      }
    }
    diagnostics(actual);
    if (selected && actual['marker'] == null) unavailable.add('marker');
  }

  void diagnostics(Map<String, dynamic> actual) {
    _keys(actual, ['marker', 'ocr_text', 'candidates'], 'engine result');
    if (actual['marker'] != null) {
      final marker = _object(actual['marker'], 'marker');
      for (final key in ['x', 'y', 'score']) {
        _number(marker[key], 'marker.$key');
      }
    }
    if (actual['ocr_text'] != null && actual['ocr_text'] is! String) {
      _invalid('ocr_text must be text or null with reason');
    }
    if (actual['candidates'] != null) {
      _array(actual['candidates'], 'candidates');
    }
  }

  void multi(Map<String, dynamic> truth, Map<String, dynamic> actual) {
    for (final field in ['unmatched', 'duplicates']) {
      if (available(actual, field) && _array(actual[field], field).isNotEmpty) {
        defects.add('reference_reported_$field');
      }
    }
    if (!available(actual, 'detections')) return;
    final expected = (truth['inspections'] as List)
        .cast<Map<String, dynamic>>();
    final assignments = {
      for (final inspection in expected)
        inspection['id'] as String: <Map<String, dynamic>>[],
    };
    final unmatched = <String>[];
    final seen = <String>{};
    for (final value in _array(actual['detections'], 'detections')) {
      final detection = _object(value, 'detection');
      final id = _text(detection['id'], 'detection.id');
      if (!seen.add(id)) {
        _invalid(
          'Detection IDs must be unique; geometric duplicate detections retain distinct IDs',
        );
      }
      _keys(detection, ['outcome'], 'detection');
      diagnostics(detection);
      if (!available(detection, 'title_roi', path: '$id.title_roi')) {
        outcome(detection, prefix: '$id.');
        unmatched.add(id);
        continue;
      }
      _point(detection['title_roi'], 'detection.title_roi', rectangle: true);
      final matches = expected
          .where(
            (inspection) => _near(
              inspection['title_roi'] as Map<String, dynamic>,
              detection['title_roi'] as Map<String, dynamic>,
              ['x', 'y', 'width', 'height'],
              truth['geometry_tolerance'] as num,
            ),
          )
          .toList();
      if (matches.length != 1) {
        final observedOutcome = outcome(detection, prefix: '$id.');
        if (matches.isEmpty &&
            observedOutcome?['disposition'] == 'recognized') {
          defect(
            '$id.extra_false_positive_selection',
            'extra_false_positive_selections',
          );
          count('wrong_identities');
        }
        unmatched.add(id);
      } else {
        assignments[matches.single['id']]!.add(detection);
      }
    }
    row['unmatched_detection_ids'] = unmatched;
    if (unmatched.isNotEmpty) {
      defects.add('unmatched_detections');
      count('unmatched_detections', unmatched.length);
    }
    row['associations'] = [
      for (final inspection in expected)
        {
          'inspection_id': inspection['id'],
          'detection_ids':
              assignments[inspection['id']]!
                  .map((detection) => detection['id'])
                  .toList()
                ..sort(),
        },
    ];
    for (final inspection in expected) {
      final matches = assignments[inspection['id']]!;
      if (matches.isEmpty) {
        defect('${inspection['id']}.missing_detection', 'missing_detections');
        if (inspection['label'] == 'readable_positive') {
          count('readable_positive_misses');
        }
      } else {
        if (matches.length > 1) {
          defects.add('${inspection['id']}.duplicate_detections');
          count('duplicate_detections', matches.length - 1);
        }
        for (final detection in matches) {
          final selected = identity(
            inspection,
            detection,
            prefix: '${inspection['id']}/${detection['id']}.',
            creditCorrect: matches.length == 1,
          );
          if (selected && detection['marker'] == null) {
            unavailable.add('${detection['id']}.marker');
          }
        }
      }
    }
  }

  void host(
    Map<String, dynamic> truth,
    Map<String, dynamic> actual,
    List<Map<String, dynamic>> divergences,
  ) {
    final accepted = identity(truth, actual, host: true);
    final policy = truth['target_policy'] as Map<String, dynamic>;
    if (available(actual, 'target_policy_id') &&
        actual['target_policy_id'] != policy['id']) {
      _invalid(
        'Host result target_policy_id differs from independent policy basis',
      );
    }
    var complete = true;
    for (final field in ['selected_evidence_ids', 'snapshot_ids', 'reasons']) {
      if (available(actual, field)) {
        _texts(actual[field], 'host.$field');
        if (accepted && (actual[field] as List).isEmpty) {
          unavailable.add(field);
          complete = false;
        }
      } else {
        complete = false;
      }
    }
    if (available(actual, 'facts')) {
      _object(actual['facts'], 'host.facts');
    } else {
      complete = false;
    }
    _keys(actual, ['decision'], 'host');
    if (actual['decision'] == null) {
      if (accepted || policy['decision'] != null) {
        available(actual, 'decision');
        return;
      }
    } else {
      _choice(actual['decision'], _decisions, 'host.decision');
      if (accepted && complete && actual['target_policy_id'] != null) {
        count('actionable_advice');
      }
    }
    if (actual['decision'] != policy['decision']) {
      if (policy['intentional_divergence'] == true) {
        divergences.add({
          'case_id': row['case_id'],
          'kind': 'intentional_target_policy',
          'expected_policy': policy,
          'reference': actual,
          'rationale': policy['rationale'],
        });
      } else {
        defect('target_policy.decision', 'policy_mismatches');
      }
    }
  }

  void geometry(Map<String, dynamic> truth, Map<String, dynamic> actual) {
    final tolerances = truth['tolerances'] as Map<String, dynamic>;
    for (final field in ['frame_revision', 'floor_group_id']) {
      if (available(actual, field)) {
        if (field == 'frame_revision') {
          _number(actual[field], 'result.frame_revision');
        } else {
          _text(actual[field], 'result.floor_group_id');
        }
        if (actual[field] != truth[field]) defect(field, 'geometry_mismatches');
      }
    }
    for (final field in ['artwork_pixel', 'normalized']) {
      if (available(actual, field)) {
        _point(actual[field], 'result.$field');
        if (!_near(
          truth[field] as Map<String, dynamic>,
          actual[field] as Map<String, dynamic>,
          ['x', 'y'],
          tolerances[field] as num,
        )) {
          defect(field, 'geometry_mismatches');
        }
      }
    }
    if (available(actual, 'game_xyz')) {
      _xyz(actual['game_xyz'], 'result.game_xyz');
      final expected = truth['game_xyz'] as Map<String, dynamic>;
      final observed = actual['game_xyz'] as Map<String, dynamic>;
      if (!_near(expected, observed, [
        'x',
        'z',
      ], tolerances['game_xyz'] as num)) {
        defect('game_xyz.xz', 'geometry_mismatches');
      }
      if (expected['y'] == null || observed['y'] == null) {
        if (expected['y'] != observed['y']) {
          defect('game_xyz.y', 'geometry_mismatches');
          if (observed['y'] == null) unavailable.add('game_xyz.y');
        }
      } else if (((expected['y'] as num) - (observed['y'] as num)).abs() >
          (tolerances['game_xyz'] as num)) {
        defect('game_xyz.y', 'geometry_mismatches');
      }
    }
    if (available(actual, 'heading')) {
      _heading(actual['heading'], 'result.heading');
      final expected = truth['heading'] as Map<String, dynamic>;
      final observed = actual['heading'] as Map<String, dynamic>;
      final raw =
          ((expected['degrees'] as num) - (observed['degrees'] as num)).abs() %
          360;
      final distance = raw > 180 ? 360 - raw : raw;
      if (expected['convention'] != observed['convention'] ||
          distance > (tolerances['heading'] as num)) {
        defect('heading', 'geometry_mismatches');
      }
    }
  }

  void panel(Map<String, dynamic> truth, Map<String, dynamic> actual) {
    if (available(actual, 'map_id')) {
      _text(actual['map_id'], 'panel.map_id');
      if (actual['map_id'] != truth['map_id']) {
        defect('map_id', 'panel_mismatches');
      }
    }
    if (available(actual, 'disposition')) {
      _choice(actual['disposition'], _panelDispositions, 'panel.disposition');
      if (actual['disposition'] != truth['disposition']) {
        defect('disposition', 'panel_mismatches');
      }
    }
    for (final field in ['extract_text', 'transit_text']) {
      _keys(actual, [field], 'panel');
      if (actual[field] != null && actual[field] is! String) {
        _invalid('panel.$field must be text or null with reason');
      }
      if (truth[field] != null) {
        if (available(actual, field) && actual[field] != truth[field]) {
          defect(field, 'panel_mismatches');
        }
      }
    }
    if (available(actual, 'matched_ids')) {
      final ids = _texts(actual['matched_ids'], 'panel.matched_ids');
      final expected = (truth['matched_ids'] as List).cast<String>().toSet();
      final inconsistent =
          (actual['disposition'] == 'matched' && ids.isEmpty) ||
          ([
                'absent',
                'present_empty',
                'no_match',
                'unreadable',
              ].contains(actual['disposition']) &&
              ids.isNotEmpty);
      if (inconsistent ||
          ids.length != expected.length ||
          !ids.toSet().containsAll(expected)) {
        defect('matched_ids', 'panel_mismatches');
      }
    }
    _keys(actual, ['ocr_spans'], 'panel');
    if (actual['ocr_spans'] != null) {
      _array(actual['ocr_spans'], 'panel.ocr_spans');
    }
  }
}
