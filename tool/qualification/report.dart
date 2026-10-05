import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'compare.dart';
import 'contracts.dart';
import 'export.dart';
import 'statistics.dart';

const _requiredRecords = [
  'provenance',
  'fixture_manifest',
  'map_controls',
  'display_matrix',
  'planned_checks',
  'environment',
];
const _metadataArtifacts = {
  'source_intake': 'm0-reference-intake-metadata',
  'source_lock': 'm0-reference-intake-metadata',
  'provenance': 'm0-provenance-metadata',
  'fixture_manifest': 'm0-original-synthetic-fixtures',
  'map_controls': 'm0-original-synthetic-fixtures',
  'display_matrix': 'm0-display-matrix-metadata',
  'planned_checks': 'm0-planned-checks-metadata',
  'environment': 'm0-setup-metadata',
};
const _reportArtifact = 'm0-authored-report-metadata';
const _maps = [
  'factory',
  'customs',
  'woods',
  'shoreline',
  'interchange',
  'lab',
  'reserve',
  'lighthouse',
  'streetsoftarkov',
  'groundzero',
  'terminal',
  'icebreaker',
  'labyrinth',
];
const _resolutions = [
  [1920, 1080],
  [2560, 1440],
  [3440, 1440],
  [3840, 2160],
];
const _scales = [100, 125, 150, 200];
const _masterSlots = [
  'ordinary-positive-a',
  'ordinary-positive-b',
  'quantity-positive-a',
  'quantity-positive-b',
  'empty-no-marker',
  'ui-chrome',
  'ambiguous',
  'occluded',
  'multi',
];
const _variantKinds = ['positive', 'no-marker', 'chrome-ambiguous', 'multi'];
const _semanticAreas = [
  'catalog',
  'projection',
  'advice',
  'lifecycle',
  'epochs',
  'late-completions',
  'targeted',
  'authority',
  'instance',
  'session-inputs',
  'aliases',
  'map',
  'persistence',
];

Never _invalid(String message) => throw ContractException(message);
List<Map<String, dynamic>> _rows(Object? value) =>
    (value as List).cast<Map<String, dynamic>>();
String _version(Map<String, dynamic> value) =>
    (value['corpus_version'] ??
            value['annotation_version'] ??
            value['schema_version'])
        .toString();

Map<String, dynamic> _gate(
  String id,
  String status,
  String owner,
  String reason,
  List<String> evidence, {
  bool required = true,
}) => {
  'id': id,
  'required': required,
  'status': status,
  'owner': owner,
  'evidence_ids': evidence,
  'reason': reason,
};

bool _reviewed(Map<String, dynamic> row) {
  final review = row['review'];
  return row['truth'] is Map &&
      row['truth']['independent_of_reference_output'] == true &&
      review is Map &&
      ['accepted', 'reviewed', 'adjudicated'].contains(review['status']) &&
      (row['adjudication_ids'] as List).toSet().length >= 2;
}

bool _realMaster(Map<String, dynamic> row) {
  if (row['data_class'] == 'synthetic' ||
      row['role'] == 'expectation_only' ||
      row['acquisition'] != 'actual' ||
      row.containsKey('parent_id') ||
      !_masterSlots.contains(row['master_slot']) ||
      !_reviewed(row)) {
    return false;
  }
  final slot = row['master_slot'] as String;
  final truth = row['truth'] as Map;
  if (slot == 'multi') {
    final inspections = truth['inspections'];
    return row['profile'] == 'engine_multi' &&
        inspections is List &&
        inspections.length >= 2 &&
        inspections.every(
          (inspection) =>
              inspection is Map &&
              inspection['item_id'] is String &&
              inspection['label'] == 'readable_positive',
        ) &&
        inspections.map((inspection) => inspection['id']).toSet().length ==
            inspections.length;
  }
  if (slot.contains('positive')) {
    return truth['label'] == 'readable_positive' && truth['item_id'] is String;
  }
  final label = switch (slot) {
    'empty-no-marker' => 'rejection',
    'ui-chrome' => 'chrome',
    'ambiguous' => 'ambiguous',
    _ => 'occluded',
  };
  return truth['label'] == label && truth['item_id'] == null;
}

bool _independentControl(Map<String, dynamic> row) =>
    row['data_class'] != 'synthetic' &&
    !['synthetic', 'derived'].contains(row['acquisition']) &&
    row['independent_of_reference_output'] == true &&
    (row['review_ids'] as List).toSet().length >= 2;

bool _noncollinear(List<Map<String, dynamic>> controls) {
  for (var a = 0; a < controls.length; a++) {
    for (var b = a + 1; b < controls.length; b++) {
      for (var c = b + 1; c < controls.length; c++) {
        final p = controls[a]['game_xyz'] as Map;
        final q = controls[b]['game_xyz'] as Map;
        final r = controls[c]['game_xyz'] as Map;
        final cross =
            ((q['x'] as num) - (p['x'] as num)) *
                ((r['z'] as num) - (p['z'] as num)) -
            ((q['z'] as num) - (p['z'] as num)) *
                ((r['x'] as num) - (p['x'] as num));
        if (cross.abs() > 1e-9) return true;
      }
    }
  }
  return false;
}

bool _inputHashKnown(
  Map<String, dynamic> source,
  String category,
  Object? hash,
) {
  final identities = source['effective_inputs'][category];
  return identities is List && identities.any((row) => row['sha256'] == hash);
}

bool _mapArtworkKnown(
  Map<String, dynamic> source,
  Map<String, dynamic> row,
  List<Map<String, dynamic>> roster,
  List<Map<String, dynamic>> checks,
) {
  final configured = roster
      .where(
        (map) =>
            map['map_id'] == row['map_id'] &&
            map['source_key'] == row['source_key'] &&
            map['frame_revision'] == row['frame_revision'],
      )
      .toList();
  if (configured.length != 1) return false;
  String? wantedPath = configured.single['artwork_path'] as String?;
  if (row['kind'] == 'floor_artwork') {
    if (!(configured.single['floor_group_ids'] as List).contains(
      row['floor_group_id'],
    )) {
      return false;
    }
    final imageChecks = checks
        .where(
          (check) =>
              check['scope'] == 'floor-artwork-anchor' &&
              check['map_id'] == row['map_id'] &&
              check['floor_group_id'] == row['floor_group_id'] &&
              check['image_path'] is String,
        )
        .toList();
    if (imageChecks.length == 1) {
      wantedPath = imageChecks.single['image_path'] as String;
    }
  }
  if (row.containsKey('kind') && row['artwork_path'] != wantedPath) {
    return false;
  }
  final identities = source['effective_inputs']['maps'];
  return wantedPath != null &&
      identities is List &&
      identities.any(
        (identity) =>
            identity['sha256'] == row['artwork_sha256'] &&
            (identity['path'] == wantedPath ||
                identity['locator'] == wantedPath),
      );
}

bool _independentAnchor(Map<String, dynamic> row) {
  if (row['data_class'] == 'synthetic' ||
      ['synthetic', 'derived'].contains(row['acquisition']) ||
      !_maps.contains(row['map_id']) ||
      row['source_key'] != row['map_id'] ||
      row['frame_revision'] != (row['map_id'] == 'lab' ? '1' : '0') ||
      !['floor_artwork', 'tile_seam', 'raster_extent'].contains(row['kind']) ||
      row['independent_of_reference_output'] != true ||
      row['source_ids'] is! List ||
      (row['source_ids'] as List).isEmpty ||
      row['review_ids'] is! List ||
      (row['review_ids'] as List).toSet().length < 2 ||
      row['width'] is! int ||
      row['height'] is! int ||
      row['width'] <= 0 ||
      row['height'] <= 0 ||
      row['uncertainty'] is! num ||
      !(row['uncertainty'] as num).isFinite ||
      row['uncertainty'] < 0 ||
      row['points'] is! List) {
    return false;
  }
  final points = row['points'] as List;
  if (points.length < (row['kind'] == 'floor_artwork' ? 1 : 2)) return false;
  if (row['kind'] == 'floor_artwork' && row['floor_group_id'] is! String) {
    return false;
  }
  return points.every(
    (point) =>
        point is Map &&
        point['x'] is num &&
        point['y'] is num &&
        (point['x'] as num).isFinite &&
        (point['y'] as num).isFinite &&
        point['x'] >= 0 &&
        point['x'] <= row['width'] &&
        point['y'] >= 0 &&
        point['y'] <= row['height'],
  );
}

bool _imageVariant(Map<String, dynamic> row, String kind) {
  if (row['role'] == 'expectation_only' ||
      row['variant_kind'] != kind ||
      !['actual', 'derived'].contains(row['acquisition']) ||
      !_reviewed(row)) {
    return false;
  }
  final truth = row['truth'] as Map;
  return switch (kind) {
    'positive' =>
      truth['label'] == 'readable_positive' && truth['item_id'] is String,
    'no-marker' => truth['label'] == 'rejection' && truth['item_id'] == null,
    'chrome-ambiguous' =>
      ['chrome', 'ambiguous'].contains(truth['label']) &&
          truth['item_id'] == null,
    'multi' =>
      row['profile'] == 'engine_multi' &&
          truth['inspections'] is List &&
          (truth['inspections'] as List).length >= 2,
    _ => false,
  };
}

String? _displayCellId(Object? value) {
  if (value is String &&
      _resolutions.any(
        (resolution) =>
            _scales.any((scale) => value == '${resolution[0]}-$scale'),
      )) {
    return value;
  }
  if (value is Map &&
      value['width'] is int &&
      value['height'] is int &&
      value['os_scale_percent'] is int &&
      _resolutions.any(
        (resolution) =>
            resolution[0] == value['width'] && resolution[1] == value['height'],
      ) &&
      _scales.contains(value['os_scale_percent'])) {
    return '${value['width']}-${value['os_scale_percent']}';
  }
  return null;
}

