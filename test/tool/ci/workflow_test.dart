import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'support/no_games_scan.dart';

/// Offline checks of `.github/workflows/ci.yml` and of the rule that only the
/// workflow's qualification step confirms that no game is running.
void main() {
  const workflowPath = '.github/workflows/ci.yml';
  const bundle = r'${{ github.workspace }}\build\windows\x64\runner\Release';
  const gates = [
    'mise run analyze',
    'mise run test',
    'mise run build:release',
    'mise run ci:qualification',
  ];

  late String source;
  late Map<String, dynamic> workflow;
  late List<Map<String, dynamic>> steps;

  Map<String, dynamic> asMap(Object? value) =>
      (value as Map).cast<String, dynamic>();

  setUp(() {
    final file = File(workflowPath);
    expect(file.existsSync(), isTrue, reason: '$workflowPath must exist');
    source = file.readAsStringSync();
    workflow = asMap(toPlain(loadYaml(source)));
    final jobs = asMap(workflow['jobs']);
    expect(jobs, hasLength(1), reason: 'CI is one job (D1)');
    steps = [
      for (final s in (asMap(jobs.values.single)['steps'] as List)) asMap(s),
    ];
  });

  Map<String, dynamic> job() => asMap(asMap(workflow['jobs']).values.single);
  String run(Map<String, dynamic> step) => '${step['run'] ?? ''}'.trim();
  bool usesAction(Map<String, dynamic> step, String action) =>
      '${step['uses'] ?? ''}'.startsWith('$action@');

  /// Index of the step with a script line that is exactly [command], or -1.
  int gateIndex(String command) => steps.indexWhere(
    (s) => run(s).split(RegExp(r'\r?\n')).any((l) => l.trim() == command),
  );

  test('triggers are pull_request and push to main only', () {
    final on = asMap(workflow['on']);
    expect(on.keys.toSet(), {'pull_request', 'push'});
    // Default pull_request types: no `types` filter.
    expect(on['pull_request'] ?? <String, dynamic>{}, isNot(contains('types')));
    expect(asMap(on['push'])['branches'], ['main']);
    expect(source, isNot(contains('pull_request_target')));
  });

  test('a push run has its own concurrency group keyed by github.sha and is '
      'never cancelled', () {
    final concurrency = asMap(workflow['concurrency']);
    expect(
      '${concurrency['group']}',
      contains("format('ci-push-{0}', github.sha)"),
    );
    final cancel = '${concurrency['cancel-in-progress']}';
    expect(cancel, contains("github.event_name == 'pull_request'"));
    expect(cancel, isNot(contains('push')));
  });

  test('pull request runs share one group per PR and cancel in progress', () {
    final concurrency = asMap(workflow['concurrency']);
    final group = '${concurrency['group']}';
    expect(group, contains("github.event_name == 'pull_request'"));
    expect(
      group,
      contains("format('ci-pr-{0}', github.event.pull_request.number)"),
    );
    expect(
      '${concurrency['cancel-in-progress']}',
      contains("github.event_name == 'pull_request'"),
    );
  });

  test(
    'tools come only from mise.toml and every gate runs through mise run',
    () {
      expect(job()['runs-on'], 'windows-2025');
      expect(job()['timeout-minutes'], 120);
      final miseSteps = steps.where((s) => usesAction(s, 'jdx/mise-action'));
      expect(miseSteps, hasLength(1));
      final inputs = asMap(miseSteps.single['with'] ?? <String, dynamic>{});
      for (final key in [
        'version',
        'tool_versions',
        'mise_toml',
        'install_args',
      ]) {
        expect(inputs, isNot(contains(key)), reason: 'no tool override: $key');
      }
      for (final gate in gates) {
        expect(gateIndex(gate), isNonNegative, reason: 'missing gate: $gate');
      }
      final scripts = steps.map(run).join('\n');
      expect(
        RegExp(r'^\s*(flutter|dart)\s', multiLine: true).hasMatch(scripts),
        isFalse,
        reason: 'a step calls flutter or dart outside mise',
      );
      expect(source, isNot(contains('flutter-action')));
      expect(source, isNot(contains('setup-dart')));
    },
  );

  test('the mise install step precedes every gate and has no fallback or '
      'continue-on-error', () {
    final install = steps.indexWhere((s) => usesAction(s, 'jdx/mise-action'));
    expect(install, isNonNegative);
    for (final gate in gates) {
      expect(install, lessThan(gateIndex(gate)), reason: gate);
    }
    expect(steps[install], isNot(contains('continue-on-error')));
    expect(steps[install], isNot(contains('if')));
  });

  test(
    'gate steps run in order analyze, test, build:release, ci:qualification',
    () {
      final indexes = [for (final g in gates) gateIndex(g)];
      expect(indexes, everyElement(isNonNegative));
      expect(indexes, [...indexes]..sort());
      expect(indexes.toSet(), hasLength(gates.length));
    },
  );

  test(
    'no gate step has continue-on-error or an always()/failure() condition',
    () {
      expect(job(), isNot(contains('continue-on-error')));
      for (final step in steps) {
        expect(step, isNot(contains('continue-on-error')), reason: '$step');
        final condition = '${step['if'] ?? ''}';
        expect(condition, isNot(contains('always()')), reason: '$step');
        expect(condition, isNot(contains('failure()')), reason: '$step');
      }
      expect(source, isNot(contains('continue-on-error')));
    },
  );

  test('checkout uses full history and no persisted credentials', () {
    final checkout = steps.firstWhere((s) => usesAction(s, 'actions/checkout'));
    expect(steps.first, same(checkout), reason: 'checkout is first');
    final inputs = asMap(checkout['with']);
    expect(inputs['fetch-depth'], 0);
    expect(inputs['persist-credentials'], false);
  });

  test('the qualification step alone sets the no-games confirmation and the '
      'bundle inputs', () {
    final index = gateIndex('mise run ci:qualification');
    expect(index, isNonNegative);
    final step = steps[index];
    final env = asMap(step['env']);
    expect(env[noGamesVariable], '1');
    expect(env['BLACKGRID_RELEASE_BUNDLE'], bundle);
    expect(env['BLACKGRID_PANEL_OCR_RUNTIME'], bundle);
    expect(step['shell'], 'pwsh');
    final script = run(step);
    final cmake = script.indexOf(
      r'$env:BLACKGRID_CMAKE = (Get-Command cmake).Source',
    );
    expect(cmake, isNonNegative, reason: 'cmake resolved from PATH');
    expect(cmake, lessThan(script.indexOf('mise run ci:qualification')));
    for (var i = 0; i < steps.length; i++) {
      if (i == index) continue;
      expect('${steps[i]}', isNot(contains(noGamesVariable)), reason: '$i');
    }
    expect('${workflow['env']}', isNot(contains(noGamesVariable)));
    expect('${job()['env']}', isNot(contains(noGamesVariable)));
    expect(
      findNoGamesSetters(workflowPath, source),
      hasLength(1),
      reason: 'exactly one env setter in the workflow',
    );
  });

  test('no other tracked script or config sets the no-games confirmation', () {
    final listing = Process.runSync('git', [
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
    ]);
    expect(listing.exitCode, 0, reason: '${listing.stderr}');
    final files = (listing.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l != workflowPath)
        .where(isScannableKind)
        .where((l) => File(l).existsSync());
    final findings = <String>[
      for (final path in files)
        ...findNoGamesSetters(path, File(path).readAsStringSync()),
    ];
    expect(findings, isEmpty, reason: 'files that set $noGamesVariable');
  });

  test('permissions are exactly contents read and no secrets are used', () {
    expect(workflow['permissions'], {'contents': 'read'});
    expect(job(), isNot(contains('permissions')));
    expect(source, isNot(contains('secrets.')));
  });

  test('every uses line is pinned to a 40-hex commit SHA', () {
    final pin = RegExp(r'^[\w.-]+/[\w./-]+@[0-9a-f]{40}$');
    final lines = source.split(RegExp(r'\r?\n'));
    var seen = 0;
    for (var i = 0; i < lines.length; i++) {
      final match = RegExp(r'^\s*(?:-\s+)?uses:\s*(\S+)').firstMatch(lines[i]);
      if (match == null) continue;
      seen++;
      expect(
        pin.hasMatch(match.group(1)!),
        isTrue,
        reason:
            '$workflowPath:${i + 1}: not pinned to a commit SHA: '
            '${lines[i].trim()}',
      );
    }
    expect(seen, isPositive);
  });

  test('caches hold only the mise downloads and the vision inputs keyed by '
      'their pins, never build output', () {
    final cacheSteps = steps
        .where((s) => '${s['uses'] ?? ''}'.startsWith('actions/cache'))
        .toList();
    expect(cacheSteps, hasLength(2), reason: 'one restore, one save');
    final restore = steps.indexWhere(
      (s) => usesAction(s, 'actions/cache/restore'),
    );
    final save = steps.indexWhere((s) => usesAction(s, 'actions/cache/save'));
    expect(restore, isNonNegative);
    expect(save, isNonNegative);
    expect(save, greaterThan(gateIndex('mise run build:release')));
    expect(save, lessThan(gateIndex('mise run ci:qualification')));
    expect(restore, lessThan(gateIndex('mise run build:release')));
    for (final step in cacheSteps) {
      final inputs = asMap(step['with']);
      expect(inputs['path'], '.dart_tool/blackgrid_vision_inputs');
      expect(
        inputs['key'],
        r"vision-inputs-${{ hashFiles('windows/vision/third_party.lock.json') }}",
      );
    }
    final mise = steps.firstWhere((s) => usesAction(s, 'jdx/mise-action'));
    final miseInputs = asMap(mise['with'] ?? <String, dynamic>{});
    expect(miseInputs['cache'] ?? true, isNot(false));
  });
}
