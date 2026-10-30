import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../../vision/fetch_runtime.dart';
import 'build_step.dart';
import 'git.dart';
import 'stamp.dart';

/// The packaging output directory, relative to the repository root.
const releaseDirPath = 'build/release';

/// The committed pin of the installer compiler.
const packagingLockPath = 'windows/installer/packaging.lock.json';

/// The installer script, relative to the repository root.
const installerScriptPath = 'windows/installer/blackgrid.iss';

/// The tool cache holding the compiler download and its unpacked form.
const packagingCachePath = '.dart_tool/blackgrid_packaging';

/// How long the compiler's portable unpack may run before it is killed.
const unpackTimeout = Duration(minutes: 5);

/// How long the installer compile may run before it is killed.
const compileTimeout = Duration(minutes: 20);

const _noticesName = 'THIRD_PARTY_NOTICES.md';
const _compilerId = 'inno-setup';

/// Fetches and verifies the pinned inputs of [lockFile] into [cacheDir].
typedef FetchInputs = Future<FetchResult> Function({
  required File lockFile,
  required Directory cacheDir,
});

/// Runs the `package` flow (add-release-packaging D1-D5).
///
/// Clears `build/release/`, admits only the stamped bundle of the clean
/// `HEAD`, re-runs `bundle:check`, then writes the zip, the installer and
/// `SHA256SUMS.txt`. Every refusal or failure removes `build/release/` and
/// throws a [ReleaseException] with exit code 1 that names the failed stage
/// and, for a child process, its own exit code.
Future<void> package({
  required Directory repoDir,
  required CommandRunner runner,
  FetchInputs fetch = fetchInputs,
  StringSink? out,
}) async {
  final sink = out ?? stdout;
  final root = _win(repoDir.absolute.path);
  final releaseDir = Directory('$root\\${_win(releaseDirPath)}');
  if (releaseDir.existsSync()) releaseDir.deleteSync(recursive: true);

  var stage = 'admission';
  ZipFileEncoder? zip;
  try {
    final stamp = await _admit(repoDir, Git(runner, repoDir));

    stage = 'bundle:check';
    await _check(
      stage,
      await runner.run(
        'mise',
        ['run', 'bundle:check', '--', bundleDir],
        workingDirectory: repoDir.path,
        stream: true,
      ),
    );

    stage = 'notices';
    final notices = File('$root\\$_noticesName');
    if (!notices.existsSync()) {
      throw ReleaseException('$_noticesName is missing from the repository.');
    }

    stage = 'compiler fetch';
    final iscc = await _compiler(root, runner, fetch, sink, (s) => stage = s);

    stage = 'zip';
    final version = stamp.version;
    final base = 'Blackgrid-$version-windows-x64';
    releaseDir.createSync(recursive: true);
    final bundle = Directory('$root\\${_win(bundleDir)}');
    final zipFile = File('${releaseDir.path}\\$base.zip');
    sink.writeln('Writing ${zipFile.path}');
    zip = ZipFileEncoder()..create(zipFile.path);
    for (final (file, relative) in _bundleFiles(bundle)) {
      await zip.addFile(file, 'Blackgrid-$version/$relative');
    }
    await zip.addFile(notices, 'Blackgrid-$version/$_noticesName');
    await zip.close();
    zip = null;

    stage = 'installer compile';
    final core = version.split(RegExp('[-+]')).first;
    sink.writeln('Compiling the installer with $iscc');
    await _check(
      stage,
      await runner.run(
        iscc,
        [
          '/Q',
          '/DAppVersion=$version',
          '/DFileVersion=$core.${stamp.buildNumber}',
          '/DSourceDir=${bundle.path}',
          '/DNoticesFile=${notices.path}',
          '/DOutputDir=${releaseDir.path}',
          '/DOutputBaseFilename=$base-setup',
          '$root\\${_win(installerScriptPath)}',
        ],
        workingDirectory: repoDir.path,
        stream: true,
        timeout: compileTimeout,
      ),
    );
    final setup = File('${releaseDir.path}\\$base-setup.exe');
    if (!setup.existsSync()) {
      throw ReleaseException('The compiler wrote no ${setup.path}.');
    }

    stage = 'checksums';
    final names = ['$base.zip', '$base-setup.exe']..sort();
    final sums = StringBuffer();
    for (final name in names) {
      final file = File('${releaseDir.path}\\$name');
      sums.write('${await sha256.bind(file.openRead()).first}  $name\n');
    }
    final temp = File('${releaseDir.path}\\SHA256SUMS.txt.tmp')
      ..writeAsStringSync(sums.toString());
    temp.renameSync('${releaseDir.path}\\SHA256SUMS.txt');
    sink.writeln('Packaged $version into ${releaseDir.path}');
  } catch (e) {
    try {
      zip?.closeSync();
    } on Object catch (_) {
      // The encoder is only closed to release its handle before deletion.
    }
    if (releaseDir.existsSync()) releaseDir.deleteSync(recursive: true);
    switch (e) {
      case ReleaseException(:final message):
        throw ReleaseException('Packaging failed at $stage: $message');
      case Exception():
        throw ReleaseException('Packaging failed at $stage: $e');
      default:
        rethrow;
    }
  }
}