// Physical actuation is required even when a completed attempt has no correct
// endpoint. Structural timing errors are invalid evidence; honest missing or
// uncorrelated observations simply cannot complete the live allocation.
bool _physicalActuationObserved(Map<String, dynamic> row) {
  final trigger = row['trigger'];
  if (trigger == null) return false;
  if (trigger is! Map<String, dynamic> || trigger['type'] != 'video') {
    _invalid('Physical actuation requires an observed video boundary');
  }
  for (final key in ['recording_id', 'clock_domain', 'name']) {
    if (trigger[key] is! String || (trigger[key] as String).trim().isEmpty) {
      _invalid('Physical actuation $key must be nonempty');
    }
  }
  for (final key in ['lower_ms', 'upper_ms']) {
    final value = trigger[key];
    if (value is! num || !value.isFinite || value < 0) {
      _invalid('Physical actuation $key must be finite and nonnegative');
    }
  }
  if ((trigger['lower_ms'] as num) > (trigger['upper_ms'] as num)) {
    _invalid('Physical actuation frame interval runs backwards');
  }
  return trigger['name'] == 'physical_actuation' &&
      trigger['observable'] == true &&
      trigger['linkage_valid'] == true &&
      trigger['ordinal'] is int &&
      trigger['ordinal'] == row['ordinal'] &&
      [
        'request_id',
        'generation',
        'case_id',
      ].every((key) => row[key] is String && trigger[key] == row[key]);
}

bool _warmLivePathComplete(
  List<Map<String, dynamic>> rows,
  String path,
  Set<dynamic> physicalAttemptIds,
  Set<dynamic> visibleAttemptIds,
) {
  final pathRows = rows.where((row) => row['intended_path'] == path).toList();
  if (pathRows.length != 100 ||
      !pathRows.every(
        (row) =>
            row['stratum_id'] == path &&
            row['executor'] == 'user' &&
            row['evidence_mode'] == 'live_user' &&
            row['warm_state'] == 'warm' &&
            row['acquisition_class'] == 'actual' &&
            row['batch_ordinal'] is int &&
            physicalAttemptIds.contains(row['id']) &&
            (row['terminal_outcome'] == 'correct'
                ? visibleAttemptIds.contains(row['id'])
                : [
                    'wrong_id',
                    'rejected',
                    'error',
                    'canceled',
                    'superseded',
                  ].contains(row['terminal_outcome'])),
      )) {
    return false;
  }
  const batches = [
    {'automatic': 17, 'manual': 17},
    {'automatic': 17, 'manual': 16},
    {'automatic': 16, 'manual': 17},
  ];
  for (var index = 0; index < batches.length; index++) {
    for (final route in batches[index].entries) {
      if (pathRows
              .where(
                (row) =>
                    row['batch_ordinal'] == index + 1 &&
                    row['trigger_kind'] == route.key,
              )
              .length !=
          route.value) {
        return false;
      }
    }
  }
  return true;
}

const _setupFields = <String, List<String>>{
  'hardware': ['cpu', 'gpu', 'ram_bytes'],
  'windows': ['version', 'architecture'],
  'runtime': ['sdk'],
  'app_build': ['id', 'version'],
  'viewport': ['width', 'height', 'client_width', 'client_height', 'ui_scale'],
  'display': ['width', 'height', 'os_scale_percent', 'origin', 'topology'],
  'observer': ['method', 'recording_id', 'clock_domain', 'uncertainty_ms'],
};

bool _nativeSetupComplete(Map<String, dynamic> environment) =>
    _setupFields.entries.every(
      (entry) =>
          environment[entry.key] is Map &&
          entry.value.every((field) => environment[entry.key][field] != null),
    ) &&
    environment['display']['origin'] is Map &&
    [
      'x',
      'y',
    ].every((axis) => environment['display']['origin'][axis] != null) &&
    [
      'locale',
      'display_mode',
      'warm_state',
    ].every((key) => environment[key] != null);

bool _setupMatchesAttempt(
  Map<String, dynamic> environment,
  Map<String, dynamic> row,
) {
  var complete = true;
  for (final entry in {
    'display': row['display_cell'],
    'viewport': row['viewport'],
  }.entries) {
    final setup = environment[entry.key];
    final observed = entry.value;
    if (setup is! Map || observed is! Map) {
      complete = false;
      continue;
    }
    final fields = entry.key == 'display'
        ? ['width', 'height', 'os_scale_percent']
        : _setupFields['viewport']!;
    for (final field in fields) {
      if (setup[field] == null || observed[field] == null) {
        complete = false;
      } else if (setup[field] != observed[field]) {
        _invalid(
          'Attempt ${row['id']} conflicts with named setup ${entry.key}.$field',
        );
      }
    }
  }
  final setupDisplay = environment['display'];
  final observedDisplay = row['display_cell'];
  if (setupDisplay is Map && observedDisplay is Map) {
    for (final key in ['origin', 'topology']) {
      if (setupDisplay[key] != null &&
          observedDisplay[key] != null &&
          canonicalJson(setupDisplay[key]) !=
              canonicalJson(observedDisplay[key])) {
        _invalid('Attempt ${row['id']} conflicts with setup display.$key');
      }
    }
  }
  final observer = environment['observer'];
  if (observer is Map) {
    final attemptObserver = row['observer'];
    if (attemptObserver is! Map ||
        attemptObserver['method'] == null ||
        observer['method'] == null) {
      complete = false;
    } else if (attemptObserver['method'] != observer['method']) {
      _invalid('Attempt ${row['id']} conflicts with setup observer.method');
    }
    final measurements = row['measurements'];
    final stamps = [
      row['trigger'],
      row['endpoint'],
      if (measurements is Map)
        for (final key in ['startup', 'first_scan'])
          if (measurements[key] is Map) ...[
            measurements[key]['start'],
            measurements[key]['end'],
          ],
    ];
    for (final stamp in stamps) {
      if (stamp is! Map) continue;
      for (final field in ['recording_id', 'clock_domain']) {
        if (observer[field] == null || stamp[field] == null) {
          complete = false;
        } else if (observer[field] != stamp[field]) {
          _invalid('Attempt ${row['id']} conflicts with setup observer.$field');
        }
      }
    }
  }
  return complete;
}

bool _elapsedObservationComplete(
  Object? value,
  Map<String, dynamic> row,
  String startName,
  String endName,
) {
  if (value is! Map || value['start'] is! Map || value['end'] is! Map) {
    return false;
  }
  final start = value['start'] as Map;
  final end = value['end'] as Map;
  for (final stamp in [start, end]) {
    if (stamp['type'] != 'video' ||
        !['name', 'recording_id', 'clock_domain'].every(
          (key) =>
              stamp[key] is String && (stamp[key] as String).trim().isNotEmpty,
        ) ||
        stamp['observable'] != true ||
        stamp['linkage_valid'] != true ||
        ![
          'request_id',
          'generation',
          'ordinal',
          'case_id',
        ].every((key) => stamp[key] == row[key])) {
      return false;
    }
  }
  if (![
    start['lower_ms'],
    start['upper_ms'],
    end['lower_ms'],
    end['upper_ms'],
  ].every((bound) => bound is num)) {
    return false;
  }
  if (start['recording_id'] != end['recording_id'] ||
      start['clock_domain'] != end['clock_domain']) {
    _invalid('Elapsed observations must use one recording clock');
  }
  if ((end['upper_ms'] as num) < (start['lower_ms'] as num)) {
    _invalid('Elapsed observation boundaries run backwards');
  }
  return start['name'] == startName &&
      end['name'] == endName &&
      end['visibility'] == 'visible';
}

bool _scopeMeasurementComplete(Map<String, dynamic> row, String scope) {
  final live = scope.startsWith('live');
  if ((scope == 'map-startup-memory'
          ? !['warm', 'cold'].contains(row['warm_state'])
          : row['warm_state'] != (scope.endsWith('cold') ? 'cold' : 'warm')) ||
      row['executor'] != (live ? 'user' : 'developer') ||
      row['evidence_mode'] != (live ? 'live_user' : 'offline') ||
      row['acquisition_class'] != 'actual' ||
      ![
        'correct',
        'wrong_id',
        'rejected',
        'error',
        'canceled',
        'superseded',
      ].contains(row['terminal_outcome'])) {
    return false;
  }
  final measurements = row['measurements'];
  if (scope == 'live-burst') {
    return _physicalActuationObserved(row) &&
        (row['terminal_outcome'] != 'correct' ||
            row['endpoint'] is Map &&
                row['endpoint']['correctness'] == 'identified_correct' &&
                _elapsedObservationComplete(
                  {'start': row['trigger'], 'end': row['endpoint']},
                  row,
                  'physical_actuation',
                  'actionable_visible',
                ));
  }
  if (scope == 'offline-warm' || scope == 'offline-cold') {
    if ((row['stages'] as List).isEmpty || row['qpc_frequency'] == null) {
      return false;
    }
    return scope == 'offline-warm' ||
        measurements is Map && measurements['initialization_ms'] is num;
  }
  if (scope == 'live-cold') {
    return measurements is Map &&
        _elapsedObservationComplete(
          measurements['startup'],
          row,
          'process_launch',
          'first_usable',
        ) &&
        _elapsedObservationComplete(
          measurements['first_scan'],
          row,
          'physical_actuation',
          row['terminal_outcome'] == 'correct'
              ? 'actionable_visible'
              : 'terminal_visible',
        ) &&
        (row['terminal_outcome'] != 'correct' ||
            measurements['first_scan']['end']['correctness'] ==
                'identified_correct') &&
        row['observer'] is Map;
  }
  if (scope == 'map-startup-memory') {
    return measurements is Map &&
        measurements['interaction_path_id'] is String &&
        [
          'map_load_ms',
          'map_switch_ms',
          'pan_ms',
          'zoom_ms',
          'floor_switch_ms',
          'process_cpu_ms',
          'process_memory_bytes',
        ].every((key) => measurements[key] is num);
  }
  return false;
}

bool _samplingRosterComplete(List<Map<String, dynamic>> checks) {
  bool declared(
    String scope,
    String stratum,
    int allocation, {
    String? profile,
  }) => checks.any(
    (row) =>
        row['required'] == true &&
        row['applicable'] == true &&
        row['scope'] == scope &&
        row['stratum_id'] == stratum &&
        row['allocation'] == allocation &&
        (profile == null || row['profile'] == profile),
  );
  return _resolutions.every(
        (resolution) => ['host-inspection', 'full-viewport'].every(
          (profile) => declared(
            'offline-warm',
            '${resolution[0]}:$profile',
            100,
            profile: profile,
          ),
        ),
      ) &&
      declared('offline-cold', 'named-primary-setup', 10) &&
      declared('live-warm', 'intended-targeted', 100) &&
      declared('live-warm', 'fallback-required', 100) &&
      declared('live-cold', 'named-primary-setup', 10) &&
      [1, 2, 3].every((index) => declared('live-burst', 'burst-$index', 5)) &&
      [
        'vector-multilevel',
        'lab',
        'icebreaker',
        'labyrinth',
      ].every((map) => declared('map-startup-memory', map, 3));
}

