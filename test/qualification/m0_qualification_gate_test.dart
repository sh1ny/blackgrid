import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/contracts.dart';
import '../../tool/qualification/report.dart';
import 'm0_comparison_test.dart' as comparison_examples;
import 'm0_report_test.dart' as report_examples;

// Entirely fabricated, in-memory test metadata. The consumer's `actual` and
// `derived` discriminators below model supported evidence records, not collected
// pixels, native executions, game interaction, user trials, or permission grants.
// Nothing here is written to an observation file or a delivered M0 dossier.
const _resolutions = [(1920, 1080), (2560, 1440), (3440, 1440), (3840, 2160)];
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
// Configured identities, not independently surveyed coordinates/artwork.
const _floors = <String, List<String>>{
  'factory': ['Ground_Floor', 'Second_Floor', 'Third_Floor', 'Basement'],
  'customs': [
    'Ground_Level',
    'Second_Floor',
    'Third_Floor',
    'Underground_Level',
  ],
  'woods': ['Ground_Level'],
  'shoreline': [
    'Ground_Level',
    'Second_Floor',
    'Third_Floor',
    'Underground_Level',
  ],
  'interchange': ['Ground_Level', 'First_Floor', 'Second_Floor'],
  'lab': ['First_Level', 'Second_Level', 'Technical_Level'],
  'reserve': ['Ground_Level', 'Bunkers'],
  'lighthouse': ['Ground_Level'],
  'streetsoftarkov': [
    'Ground_Level',
    'Second_Floor',
    'Third_Floor',
    'Fourth_Floor',
    'Fifth_Floor',
    'Underground_Level',
  ],
  'groundzero': [
    'Ground_Level',
    'Second_Floor',
    'Third_Floor',
    'Underground_Level',
  ],
  'terminal': ['Ground_Level'],
  'icebreaker': [
    'Control_Room',
    'Engine_Room',
    'Engine_Room_Upper',
    'Fuel_Pumps_Lower',
    'Fuel_Pumps',
    'Storage_Security',
    'Infirmary',
    'Helipad',
    'Gym_Canteen',
    'Accommodation_Lower',
    'Accommodation_Mid',
    'Accommodation_Upper',
    'Officers_Deck',
    'Stairs_Blocked',
    'Bridge',
    'Bridge_Roof',
  ],
  'labyrinth': [],
};

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

Map<String, dynamic> _reviewedFixture(
  String id,
  String profile,
  Map<String, dynamic> truth, {
  int width = 1920,
  int height = 1080,
  int scale = 100,
}) => comparison_examples.fixture(id, profile, truth)
  ..['source_id'] = 'synthetic-source-$id'
  ..['acquisition'] = 'actual'
  ..['display_cell_id'] = '$width-$scale'
  ..['input'] = {
    'path': 'synthetic-test-metadata/$id.json',
    'sha256': sha256Json({'synthetic_input_id': id}),
    'width': width,
    'height': height,
  }
  ..['review'] = {'status': 'adjudicated'}
  ..['adjudication_ids'] = ['synthetic-reviewer-a', 'synthetic-reviewer-b']
  ..['truth']['independent_of_reference_output'] = true;

Map<String, dynamic> _planned(
  String id,
  String scope,
  String stratum,
  int allocation,
  String freeze, {
  List<String> cases = const [],
  List<String> evidence = const [],
  Map<String, dynamic> fields = const {},
}) => {
  'id': id,
  'required': true,
  'applicable': true,
  'attempted': true,
  'owner': scope.startsWith('live') ? 'user' : 'synthetic-evidence-owner',
  'scope': scope,
  'stratum_id': stratum,
  'allocation': allocation,
  'reason': 'Synthetic consumer record requires its applicable observation.',
  'case_ids': cases,
  'evidence_ids': evidence,
  'disposition': 'observed',
  'freeze_id': freeze,
  ...fields,
};

Map<String, dynamic> _syntheticReplay(Map<String, dynamic> fixture) {
  final truth = fixture['truth'] as Map<String, dynamic>;
  final result = switch (fixture['profile']) {
    'host_resolution' => comparison_examples.host(
      fixture['id'] == 'variant-1' ? 'Sell' : 'Check',
    ),
    'engine_multi' => comparison_examples.multi([
      comparison_examples.detection('synthetic-left', 10, 'item-a'),
      comparison_examples.detection('synthetic-right', 300, 'item-b'),
    ]),
    _ => comparison_examples.engine(
      truth['label'] == 'readable_positive' ? 'recognized' : 'rejected',
      truth['item_id'] as String?,
    ),
  };
  return comparison_examples.observation(
    fixture['id'] as String,
    fixture['profile'] as String,
    result,
  )..['input_sha256'] = fixture['input']['sha256'];
}

