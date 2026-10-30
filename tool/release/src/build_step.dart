import 'dart:io';

import 'git.dart';
import 'stamp.dart';

const maxBuildNumber = 65535;
const bundleDir = 'build/windows/x64/runner/Release';

/// Runs the `build` flow (design D7). Throws [ReleaseException] on the first
/// refusal or failing stage; a failing stage's exit code is propagated.
///
/// Any earlier build stamp is deleted first; a new one is written only after
/// `bundle:check` passes (add-release-packaging D1).
Future<void> build({
  required Directory repoDir,
  required CommandRunner runner,
  StringSink? out,
}) async {
  final sink = out ?? stdout;
  final git = Git(runner, repoDir);
  final stamp = stampFile(repoDir);
  if (stamp.existsSync()) stamp.deleteSync();

  final dirty = await git.output([
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]);
  if (dirty.isNotEmpty) {
    throw ReleaseException(
      'The working tree is not clean; commit, stash or remove:\n$dirty',
    );
  }

  final pubspec = File('${repoDir.path}/pubspec.yaml').readAsStringSync();
  final versions = RegExp(
    r'^version:[ \t]*(\S+)[ \t]*$',
    multiLine: true,
  ).allMatches(pubspec).toList();
  if (versions.length != 1) {
    throw ReleaseException(
      'pubspec.yaml must have exactly one top-level "version:" line, '
      'found ${versions.length}.',
    );
  }
  final version = versions.single.group(1)!;

  final head = await git.output(['rev-parse', 'HEAD']);
  final countText = await git.output(['rev-list', '--count', 'HEAD']);
  final count = int.tryParse(countText);
  if (count == null) {
    throw ReleaseException('Unexpected commit count "$countText".');
  }
  if (count > maxBuildNumber) {
    throw ReleaseException(
      'HEAD has $count commits, above the $maxBuildNumber limit of the '
      'executable file-version build number.',
    );
  }

  sink.writeln('Building $version+$count');
  final stages = <(String, String, List<String>)>[
    ('vision:fetch', 'mise', ['run', 'vision:fetch']),
    (
      'flutter build',
      'flutter',
      [
        'build',
        'windows',
        '--release',
        '--build-name',
        version,
        '--build-number',
        '$count',
        '--dart-define=BLACKGRID_VERSION=$version+$count',
      ],
    ),
    ('bundle:check', 'mise', ['run', 'bundle:check', '--', bundleDir]),
  ];
  for (final (name, exe, args) in stages) {
    final r = await runner.run(
      exe,
      args,
      workingDirectory: repoDir.path,
      stream: true,
    );
    if (r.exitCode != 0) {
      throw ReleaseException(
        'Stage $name failed with exit code ${r.exitCode} '
        '(see its output above).',
        exitCode: r.exitCode,
      );
    }
  }
  writeStamp(
    stamp,
    BuildStamp(version: version, buildNumber: count, commit: head),
  );
  sink.writeln('Built $version+$count; bundle check passed.');
}