/// Builds a portable evidence dossier from explicit serialized inputs only.
/// No supplied asserted gate status is trusted; coverage is computed from rows.
Map<String, dynamic> buildDossier(
  Map<String, Map<String, dynamic>> records, {
  required String runId,
}) {
  if (runId.trim().isEmpty) _invalid('runId must be nonempty');
  final hasIntake = records.containsKey('source_intake');
  if (hasIntake == records.containsKey('source_lock')) {
    _invalid('Supply exactly one source_intake or final source_lock');
  }
  final allowedKeys = {
    ..._requiredRecords,
    'source_intake',
    'source_lock',
    'oracle_results',
    'attempt_bundle',
  };
  if (records.keys.any((key) => !allowedKeys.contains(key))) {
    _invalid('Unexpected dossier input record');
  }
  for (final key in _requiredRecords) {
    if (!records.containsKey(key)) {
      _invalid('Missing required input record: $key');
    }
  }
  for (final entry in records.entries) {
    if (entry.value['record_type'] != entry.key) {
      _invalid('Input key/type mismatch: ${entry.key}');
    }
    // Invalid measured records are retained as evidence-validity failures below,
    // not reclassified as reference defects or missing collection.
    if (entry.key != 'oracle_results' && entry.key != 'attempt_bundle') {
      validateRecord(entry.value);
    }
  }
  final sourceKey = hasIntake ? 'source_intake' : 'source_lock';
  final source = records[sourceKey]!;
  final provenance = records['provenance']!;
  final manifest = records['fixture_manifest']!;
  final environment = records['environment']!;
  final cases = _rows(manifest['cases']);
  final caseById = {for (final row in cases) row['id'] as String: row};
  final checks = _rows(records['planned_checks']!['checks']);
  final controls = _rows(records['map_controls']!['controls']);
  final anchors = records['map_controls']!['anchors'] is List
      ? _rows(records['map_controls']!['anchors'])
      : <Map<String, dynamic>>[];
  final expectedCaseIds = <String>{
    ...caseById.keys,
    for (final check in checks) ...(check['case_ids'] as List).cast<String>(),
  };
  final gates = <Map<String, dynamic>>[];
  final rightsBlockers = <Map<String, dynamic>>[];
  final missingDeclaredCases =
      expectedCaseIds.where((id) => !caseById.containsKey(id)).toList()..sort();
  gates.add(
    _gate(
      'declared-case-roster',
      missingDeclaredCases.isEmpty ? 'pass' : 'unverified',
      'fixture-owner',
      missingDeclaredCases.isEmpty
          ? 'Every requested case ID exists in the supplied manifest.'
          : 'Requested planned-check cases are missing from the manifest: ${missingDeclaredCases.join(', ')}.',
      missingDeclaredCases.isEmpty
          ? [
              manifest['id'] as String,
              records['planned_checks']!['id'] as String,
            ]
          : [],
    ),
  );
  final inputs = <Map<String, dynamic>>[
    {
      'id': '${manifest['id']}-annotation-input',
      'version': manifest['annotation_version'],
      'sha256': sha256Json({
        'cases': [
          for (final row in cases)
            {
              'id': row['id'],
              'truth': row['truth'],
              'adjudication_ids': row['adjudication_ids'],
              if (row.containsKey('review')) 'review': row['review'],
            },
        ],
        'annotation_reviews': manifest['annotation_reviews'] ?? <dynamic>[],
      }),
    },
    for (final entry in records.entries)
      {
        'id': entry.value['id'],
        'version': _version(entry.value),
        'sha256': sha256Json(entry.value),
      },
    for (final category in (source['effective_inputs'] as Map).entries)
      if (category.value is List)
        for (final identity in category.value as List)
          {
            'id': identity['id'],
            'version': identity['version'],
            'sha256': identity['sha256'],
          },
  ];
  gates.add(
    _gate(
      'effective-reference-freeze',
      hasIntake ? 'unverified' : 'pass',
      'reference-input-owner',
      hasIntake ? source['freeze_id_reason'] as String : 'Validated immutable effective closure and scoped private-reference permission.',
      hasIntake ? [] : [source['id'] as String],
    ),
  );

  Map<String, dynamic>? comparison;
  var oracleValid = false;
  final oracle = records['oracle_results'];
  ExportDecision? oracleExportDecision;
  if (oracle == null) {
    gates.add(
      _gate(
        'oracle-evidence-linkage',
        'unverified',
        'implementing-agent',
        'No permitted private snapshot/native wrapper or actual offline reference replay is supplied; source inspection and comparator tests are not native evidence.',
        [],
      ),
    );
  } else {
    try {
      validateRecord(oracle);
      if (hasIntake) {
        _invalid(
          'Reference results require a final source_lock, not source intake',
        );
      }
      if (oracle['run_id'] != runId ||
          oracle['environment_id'] != environment['id']) {
        _invalid(
          'Reference results do not bind the requested run and environment',
        );
      }
      comparison = compareReferenceResults(
        manifest,
        oracle,
        sourceLock: source,
      );
      oracleValid = true;
      oracleExportDecision = inspectExport(
        oracle,
        (oracle['provenance_ids'] as List).cast<String>(),
        provenance,
      );
      // Public derivatives cannot launder observations through metadata grants.
      if (!oracleExportDecision.allowed) comparison = null;
      gates.add(
        _gate(
          'oracle-evidence-linkage',
          'pass',
          'implementing-agent',
          'Actual serialized observations bind the frozen source, manifest, inputs, run and environment; reference defects are separate.',
          [oracle['id'] as String],
        ),
      );
    } on ContractException catch (error) {
      gates.add(
        _gate(
          'oracle-evidence-linkage',
          'fail',
          'implementing-agent',
          error.message,
          [oracle['id'] as String],
        ),
      );
    }
  }
  final observedIds = comparison == null
      ? <String>{}
      : _rows(comparison['cases'])
            .where((row) => row['status'] == 'observed')
            .map((row) => row['case_id'] as String)
            .toSet();
  gates.add(
    _gate(
      'offline-reference-characterization',
      comparison?['evidence_validity'] == 'pass' ? 'pass' : 'unverified',
      'implementing-agent',
      comparison?['evidence_validity'] == 'pass'
          ? 'Every eligible declared case has a complete faithful comparison, including wrong outcomes.'
          : 'Required real corpus/native replay remains missing or incompletely measured; zero eligible cases do not qualify requested masters and maps.',
      comparison?['evidence_validity'] == 'pass'
          ? [oracle!['id'] as String]
          : [],
    ),
  );

  Map<String, dynamic> baseline = _missingBaseline(
    runId,
    environment['id'] as String,
    'No actual attempt collection is supplied. Planned allocations are not attempts.',
  );
  var attemptsValid = false;
  final physicalAttemptIds = <String>{};
  final setupMatchedAttemptIds = <String>{};
  final bundle = records['attempt_bundle'];
  ExportDecision? attemptExportDecision;
  if (bundle != null) {
    try {
      validateRecord(bundle);
      if (hasIntake ||
          bundle['freeze_id'] != source['freeze_id'] ||
          bundle['run_id'] != runId ||
          bundle['environment_id'] != environment['id']) {
        _invalid(
          'Attempt bundle does not bind a final freeze, requested run and environment',
        );
      }
      for (final row in _rows(bundle['attempts'])) {
        if (row['case_id'] is! String ||
            !caseById.containsKey(row['case_id'])) {
          _invalid(
            'Attempt ${row['id']} lacks a declared fixture case linkage',
          );
        }
        final fixture = caseById[row['case_id']]!;
        if (fixture['role'] == 'expectation_only' ||
            row['input_sha256'] != fixture['input']['sha256']) {
          _invalid(
            'Attempt ${row['id']} differs from its actual input hash or references expectation-only data',
          );
        }
        if ([
          'offline-warm',
          'offline-cold',
          'live-cold',
          'live-burst',
          'map-startup-memory',
        ].contains(row['scope'])) {
          // Validate supplied cross-boundary evidence before computing gates.
          _scopeMeasurementComplete(row, row['scope'] as String);
        }
        if (['live-warm', 'live-cold', 'live-burst'].contains(row['scope']) &&
            _setupMatchesAttempt(environment, row)) {
          setupMatchedAttemptIds.add(row['id'] as String);
        }
        if (row['scope'] == 'live-warm' && _physicalActuationObserved(row)) {
          physicalAttemptIds.add(row['id'] as String);
        }
      }
      attemptExportDecision = inspectExport(
        bundle,
        (bundle['provenance_ids'] as List).cast<String>(),
        provenance,
      );
      if (attemptExportDecision.allowed) {
        baseline = summarizeAttempts(bundle);
        baseline['provenance_ids'] = attemptExportDecision.artifactIds;
        final rowsById = {
          for (final row in _rows(bundle['attempts'])) row['id']: row,
        };
        for (final summary in _rows(baseline['attempt_summaries'])) {
          final row = rowsById[summary['id']]!;
          if (row.containsKey('measurements')) {
            summary['measurements'] = row['measurements'];
            if (row['measurements'] == null) {
              summary['measurements_reason'] = row['measurements_reason'];
            }
          }
        }
      } else {
        baseline = _missingBaseline(
          runId,
          environment['id'] as String,
          'Measurement report_export disposition unresolved; observations are not exported.',
        );
      }
      attemptsValid = true;
      gates.add(
        _gate(
          'attempt-evidence-linkage',
          'pass',
          'measurement-owner',
          'Every actual attempt is bound to the requested frozen input, run, setup and declared case.',
          [bundle['id'] as String],
        ),
      );
    } on ContractException catch (error) {
      final suppliedRows = bundle['attempts'];
      final suppliedProvenanceIds = bundle['provenance_ids'];
      final originalDecision = inspectExport(
        bundle,
        suppliedProvenanceIds is List
            ? suppliedProvenanceIds.whereType<String>().toList()
            : <String>[],
        provenance,
      );
      final linkedArtifactIds = originalDecision.artifactIds;
      final metadataOnlyBundle = <String, dynamic>{
        ...bundle,
        'attempts': <dynamic>[],
      };
      final observationUseCleared =
          originalDecision.privacyBlockers.isEmpty &&
          suppliedProvenanceIds is List &&
          inspectExport(
            metadataOnlyBundle,
            linkedArtifactIds,
            provenance,
          ).allowed;
      final publicReason = observationUseCleared
          ? error.message
          : 'Supplied measurement linkage is invalid; observations are not cleared for report export.';
      baseline = _missingBaseline(
        runId,
        environment['id'] as String,
        'Supplied measurements are invalid evidence: $publicReason',
      );
      if (observationUseCleared &&
          suppliedRows is List &&
          suppliedRows.every(
            (row) =>
                row is Map &&
                row['id'] is String &&
                row['terminal_outcome'] is String,
          )) {
        baseline['provenance_ids'] = linkedArtifactIds;
        baseline['attempt_n'] = suppliedRows.length;
        baseline['attempt_ids'] = suppliedRows.map((row) => row['id']).toList();
        final outcomes = <String, int>{};
        for (final row in suppliedRows) {
          final outcome = row['terminal_outcome'] as String;
          outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;
        }
        baseline['outcome_counts'] = outcomes;
        baseline['collection_status'] = 'invalid_evidence';
        baseline['physical_to_actionable_visible']['missing_n'] =
            suppliedRows.length;
        baseline['physical_to_actionable_visible']['missing_reasons'] = {
          'Invalid evidence linkage; no eligible visible measurement.':
              suppliedRows.length,
        };
      }
      gates.add(
        _gate(
          'attempt-evidence-linkage',
          'fail',
          'measurement-owner',
          publicReason,
          [bundle['id'] as String],
        ),
      );
    }
  } else {
    gates.add(
      _gate(
        'attempt-evidence-linkage',
        'unverified',
        'measurement-owner',
        'No actual offline or user-operated native/live attempts have been collected.',
        [],
      ),
    );
  }
  final attempts = attemptsValid && attemptExportDecision?.allowed == true
      ? _rows(bundle!['attempts'])
      : <Map<String, dynamic>>[];

  // Repeated variants, duplicate bytes and repeated source IDs cannot increase
  // independent-master coverage. A slot is filled only by adjudicated real truth.
  final uniqueSources = <String>{};
  final uniqueBytes = <String>{};
  final masters = <Map<String, dynamic>>[];
  for (final row in cases.where(_realMaster)) {
    final sourceId = row['source_id'] as String;
    final hash = row['input']['sha256'] as String;
    if (!uniqueSources.contains(sourceId) && !uniqueBytes.contains(hash)) {
      uniqueSources.add(sourceId);
      uniqueBytes.add(hash);
      masters.add(row);
    }
  }
  final masterStrata = <Map<String, dynamic>>[];
  var masterComplete = true;
  for (final resolution in _resolutions) {
    final rows = masters
        .where(
          (row) =>
              row['input']['width'] == resolution[0] &&
              row['input']['height'] == resolution[1],
        )
        .toList();
    final missing = _masterSlots
        .where(
          (slot) => !rows.any(
            (row) =>
                row['master_slot'] == slot &&
                (slot != 'multi' ||
                    (row['truth']['inspections'] is List &&
                        (row['truth']['inspections'] as List).length >= 2)),
          ),
        )
        .toList();
    masterComplete = masterComplete && missing.isEmpty;
    masterStrata.add({
      'id': resolution[0].toString(),
      'planned_allocation': 9,
      'actual_master_n': rows.length,
      'case_ids': rows.map((row) => row['id']).toList(),
      'missing_case_ids': missing,
    });
  }
  gates.add(
    _gate(
      'scanner-independent-masters',
      masterComplete && masters.length >= 36 ? 'pass' : 'unverified',
      'user-and-independent-annotators',
      'Require 36 distinct adjudicated real master/source cases: four positives, four negatives and one independently identified multi-inspection per resolution.',
      masterComplete ? masters.map((row) => row['id'] as String).toList() : [],
    ),
  );

  final declaredCells = _rows(records['display_matrix']!['cells']);
  final displayRows = <Map<String, dynamic>>[];
  final cellCoverage = <Map<String, dynamic>>[];
  for (final resolution in _resolutions) {
    for (final scale in _scales) {
      final id = '${resolution[0]}-$scale';
      final found = declaredCells.where((row) => row['id'] == id).toList();
      final cell = found.isEmpty
          ? <String, dynamic>{
              'id': id,
              'width': resolution[0],
              'height': resolution[1],
              'os_scale_percent': scale,
              'evidence_class': 'planned',
              'case_ids': <String>[],
              'evidence_ids': <String>[],
              'limitations': 'Required display cell is absent from the supplied matrix; no observation is inferred.',
            }
          : Map<String, dynamic>.from(found.single);
      if (cell['width'] != resolution[0] ||
          cell['height'] != resolution[1] ||
          cell['os_scale_percent'] != scale) {
        _invalid('Display cell identity/dimensions disagree: $id');
      }
      final cellCases = <Map<String, dynamic>>[];
      for (final caseId in cell['case_ids'] as List) {
        final fixture = caseById[caseId];
        if (fixture == null || fixture['display_cell_id'] != id) {
          _invalid('Display cell $id has invalid case linkage');
        }
        cellCases.add(fixture);
      }
      final missingVariants = _variantKinds
          .where((kind) => !cellCases.any((row) => _imageVariant(row, kind)))
          .toList();
      final observed = cellCases
          .where((row) => observedIds.contains(row['id']))
          .map((row) => row['id'])
          .toList();
      final cellAttempts = attempts
          .where((row) => _displayCellId(row['display_cell']) == id)
          .toList();
      final nativeObserved = cellAttempts.any(
        (row) =>
            row['evidence_mode'] == 'live_user' &&
            row['executor'] == 'user' &&
            row['acquisition_class'] == 'actual',
      );
      final observedEvidenceIds = <String>{
        ...observed.cast<String>(),
        for (final row in cellAttempts) row['id'] as String,
        if (observed.isNotEmpty && oracleValid) oracle!['id'] as String,
        if (cellAttempts.isNotEmpty && attemptsValid) bundle!['id'] as String,
      };
      final actualCellClaim = cell['evidence_class'] == 'live_user'
          ? nativeObserved
          : observed.isNotEmpty || cellAttempts.isNotEmpty;
      if (['offline', 'live_user'].contains(cell['evidence_class']) &&
          (!actualCellClaim ||
              !(cell['evidence_ids'] as List).every(
                observedEvidenceIds.contains,
              ))) {
        gates.add(
          _gate(
            'display-linkage-$id',
            'fail',
            'evidence-owner',
            'Display row asserts observations or live/native behavior without matching actual linked evidence.',
            (cell['evidence_ids'] as List).cast<String>(),
          ),
        );
      }
      displayRows.add(cell);
      cellCoverage.add({
        'id': id,
        'evidence_class': cell['evidence_class'],
        'expected_only': cellCases
            .where((row) => row['role'] == 'expectation_only')
            .length,
        'observed_count': observed.length,
        'observed_case_ids': observed,
        'missing_variants': missingVariants,
        'case_ids': cell['case_ids'],
        'native_status': nativeObserved ? 'observed' : 'unverified',
      });
      gates.add(
        _gate(
          'display-offline-$id',
          missingVariants.isEmpty ? 'pass' : 'unverified',
          'fixture-owner',
          'Each display cell requires adjudicated positive, no-marker, chrome/ambiguous and multi image variants; synthetic geometry cannot satisfy recognition/native gates.',
          missingVariants.isEmpty
              ? cellCases.map((row) => row['id'] as String).toList()
              : [],
        ),
      );
    }
  }
  if (declaredCells.any(
    (row) => !displayRows.any((cell) => cell['id'] == row['id']),
  )) {
    _invalid('Display matrix contains an unrequested display cell');
  }

  final declaredRoster = records['map_controls']!['expected_roster'] is List
      ? _rows(records['map_controls']!['expected_roster'])
      : <Map<String, dynamic>>[];
  final mapCoverage = <Map<String, dynamic>>[];
  var mapsComplete = true;
  final controlSources = <String>{};
  final independent = <Map<String, dynamic>>[];
  final invalidMapIds = <String>[];
  for (final row in controls) {
    if (!_mapArtworkKnown(source, row, declaredRoster, checks) ||
        !_inputHashKnown(source, 'config', row['config_sha256'])) {
      invalidMapIds.add(row['id'] as String);
      continue;
    }
    final identity = canonicalJson({
      'map_id': row['map_id'],
      'frame_revision': row['frame_revision'],
      'game_xyz': row['game_xyz'],
      'artwork_pixel': row['artwork_pixel'],
    });
    if (records['map_controls']!['data_class'] != 'synthetic' &&
        _independentControl(row) &&
        controlSources.add(identity)) {
      independent.add(row);
    }
  }
  final independentAnchors = <Map<String, dynamic>>[];
  for (final row in anchors) {
    if (!_mapArtworkKnown(source, row, declaredRoster, checks) ||
        !_inputHashKnown(source, 'config', row['config_sha256'])) {
      invalidMapIds.add(row['id'] as String);
      continue;
    }
    if (records['map_controls']!['data_class'] != 'synthetic' &&
        _independentAnchor(row)) {
      independentAnchors.add(row);
    }
  }
  final declaredMapHashes =
      source['effective_inputs']['maps'] is List &&
      source['effective_inputs']['config'] is List;
  gates.add(
    _gate(
      'map-input-linkage',
      invalidMapIds.isNotEmpty && declaredMapHashes
          ? 'fail'
          : controls.isEmpty && anchors.isEmpty || !declaredMapHashes
          ? 'unverified'
          : 'pass',
      'map-evidence-owner',
      invalidMapIds.isNotEmpty
          ? 'Independent map evidence does not bind the declared artwork/config input hashes: ${invalidMapIds.join(', ')}.'
          : 'Independent map evidence must bind actual declared artwork/config hashes; absent controls are not measurements.',
      (controls.isNotEmpty || anchors.isNotEmpty) &&
              invalidMapIds.isEmpty &&
              declaredMapHashes
          ? [records['map_controls']!['id'] as String]
          : [],
    ),
  );
  for (final mapId in _maps) {
    final configured = declaredRoster
        .where((row) => row['map_id'] == mapId)
        .toList();
    final revision = mapId == 'lab' ? '1' : '0';
    final rows = independent
        .where(
          (row) =>
              row['map_id'] == mapId &&
              row['frame_revision'].toString() == revision &&
              row['source_key'] == mapId,
        )
        .toList();
    final noncollinear = _noncollinear(rows);
    final floorIds = configured.isEmpty
        ? <dynamic>[]
        : configured.single['floor_group_ids'] as List;
    final missingFloors = floorIds
        .where(
          (floor) => !independentAnchors.any(
            (row) =>
                row['map_id'] == mapId &&
                row['kind'] == 'floor_artwork' &&
                row['floor_group_id'] == floor,
          ),
        )
        .toList();
    final complete =
        configured.isNotEmpty &&
        rows.length >= 3 &&
        noncollinear &&
        missingFloors.isEmpty;
    mapsComplete = mapsComplete && complete;
    mapCoverage.add({
      'map_id': mapId,
      'source_key': mapId,
      'frame_revision': revision,
      'planned_allocation': 3,
      'actual': rows.length,
      'control_ids': rows.map((row) => row['id']).toList(),
      'noncollinear': noncollinear,
      'floor_group_ids': floorIds,
      'missing_case_ids': missingFloors,
      'status': complete ? 'pass' : 'unverified',
    });
  }
  gates.add(
    _gate(
      'map-independent-controls',
      mapsComplete && independent.length >= 39 ? 'pass' : 'unverified',
      'user-and-independent-annotators',
      'Require all 13 configured frames, at least 39 independently reviewed distinct noncollinear controls and configured floor identities; synthetic geometry/reference predictions cannot supply landmarks.',
      mapsComplete
          ? independent.map((row) => row['id'] as String).toList()
          : [],
    ),
  );
  final areas = <Map<String, dynamic>>[];
  for (final area in _semanticAreas) {
    final rows = cases
        .where(
          (row) =>
              row['coverage_tags'] is List &&
              (row['coverage_tags'] as List).any(
                (tag) => tag is String && tag.startsWith('$area:'),
              ),
        )
        .toList();
    areas.add({
      'id': area,
      'case_ids': rows.map((row) => row['id']).toList(),
      'expected_only': rows
          .where((row) => row['role'] == 'expectation_only')
          .length,
      'observed_count': rows
          .where((row) => observedIds.contains(row['id']))
          .length,
      'status': rows.isNotEmpty && rows.every(_reviewed)
          ? 'pass'
          : 'unverified',
    });
  }
  final semanticComplete = areas.every((row) => row['status'] == 'pass');
  gates.add(
    _gate(
      'semantic-roster',
      semanticComplete ? 'pass' : 'unverified',
      'independent-reviewer',
      'Every requested semantic area must be present with adjudicated independent truth; authored pending expectations are not observed product/reference behavior.',
      semanticComplete ? [manifest['id'] as String] : [],
    ),
  );

  final samplingRosterComplete = _samplingRosterComplete(checks);
  gates.add(
    _gate(
      'sampling-allocation-roster',
      samplingRosterComplete ? 'pass' : 'unverified',
      'measurement-protocol-owner',
      'The approved 800 warm-offline, 10 cold-offline, 200 balanced live-warm, 10 live-cold, 15 burst and 12 map/startup allocations must stay preregistered even when unattempted.',
      samplingRosterComplete
          ? [records['planned_checks']!['id'] as String]
          : [],
    ),
  );
  final visibleAttemptIds = _rows(baseline['attempt_summaries'])
      .where(
        (row) =>
            row['physical_to_actionable_visible'] is Map &&
            row['physical_to_actionable_visible']['interval'] != null,
      )
      .map((row) => row['id'])
      .toSet();
  final warmLive = attempts
      .where((row) => row['scope'] == 'live-warm')
      .toList();
  final collectionComplete =
      attemptsValid &&
      attemptExportDecision?.allowed == true &&
      bundle!['collection_status'] == 'observed';
  final warmPathComplete = {
    for (final path in ['intended-targeted', 'fallback-required'])
      path:
          collectionComplete &&
          _warmLivePathComplete(
            warmLive,
            path,
            physicalAttemptIds,
            visibleAttemptIds,
          ),
  };
  final actualCheckRows = <Map<String, dynamic>>[];
  for (final check in checks) {
    final matchedAttempts = attempts
        .where(
          (row) =>
              row['stratum_id'] == check['stratum_id'] &&
              row['scope'] == check['scope'] &&
              (!check.containsKey('profile') ||
                  row['sampling_profile'] == check['profile']),
        )
        .toList();
    final linkedCases = (check['case_ids'] as List)
        .map((id) => caseById[id])
        .whereType<Map<String, dynamic>>()
        .toList();
    final linkedControls = independent
        .where(
          (row) =>
              (check['evidence_ids'] as List).contains(row['id']) &&
              row['map_id'] == check['stratum_id'] &&
              row['source_key'] == check['source_key'] &&
              row['frame_revision'] == check['frame_revision'],
        )
        .toList();
    final linkedAnchors = independentAnchors
        .where(
          (row) =>
              (check['evidence_ids'] as List).contains(row['id']) &&
              row['map_id'] == check['stratum_id'] &&
              (check['scope'] == 'floor-artwork-anchor'
                  ? row['kind'] == 'floor_artwork' &&
                        row['floor_group_id'] == check['floor_group_id']
                  : row['kind'] ==
                        (check['id'] == 'labs-tile-seam'
                            ? 'tile_seam'
                            : 'raster_extent')),
        )
        .toList();
    final sourceCount = linkedCases
        .where(
          (row) =>
              _realMaster(row) &&
              row['master_slot'] == check['master_slot'] &&
              row['input']['width'].toString() == check['stratum_id'],
        )
        .map((row) => row['source_id'])
        .toSet()
        .length;
    final imageCount = linkedCases
        .where(
          (row) =>
              row['display_cell_id'] == check['stratum_id'] &&
              _imageVariant(row, check['variant_kind'] as String? ?? ''),
        )
        .length;
    final panelCount = linkedCases
        .where(
          (row) =>
              row['acquisition'] == 'actual' &&
              row['profile'] == 'exfil_panel' &&
              _reviewed(row),
        )
        .map((row) => row['source_id'])
        .toSet()
        .length;
    final actualCount = switch (check['scope']) {
      'scanner-master' => sourceCount,
      'display-image-variant' => imageCount,
      'independent-map-control' => linkedControls.length,
      'floor-artwork-anchor' || 'raster-extent' => linkedAnchors.length,
      'real-panel-crop' => panelCount,
      'native-display' =>
        matchedAttempts
            .where(
              (row) =>
                  row['executor'] == 'user' &&
                  row['evidence_mode'] == 'live_user' &&
                  row['acquisition_class'] == 'actual',
            )
            .length,
      'offline-characterization' =>
        linkedCases.where((row) => observedIds.contains(row['id'])).length,
      'offline-warm' ||
      'offline-cold' ||
      'live-warm' ||
      'live-cold' ||
      'live-burst' ||
      'map-startup-memory' => matchedAttempts.length,
      _ => 0,
    };
    final evidenceIds = (check['evidence_ids'] as List).cast<String>();
    final knownEvidenceIds = <String>{
      for (final row in linkedCases) row['id'] as String,
      for (final row in linkedControls) row['id'] as String,
      for (final row in linkedAnchors) row['id'] as String,
      for (final row in matchedAttempts) row['id'] as String,
      if (oracleValid) oracle!['id'] as String,
      if (attemptsValid) bundle!['id'] as String,
      records['fixture_manifest']!['id'] as String,
      records['map_controls']!['id'] as String,
    };
    final hasEvidence =
        evidenceIds.isNotEmpty &&
        evidenceIds.every(knownEvidenceIds.contains) &&
        actualCount > 0;
    final allocationComplete = check['scope'] == 'live-warm'
        ? check['allocation'] == 100 &&
              warmPathComplete[check['stratum_id']] == true &&
              matchedAttempts.length == 100 &&
              _nativeSetupComplete(environment) &&
              matchedAttempts.every(
                (row) =>
                    row['intended_path'] == check['stratum_id'] &&
                    setupMatchedAttemptIds.contains(row['id']),
              )
        : actualCount >= (check['allocation'] as int);
    final measurementScope = [
      'offline-warm',
      'offline-cold',
      'live-cold',
      'live-burst',
      'map-startup-memory',
    ].contains(check['scope']);
    final measurementComplete =
        !measurementScope ||
        collectionComplete &&
            matchedAttempts.isNotEmpty &&
            matchedAttempts.every(
              (row) =>
                  _scopeMeasurementComplete(row, check['scope'] as String) &&
                  (!['live-cold', 'live-burst'].contains(check['scope']) ||
                      _nativeSetupComplete(environment) &&
                          setupMatchedAttemptIds.contains(row['id'])),
            );
    final completed =
        check['attempted'] == true &&
        check['disposition'] == 'observed' &&
        check['freeze_id'] == source['freeze_id'] &&
        !hasIntake &&
        hasEvidence &&
        allocationComplete &&
        measurementComplete;
    final status = completed
        ? 'pass'
        : check['required'] == false && check['applicable'] == false
        ? 'not_applicable'
        : 'unverified';
    gates.add(
      _gate(
        'planned-${check['id']}',
        status,
        check['owner'] as String,
        completed
            ? 'Declared allocation has actual linked evidence; failures and errors remain in all-attempt counts.'
            : check['reason'] as String,
        completed ? (check['evidence_ids'] as List).cast<String>() : [],
        required: check['required'] as bool,
      ),
    );
    actualCheckRows.add({
      ...check,
      'actual_attempt_n': matchedAttempts.length,
      'completed_n': matchedAttempts
          .where((row) => row['terminal_outcome'] == 'correct')
          .length,
      'actual': actualCount,
      if (measurementScope)
        'measurement_complete_n': matchedAttempts
            .where(
              (row) => _scopeMeasurementComplete(row, check['scope'] as String),
            )
            .length,
    });
  }
  final requiredAnchorChecks = checks
      .where(
        (row) =>
            row['scope'] == 'floor-artwork-anchor' ||
            row['scope'] == 'raster-extent',
      )
      .toList();
  final requiredAnchorChecksPass =
      requiredAnchorChecks.isNotEmpty &&
      requiredAnchorChecks.every(
        (row) => gates.any(
          (gate) =>
              gate['id'] == 'planned-${row['id']}' && gate['status'] == 'pass',
        ),
      );
  gates.add(
    _gate(
      'map-floor-raster-anchors',
      requiredAnchorChecksPass ? 'pass' : 'unverified',
      'independent-map-annotators',
      'Configured floor artwork, Labs tile seam/extent, all 16 Icebreaker floor identities and Labyrinth raster bounds remain explicit required independent anchors.',
      requiredAnchorChecksPass
          ? requiredAnchorChecks.map((row) => row['id'] as String).toList()
          : [],
    ),
  );
  final nativeCells = warmLive
      .map((row) => _displayCellId(row['display_cell']))
      .toSet();
  final liveComplete =
      collectionComplete &&
      warmLive.length == 200 &&
      warmPathComplete.values.every((complete) => complete) &&
      nativeCells.length == 1 &&
      nativeCells.single is String &&
      displayRows.any((row) => row['id'] == nativeCells.single) &&
      _nativeSetupComplete(environment) &&
      warmLive.every((row) => setupMatchedAttemptIds.contains(row['id']));
  gates.add(
    _gate(
      'user-native-visible-baseline',
      liveComplete ? 'pass' : 'unverified',
      'user',
      'Require one named native setup and exactly 200 warm live attempts: 100 per intended path, 50 automatic/50 manual, with batches 17/17, 17/16, 16/17. Every attempt needs correlated observable physical actuation; only correct outcomes need eligible actionable-visible endpoints. Known completed noncorrect outcomes retain the denominator; incomplete collection/outcomes stay unverified.',
      liveComplete ? [bundle['id'] as String, environment['id'] as String] : [],
    ),
  );

  for (final artifact in _rows(provenance['artifacts'])) {
    for (final use in (artifact['uses'] as Map).entries) {
      if (use.value['status'] != 'cleared') {
        rightsBlockers.add({
          'id': artifact['id'],
          'use': use.key,
          'status': use.value['status'],
          'reason': use.value['reason'],
          'owner': use.value['owner'] ?? 'designated-rights-reviewer',
          'evidence_ids': use.value['evidence_ids'],
        });
      }
    }
  }
  final evidenceIndex = <Map<String, dynamic>>[];
  final exports = <Map<String, dynamic>>[];
  // Unverified index rows cite identity only; provenance_ids authorize payload
  // export and must not turn a denied observation into a report dependency.
  for (final entry in records.entries) {
    final artifact = _metadataArtifacts[entry.key];
    if (artifact == null) continue;
    final decision = inspectExport(entry.value, [artifact], provenance);
    evidenceIndex.add({
      'id': entry.value['id'],
      'version': _version(entry.value),
      'sha256': sha256Json(entry.value),
      'path': 'inputs/${entry.key}.json',
      if (decision.allowed) 'provenance_ids': [artifact],
      'status': decision.allowed ? 'pass' : 'unverified',
      'reason': decision.allowed
          ? 'Sanitized original metadata is allowlisted for report export.'
          : decision.blockers.join(' | '),
    });
    if (decision.allowed) {
      exports.add({
        'path': 'inputs/${entry.key}.json',
        'sha256': sha256Json(entry.value),
        'provenance_ids': [artifact],
      });
    }
  }
  final attemptProvenanceIds = baseline['provenance_ids'] is List
      ? (baseline['provenance_ids'] as List).cast<String>()
      : <String>[];
  if (bundle != null) {
    final decision = attemptExportDecision;
    evidenceIndex.add({
      'id': bundle['id'],
      'version': _version(bundle),
      'sha256': sha256Json(bundle),
      if (decision?.allowed == true) 'provenance_ids': decision!.artifactIds,
      'status': decision?.allowed == true ? 'pass' : 'unverified',
      'reason': decision == null
          ? 'Invalid measurement linkage cannot authorize export.'
          : decision.allowed
          ? 'Measurement artifact and dependency uses explicitly cleared for report export.'
          : 'Measurement payload or linked artifact uses are not cleared for report export.',
    });
  }
  final oracleProvenanceIds = oracleValid
      ? (oracle!['provenance_ids'] as List).cast<String>()
      : <String>[];
  if (oracle != null) {
    final decision = oracleExportDecision;
    evidenceIndex.add({
      'id': oracle['id'],
      'version': _version(oracle),
      'sha256': sha256Json(oracle),
      'path': 'reference-results.json',
      if (decision?.allowed == true) 'provenance_ids': decision!.artifactIds,
      'status': decision?.allowed == true ? 'pass' : 'unverified',
      'reason': decision == null
          ? 'Invalid observation linkage cannot authorize export.'
          : decision.allowed
          ? 'Observation artifact and dependency uses explicitly cleared for report export.'
          : 'Observation payload or linked artifact uses are not cleared for report export.',
    });
  }
  final observedDivergences = <Map<String, dynamic>>[
    if (comparison != null)
      for (final row in _rows(comparison['cases']))
        if ((row['defects'] as List).isNotEmpty || row['status'] == 'error')
          {
            'case_id': row['case_id'],
            'profile': row['profile'],
            'status': row['status'],
            'defects': row['defects'],
            'errors': row['errors'],
            'expected': row['expected'],
            'observed': row['reference'],
            if (row['reference'] == null)
              'observed_reason': row['reference_reason'],
          },
    if (comparison != null)
      for (final row in _rows(comparison['divergences']))
        {
          'case_id': row['case_id'],
          'profile': caseById[row['case_id']]!['profile'],
          'kind': row['kind'],
          'status': 'observed',
          'defects': <String>[],
          'errors': <String>[],
          'expected': row['expected_policy'],
          'observed': row['reference'],
          'rationale': row['rationale'],
          'evidence_ids': [oracle!['id']],
        },
  ];
  if (attemptsValid && attemptExportDecision?.allowed == true) {
    for (final stratum in _rows(baseline['strata'])) {
      final metrics = <String, dynamic>{
        ...(stratum['internal_stages'] as Map<String, dynamic>),
        'physical_to_actionable_visible':
            stratum['physical_to_actionable_visible'],
        'physical_to_fallback_visible': stratum['physical_to_fallback_visible'],
      };
      for (final entry in metrics.entries) {
        final metric = entry.value as Map<String, dynamic>;
        if (metric['threshold_status'] != 'fail') continue;
        final attemptIds = (stratum['attempt_ids'] as List).toSet();
        final linkedCaseIds =
            attempts
                .where((row) => attemptIds.contains(row['id']))
                .map((row) => row['case_id'] as String)
                .toSet()
                .toList()
              ..sort();
        observedDivergences.add({
          'kind': 'reference_speed',
          'status': 'observed',
          'case_ids': linkedCaseIds,
          'defects': ['latency_target_exceeded'],
          'errors': <String>[],
          'stratum': stratum['stratum'],
          'evidence_ids': [bundle!['id']],
          'expected': {'target_ms': metric['target_ms']},
          'observed': {
            'name': entry.key,
            'n': metric['n'],
            if (metric.containsKey('p95_ms')) 'p95_ms': metric['p95_ms'],
            if (metric.containsKey('p95_lower_ms'))
              'p95_lower_ms': metric['p95_lower_ms'],
            if (metric.containsKey('p95_upper_ms'))
              'p95_upper_ms': metric['p95_upper_ms'],
          },
        });
      }
    }
  }
  final expectationPolicies = <Map<String, dynamic>>[
    for (final row in cases)
      if (!observedDivergences.any(
            (divergence) => divergence['case_id'] == row['id'],
          ) &&
          ((row['coverage_tags'] is List &&
                  (row['coverage_tags'] as List).any(
                    (tag) => tag is String && tag.startsWith('advice:'),
                  )) ||
              (row['truth'] is Map &&
                  row['truth']['target_policy'] is Map &&
                  row['truth']['target_policy']['intentional_divergence'] ==
                      true)))
        {
          'case_id': row['id'],
          'status': 'expectation_only',
          'expected': row['truth'],
          'evidence_ids': row['adjudication_ids'],
          'reason': 'Source-level target policy expectation, not an observed reference Sell or other reference divergence.',
        },
  ];
  final divergenceRegister = <String, dynamic>{
    'schema_version': 1,
    'record_type': 'divergence_register',
    'id': '$runId-divergences',
    if (comparison != null || attemptProvenanceIds.isNotEmpty)
      'provenance_ids': [
        if (comparison != null) ...oracleProvenanceIds,
        ...attemptProvenanceIds,
      ],
    'run_id': runId,
    'data_class': manifest['data_class'] ?? 'metadata',
    'observed': observedDivergences,
    'expectation_only': expectationPolicies,
  };
  final timingStagesAvailable =
      attemptsValid &&
      _rows(baseline['strata']).any(
        (row) =>
            row['internal_stages'] is Map &&
            (row['internal_stages'] as Map).values.any(
              (metric) =>
                  metric is Map && metric['n'] is int && metric['n'] > 0,
            ),
      );
  final qualification = <String, dynamic>{
    'schema_version': 1,
    'record_type': 'qualification_report',
    'id': '$runId-qualification',
    if (comparison != null || attemptProvenanceIds.isNotEmpty)
      'provenance_ids': [
        if (comparison != null) ...oracleProvenanceIds,
        ...attemptProvenanceIds,
      ],
    'run_id': runId,
    'inputs': inputs,
    'planned_checks_id': records['planned_checks']!['id'],
    'coverage': {
      'checks': actualCheckRows,
      'cells': cellCoverage,
      'maps': mapCoverage,
      'semantic_areas': areas,
      'scanner_masters': {
        'planned_allocation': 36,
        'actual_master_n': masters.length,
        'actual_source_n': uniqueSources.length,
        'strata': masterStrata,
      },
      'expected_only': cases
          .where((row) => row['role'] == 'expectation_only')
          .length,
      'observed_count': observedIds.length,
      'recognition': comparison == null
          ? {
              'status': 'unverified',
              'reason': oracle == null
                  ? 'No native/host reference results supplied.'
                  : oracleValid
                  ? 'Observation report_export disposition is unresolved; observation-derived metrics are not exported.'
                  : 'Supplied observations have invalid linkage; they are not valid independent comparisons.',
              'observed_count': 0,
              'attempted_rows':
                  oracle != null && oracleExportDecision?.allowed != true
                  ? 0
                  : oracle?['observations'] is List
                  ? (oracle!['observations'] as List).length
                  : 0,
              'errors': oracle != null && oracleExportDecision?.allowed != true
                  ? 0
                  : oracle?['observations'] is List
                  ? (oracle!['observations'] as List)
                        .where((row) => row is Map && row['status'] == 'error')
                        .length
                  : 0,
              'metrics': null,
              'metrics_reason': 'No valid independent comparison is available; no accuracy or wrong-identity counts are invented.',
            }
          : {
              'status': comparison['evidence_validity'],
              'metrics': comparison['metrics'],
              'denominators': comparison['denominators'],
              'reference_behavior': comparison['reference_behavior'],
            },
    },
    'denominators': {
      'planned_allocation': checks.fold<int>(
        0,
        (sum, row) => sum + (row['allocation'] as int),
      ),
      'actual_attempt_n': baseline['attempt_n'],
      'completed_n': baseline['actionable_sample_n'],
      'expected_case_ids': expectedCaseIds.toList()..sort(),
      'observed_case_ids': observedIds.toList()..sort(),
      'missing_case_ids': [
        ...missingDeclaredCases,
        ...cases
            .where(
              (row) =>
                  row['role'] != 'expectation_only' &&
                  !observedIds.contains(row['id']),
            )
            .map((row) => row['id']),
      ],
    },
    'timing': {
      'status': baseline['status'],
      'attempt_n': baseline['attempt_n'],
      'internal_stages': timingStagesAvailable ? baseline['strata'] : null,
      if (!timingStagesAvailable) 'internal_stages_reason': 'No actual valid QPC stage observations are supplied; no stage durations are inferred.',
      'actionable_sample_n': baseline['actionable_sample_n'],
      'quantile_method': 'nearest_rank',
      'quantile': 0.95,
      'strata': baseline['strata'],
      'limitations': 'Internal stages and publication are not physical-trigger-to-visible measurements. Zero samples yield null latency; no run or freeze is invented.',
    },
    'strata': [...masterStrata, ...cellCoverage, ...mapCoverage],
    'divergences': observedDivergences,
    'display_matrix': {'cells': displayRows},
    'rights_blockers': rightsBlockers,
    'exports': exports,
    'gates': gates,
    'limitations': 'Incomplete evidence is not full M0 qualification. Native wrapper/materialization/replay and live/user collection remain blocked by actual prerequisites; synthetic vectors establish target expectations only.',
  };
  // Inspect every candidate before exporting. A blocked original attachment stays
  // in the index, but none of its bytes enter the portable dossier.
  final summaryDecision = inspectExport(baseline, [
    _reportArtifact,
    ...attemptProvenanceIds,
  ], provenance);
  final divergenceDecision = inspectExport(divergenceRegister, [
    _reportArtifact,
  ], provenance);
  if (summaryDecision.allowed) {
    exports.add({
      'path': 'baseline-summary.json',
      'sha256': sha256Json(baseline),
      'provenance_ids': [_reportArtifact, ...attemptProvenanceIds],
    });
  }
  if (divergenceDecision.allowed) {
    exports.add({
      'path': 'divergences.json',
      'sha256': sha256Json(divergenceRegister),
      'provenance_ids': [
        _reportArtifact,
        if (comparison != null) ...oracleProvenanceIds,
        ...attemptProvenanceIds,
      ],
    });
  }
  if (oracleValid && oracleExportDecision!.allowed) {
    exports.add({
      'path': 'reference-results.json',
      'sha256': sha256Json(oracle),
      'provenance_ids': oracleProvenanceIds,
    });
  }
  final authoredUse = _rows(provenance['artifacts'])
      .where((row) => row['id'] == _reportArtifact)
      .toList();
  final exportReady =
      authoredUse.length == 1 &&
      authoredUse.single['uses']['report_export']['status'] == 'cleared' &&
      summaryDecision.allowed &&
      divergenceDecision.allowed &&
      evidenceIndex.every((row) => row['status'] == 'pass');
  gates.add(
    _gate(
      'report-export',
      exportReady ? 'pass' : 'unverified',
      'designated-rights-reviewer',
      exportReady
          ? 'Original authored metadata and listed sibling payloads have explicit sanitized export clearance.'
          : 'One or more requested metadata payloads/uses cannot be exported. Blocked records remain indexed without copying their bytes.',
      exportReady ? [_reportArtifact] : [],
    ),
  );
  qualification['status'] = qualificationStatus(gates);
  validateRecord(qualification);
  return {
    'qualification': qualification,
    'baseline_summary': baseline,
    'divergence_register': divergenceRegister,
    'evidence_index': evidenceIndex,
  };
}

