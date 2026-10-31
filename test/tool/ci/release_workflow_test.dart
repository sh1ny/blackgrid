import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'support/no_games_scan.dart';

/// Offline structure checks of `.github/workflows/release.yml`: what starts
/// it, which jobs run in which order, and which of them may write. The scripts
/// of the jobs are exercised in `release_workflow_scripts_test.dart`.
void main() {
  const releasePath = '.github/workflows/release.yml';
  const ciPath = '.github/workflows/ci.yml';
  const gatesUses = './.github/workflows/gates.yml';

  Map<String, dynamic> asMap(Object? value) =>
      (value as Map).cast<String, dynamic>();

  Map<String, dynamic> load(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path must exist');
    return asMap(toPlain(loadYaml(file.readAsStringSync())));
  }

  late Map<String, dynamic> release;
  late Map<String, dynamic> jobs;

  setUp(() {
    release = load(releasePath);
    jobs = asMap(release['jobs']);
  });

  List<Map<String, dynamic>> stepsOf(String job) => [
    for (final s in (asMap(jobs[job])['steps'] as List? ?? const [])) asMap(s),
  ];

  test('triggers are tag pushes matching v* and workflow_dispatch with a tag '
      'input', () {
    final on = asMap(release['on']);
    // No branches, pull_request or schedule: a branch push or a PR starts
    // nothing.
    expect(on.keys.toSet(), {'push', 'workflow_dispatch'});
    expect(asMap(on['push']), {
      'tags': ['v*'],
    });
    final tag = asMap(asMap(asMap(on['workflow_dispatch'])['inputs'])['tag']);
    expect(tag['required'], true);
    expect(tag['type'], 'string');
  });

  test('gates job runs the shared gates workflow and publish needs it', () {
    expect(jobs.keys.toSet(), {'preflight', 'gates', 'publish'});
    final gates = asMap(jobs['gates']);
    expect(gates['uses'], gatesUses);
    expect(gates['needs'], 'preflight');
    expect(asMap(gates['with']), {
      'release_tag': r'${{ needs.preflight.outputs.tag }}',
    });
    expect(gates, isNot(contains('steps')));
    expect(gates, isNot(contains('secrets')));
    expect(gates, isNot(contains('if')));
    expect(gates, isNot(contains('continue-on-error')));
    expect(asMap(jobs['preflight']), isNot(contains('needs')));
    expect(asMap(jobs['publish'])['needs'], ['preflight', 'gates']);
    expect(asMap(jobs['publish']), isNot(contains('if')));
    expect(asMap(jobs['publish']), isNot(contains('continue-on-error')));
  });

  test('ci and release call the same gates workflow', () {
    final ci = load(ciPath);
    final ciUses = asMap(asMap(ci['jobs'])['ci'])['uses'];
    expect(ciUses, gatesUses);
    expect(asMap(jobs['gates'])['uses'], ciUses);
  });

  test('top-level contents read and only preflight and publish widen to '
      'write', () {
    expect(release['permissions'], {'contents': 'read'});
    final widened = {
      for (final MapEntry(:key, :value) in jobs.entries)
        if (asMap(value)['permissions'] != null &&
            asMap(asMap(value)['permissions'])['contents'] == 'write')
          key,
    };
    expect(widened, {'preflight', 'publish'});
    expect(asMap(jobs['preflight'])['permissions'], {'contents': 'write'});
    expect(asMap(jobs['publish'])['permissions'], {'contents': 'write'});
    expect(asMap(jobs['gates'])['permissions'], {'contents': 'read'});
    // The run's own token is the only credential.
    expect(File(releasePath).readAsStringSync(), isNot(contains('secrets.')));
  });

  test('no job with contents write has a checkout, mise or local workflow '
      'step', () {
    var checked = 0;
    for (final MapEntry(:key, :value) in jobs.entries) {
      final job = asMap(value);
      final permissions = job['permissions'];
      if (permissions == null || asMap(permissions)['contents'] != 'write') {
        continue;
      }
      checked++;
      expect(job, isNot(contains('uses')), reason: 'job $key calls a workflow');
      for (final step in stepsOf(key)) {
        final uses = '${step['uses'] ?? ''}';
        final run = '${step['run'] ?? ''}';
        expect(
          uses,
          isNot(anyOf(startsWith('actions/checkout'), startsWith('jdx/mise'))),
          reason: 'job $key has a checkout or mise step: $uses',
        );
        expect(
          uses,
          isNot(startsWith('./')),
          reason: 'job $key runs a local action or workflow: $uses',
        );
        expect(
          run,
          isNot(contains(RegExp(r'\bmise\b'))),
          reason: 'job $key runs mise',
        );
      }
    }
    expect(checked, 2);
  });

  test('the run for a tag is serialized without cancelling and the write '
      'jobs have 15 minute timeouts', () {
    expect(asMap(release['concurrency']), {
      'group': r'release-${{ inputs.tag || github.ref_name }}',
      'cancel-in-progress': false,
    });
    for (final job in ['preflight', 'publish']) {
      expect(asMap(jobs[job])['runs-on'], 'ubuntu-latest', reason: job);
      expect(asMap(jobs[job])['timeout-minutes'], 15, reason: job);
    }
  });

  test('scripts are strict, take values only through env, and publish '
      'downloads the pinned artifact action', () {
    for (final job in ['preflight', 'publish']) {
      for (final step in stepsOf(job)) {
        final run = '${step['run'] ?? ''}';
        if (run.isEmpty) continue;
        expect(run, startsWith('set -euo pipefail'), reason: '$job: $step');
        expect(run, isNot(contains(r'${{')), reason: '$job: $step');
      }
    }
    final download = stepsOf('publish').first;
    expect(
      download['uses'],
      startsWith(
        'actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333',
      ),
    );
    expect(asMap(download['with'])['path'], 'dist');
    expect(
      asMap(download['with'])['name'],
      r'release-${{ needs.preflight.outputs.tag }}',
    );
  });
}