/// Refuses unless the tree is clean and the stamp names `HEAD` and the
/// pubspec version (D1); returns the admitted stamp.
Future<BuildStamp> _admit(Directory repoDir, Git git) async {
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
  final stamp = readStamp(stampFile(repoDir));
  if (stamp == null || !Directory('${repoDir.path}/$bundleDir').existsSync()) {
    throw const ReleaseException(
      'No stamped Release bundle; run `mise run build:release` first.',
    );
  }
  final head = await git.output(['rev-parse', 'HEAD']);
  if (stamp.commit != head) {
    throw ReleaseException(
      'The bundle was built from ${stamp.commit}, but HEAD is $head; '
      'run `mise run build:release` again.',
    );
  }
  final version = readPubspecVersion(repoDir);
  if (stamp.version != version) {
    throw ReleaseException(
      'The bundle was built as ${stamp.version}, but pubspec.yaml says '
      '$version; run `mise run build:release` again.',
    );
  }
  return stamp;
}

/// Fetches the pinned compiler and unpacks it once into its own cache
/// directory (D2); returns the absolute path of its `ISCC.exe`.
Future<String> _compiler(
  String root,
  CommandRunner runner,
  FetchInputs fetch,
  StringSink sink,
  void Function(String) setStage,
) async {
  final lockFile = File('$root\\${_win(packagingLockPath)}');
  final cache = '$root\\${_win(packagingCachePath)}';
  try {
    await fetch(lockFile: lockFile, cacheDir: Directory('$cache\\downloads'));
  } on FetchException catch (e) {
    throw ReleaseException('$e');
  }
  final (:name, :sha) = _compilerPin(lockFile);

  setStage('compiler unpack');
  final dir = Directory('$cache\\innosetup-$sha');
  final marker = File('${dir.path}\\.complete');
  final iscc = '${dir.path}\\ISCC.exe';
  if (marker.existsSync()) return iscc;
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final log = '${dir.path}.log';
  sink.writeln('Unpacking Inno Setup into ${dir.path}');
  final result = await runner.run(
    '$cache\\downloads\\$sha\\$name',
    [
      '/PORTABLE=1',
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/SP-',
      '/NORESTART',
      '/CURRENTUSER',
      '/NOICONS',
      '/DIR=${dir.path}',
      '/LOG=$log',
    ],
    workingDirectory: root,
    timeout: unpackTimeout,
  );
  await _check('compiler unpack', result, detail: 'see $log');
  if (!File(iscc).existsSync()) {
    throw ReleaseException('The unpack wrote no ISCC.exe; see $log.');
  }
  marker.writeAsStringSync('');
  return iscc;
}

/// The cached file name and SHA-256 of the compiler entry in [lockFile].
({String name, String sha}) _compilerPin(File lockFile) {
  final lock = jsonDecode(lockFile.readAsStringSync());
  if (lock case {'format': 1, 'inputs': final List<Object?> inputs}) {
    for (final input in inputs) {
      if (input case {
        'id': _compilerId,
        'name': final String name,
        'sha256': final String sha,
      }) {
        return (name: name, sha: sha);
      }
    }
  }
  throw ReleaseException('$packagingLockPath has no "$_compilerId" entry.');
}

/// Throws when [result] of [stage] timed out or exited non-zero.
Future<void> _check(
  String stage,
  CommandResult result, {
  String? detail,
}) async {
  final suffix = detail == null ? '' : '; $detail';
  if (result.timedOut) {
    throw ReleaseException(
      'Stage $stage timed out; its process tree was killed$suffix.',
    );
  }
  if (result.exitCode != 0) {
    throw ReleaseException(
      'Stage $stage failed with exit code ${result.exitCode}$suffix.',
    );
  }
}

/// Every file under [bundle] with its `/`-separated relative path, sorted.
List<(File, String)> _bundleFiles(Directory bundle) {
  final prefix = bundle.path.length + 1;
  return [
    for (final entity in bundle.listSync(recursive: true, followLinks: false))
      if (entity is File)
        (entity, entity.path.substring(prefix).replaceAll(r'\', '/')),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
}

/// [path] with Windows separators, the form ISCC and its setup expect.
String _win(String path) => path.replaceAll('/', r'\');
