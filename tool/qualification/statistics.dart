import 'contracts.dart';

/// Nearest rank: sorted sample ceil(quantile * N), using a one-based rank.
/// Empty observations return null, never a fabricated zero duration.
num? nearestRankQuantile(List<num> samples, {double quantile = 0.95}) {
  if (!quantile.isFinite || quantile <= 0 || quantile > 1) {
    throw const ContractException('Quantile must be in (0, 1]');
  }
  if (samples.any((value) => !value.isFinite)) {
    throw const ContractException('Quantiles require finite observations');
  }
  if (samples.isEmpty) return null;
  final ordered = List<num>.of(samples)..sort();
  return ordered[(quantile * ordered.length).ceil() - 1];
}

const _timelineStages = [
  'queue',
  'capture',
  'targeted',
  'fallback_work',
  'host_match',
  'host_decision',
  'acceptance',
  'publication',
  'ui_assignment',
];

/// Summarizes serialized evidence only; this function performs no collection.
///
/// U1 stage rows remain {name, start_tick, end_tick}. Their implicit QPC
/// timestamps inherit attempt.qpc_frequency and attempt.clock_domain. An
/// expanded stage supplies BOTH start/end: {tick, frequency, domain, name};
/// their ticks must equal the raw stage ticks. All timestamps must share the
/// attempt's QPC frequency/domain. Optional qpc_events is an array of these
/// timestamp objects, including fallback_start and fallback_deadline. It records
/// event boundaries, not visible observations. A fallback_work stage or an
/// actual fallback_start event establishes worker start; a deadline does not.
///
/// trigger/endpoint/fallback_endpoint video objects are:
/// {type:'video', name, recording_id, clock_domain, lower_ms, upper_ms,
///  request_id, generation, ordinal, case_id, observable, linkage_valid}.
/// trigger.name is physical_actuation; endpoint.name is actionable_visible,
/// with visibility:'visible', correctness:'identified_correct'. Only terminal
/// outcome 'correct' is an actionable identity sample (an honest Check may be
/// correct; a rejection is not). fallback_endpoint.name is fallback_visible,
/// with visibility:'visible', phase:'fallback_running'. It measures genuine
/// visible running fallback, not its eventual identity/result, and additionally
/// requires actual worker-start evidence for the same attempt. It may exist on
/// rejected/error/canceled attempts. No video/QPC subtraction is performed.
/// Video pairs must share recording_id AND clock_domain. Request/generation,
/// ordinal and case linkage must match; occluded or incorrect annotations remain
/// missing samples. UI assignment/publication can never substitute for video.
///
/// Strata: bundle.environment_id and attempt warm_state, profile, evidence_mode,
/// display_cell (including resolution/scaling), acquisition_class, intended_path,
/// actual_path, terminal_outcome, trigger_kind. Unavailable additive fields are explicit null
/// plus reason, not inferred settings. No pooled route/environment quantile is
/// emitted. master_case_id and source_id count unique coverage; case variants
/// and replays do not increase these counts. Outcome categories are retained.
///
/// Optional bundle.targets_ms maps metric/stage names to nonnegative targets;
/// interval crossing is indeterminate. Missing targets never produce a pass.
/// external_data_age_ms is a number, null+reason, or {status,reason}; status is
/// absent/future/unsupported, or measured with age_ms. Negative numbers are
/// future times, not fresh data. All original age values and reasons survive.
Map<String, dynamic> summarizeAttempts(Map<String, dynamic> bundle) {
  validateRecord(bundle);
  if (bundle['record_type'] != 'attempt_bundle') {
    throw const ContractException('Statistics require an attempt_bundle');
  }
  final targets = _targets(bundle['targets_ms']);
  final rows = (bundle['attempts'] as List).cast<Map<String, dynamic>>();
  final stageNames = <String>{..._timelineStages};
  final parsed = <Map<String, dynamic>>[];
  final groups = <String, List<Map<String, dynamic>>>{};
  final strata = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    final stages = _stageDurations(row);
    stageNames.addAll(stages.keys);
    stageNames.addAll(
      (row['missing_stage_reasons'] as Map<String, dynamic>).keys,
    );
    final events = _qpcEvents(row);
    final actionable = _videoInterval(
      row,
      'endpoint',
      'actionable_visible',
      eligible: row['terminal_outcome'] == 'correct',
    );
    final fallback = _videoInterval(
      row,
      'fallback_endpoint',
      'fallback_visible',
      eligible:
          stages.containsKey('fallback_work') ||
          events.any((event) => event['name'] == 'fallback_start'),
    );
    final item = <String, dynamic>{
      'row': row,
      'stages': stages,
      'qpc_events': events,
      'actionable': actionable,
      'fallback': fallback,
    };
    parsed.add(item);
    final cell = <String, dynamic>{'environment_id': bundle['environment_id']};
    for (final name in [
      'warm_state',
      'profile',
      'evidence_mode',
      'display_cell',
      'acquisition_class',
      'intended_path',
      'actual_path',
      'terminal_outcome',
      'trigger_kind',
    ]) {
      cell[name] = row[name];
      if (row[name] == null) {
        cell['${name}_reason'] =
            row['${name}_reason'] ?? 'Not recorded in the attempt bundle.';
      }
    }
    final key = canonicalJson(cell);
    strata[key] = cell;
    groups.putIfAbsent(key, () => []).add(item);
  }
  final orderedStages = stageNames.toList()..sort();
  final keys = groups.keys.toList()..sort();
  final cells = <Map<String, dynamic>>[];
  for (final key in keys) {
    final items = groups[key]!;
    final attempts = items
        .map((item) => item['row'] as Map<String, dynamic>)
        .toList();
    cells.add({
      'stratum': strata[key],
      'attempt_n': items.length,
      'attempt_ids': attempts.map((row) => row['id']).toList(),
      'outcome_counts': _counts(
        attempts.map((row) => row['terminal_outcome'] as String),
      ),
      'coverage': _coverage(attempts),
      'internal_stages': {
        for (final name in orderedStages)
          name: _stageMetric(items, name, targets[name]),
      },
      'physical_to_actionable_visible': _videoMetric(
        items,
        'actionable',
        targets['physical_to_actionable_visible'],
      ),
      'physical_to_fallback_visible': _videoMetric(
        items,
        'fallback',
        targets['physical_to_fallback_visible'],
      ),
      'external_data_ages': _ages(attempts),
    });
  }
  final actionableN = parsed
      .where((item) => item['actionable']['interval'] != null)
      .length;
  final collectionStatus = bundle['collection_status'];
  final result = <String, dynamic>{
    'schema_version': 1,
    'record_type': 'baseline_summary',
    'id': '${bundle['id']}-summary',
    'attempt_bundle_id': bundle['id'],
    'attempt_bundle_sha256': sha256Json(bundle),
    'freeze_id': bundle['freeze_id'],
    'run_id': bundle['run_id'],
    'environment_id': bundle['environment_id'],
    'quantile_method': 'nearest_rank',
    'quantile': 0.95,
    'status':
        actionableN == 0 ||
            collectionStatus == 'skipped' ||
            collectionStatus == 'unattempted'
        ? 'incomplete'
        : 'descriptive',
    'visible_evidence_status': actionableN == 0 ? 'unverified' : 'observed',
    'attempt_n': rows.length,
    'attempt_ids': rows.map((row) => row['id']).toList(),
    'outcome_counts': _counts(
      rows.map((row) => row['terminal_outcome'] as String),
    ),
    'actionable_sample_n': actionableN,
    'fallback_visible_sample_n': parsed
        .where((item) => item['fallback']['interval'] != null)
        .length,
    'coverage': _coverage(rows),
    'external_data_ages': _ages(rows),
    'strata': cells,
    'attempt_summaries': [for (final item in parsed) _attemptSummary(item)],
    'collection_status': collectionStatus,
  };
  if (collectionStatus == null) {
    result['collection_status_reason'] =
        bundle['collection_status_reason'] ??
        'No collection disposition was recorded.';
  }
  if (bundle.containsKey('collection_rationale')) {
    result['collection_rationale'] = bundle['collection_rationale'];
  }
  return result;
}