Map<String, Map<String, dynamic>> _syntheticCompleteConsumerBundle() {
  // Reuse the established complete named setup, physical-video linkage, and
  // exact 17/17, 17/16, 16/17 automatic/manual warm-path allocation.
  final records = report_examples.finiteLiveInputs();
  final source = records['source_lock']!;
  final checks = <Map<String, dynamic>>[];
  final cases = <Map<String, dynamic>>[];
  final cells = <Map<String, dynamic>>[];
  final masters = <String, Map<String, dynamic>>{};
  for (final (width, height) in _resolutions) {
    for (final slot in _masterSlots) {
      final label = switch (slot) {
        'empty-no-marker' => 'rejection',
        'ui-chrome' => 'chrome',
        'ambiguous' => 'ambiguous',
        'occluded' => 'occluded',
        _ => 'readable_positive',
      };
      final id = 'synthetic-master-$width-$slot';
      final fixture = _reviewedFixture(
        id,
        slot == 'multi' ? 'engine_multi' : 'engine_inspection',
        slot == 'multi'
            ? comparison_examples.multiTruth()
            : comparison_examples.inspectionTruth(
                label,
                label == 'readable_positive' ? 'synthetic-item-$slot' : null,
              ),
        width: width,
        height: height,
      )..['master_slot'] = slot;
      masters['$width:$slot'] = fixture;
      cases.add(fixture);
    }
    for (final scale in _scales) {
      final cellId = '$width-$scale';
      final variants = <String>[];
      for (final kind in [
        'positive',
        'no-marker',
        'chrome-ambiguous',
        'multi',
      ]) {
        final parentSlot = switch (kind) {
          'positive' => 'ordinary-positive-a',
          'no-marker' => 'empty-no-marker',
          'chrome-ambiguous' => 'ui-chrome',
          _ => 'multi',
        };
        final parent = masters['$width:$parentSlot']!;
        final id = 'synthetic-variant-$cellId-$kind';
        final transform = {
          'type': 'synthetic-test-rescale',
          'os_scale_percent': scale,
          'parent_bindings': [
            {'id': parent['id'], 'sha256': parent['input']['sha256']},
          ],
        };
        final fixture =
            _reviewedFixture(
                id,
                parent['profile'] as String,
                _copy(parent['truth']),
                width: width,
                height: height,
                scale: scale,
              )
              ..['acquisition'] = 'derived'
              ..['source_id'] = parent['source_id']
              ..['parent_id'] = parent['id']
              ..['transform'] = transform
              ..['recipe_sha256'] = sha256Json(transform)
              ..['variant_kind'] = kind;
        variants.add(id);
        cases.add(fixture);
      }
      cells.add({
        'id': cellId,
        'width': width,
        'height': height,
        'os_scale_percent': scale,
        'evidence_class': 'offline',
        'case_ids': variants,
        'evidence_ids': ['synthetic-results'],
        'limitations':
            'Fabricated serialized test metadata; not native display evidence.',
      });
    }
  }
  for (final area in _semanticAreas) {
    // Keep variant-1 for the existing live helper's case linkage.
    final id = area == 'catalog' ? 'variant-1' : 'synthetic-semantic-$area';
    cases.add(
      _reviewedFixture(
        id,
        'host_resolution',
        comparison_examples.policyTruth('Check', divergence: id == 'variant-1'),
      )..['coverage_tags'] = ['$area:synthetic-consumer-regression'],
    );
  }

  final controls = <Map<String, dynamic>>[];
  final anchors = <Map<String, dynamic>>[];
  final roster = <Map<String, dynamic>>[];
  final artworkInputs = <Map<String, dynamic>>[];
  final configHash = source['effective_inputs']['config'][0]['sha256'];
  for (final entry in _floors.entries) {
    final map = entry.key;
    final revision = map == 'lab' ? '1' : '0';
    final artworkPath = 'synthetic-test-metadata/maps/$map.svg';
    final artworkHash = sha256Json({'synthetic_artwork_id': map});
    artworkInputs.add({
      'id': 'synthetic-artwork-$map',
      'sha256': artworkHash,
      'version': revision,
      'locator': artworkPath,
    });
    roster.add({
      'map_id': map,
      'source_key': map,
      'frame_revision': revision,
      'artwork_path': artworkPath,
      'floor_group_ids': entry.value,
      'required_control_count': 3,
      'pin_aliases': map == 'lab' ? ['thelab'] : <String>[],
    });
    final common = <String, dynamic>{
      'map_id': map,
      'source_key': map,
      'frame_revision': revision,
      'artwork_path': artworkPath,
      'artwork_sha256': artworkHash,
      'config_sha256': configHash,
      'independent_of_reference_output': true,
      'review_ids': ['synthetic-reviewer-a', 'synthetic-reviewer-b'],
      'uncertainty': 1,
    };
    var ordinal = 0;
    for (final (x, z) in [(0, 0), (100, 0), (0, 100)]) {
      controls.add({
        ...common,
        'id': 'synthetic-control-$map-${ordinal++}',
        'game_xyz': {'x': x, 'y': 0, 'z': z},
        'artwork_pixel': {'x': x + 10, 'y': z + 10},
        'normalized': {'x': (x + 10) / 200, 'y': (z + 10) / 200},
        'floor_group_id': entry.value.isEmpty
            ? 'synthetic-raster'
            : entry.value.first,
        'heading_convention': 'clockwise-north',
        'tolerance': 1,
        'source_ids': ['synthetic-survey-$map-$x-$z'],
      });
    }
    for (final floor in entry.value) {
      final floorPath = map == 'icebreaker'
          ? 'synthetic-test-metadata/maps/icebreaker/$floor.png'
          : artworkPath;
      final floorHash = map == 'icebreaker'
          ? sha256Json({'synthetic_floor_image_id': floor})
          : artworkHash;
      if (map == 'icebreaker') {
        artworkInputs.add({
          'id': 'synthetic-icebreaker-image-$floor',
          'sha256': floorHash,
          'version': revision,
          'locator': floorPath,
        });
      }
      anchors.add({
        ...common,
        'id': 'synthetic-floor-$map-$floor',
        'kind': 'floor_artwork',
        'floor_group_id': floor,
        'artwork_path': floorPath,
        'artwork_sha256': floorHash,
        'width': 200,
        'height': 200,
        'points': [
          {'x': 10, 'y': 10},
        ],
        'source_ids': ['synthetic-floor-survey-$map-$floor'],
      });
    }
    if (map == 'lab' || map == 'labyrinth') {
      for (final kind
          in map == 'lab'
              ? ['tile_seam', 'raster_extent']
              : ['raster_extent']) {
        anchors.add({
          ...common,
          'id': 'synthetic-$kind-$map',
          'kind': kind,
          'floor_group_id': null,
          'floor_group_id_reason': 'Synthetic extent/seam is frame-wide.',
          'width': 200,
          'height': 200,
          'points': [
            {'x': 0, 'y': 0},
            {'x': 200, 'y': 200},
          ],
          'source_ids': ['synthetic-extent-survey-$map-$kind'],
        });
      }
    }
  }
  source['effective_inputs']['maps'] = artworkInputs;
  source['freeze_id'] = sourceFreezeId(source);
  final freeze = source['freeze_id'] as String;
  records['fixture_manifest'] = comparison_examples.manifest(cases)
    ..['freeze_id'] = freeze;
  records['map_controls'] = report_examples.record(
    'map_controls',
    'synthetic-maps',
    {'expected_roster': roster, 'controls': controls, 'anchors': anchors},
  );
  records['display_matrix']!['cells'] = cells;
  records['oracle_results'] =
      comparison_examples.results(
          records['fixture_manifest']!,
          cases.map(_syntheticReplay).toList(),
        )
        ..['run_id'] = 'test-run'
        ..['environment_id'] = records['environment']!['id'];

  final attemptBundle = records['attempt_bundle']!;
  attemptBundle['freeze_id'] = freeze;
  final attempts = (attemptBundle['attempts'] as List)
      .cast<Map<String, dynamic>>();
  final caseById = {for (final fixture in cases) fixture['id']: fixture};
  for (final row in attempts) {
    final fixture = caseById[row['case_id']]!;
    row['input_sha256'] = fixture['input']['sha256'];
    row['master_case_id'] = fixture['id'];
    row['source_id'] = fixture['source_id'];
  }
  // A known completed wrong identity must remain in the live denominator without
  // inventing a correct endpoint. Valid evidence does not mean perfect accuracy.
  attempts.first['terminal_outcome'] = 'wrong_id';
  attempts.first['endpoint'] = null;
  attempts.first['endpoint_reason'] =
      'Synthetic known completed wrong identity.';
  checks.addAll(
    (records['planned_checks']!['checks'] as List)
        .cast<Map<String, dynamic>>()
        .map((check) => _copy(check)..['freeze_id'] = freeze),
  );

  final measurementTemplates = <String, Map<String, dynamic>>{};
  void addMeasurements(
    String scope,
    String stratum,
    int count, {
    String? profile,
  }) {
    final template = measurementTemplates.putIfAbsent(
      scope,
      () => scope == 'live-burst'
          ? _copy(attempts[1])
          : report_examples.measuredInputs(
                  scope,
                )['attempt_bundle']!['attempts'][0]
                as Map<String, dynamic>,
    );
    final fixture = scope == 'offline-warm'
        ? masters['${stratum.split(':').first}:${profile == 'full-viewport' ? 'multi' : 'ordinary-positive-a'}']!
        : caseById['variant-1']!;
    for (var index = 0; index < count; index++) {
      final row = _copy(template);
      final ordinal = attempts.length + 1;
      row.addAll({
        'id': 'synthetic-measurement-$ordinal',
        'ordinal': ordinal,
        'request_id': 'synthetic-request-$ordinal',
        'generation': 'synthetic-generation-$ordinal',
        'scope': scope,
        'stratum_id': stratum,
        'sampling_profile': ?profile,
        if (scope == 'offline-warm')
          'batch_ordinal': index < 34
              ? 1
              : index < 67
              ? 2
              : 3,
        'case_id': fixture['id'],
        'master_case_id': fixture['id'],
        'source_id': fixture['source_id'],
        'profile': fixture['profile'],
        'input_sha256': fixture['input']['sha256'],
        'display_cell': {
          'width': fixture['input']['width'],
          'height': fixture['input']['height'],
          'os_scale_percent': 100,
        },
        'viewport': {
          'width': fixture['input']['width'],
          'height': fixture['input']['height'],
          'client_width': fixture['input']['width'],
          'client_height': fixture['input']['height'],
          'ui_scale': 1,
        },
      });
      for (final stamp in [
        row['trigger'],
        row['endpoint'],
        if (row['measurements'] is Map) ...[
          row['measurements']['startup']?['start'],
          row['measurements']['startup']?['end'],
          row['measurements']['first_scan']?['start'],
          row['measurements']['first_scan']?['end'],
        ],
      ].whereType<Map>()) {
        for (final key in ['ordinal', 'request_id', 'generation', 'case_id']) {
          stamp[key] = row[key];
        }
      }
      attempts.add(row);
    }
    checks.add(
      _planned(
        'synthetic-$scope-$stratum',
        scope,
        stratum,
        count,
        freeze,
        cases: [fixture['id'] as String],
        evidence: [attemptBundle['id'] as String],
        fields: {'profile': ?profile},
      ),
    );
  }

  for (final (width, _) in _resolutions) {
    for (final profile in ['host-inspection', 'full-viewport']) {
      addMeasurements('offline-warm', '$width:$profile', 100, profile: profile);
    }
  }
  addMeasurements('offline-cold', 'named-primary-setup', 10);
  addMeasurements('live-cold', 'named-primary-setup', 10);
  for (var burst = 1; burst <= 3; burst++) {
    addMeasurements('live-burst', 'burst-$burst', 5);
  }
  for (final map in ['vector-multilevel', 'lab', 'icebreaker', 'labyrinth']) {
    addMeasurements('map-startup-memory', map, 3);
  }
  attemptBundle['attempts'] = attempts;

  for (final fixture in masters.values) {
    checks.add(
      _planned(
        fixture['id'] as String,
        'scanner-master',
        '${fixture['input']['width']}',
        1,
        freeze,
        cases: [fixture['id'] as String],
        evidence: [fixture['id'] as String],
        fields: {'master_slot': fixture['master_slot']},
      ),
    );
  }
  for (final fixture in cases.where((row) => row.containsKey('variant_kind'))) {
    checks.add(
      _planned(
        fixture['id'] as String,
        'display-image-variant',
        fixture['display_cell_id'] as String,
        1,
        freeze,
        cases: [fixture['id'] as String],
        evidence: [fixture['id'] as String],
        fields: {'variant_kind': fixture['variant_kind']},
      ),
    );
  }
  checks.add(
    _planned(
      'synthetic-offline-replay',
      'offline-characterization',
      'synthetic-corpus',
      cases.length,
      freeze,
      cases: cases.map((fixture) => fixture['id'] as String).toList(),
      evidence: [records['oracle_results']!['id'] as String],
    ),
  );
  for (final row in roster) {
    checks.add(
      _planned(
        'synthetic-map-${row['map_id']}',
        'independent-map-control',
        row['map_id'] as String,
        3,
        freeze,
        evidence: controls
            .where((control) => control['map_id'] == row['map_id'])
            .map((control) => control['id'] as String)
            .toList(),
        fields: {
          'source_key': row['source_key'],
          'frame_revision': row['frame_revision'],
        },
      ),
    );
  }
  for (final anchor in anchors) {
    final id = anchor['kind'] == 'tile_seam'
        ? 'labs-tile-seam'
        : anchor['id'] as String;
    checks.add(
      _planned(
        id,
        anchor['kind'] == 'floor_artwork'
            ? 'floor-artwork-anchor'
            : 'raster-extent',
        anchor['map_id'] as String,
        1,
        freeze,
        evidence: [anchor['id'] as String],
        fields: {
          'map_id': anchor['map_id'],
          'source_key': anchor['source_key'],
          'frame_revision': anchor['frame_revision'],
          if (anchor['kind'] == 'floor_artwork')
            'floor_group_id': anchor['floor_group_id'],
          'image_path': anchor['artwork_path'],
        },
      ),
    );
  }
  for (final cell in cells) {
    // Comprehensive native display qualification remains visible but is M2/M6,
    // not an M0 requirement. Even the named baseline is not this full obligation.
    checks.add({
      ..._planned(
        'synthetic-native-${cell['id']}',
        'native-display',
        cell['id'] as String,
        1,
        freeze,
      ),
      'required': false,
      'attempted': false,
      'disposition': 'missing',
      'freeze_id': null,
      'freeze_id_reason':
          'Comprehensive native display observations are not collected.',
      'reason': 'Later-milestone native display qualification is unverified.',
    });
  }
  records['planned_checks']!['checks'] = checks;
  return records;
}