Map<String, dynamic> _missingBaseline(
  String runId,
  String environmentId,
  String reason,
) => {
  'schema_version': 1,
  'record_type': 'baseline_summary',
  'id': '$runId-baseline-summary',
  'attempt_bundle_id': null,
  'attempt_bundle_id_reason': reason,
  'attempt_bundle_sha256': null,
  'attempt_bundle_sha256_reason': reason,
  'freeze_id': null,
  'freeze_id_reason': 'No valid frozen measurement input is available.',
  'run_id': runId,
  'environment_id': environmentId,
  'quantile_method': 'nearest_rank',
  'quantile': 0.95,
  'status': 'incomplete',
  'visible_evidence_status': 'unverified',
  'attempt_n': 0,
  'attempt_ids': <String>[],
  'outcome_counts': <String, int>{},
  'actionable_sample_n': 0,
  'fallback_visible_sample_n': 0,
  'coverage': {
    'unique_master_n': 0,
    'unique_source_n': 0,
    'master_ids': <String>[],
    'source_ids': <String>[],
    'missing_master_id_n': 0,
    'missing_source_id_n': 0,
    'unique_master_outcome_counts': <String, int>{},
  },
  'external_data_ages': {
    'counts': {'measured': 0, 'absent': 0, 'future': 0, 'unsupported': 0},
    'observations': <dynamic>[],
    'measured_ms': _missingMetric(reason),
  },
  'strata': <dynamic>[],
  'attempt_summaries': <dynamic>[],
  'collection_status': 'unattempted',
  'collection_rationale': reason,
  'physical_to_actionable_visible': {
    'n': 0,
    'missing_n': 0,
    'missing_reasons': <String, int>{},
    'p95_lower_ms': null,
    'p95_lower_ms_reason': reason,
    'p95_upper_ms': null,
    'p95_upper_ms_reason': reason,
    'target_ms': null,
    'target_ms_reason': 'No measured baseline target supplied.',
    'threshold_status': 'unverified',
  },
};
Map<String, dynamic> _missingMetric(String reason) => {
  'n': 0,
  'missing_n': 0,
  'missing_reasons': <String, int>{},
  'p95_ms': null,
  'p95_ms_reason': reason,
  'target_ms': null,
  'target_ms_reason': 'No measured baseline target supplied.',
  'threshold_status': 'unverified',
};