Map<String, num> _targets(Object? value) {
  if (value == null) return {};
  if (value is! Map<String, dynamic>) {
    throw const ContractException('targets_ms must be an object');
  }
  return value.map((key, target) {
    if (target is! num || !target.isFinite || target < 0) {
      throw ContractException('Target $key must be finite and nonnegative');
    }
    return MapEntry(key, target);
  });
}

void _qpc(Map<String, dynamic> stamp, Map<String, dynamic> row) {
  if (stamp['tick'] is! int ||
      (stamp['tick'] as int) < 0 ||
      stamp['frequency'] is! int ||
      (stamp['frequency'] as int) <= 0 ||
      stamp['name'] is! String ||
      (stamp['name'] as String).trim().isEmpty ||
      stamp['domain'] != row['clock_domain'] ||
      stamp['frequency'] != row['qpc_frequency']) {
    throw const ContractException(
      'QPC timestamp requires matching tick/frequency/domain/name',
    );
  }
}

List<Map<String, dynamic>> _qpcEvents(Map<String, dynamic> row) {
  final value = row['qpc_events'];
  if (value == null) return [];
  if (value is! List) {
    throw const ContractException('qpc_events must be an array');
  }
  final events = <Map<String, dynamic>>[];
  final names = <String>{};
  for (final event in value) {
    if (event is! Map<String, dynamic>) {
      throw const ContractException('QPC event must be an object');
    }
    _qpc(event, row);
    if (!names.add(event['name'] as String)) {
      throw const ContractException('Duplicate QPC event name');
    }
    events.add(Map<String, dynamic>.from(event));
  }
  return events;
}

