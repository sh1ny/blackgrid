import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'support/no_games_scan.dart';

/// Offline checks of `.github/workflows/ci.yml`, of the shared
/// `.github/workflows/gates.yml` it calls, and of the rule that only the gates
/// workflow's qualification step confirms that no game is running.
void main() {
  const workflowsDir = '.github/workflows';
  const ciPath = '$workflowsDir/ci.yml';
  const gatesPath = '$workflowsDir/gates.yml';
  const bundle = r'${{ github.workspace }}\build\windows\x64\runner\Release';
  const releaseOnly = "inputs.release_tag != ''";
  const gates = [
    'mise run analyze',
    'mise run test',
    'mise run build:release',
    'mise run ci:qualification',
    'mise run package:release',
  ];
  const verifyTag =
      r'mise run release:verify-tag -- $env:RELEASE_TAG --out build/release-meta';

  late String ciSource;
  late Map<String, dynamic> ci;
  late String source;
  late Map<String, dynamic> workflow;
  late List<Map<String, dynamic>> steps;

  Map<String, dynamic> asMap(Object? value) =>
      (value as Map).cast<String, dynamic>();

  Map<String, dynamic> load(String path, void Function(String) keep) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path must exist');
    final text = file.readAsStringSync();
    keep(text);
    return asMap(toPlain(loadYaml(text)));
  }

  setUp(() {
    ci = load(ciPath, (t) => ciSource = t);
    workflow = load(gatesPath, (t) => source = t);
    final jobs = asMap(workflow['jobs']);
    expect(jobs, hasLength(1), reason: 'the gates are one job (D1)');
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

  bool isGuard(Map<String, dynamic> step) =>
      run(step).contains('predates release publishing');

  test('triggers are pull_request and push to main only', () {
    final on = asMap(ci['on']);
    expect(on.keys.toSet(), {'pull_request', 'push'});
    // Default pull_request types: no `types` filter.
    expect(on['pull_request'] ?? <String, dynamic>{}, isNot(contains('types')));
    expect(asMap(on['push'])['branches'], ['main']);
    expect(ciSource, isNot(contains('pull_request_target')));
  });

  test('a push run has its own concurrency group keyed by github.sha and is '
      'never cancelled', () {
    final concurrency = asMap(ci['concurrency']);
    expect(
      '${concurrency['group']}',
      contains("format('ci-push-{0}', github.sha)"),
    );
    final cancel = '${concurrency['cancel-in-progress']}';
    expect(cancel, contains("github.event_name == 'pull_request'"));
    expect(cancel, isNot(contains('push')));
  });

  test('pull request runs share one group per PR and cancel in progress', () {
    final concurrency = asMap(ci['concurrency']);
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

  test('ci.yml has one job that calls the gates workflow with no release '
      'tag', () {
    final jobs = asMap(ci['jobs']);
    expect(jobs, hasLength(1));
    final call = asMap(jobs.values.single);
    expect(call['uses'], './$gatesPath');
    expect(call, isNot(contains('steps')));
    expect(call, isNot(contains('with')), reason: 'no release_tag in CI');
    expect(call, isNot(contains('secrets')));
    expect(call, isNot(contains('if')));
    expect(call, isNot(contains('continue-on-error')));
    expect(jobs.keys.single, 'ci', reason: 'the PR check is named ci / ...');
  });

  test('the gates workflow is callable with an optional release_tag input '
      'and a sums_sha256 output', () {
    final on = asMap(workflow['on']);
    expect(on.keys.toSet(), {'workflow_call'});
    final call = asMap(on['workflow_call']);
    final input = asMap(asMap(call['inputs'])['release_tag']);
    expect(input['type'], 'string');
    expect(input['required'], false);
    expect(input['default'], '');
    final output = asMap(asMap(call['outputs'])['sums_sha256']);
    expect('${output['value']}', contains('jobs.'));
    expect('${output['value']}', contains('.outputs.sums_sha256'));
    final jobOutputs = asMap(job()['outputs']);
    expect('${jobOutputs['sums_sha256']}', contains('steps.'));
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
    'gate steps run in order analyze, test, build:release, ci:qualification, '
    'package:release',
    () {
      final indexes = [for (final g in gates) gateIndex(g)];
      expect(indexes, everyElement(isNonNegative));
      expect(indexes, [...indexes]..sort());
      expect(indexes.toSet(), hasLength(gates.length));
    },
  );

  test('the package step sets no env and has no condition', () {
    final step = steps[gateIndex('mise run package:release')];
    expect(run(step), 'mise run package:release');
    expect(step, isNot(contains('env')));
    expect(step, isNot(contains('if')));
    expect(step, isNot(contains('continue-on-error')));
  });

  test('in release mode the checkout pins refs/tags/<tag> and the guard and '
      'verify-tag steps follow the mise install', () {
    final checkout = steps.first;
    expect(usesAction(checkout, 'actions/checkout'), isTrue);
    final ref = '${asMap(checkout['with'])['ref']}';
    expect(ref, contains("format('refs/tags/{0}', inputs.release_tag)"));
    expect(ref, contains(releaseOnly));
    final install = steps.indexWhere((s) => usesAction(s, 'jdx/mise-action'));
    final guard = steps.indexWhere(isGuard);
    final verify = gateIndex(verifyTag);
    expect(guard, isNonNegative, reason: 'tag-tooling guard step');
    expect(verify, isNonNegative, reason: 'verify-tag step');
    expect(install, lessThan(guard));
    expect(guard, lessThan(verify));
    expect(verify, lessThan(gateIndex('mise run analyze')));
    final guardScript = run(steps[guard]);
    expect(guardScript, contains('release:verify-tag'));
    expect(guardScript, contains('package:release'));
    expect(steps[guard]['shell'], 'pwsh');
    for (final i in [guard, verify]) {
      expect(steps[i]['if'], releaseOnly);
      expect(
        asMap(steps[i]['env'])['RELEASE_TAG'],
        r'${{ inputs.release_tag }}',
      );
    }
  });

  test('the tag reaches scripts only through env, never an expression in '
      'run', () {
    for (final step in steps) {
      expect(run(step), isNot(contains(r'${{')), reason: '$step');
    }
  });

  test('in release mode the upload step follows Package and no gate step has '
      'a condition', () {
    final package = gateIndex('mise run package:release');
    final upload = steps.indexWhere(
      (s) => usesAction(s, 'actions/upload-artifact'),
    );
    expect(upload, isNonNegative);
    expect(upload, greaterThan(package));
    expect(steps[upload]['if'], releaseOnly);
    final inputs = asMap(steps[upload]['with']);
    expect(inputs['name'], r'release-${{ inputs.release_tag }}');
    expect(inputs['retention-days'], 1);
    expect(inputs['if-no-files-found'], 'error');
    expect(inputs['compression-level'], 0);
    final paths = '${inputs['path']}'.split(RegExp(r'\s+'))..remove('');
    expect(paths, ['build/release/*', 'build/release-meta/*']);
    final sums = steps.indexWhere((s) => s['id'] == 'sums');
    expect(sums, inInclusiveRange(package + 1, upload - 1));
    expect(run(steps[sums]), contains('build/release/SHA256SUMS.txt'));
    expect(run(steps[sums]), contains('sums_sha256='));
    expect(steps[sums]['if'], releaseOnly);
    // Only the four release-mode steps carry a condition; every gate, cache
    // and the install is unconditional, so release and CI run identical gates.
    final conditional = {
      for (final (i, s) in steps.indexed)
        if (s.containsKey('if')) i,
    };
    expect(conditional, {
      steps.indexWhere(isGuard),
      gateIndex(verifyTag),
      sums,
      upload,
    });
    for (final gate in gates) {
      expect(steps[gateIndex(gate)], isNot(contains('if')), reason: gate);
    }
  });

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
      expect(ciSource, isNot(contains('continue-on-error')));
    },
  );

  test('checkout uses full history and no persisted credentials', () {
    final checkout = steps.firstWhere((s) => usesAction(s, 'actions/checkout'));
    expect(steps.first, same(checkout), reason: 'checkout is first');
    final inputs = asMap(checkout['with']);
    expect(inputs['fetch-depth'], 0);
    expect(inputs['persist-credentials'], false);
  });

  test('the qualification step of the gates workflow alone sets the no-games '
      'confirmation and the bundle inputs', () {
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
      findNoGamesSetters(gatesPath, source),
      hasLength(1),
      reason: 'exactly one env setter in the workflow',
    );
    expect(ciSource, isNot(contains(noGamesVariable)));
    expect(findNoGamesSetters(ciPath, ciSource), isEmpty);
  });

  test('no other tracked file, including ci.yml and release.yml, sets the '
      'no-games confirmation', () {
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
        .where((l) => l.isNotEmpty && l != gatesPath)
        .where(isScannableKind)
        .where((l) => File(l).existsSync());
    final findings = <String>[
      for (final path in files)
        ...findNoGamesSetters(path, File(path).readAsStringSync()),
    ];
    expect(findings, isEmpty, reason: 'files that set $noGamesVariable');
  });

  test('ci and gates permissions are exactly contents read and no secrets are '
      'used', () {
    for (final (name, doc, text) in [
      (ciPath, ci, ciSource),
      (gatesPath, workflow, source),
    ]) {
      expect(doc['permissions'], {'contents': 'read'}, reason: name);
      for (final j in asMap(doc['jobs']).values) {
        expect(asMap(j), isNot(contains('permissions')), reason: name);
      }
      expect(text, isNot(contains('secrets')), reason: name);
    }
  });

  test('every uses line in every workflow is pinned to a 40-hex commit SHA', () {
    final pin = RegExp(r'^[\w.-]+/[\w./-]+@[0-9a-f]{40}$');
    final files = [
      for (final e in Directory(workflowsDir).listSync())
        if (e is File && RegExp(r'\.ya?ml$').hasMatch(e.path))
          e.path.replaceAll(r'\', '/'),
    ]..sort();
    expect(files, containsAll([ciPath, gatesPath]));
    var seen = 0;
    for (final path in files) {
      final lines = File(path).readAsStringSync().split(RegExp(r'\r?\n'));
      for (var i = 0; i < lines.length; i++) {
        final match = RegExp(r'^\s*(?:-\s+)?uses:\s*(\S+)')
            .firstMatch(lines[i]);
        if (match == null) continue;
        seen++;
        final target = match.group(1)!;
        // A reusable workflow of this repository is a path, not an action.
        if (target.startsWith('./$workflowsDir/')) {
          expect(
            File(target.substring(2)).existsSync(),
            isTrue,
            reason: '$path:${i + 1}: missing local workflow: $target',
          );
          continue;
        }
        expect(
          pin.hasMatch(target),
          isTrue,
          reason:
              '$path:${i + 1}: not pinned to a commit SHA: ${lines[i].trim()}',
        );
      }
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
      expect(step, isNot(contains('if')));
    }
    final mise = steps.firstWhere((s) => usesAction(s, 'jdx/mise-action'));
    final miseInputs = asMap(mise['with'] ?? <String, dynamic>{});
    expect(miseInputs['cache'] ?? true, isNot(false));
  });
}
