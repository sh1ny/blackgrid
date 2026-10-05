import 'contracts.dart';

/// A refusal remains reportable; no payload is silently redacted or downgraded.
class ExportDecision {
  const ExportDecision(
    this.allowed,
    this.blockers,
    this.artifactIds,
    this.privacyBlockers,
  );

  final bool allowed;
  final List<String> blockers;

  /// The explicit and nested artifact links checked by this decision.
  final List<String> artifactIds;

  /// The original payload's recursive allowlist and privacy refusals.
  ///
  /// Schema validity and scoped artifact uses are checked separately and still
  /// contribute to [blockers]; an empty list here does not authorize export.
  final List<String> privacyBlockers;
}

const _uses = {
  'private_reference',
  'repository_fixture',
  'report_export',
  'release',
};
const _common = {'schema_version', 'record_type', 'id', 'data_class'};
const _recordFields = <String, Set<String>>{
  'source_intake': {
    'reference',
    'submodules',
    'files',
    'effective_inputs',
    'closure_complete',
    'closure_declaration',
    'freeze_id',
    'collected_at',
  },
  'source_lock': {
    'reference',
    'submodules',
    'files',
    'effective_inputs',
    'closure_complete',
    'closure_declaration',
    'freeze_id',
    'collected_at',
    'permission',
  },
  'environment': {
    'setup_alias',
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
  },
  'provenance': {
    'artifacts',
    'intake',
    'review_evidence',
    'blocked_uses',
    'inventory_summary',
  },
  'fixture_manifest': {
    'authoring_source_id',
    'corpus_version',
    'annotation_version',
    'catalog_version',
    'config_version',
    'cases',
    'files',
    'coverage_claims',
    'limitations',
    'mode',
    'freeze_id',
    'annotation_reviews',
  },
  'map_controls': {
    'controls',
    'expected_roster',
    'limitations',
    'anchors',
    'independent_control_status',
    'source_identity_basis',
  },
  'display_matrix': {'cells', 'limitations'},
  'oracle_results': {
    'freeze_id',
    'run_id',
    'environment_id',
    'fixture_manifest_sha256',
    'observations',
    'comparison_basis',
    'provenance_ids',
  },
  'attempt_bundle': {
    'provenance_ids',
    'freeze_id',
    'run_id',
    'environment_id',
    'attempts',
    'targets_ms',
    'collection_status',
    'collection_rationale',
  },
  'planned_checks': {'checks'},
  'qualification_report': {
    'run_id',
    'inputs',
    'planned_checks_id',
    'coverage',
    'denominators',
    'timing',
    'strata',
    'divergences',
    'display_matrix',
    'exports',
    'gates',
    'status',
    'rights_blockers',
    'limitations',
    'evidence_index',
    'provenance_ids',
  },
  'divergence_register': {
    'run_id',
    'observed',
    'expectation_only',
    'provenance_ids',
  },
  'baseline_summary': {
    'provenance_ids',
    'attempt_bundle_id',
    'attempt_bundle_sha256',
    'freeze_id',
    'run_id',
    'environment_id',
    'quantile_method',
    'quantile',
    'status',
    'visible_evidence_status',
    'attempt_n',
    'attempt_ids',
    'outcome_counts',
    'actionable_sample_n',
    'fallback_visible_sample_n',
    'coverage',
    'external_data_ages',
    'strata',
    'attempt_summaries',
    'collection_status',
    'collection_rationale',
    'physical_to_actionable_visible',
  },
};