Map<String, num> _stageDurations(Map<String, dynamic> row) {
  final durations = <String, num>{};
  for (final stage in row['stages'] as List) {
    final name = stage['name'] as String;
    if (durations.containsKey(name)) {
      throw const ContractException('Duplicate stage name in an attempt');
    }
    if (stage.containsKey('start') || stage.containsKey('end')) {
      for (final side in ['start', 'end']) {
        final stamp = stage[side];
        if (stamp is! Map<String, dynamic>) {
          throw const ContractException(
            'Expanded QPC stages require both timestamps',
          );
        }
        _qpc(stamp, row);
        if (stamp['tick'] != stage['${side}_tick']) {
          throw const ContractException(
            'QPC timestamp differs from raw stage tick',
          );
        }
      }
    }
    durations[name] =
        ((stage['end_tick'] as int) - (stage['start_tick'] as int)) *
        1000 /
        (row['qpc_frequency'] as int);
  }
  return durations;
}

Map<String, dynamic> _videoInterval(
  Map<String, dynamic> row,
  String field,
  String endpointName, {
  required bool eligible,
}) {
  Map<String, dynamic> missing(String reason) => {
    'interval': null,
    'interval_reason': reason,
  };
  final trigger = row['trigger'];
  final endpoint = row[field];
  if (trigger == null || endpoint == null) {
    return missing(
      row['${field}_reason'] as String? ??
          row['trigger_reason'] as String? ??
          'No observed $endpointName endpoint.',
    );
  }
  if (trigger is! Map<String, dynamic> || endpoint is! Map<String, dynamic>) {
    throw const ContractException('Video trigger and endpoint must be objects');
  }
  if (trigger['type'] != 'video' || endpoint['type'] != 'video') {
    throw const ContractException(
      'Uncalibrated video/QPC subtraction is forbidden',
    );
  }
  for (final value in [trigger, endpoint]) {
    for (final name in ['recording_id', 'clock_domain', 'name']) {
      if (value[name] is! String || (value[name] as String).trim().isEmpty) {
        throw ContractException('Video $name must be nonempty');
      }
    }
    for (final bound in ['lower_ms', 'upper_ms']) {
      if (value[bound] is! num ||
          !(value[bound] as num).isFinite ||
          (value[bound] as num) < 0) {
        throw ContractException('Video $bound must be finite and nonnegative');
      }
    }
    if ((value['lower_ms'] as num) > (value['upper_ms'] as num)) {
      throw const ContractException('Video frame interval runs backwards');
    }
  }
  if (trigger['recording_id'] != endpoint['recording_id'] ||
      trigger['clock_domain'] != endpoint['clock_domain']) {
    throw const ContractException(
      'Video interval requires the same recording and clock',
    );
  }
  if (trigger['name'] != 'physical_actuation' ||
      endpoint['name'] != endpointName) {
    return missing(
      'Not the required physical actuation/$endpointName boundary.',
    );
  }
  for (final value in [trigger, endpoint]) {
    if (value['observable'] != true || value['linkage_valid'] != true) {
      return missing('Boundary is unobservable or linkage is invalid.');
    }
    if (value['ordinal'] is! int || value['ordinal'] != row['ordinal']) {
      return missing('Boundary ordinal does not identify this attempt.');
    }
    for (final name in ['request_id', 'generation', 'case_id']) {
      if (row[name] is! String || value[name] != row[name]) {
        return missing('Boundary $name does not identify this attempt.');
      }
    }
  }
  if (endpoint['visibility'] != 'visible') {
    return missing('Endpoint is not observed visible.');
  }
  if (field == 'endpoint' && endpoint['correctness'] != 'identified_correct') {
    return missing(
      'Endpoint does not identify the independently correct item.',
    );
  }
  if (field == 'fallback_endpoint' && endpoint['phase'] != 'fallback_running') {
    return missing('Endpoint does not observe a running fallback phase.');
  }
  if (!eligible) {
    return missing(
      field == 'endpoint'
          ? 'Terminal outcome is not a correct actionable identity.'
          : 'No actual fallback worker-start evidence; a deadline/label is insufficient.',
    );
  }
  final lower = (endpoint['lower_ms'] as num) - (trigger['upper_ms'] as num);
  final upper = (endpoint['upper_ms'] as num) - (trigger['lower_ms'] as num);
  if (upper < 0) {
    throw const ContractException(
      'Visible endpoint precedes physical actuation',
    );
  }
  // Overlapping frame uncertainty gives a physically nonnegative lower bound,
  // not a measured zero; its upper bound and annotation uncertainty survive.
  return {
    'interval': {'lower_ms': lower < 0 ? 0 : lower, 'upper_ms': upper},
  };
}