List<Map<String, dynamic>> _gates(Map<String, dynamic> dossier) =>
    (dossier['qualification']['gates'] as List).cast<Map<String, dynamic>>();

String _requiredNonpassDiagnostics(Map<String, dynamic> dossier) =>
    _gates(dossier)
        .where((gate) => gate['required'] == true && gate['status'] != 'pass')
        .map((gate) => '${gate['id']}: ${gate['status']}: ${gate['reason']}')
        .join('\n');

void main() {
  test('synthetic consumer bundle qualifies all required M0 gates without comprehensive native16', () {
    final records = _syntheticCompleteConsumerBundle();
    final dossier = buildDossier(records, runId: 'test-run');
    final report = dossier['qualification'] as Map<String, dynamic>;
    expect(
      report['status'],
      'qualified',
      reason: _requiredNonpassDiagnostics(dossier),
    );
    expect(
      _gates(dossier).where((gate) => gate['required'] == true),
      everyElement(containsPair('status', 'pass')),
    );
    expect(report['display_matrix']['cells'], hasLength(16));
    expect(
      report['display_matrix']['cells']
          .map((dynamic cell) => cell['id'])
          .toSet(),
      {
        for (final (width, _) in _resolutions)
          for (final scale in _scales) '$width-$scale',
      },
    );
    expect(
      _gates(
        dossier,
      ).where((gate) => (gate['id'] as String).startsWith('display-offline-')),
      hasLength(16),
    );
    final native = _gates(dossier)
        .where(
          (gate) =>
              (gate['id'] as String).startsWith('planned-synthetic-native-'),
        )
        .toList();
    expect(native, hasLength(16));
    expect(
      native,
      everyElement(
        allOf(
          containsPair('required', false),
          containsPair('status', 'unverified'),
        ),
      ),
    );
    expect(
      report_examples.gate(dossier, 'user-native-visible-baseline'),
      allOf(
        containsPair('required', true),
        containsPair('status', 'pass'),
        containsPair('evidence_ids', contains(records['environment']!['id'])),
      ),
    );
    final warm = (records['attempt_bundle']!['attempts'] as List)
        .where((dynamic row) => row['scope'] == 'live-warm')
        .toList();
    expect(warm, hasLength(200));
    expect(
      warm.map((dynamic row) => canonicalJson(row['display_cell'])).toSet(),
      hasLength(1),
    );
    expect(report['coverage']['scanner_masters']['actual_master_n'], 36);
    expect(
      report['coverage']['maps'],
      everyElement(
        allOf(containsPair('actual', 3), containsPair('status', 'pass')),
      ),
    );
    final measurementChecks = (report['coverage']['checks'] as List)
        .cast<Map<String, dynamic>>()
        .where(
          (check) => [
            'offline-warm',
            'offline-cold',
            'live-warm',
            'live-cold',
            'live-burst',
            'map-startup-memory',
          ].contains(check['scope']),
        )
        .toList();
    expect(measurementChecks, hasLength(19));
    for (final check in measurementChecks) {
      expect(
        check['actual_attempt_n'],
        check['allocation'],
        reason: check['id'] as String,
      );
    }
    final attempts = (records['attempt_bundle']!['attempts'] as List)
        .cast<Map<String, dynamic>>();
    for (final check in measurementChecks.where(
      (check) => check['scope'] == 'offline-warm',
    )) {
      final stratum = attempts
          .where(
            (row) =>
                row['scope'] == 'offline-warm' &&
                row['stratum_id'] == check['stratum_id'] &&
                row['sampling_profile'] == check['profile'],
          )
          .toList();
      expect(
        [
          for (final batch in [1, 2, 3])
            stratum.where((row) => row['batch_ordinal'] == batch).length,
        ],
        [34, 33, 33],
        reason: check['id'] as String,
      );
    }
    final icebreaker = (records['map_controls']!['anchors'] as List)
        .where((dynamic anchor) => anchor['map_id'] == 'icebreaker')
        .toList();
    expect(icebreaker, hasLength(16));
    expect(
      icebreaker.map((dynamic anchor) => anchor['artwork_sha256']).toSet(),
      hasLength(16),
    );
    expect(report['denominators']['missing_case_ids'], isEmpty);
    expect(dossier['baseline_summary']['attempt_n'], 1047);
    expect(dossier['baseline_summary']['outcome_counts']['wrong_id'], 1);
  });

  test('one missing required visible observation makes qualified synthetic bundle incomplete without shrinking denominators', () {
    final records = _syntheticCompleteConsumerBundle();
    final complete = buildDossier(records, runId: 'test-run');
    expect(
      complete['qualification']['status'],
      'qualified',
      reason: _requiredNonpassDiagnostics(complete),
    );
    final row = (records['attempt_bundle']!['attempts'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere(
          (row) =>
              row['scope'] == 'live-warm' &&
              row['terminal_outcome'] == 'correct',
        );
    row['endpoint'] = null;
    row['endpoint_reason'] = 'Synthetic required actionable-visible observation deliberately omitted.';
    final incomplete = buildDossier(records, runId: 'test-run');
    expect(
      incomplete['qualification']['status'],
      'incomplete',
      reason: _requiredNonpassDiagnostics(incomplete),
    );
    expect(
      report_examples.gate(incomplete, 'attempt-evidence-linkage')['status'],
      'pass',
    );
    expect(
      report_examples.gate(incomplete, 'user-native-visible-baseline'),
      allOf(
        containsPair('required', true),
        containsPair('status', 'unverified'),
      ),
    );
    expect(
      report_examples.gate(
        incomplete,
        'planned-live-warm-intended-targeted',
      )['status'],
      'unverified',
    );
    final before =
        complete['qualification']['denominators'] as Map<String, dynamic>;
    final after =
        incomplete['qualification']['denominators'] as Map<String, dynamic>;
    for (final field in [
      'planned_allocation',
      'actual_attempt_n',
      'expected_case_ids',
      'observed_case_ids',
      'missing_case_ids',
    ]) {
      expect(after[field], before[field], reason: field);
    }
    expect(after['completed_n'], before['completed_n'] - 1);
    expect(
      incomplete['baseline_summary']['attempt_n'],
      complete['baseline_summary']['attempt_n'],
    );
    expect(
      incomplete['baseline_summary']['attempt_ids'],
      complete['baseline_summary']['attempt_ids'],
    );
    expect(
      incomplete['baseline_summary']['outcome_counts'],
      complete['baseline_summary']['outcome_counts'],
    );
    expect(
      incomplete['baseline_summary']['actionable_sample_n'],
      complete['baseline_summary']['actionable_sample_n'] - 1,
    );
    expect(
      _gates(incomplete).where((gate) => gate['required'] == true),
      isNot(contains(containsPair('status', 'fail'))),
    );
  });
}