// Deliberate vocabulary, not an open extension bag. Per-record roots above are
// narrower; named ID dictionaries below allow identifiers, never opaque objects.
const _fields = {
  'id',
  'kind',
  'purpose',
  'source',
  'sha256',
  'sha512',
  'declared_terms',
  'depends_on',
  'data_class',
  'dependency',
  'upstream',
  'review',
  'second_review_required',
  'annotation_source_id',
  'coverage_tags',
  'state',
  'args',
  'assertions',
  'equals',
  'independent_of_reference_output',
  'parent_ids',
  'parent_bindings',
  'recipe',
  'recipe_sha256',
  'authoring_source_id',
  'coverage_claims',
  'physical_client_px',
  'monitor_origin_px',
  'flutter_logical_size',
  'game_ui_scale',
  'buffer',
  'stride_bytes',
  'channels',
  'orientation',
  'frame',
  'rotation_degrees',
  'affine',
  'native_zoom',
  'pixel_size',
  'bands',
  'artwork_path',
  'master_slot',
  'variant_kind',
  'batches',
  'trigger_allocation',
  'prerequisites',
  'floor_group_ids',
  'artwork_identity_status',
  'geometry_case_ids',
  'required_image_variants',
  'native_status',
  'comparison_basis',
  'corpus_version',
  'annotation_version',
  'catalog_version',
  'config_version',
  'fixture_manifest_sha256',
  'rationale',
  'actual_master_cases',
  'native_display_cells',
  'independent_map_controls',
  'synthetic_geometry_cells',
  'planned_check_id',
  'pin_aliases',
  'automatic',
  'manual',
  'attempt_bundle_id',
  'attempt_bundle_sha256',
  'quantile_method',
  'quantile',
  'visible_evidence_status',
  'attempt_n',
  'attempt_ids',
  'outcome_counts',
  'actionable_sample_n',
  'fallback_visible_sample_n',
  'external_data_ages',
  'attempt_summaries',
  'collection_status',
  'collection_rationale',
  'unique_master_n',
  'unique_source_n',
  'master_ids',
  'missing_master_id_n',
  'missing_source_id_n',
  'unique_master_outcome_counts',
  'stratum',
  'internal_stages',
  'physical_to_actionable_visible',
  'physical_to_fallback_visible',
  'display_cell',
  'acquisition_class',
  'n',
  'missing_n',
  'missing_reasons',
  'p95_ms',
  'target_ms',
  'threshold_status',
  'p95_lower_ms',
  'p95_upper_ms',
  'counts',
  'measured',
  'absent',
  'future',
  'unsupported',
  'observations',
  'attempt_id',
  'value',
  'detail',
  'measured_ms',
  'age_ms',
  'internal_stage_ms',
  'qpc_events',
  'tick',
  'frequency',
  'domain',
  'interval',
  'scanner_masters',
  'evidence_index',
  'anchors',
  'points',
  'geometry_tolerance',
  'tolerances',
  'inspections',
  'instance_fir',
  'keep_need',
  'intentional_divergence',
  'target_policy',
  'claim',
  'reference_eligible',
  'eligibility_rationale',
  'targets_ms',
  'sampling_profile',
  'batch_id',
  'batch_ordinal',
  'type',
  'observable',
  'linkage_valid',
  'visibility',
  'correctness',
  'phase',
  'fallback_endpoint',
  'start',
  'end',
  'independent_control_status',
  'source_identity_basis',
  'expected_roster',
  'required_control_count',
  'configured_floor_count',
  'independent',
  'independently_labeled',
  'master_case_id',
  'minimum_independent_identities',
  'review_status',
  'landmark_id',
  'control_ids',
  'anchor_ids',
  'noncollinear',
  'semantic_areas',
  'missing_case_ids',
  'missing_cell_ids',
  'missing_map_ids',
  'observed_case_ids',
  'expected_case_ids',
  'missing_variants',
  'actual_master_n',
  'actual_source_n',
  'positive_n',
  'negative_n',
  'multi_n',
  'planned_allocation',
  'actual_attempt_n',
  'completed_n',
  'check_id',
  'checks',
  'reference_behavior',
  'recognition',
  'eligible_cases',
  'attempted_rows',
  'missing_rows',
  'complete_comparisons',
  'expectation_only_cases',
  'ineligible_cases',
  'defects',
  'unavailable',
  'reference',
  'manifest_id',
  'results_id',
  'oracle_results_sha256',
  'evidence_validity',
  'metrics',
  'profiles',
  'ineligible',
  'correct_positive_ids',
  'wrong_positive_ids',
  'accepted_negatives',
  'recognized_negatives',
  'wrong_identities',
  'extra_false_positive_selections',
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
  'image_path',
  'derived_from',
  'build_inputs',
  'notices',
  'modifications',
  'uses',
  'status',
  'scope',
  'reason',
  'evidence_ids',
  'reviewer',
  'reviewed_at',
  'owner',
  'missing_evidence',
  'affected_milestone',
  'next_action',
  'expression',
  'text_locator',
  'text_sha256',
  'declaration_basis',
  'conclusion',
  'name',
  'version',
  'revision',
  'commit',
  'dirty',
  'closure_status',
  'path',
  'locator',
  'size_bytes',
  'role',
  'relationship',
  'map_id',
  'source_key',
  'frame_revision',
  'artwork_sha256',
  'config_sha256',
  'game_xyz',
  'artwork_pixel',
  'normalized',
  'floor_group_id',
  'heading_convention',
  'tolerance',
  'uncertainty',
  'source_ids',
  'review_ids',
  'x',
  'y',
  'z',
  'width',
  'height',
  'view_box',
  'resources',
  'group_id',
  'floor',
  'map_ids',
  'reference_commit',
  'reference_dirty',
  'rat_eye_commit',
  'rat_eye_dirty',
  'file_count',
  'svg_count',
  'labs_tile_count',
  'icebreaker_floor_count',
  'marker_resource_count',
  'closure_complete',
  'freeze_id',
  'collected_at',
  'metadata_only',
  'collection_id',
  'private_reference',
  'repository_fixture',
  'report_export',
  'release',
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
  'use',
  'scope_paths',
  'source_id',
  'display_cell_id',
  'provenance_ids',
  'adjudication_ids',
  'truth',
  'label',
  'initial_context',
  'ordered_inputs',
  'expected_effects',
  'profile',
  'seam',
  'input',
  'acquisition',
  'parent_id',
  'transform',
  'limitations',
  'os_scale_percent',
  'evidence_class',
  'case_ids',
  'cells',
  'required',
  'applicable',
  'attempted',
  'stratum_id',
  'allocation',
  'disposition',
  'skip_decision_id',
  'case_id',
  'input_sha256',
  'result',
  'comparison',
  'stage_timings',
  'errors',
  'marker',
  'title_roi',
  'ocr_text',
  'candidates',
  'outcome',
  'detections',
  'unmatched',
  'duplicates',
  'selected_evidence_ids',
  'decision',
  'reasons',
  'facts',
  'snapshot_ids',
  'target_policy_id',
  'heading',
  'extract_text',
  'transit_text',
  'matched_ids',
  'ocr_spans',
  'confidence',
  'score',
  'item_id',
  'expected',
  'observed',
  'basis',
  'divergence',
  'request_id',
  'generation',
  'ordinal',
  'executor',
  'evidence_mode',
  'intended_path',
  'actual_path',
  'terminal_outcome',
  'trigger_kind',
  'clock_domain',
  'stages',
  'start_tick',
  'end_tick',
  'qpc_frequency',
  'missing_stage_reasons',
  'endpoint',
  'trigger',
  'observer',
  'external_data_age_ms',
  'recording_id',
  'first_frame',
  'last_frame',
  'clock',
  'method',
  'sample_count',
  'lower_ms',
  'upper_ms',
  'value_ms',
  'setup_alias',
  'hardware',
  'windows',
  'runtime',
  'app_build',
  'viewport',
  'display',
  'cpu',
  'gpu',
  'ram',
  'ram_bytes',
  'build_number',
  'architecture',
  'sdk',
  'dart_version',
  'flutter_version',
  'framework_revision',
  'engine_revision',
  'locale',
  'display_mode',
  'warm_state',
  'monitor_origin',
  'origin',
  'client_width',
  'client_height',
  'ui_scale',
  'uncertainty_ms',
  'measurements',
  'initialization_ms',
  'startup',
  'first_scan',
  'map_load_ms',
  'map_switch_ms',
  'pan_ms',
  'zoom_ms',
  'floor_switch_ms',
  'process_cpu_ms',
  'process_memory_bytes',
  'interaction_path_id',
  'measurement_complete_n',
  'expected_policy',
  'topology',
  'run_id',
  'environment_id',
  'inputs',
  'planned_checks_id',
  'coverage',
  'denominators',
  'timing',
  'strata',
  'divergences',
  'display_matrix',
  'exports',
  'gates',
  'rights_blockers',
  'planned',
  'actual',
  'count',
  'expected_only',
  'observed_count',
  'unverified',
  'blocked',
  'excluded',
  'missing',
  'skipped',
  'total',
  'completed',
  'failed',
  'p50',
  'p95',
  'mean',
  'min',
  'max',
  'cold',
  'warm',
  'offline',
  'live_user',
  'event',
  'progression',
  'progress',
  'level',
  'completed_task_ids',
  'progression_changed',
  'fir',
  'quantity',
  'mode',
  'policy',
  'session',
  'history',
  'correction',
  'persistence',
  'import',
  'effects',
  'non_effects',
};
const _semanticFields = {
  'state',
  'args',
  'equals',
  'progression',
  'progress',
  'completed_task_ids',
  'progression_changed',
  'session',
  'history',
  'correction',
  'persistence',
  'import',
};
const _syntheticObjects = {'state', 'args', 'equals'};
const _idDictionaries = {
  'missing_stage_reasons',
  'outcome_counts',
  'unique_master_outcome_counts',
  'internal_stages',
  'internal_stage_ms',
  'missing_reasons',
  'profiles',
  'targets_ms',
};
final _forbiddenKey = RegExp(
  r'(^|_)(tokens?|secrets?|passwords?|credentials?|accounts?|chats?|username|email|cookies?|authorization|api_?keys?|access_?keys?|local_locators|source_root|materialized_root|input_manifest_path|attachments?|bytes|base64|raw_capture|private_locator|personal_progress|appdata)(_|$)',
  caseSensitive: false,
);
// Embedded Unix paths need an attached token, not a standalone separator or
// division operator. Complete strings starting with '/' are refused separately.
final _absolute = RegExp(
  r'(^|[\s"\x27=(:,;\[\{])(?:[a-zA-Z]:[/\\]|\\\\|file:|/(?![/\s"\x27]|$))',
  caseSensitive: false,
);
final _binaryAttachment = RegExp(
  r'\.(exe|dll|so|dylib|zip|7z|tar|gz|mp4|mkv|avi|mov|traineddata)$',
  caseSensitive: false,
);