Map<String, int> _counts(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

Map<String, dynamic> _scalarMetric(
  List<num> values,
  int denominator,
  Map<String, int> missing,
  num? target,
) {
  final p95 = nearestRankQuantile(values);
  return {
    'n': values.length,
    'missing_n': denominator - values.length,
    'missing_reasons': missing,
    'p95_ms': p95,
    if (p95 == null) 'p95_ms_reason': 'No eligible observations.',
    ..._threshold(p95, p95, target),
  };
}

Map<String, dynamic> _threshold(num? lower, num? upper, num? target) => {
  'target_ms': target,
  if (target == null) 'target_ms_reason': 'No performance target was supplied.',
  'threshold_status': lower == null || upper == null || target == null
      ? 'unverified'
      : upper <= target
      ? 'pass'
      : lower > target
      ? 'fail'
      : 'indeterminate',
};

Map<String, dynamic> _stageMetric(
  List<Map<String, dynamic>> items,
  String name,
  num? target,
) {
  final values = <num>[];
  final reasons = <String>[];
  for (final item in items) {
    final value = item['stages'][name];
    if (value != null) {
      values.add(value as num);
    } else {
      reasons.add(
        item['row']['missing_stage_reasons'][name] as String? ??
            'Stage was not recorded.',
      );
    }
  }
  return _scalarMetric(values, items.length, _counts(reasons), target);
}

Map<String, dynamic> _videoMetric(
  List<Map<String, dynamic>> items,
  String key,
  num? target,
) {
  final lower = <num>[];
  final upper = <num>[];
  final reasons = <String>[];
  for (final item in items) {
    final metric = item[key];
    if (metric['interval'] == null) {
      reasons.add(metric['interval_reason'] as String);
    } else {
      lower.add(metric['interval']['lower_ms'] as num);
      upper.add(metric['interval']['upper_ms'] as num);
    }
  }
  final lower95 = nearestRankQuantile(lower);
  final upper95 = nearestRankQuantile(upper);
  return {
    'n': lower.length,
    'missing_n': items.length - lower.length,
    'missing_reasons': _counts(reasons),
    'p95_lower_ms': lower95,
    'p95_upper_ms': upper95,
    if (lower95 == null) 'p95_lower_ms_reason': 'No eligible observations.',
    if (upper95 == null) 'p95_upper_ms_reason': 'No eligible observations.',
    ..._threshold(lower95, upper95, target),
  };
}

Map<String, dynamic> _coverage(List<Map<String, dynamic>> rows) {
  final masters = <String>{};
  final sources = <String>{};
  final byOutcome = <String, Set<String>>{};
  var missingMaster = 0;
  var missingSource = 0;
  for (final row in rows) {
    final master = row['master_case_id'];
    final source = row['source_id'];
    if (master is String && master.trim().isNotEmpty) {
      masters.add(master);
      byOutcome
          .putIfAbsent(row['terminal_outcome'] as String, () => <String>{})
          .add(master);
    } else {
      missingMaster++;
    }
    if (source is String && source.trim().isNotEmpty) {
      sources.add(source);
    } else {
      missingSource++;
    }
  }
  return {
    'unique_master_n': masters.length, 'unique_source_n': sources.length,
    'master_ids': masters.toList()..sort(),
    'source_ids': sources.toList()..sort(),
    'missing_master_id_n': missingMaster, 'missing_source_id_n': missingSource,
    // A master can have multiple observed outcomes; these counts are not a
    // disjoint accuracy denominator and do not erase repeated disagreements.
    'unique_master_outcome_counts': byOutcome.map(
      (key, value) => MapEntry(key, value.length),
    ),
  };
}

Map<String, dynamic> _ages(List<Map<String, dynamic>> rows) {
  final observations = <Map<String, dynamic>>[];
  final measured = <num>[];
  final counts = <String, int>{
    'measured': 0,
    'absent': 0,
    'future': 0,
    'unsupported': 0,
  };
  for (final row in rows) {
    final value = row['external_data_age_ms'];
    String status;
    num? age;
    String? reason;
    if (value == null) {
      status = 'absent';
      reason = row['external_data_age_ms_reason'] as String;
    } else if (value is num) {
      status = value < 0 ? 'future' : 'measured';
      age = value;
    } else if (value is Map<String, dynamic> &&
        [
          'measured',
          'absent',
          'future',
          'unsupported',
        ].contains(value['status'])) {
      status = value['status'] as String;
      if (status == 'measured') {
        if (value['age_ms'] is! num || (value['age_ms'] as num) < 0) {
          throw const ContractException(
            'Measured external age requires nonnegative age_ms',
          );
        }
        age = value['age_ms'] as num;
      } else {
        if (value['reason'] is! String ||
            (value['reason'] as String).trim().isEmpty) {
          throw const ContractException(
            'Unavailable external age requires a reason',
          );
        }
        reason = value['reason'] as String;
      }
    } else {
      status = 'unsupported';
      reason = 'External age representation is unsupported.';
    }
    counts[status] = counts[status]! + 1;
    if (status == 'measured') measured.add(age!);
    observations.add({
      'attempt_id': row['id'],
      'status': status,
      'value': value,
      if (value == null) 'value_reason': reason,
      'detail': ?reason,
    });
  }
  return {
    'counts': counts,
    'observations': observations,
    'measured_ms': _scalarMetric(measured, rows.length, {
      for (final entry in counts.entries)
        if (entry.key != 'measured' && entry.value > 0) entry.key: entry.value,
    }, null),
  };
}

Map<String, dynamic> _attemptSummary(Map<String, dynamic> item) {
  final row = item['row'] as Map<String, dynamic>;
  return {
    'id': row['id'],
    'request_id': row['request_id'],
    'generation': row['generation'],
    'ordinal': row['ordinal'],
    'terminal_outcome': row['terminal_outcome'],
    'actual_path': row['actual_path'],
    'internal_stage_ms': item['stages'],
    'qpc_events': item['qpc_events'],
    'physical_to_actionable_visible': item['actionable'],
    'physical_to_fallback_visible': item['fallback'],
    'missing_stage_reasons': row['missing_stage_reasons'],
  };
}