Future<void> _directoryAncestry(Directory directory) async {
  var current = directory.absolute;
  while (true) {
    if (await FileSystemEntity.type(current.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      _invalid(
        'Input/output ancestry must contain real directories, never links',
      );
    }
    if (current.parent.path == current.path) return;
    current = current.parent;
  }
}

Future<File> _explicitFile(Directory root, String path) async {
  if (!isPortableRelativePath(path)) {
    _invalid('Record/payload path must be portable and explicit');
  }
  var current = root.path;
  final parts = path.split('/');
  for (var index = 0; index < parts.length; index++) {
    current = '$current${Platform.pathSeparator}${parts[index]}';
    final expected = index == parts.length - 1
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    if (await FileSystemEntity.type(current, followLinks: false) != expected) {
      _invalid('Explicit input is missing, linked or the wrong kind: $path');
    }
  }
  return File(current);
}

Map<String, dynamic> _decodeRecord(List<int> bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    // Decoder excerpts could expose a malformed private field in diagnostics.
    _invalid(
      'Dossier JSON is malformed; payload text is not included in diagnostics',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    _invalid('Dossier JSON must be an object');
  }
  return decoded;
}

Future<({Map<String, dynamic> record, String byteHash})> _readRecord(
  File file,
) async {
  final bytes = await file.readAsBytes();
  return (
    record: _decodeRecord(bytes),
    byteHash: sha256.convert(bytes).toString(),
  );
}

/// Reads only the request's explicit portable records and declared fixture files.
/// Source closure paths are metadata, never instructions to read an old checkout.
/// Every record, manifest.files path and case input path is relative to inputRoot,
/// never relative to the manifest directory; no root discovery or '..' is used.
Future<void> generateDossier(
  String requestPath, {
  required String inputRoot,
  required String outputRoot,
}) async {
  final root = Directory(
    Directory(inputRoot).absolute.uri.normalizePath().toFilePath(),
  );
  await _directoryAncestry(root);
  final requestFile = File(
    File(requestPath).absolute.uri.normalizePath().toFilePath(),
  );
  // The caller names this one request, not a discovery directory. Resolve its
  // relative name under the input root and apply the same anti-link boundary.
  final rootPrefix = root.path.endsWith(Platform.pathSeparator)
      ? root.path
      : '${root.path}${Platform.pathSeparator}';
  final comparableRequest = Platform.isWindows
      ? requestFile.path.toLowerCase()
      : requestFile.path;
  final comparableRoot = Platform.isWindows
      ? rootPrefix.toLowerCase()
      : rootPrefix;
  if (!comparableRequest.startsWith(comparableRoot)) {
    _invalid('Request must be rooted at inputRoot');
  }
  final relativeRequest = requestFile.path
      .substring(rootPrefix.length)
      .replaceAll('\\', '/');
  final consumedRequest = await _readRecord(
    await _explicitFile(root, relativeRequest),
  );
  final request = consumedRequest.record;
  if (request['record_type'] != 'dossier_request') {
    _invalid('Report requires a dossier_request record');
  }
  validateRecord(request);
  final recordPaths = request['records'] as Map<String, dynamic>;
  final records = <String, Map<String, dynamic>>{};
  final recordByteHashes = <String, String>{};
  for (final entry in recordPaths.entries) {
    final consumed = await _readRecord(
      await _explicitFile(root, entry.value as String),
    );
    records[entry.key] = consumed.record;
    recordByteHashes[entry.key] = consumed.byteHash;
  }
  final dossier = buildDossier(records, runId: request['run_id'] as String);
  final qualification = dossier['qualification'] as Map<String, dynamic>;
  final provenance = records['provenance']!;
  (qualification['inputs'] as List).add({
    'id': request['id'],
    'version': '1',
    'sha256': sha256Json(request),
  });
  (qualification['inputs'] as List).add({
    'id': '${request['id']}-original-json-bytes',
    'version': '1',
    'sha256': consumedRequest.byteHash,
  });
  for (final entry in records.entries) {
    (qualification['inputs'] as List).add({
      'id': '${entry.value['id']}-original-json-bytes',
      'version': _version(entry.value),
      'sha256': recordByteHashes[entry.key],
    });
  }
  if (!records.containsKey('attempt_bundle')) {
    final missing = _missingBaseline(
      request['run_id'] as String,
      records['environment']!['id'] as String,
      request['attempt_bundle_reason'] as String,
    );
    dossier['baseline_summary'] = missing;
    for (final row in _rows(qualification['exports'])) {
      if (row['path'] == 'baseline-summary.json') {
        row['sha256'] = sha256Json(missing);
      }
    }
  }
  if (!records.containsKey('oracle_results')) {
    final missingGate = _rows(qualification['gates'])
        .singleWhere((row) => row['id'] == 'oracle-evidence-linkage');
    missingGate['reason'] =
        '${request['oracle_results_reason']} ${missingGate['reason']}';
  }
  // A forbidden/private attachment is rejected before creating output; rights
  // refusals can instead be represented as absent attachments in the dossier.
  for (final entry in records.entries) {
    final artifacts =
        ['oracle_results', 'attempt_bundle'].contains(entry.key) &&
            entry.value['provenance_ids'] is List
        ? (entry.value['provenance_ids'] as List).whereType<String>().toList()
        : [_metadataArtifacts[entry.key] ?? _reportArtifact];
    final decision = inspectExport(entry.value, artifacts, provenance);
    if (decision.blockers.any(
      (reason) =>
          reason.startsWith('payload') ||
          reason.startsWith('Record type') ||
          reason.contains('absolute/private locator') ||
          reason.contains('forbidden') ||
          reason.contains('not allowlisted'),
    )) {
      _invalid('Unsafe dossier input cannot be exported: ${entry.key}');
    }
  }
  // Check the declared local independent payloads, not source intake closure.
  final manifest = records['fixture_manifest']!;
  if (manifest['files'] is List) {
    final payloadCases = <String, Map<String, dynamic>>{};
    final fileRows = _rows(manifest['files']);
    for (final row in fileRows) {
      final file = await _explicitFile(root, row['path'] as String);
      final bytes = await file.readAsBytes();
      if (sha256.convert(bytes).toString() != row['sha256'] ||
          bytes.length != row['size_bytes']) {
        _invalid('Fixture payload hash/size drift: ${row['id']}');
      }
      Map<String, dynamic>? verifiedPayload;
      for (final entry in records.entries) {
        if (entry.value['id'] != row['id']) continue;
        // Frozen files bind exact bytes; exported role records bind the same
        // logical JSON even when canonical serialization changes those bytes.
        verifiedPayload ??= _decodeRecord(bytes);
        if (canonicalJson(entry.value) != canonicalJson(verifiedPayload)) {
          _invalid(
            'Consumed record differs from its declared manifest file: ${row['id']}',
          );
        }
      }
      if ((row['path'] as String).endsWith('.json')) {
        final payload = verifiedPayload ?? _decodeRecord(bytes);
        if (payload['record_type'] == 'fixture_manifest') {
          validateRecord(payload);
          for (final fixture in _rows(payload['cases'])) {
            final id = fixture['id'] as String;
            if (payloadCases.containsKey(id)) {
              _invalid('Declared payload files duplicate a fixture case');
            }
            payloadCases[id] = fixture;
          }
        }
      }
    }
    if (payloadCases.isNotEmpty) {
      final embeddedCases = _rows(manifest['cases']);
      if (embeddedCases.length != payloadCases.length ||
          embeddedCases.any(
            (row) =>
                !payloadCases.containsKey(row['id']) ||
                canonicalJson(row) != canonicalJson(payloadCases[row['id']]),
          )) {
        _invalid(
          'Manifest case roster/truth differs from its declared hashed payload files',
        );
      }
    }
  }
  for (final row in _rows(manifest['cases'])) {
    if (row['role'] == 'expectation_only') continue;
    final input = row['input'] as Map<String, dynamic>;
    final file = await _explicitFile(root, input['path'] as String);
    if ((await sha256.bind(file.openRead()).first).toString() !=
        input['sha256']) {
      _invalid('Case input hash drift: ${row['id']}');
    }
  }
  final outputs = <String, Map<String, dynamic>>{
    for (final entry in records.entries)
      if (_metadataArtifacts.containsKey(entry.key))
        'inputs/${entry.key}.json': entry.value,
    'baseline-summary.json':
        dossier['baseline_summary'] as Map<String, dynamic>,
    'divergences.json': dossier['divergence_register'] as Map<String, dynamic>,
    if (records.containsKey('oracle_results'))
      'reference-results.json': records['oracle_results']!,
  };
  final serialized = <String, String>{};
  for (final export in _rows(qualification['exports'])) {
    final path = export['path'] as String;
    final payload = outputs[path]!;
    final sanitized = sanitizedExport(
      payload,
      (export['provenance_ids'] as List).cast<String>(),
      provenance,
    );
    final canonical = canonicalJson(sanitized);
    if (sha256.convert(utf8.encode(canonical)).toString() != export['sha256']) {
      _invalid('Export payload identity drift');
    }
    serialized[path] = canonical;
  }
  // Required authored report files cannot be silently omitted. A denied report
  // grant stops this export while buildDossier remains usable for local metadata.
  if (!serialized.containsKey('baseline-summary.json') ||
      !serialized.containsKey('divergences.json')) {
    _invalid('Authored report summaries are not cleared for sanitized export');
  }
  qualification['evidence_index'] = dossier['evidence_index'];
  sanitizedExport(qualification, [_reportArtifact], provenance);
  serialized['qualification.json'] = canonicalJson(qualification);
  final output = Directory(outputRoot).absolute;
  if (await FileSystemEntity.type(output.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    _invalid(
      'Dossier output must be a new directory; existing evidence is never overwritten',
    );
  }
  var existingParent = output.parent;
  while (await FileSystemEntity.type(existingParent.path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    if (existingParent.parent.path == existingParent.path) {
      _invalid('Output volume/root does not exist');
    }
    existingParent = existingParent.parent;
  }
  await _directoryAncestry(existingParent);
  final outputComparable = Platform.isWindows
      ? output.path.toLowerCase()
      : output.path;
  if (outputComparable ==
      (Platform.isWindows ? root.path.toLowerCase() : root.path)) {
    _invalid('Output cannot replace the input root');
  }
  await output.create(recursive: true);
  await Directory('${output.path}/inputs').create();
  for (final entry in serialized.entries) {
    await File('${output.path}/${entry.key}')
        .writeAsString(entry.value, flush: true);
  }
  final readme = _readme(
    qualification,
    dossier['baseline_summary'] as Map<String, dynamic>,
  );
  await File('${output.path}/README.md').writeAsString(readme, flush: true);
}

String _readme(Map<String, dynamic> report, Map<String, dynamic> baseline) {
  final lines = <String>[
    '# M0 qualification dossier: ${report['run_id']}',
    '',
    'Status: **${report['status']}**. Qualification JSON SHA-256: `${sha256Json(report)}`.',
    '',
    'This dossier consumes only explicit portable serialized evidence; no old checkout, .NET oracle, private captures, network or running application is required.',
    'Missing required observations are not user-approved skips. Synthetic vectors are expectations, not real screenshots, independent landmarks, native recognition or live display proof.',
    '',
    '## Actual measurement denominators',
    '',
    '- Actual attempts: ${baseline['attempt_n']}; actionable-visible samples: ${baseline['actionable_sample_n']}.',
    '- Unique real scanner masters: ${report['coverage']['scanner_masters']['actual_master_n']} of 36.',
    '- All 16 requested display rows and all 13 requested maps remain in qualification.json.',
    '- Internal stage/publication latency does not establish physical-trigger-to-actionable-visible latency.',
    '',
    '## Required evidence gates',
    '',
  ];
  for (final row in _rows(report['gates'])) {
    lines.add(
      '- `${row['id']}`: ${row['status']} (${row['required'] ? 'required' : 'optional'}); owner `${row['owner']}`. ${row['reason']}',
    );
  }
  lines.addAll([
    '',
    '## Exported siblings',
    '',
    'Only qualification.exports payloads have been exported; each listed SHA-256 binds the actual canonical JSON bytes. qualification.json does not hash itself; this external README names its hash.',
    'Blocked attachments and affected uses remain visible in evidence_index and rights_blockers; their bytes are absent.',
    '',
  ]);
  for (final row in _rows(report['exports'])) {
    lines.add('- `${row['path']}` — `${row['sha256']}`');
  }
  lines.addAll([
    '',
    '## Remaining full-M0 observations',
    '',
    'Use the required evidence gates above to identify outstanding observations: reviewed affected-use permissions and final effective closure; actual permitted private native wrapper/materialization/replay; 36 independently adjudicated real masters and image variants across all 16 offline cells; 39 independent map controls and configured floor/raster anchors; named-setup offline warm/cold and map/startup/memory observations; user-performed warm targeted/fallback, cold/startup, burst and same-clock physical/visible measurements.',
    'No oracle result file, synthetic failed attempt or non-null freeze is fabricated when those records are unavailable.',
    '',
  ]);
  return lines.join('\n');
}