bool isPortableRelativePath(String value) =>
    value.isNotEmpty &&
    !value.startsWith('/') &&
    !value.contains('\\') &&
    !value.contains(':') &&
    value
        .split('/')
        .every((part) => part.isNotEmpty && part != '.' && part != '..');

String _base(String key) =>
    key.endsWith('_reason') ? key.substring(0, key.length - 7) : key;

ExportDecision inspectExport(
  Map<String, dynamic> payload,
  List<String> artifactIds,
  Map<String, dynamic> provenance, {
  String use = 'report_export',
}) {
  final blockers = <String>[];
  if (!_uses.contains(use)) blockers.add('Unsupported scoped use: $use.');
  for (final entry in {'payload': payload, 'provenance': provenance}.entries) {
    try {
      validateRecord(entry.value);
    } on ContractException catch (error) {
      blockers.add('${entry.key}: ${error.message}');
    }
  }
  if (provenance['record_type'] != 'provenance') {
    blockers.add('The use ledger must be a provenance record.');
  }
  if (payload['record_type'] == 'baseline_summary' &&
      payload['attempt_bundle_id'] != null &&
      (payload['provenance_ids'] is! List ||
          (payload['provenance_ids'] as List).isEmpty)) {
    blockers.add(
      'payload: measured summary requires explicit observation provenance_ids.',
    );
  }
  final roots = _recordFields[payload['record_type']];
  if (roots == null) blockers.add('Record type is not export-allowlisted.');
  final requested = artifactIds.toSet();
  if (requested.isEmpty) {
    blockers.add('Export requires explicit artifact linkage.');
  }

  bool metadataAttachmentLocation(String where) {
    if (payload['record_type'] == 'provenance') {
      return RegExp(
        r'^payload\.artifacts\[\d+\]\.(source(?:\.resources\[\d+\])?|declared_terms)$',
      ).hasMatch(where);
    }
    if (payload['record_type'] == 'source_intake' ||
        payload['record_type'] == 'source_lock') {
      return RegExp(
        r'^payload\.(files\[\d+\]|effective_inputs\.(config|native|model|catalog|build|archive|adapter|instrumentation|packages|maps)\[\d+\])$',
      ).hasMatch(where);
    }
    return false;
  }

  final privacyBlockers = <String>[];
  void walk(
    Object? value,
    String where, {
    bool synthetic = false,
    bool root = false,
    bool dictionary = false,
    bool semanticObject = false,
    bool caseRow = false,
  }) {
    final blockers = privacyBlockers;
    if (value is Map) {
      // Only original synthetic fixture scenarios permit progression semantics.
      final caseSynthetic =
          caseRow &&
          payload['record_type'] == 'fixture_manifest' &&
          ((payload['data_class'] == 'synthetic' &&
                  value['role'] == 'expectation_only') ||
              value['acquisition'] == 'synthetic');
      final isSynthetic = synthetic || caseSynthetic;
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          blockers.add('$where has a non-string field.');
          continue;
        }
        final base = _base(key);
        final normalizedKey = key
            .replaceAllMapped(
              RegExp(r'([a-z0-9])([A-Z])'),
              (match) => '${match[1]}_${match[2]}',
            )
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9_]'), '_');
        if (_forbiddenKey.hasMatch(normalizedKey) &&
            !{
              'size_bytes',
              'stride_bytes',
              'ram_bytes',
              'process_memory_bytes',
            }.contains(_base(normalizedKey))) {
          blockers.add('$where.$key is forbidden.');
        } else {
          final bool notAllowlisted;
          if (root) {
            notAllowlisted =
                !(_common.contains(base) || (roots?.contains(base) ?? false));
          } else if (dictionary) {
            notAllowlisted =
                key.isEmpty ||
                key.startsWith('/') ||
                _absolute.hasMatch(key) ||
                RegExp(r'[\x00-\x1f\\]').hasMatch(key);
          } else if (semanticObject) {
            notAllowlisted = !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(key);
          } else {
            notAllowlisted = !_fields.contains(base);
          }
          if (notAllowlisted) {
            blockers.add('$where.$key is not allowlisted.');
          }
        }
        if (_semanticFields.contains(base) && !isSynthetic) {
          blockers.add(
            '$where.$key requires an original synthetic fixture scenario.',
          );
        }
        if (base == 'provenance_ids' && entry.value is List) {
          requested.addAll((entry.value as List).whereType<String>());
        }
        final pathKey = _base(normalizedKey);
        if (!key.endsWith('_reason') &&
            (pathKey == 'path' ||
                pathKey.endsWith('_path') ||
                pathKey == 'locator' ||
                pathKey.endsWith('_locator'))) {
          final path = entry.value;
          if (path != null && path is! String) {
            blockers.add('$where.$key must be a string or an honest null.');
          } else if (path is String) {
            final uri = Uri.tryParse(path);
            final publicSource =
                (pathKey == 'locator' || pathKey.endsWith('_locator')) &&
                uri?.scheme == 'https' &&
                uri!.host.isNotEmpty &&
                uri.userInfo.isEmpty &&
                !uri.hasQuery &&
                !uri.hasFragment;
            if (!publicSource && !isPortableRelativePath(path)) {
              blockers.add('$where.$key is not portable.');
            }
            // Source ledger paths describe hashes, not attachment bytes.
            if (_binaryAttachment.hasMatch(path) &&
                !metadataAttachmentLocation(where)) {
              blockers.add('$where.$key is a forbidden attachment.');
            }
          }
        }
        walk(
          entry.value,
          '$where.$key',
          synthetic: isSynthetic,
          dictionary: _idDictionaries.contains(base),
          semanticObject:
              semanticObject ||
              (isSynthetic && _syntheticObjects.contains(base)),
        );
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        walk(
          value[i],
          '$where[$i]',
          synthetic: synthetic,
          semanticObject: semanticObject,
          caseRow:
              payload['record_type'] == 'fixture_manifest' &&
              where == 'payload.cases',
        );
      }
    } else if (value is String) {
      if (_absolute.hasMatch(value) || value.startsWith('/')) {
        blockers.add('$where contains an absolute/private locator.');
      }
      final uri = Uri.tryParse(value);
      if (uri != null &&
          ({'data', 'mailto'}.contains(uri.scheme) ||
              (uri.scheme == 'http') ||
              (uri.scheme == 'https' &&
                  (uri.userInfo.isNotEmpty ||
                      uri.hasQuery ||
                      uri.hasFragment)))) {
        blockers.add(
          '$where contains a non-public source locator or attachment.',
        );
      }
    }
  }

  walk(payload, 'payload', root: true);
  blockers.addAll(privacyBlockers);
  final artifacts = <String, Map>{};
  if (provenance['artifacts'] is List) {
    for (final row in provenance['artifacts'] as List) {
      if (row is Map && row['id'] is String) {
        artifacts[row['id'] as String] = row;
      }
    }
  }
  final visited = <String>{};
  void inspectArtifact(String id) {
    if (!visited.add(id)) return;
    final row = artifacts[id];
    if (row == null) {
      blockers.add('$id: missing artifact for $use.');
      return;
    }
    final dispositions = row['uses'];
    final decision = dispositions is Map ? dispositions[use] : null;
    if (decision is! Map || decision['status'] != 'cleared') {
      blockers.add(
        '$id: $use ${decision is Map ? decision['status'] : 'unresolved'}; ${decision is Map ? decision['reason'] : 'missing scoped decision'}.',
      );
    }
    for (final relation in ['depends_on', 'derived_from', 'build_inputs']) {
      if (row[relation] is List) {
        for (final dependency in (row[relation] as List).whereType<String>()) {
          inspectArtifact(dependency);
        }
      }
    }
  }

  for (final id in requested) {
    inspectArtifact(id);
  }
  return ExportDecision(
    blockers.isEmpty,
    List.unmodifiable(blockers),
    List.unmodifiable(requested),
    List.unmodifiable(privacyBlockers),
  );
}

Map<String, dynamic> sanitizedExport(
  Map<String, dynamic> payload,
  List<String> artifactIds,
  Map<String, dynamic> provenance, {
  String use = 'report_export',
}) {
  final decision = inspectExport(payload, artifactIds, provenance, use: use);
  if (!decision.allowed) {
    throw ContractException('Export refused: ${decision.blockers.join(' | ')}');
  }
  return payload;
}
