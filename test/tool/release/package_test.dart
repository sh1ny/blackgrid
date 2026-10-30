import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/src/git.dart';
import '../../../tool/release/src/package_step.dart';
import '../../../tool/release/src/stamp.dart';
import '../../../tool/vision/fetch_runtime.dart';

const _identity = {
  'GIT_AUTHOR_NAME': 'Test Author',
  'GIT_AUTHOR_EMAIL': 'author@example.invalid',
  'GIT_COMMITTER_NAME': 'Test Committer',
  'GIT_COMMITTER_EMAIL': 'committer@example.invalid',
  'GIT_CONFIG_GLOBAL': '',
  'GIT_CONFIG_NOSYSTEM': '1',
};

const _installerName = 'innosetup-7.1.1-x64.exe';
final _installerBytes = utf8.encode('fake inno setup installer');
final _installerSha = sha256.convert(_installerBytes).toString();

class Call {
  Call(this.executable, this.arguments, this.stream, this.timeout);

  final String executable;
  final List<String> arguments;
  final bool stream;
  final Duration? timeout;
}

/// Git runs for real against the fixture. `mise run bundle:check`, the
/// compiler setup and `ISCC.exe` are stubbed and recorded.
class FakeRunner implements CommandRunner {
  FakeRunner(this.real);

  final CommandRunner real;
  final List<Call> calls = [];
  int bundleCheckExit = 0;
  int unpackExit = 0;
  int isccExit = 0;

  List<Call> get external => [
    for (final c in calls)
      if (c.executable != 'git') c,
  ];

  Iterable<Call> get unpacks =>
      external.where((c) => c.executable.endsWith(_installerName));

  Iterable<Call> get isccs =>
      external.where((c) => c.executable.endsWith('ISCC.exe'));

  String _arg(List<String> arguments, String prefix) => arguments
      .firstWhere((a) => a.startsWith(prefix))
      .substring(prefix.length);

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    calls.add(Call(executable, arguments, stream, timeout));
    if (executable == 'git') {
      return real.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    }
    if (executable == 'mise' &&
        arguments.join(' ').startsWith('run bundle:check')) {
      return CommandResult(bundleCheckExit, '', '');
    }
    if (executable.endsWith(_installerName)) {
      if (unpackExit != 0) return CommandResult(unpackExit, '', '');
      File('${_arg(arguments, '/DIR=')}/ISCC.exe')
        ..createSync(recursive: true)
        ..writeAsStringSync('fake iscc');
      return const CommandResult(0, '', '');
    }
    if (executable.endsWith('ISCC.exe')) {
      if (isccExit != 0) return CommandResult(isccExit, '', '');
      final out = _arg(arguments, '/DOutputDir=');
      final name = _arg(arguments, '/DOutputBaseFilename=');
      File('$out/$name.exe').writeAsStringSync('fake setup');
      return const CommandResult(0, '', '');
    }
    fail('unexpected command: $executable ${arguments.join(' ')}');
  }
}

String _git(Directory dir, List<String> args) {
  final r = Process.runSync(
    'git',
    ['-c', 'commit.gpgsign=false', ...args],
    workingDirectory: dir.path,
    environment: _identity,
  );
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
  return (r.stdout as String).trim();
}

/// Windows path form of [path], as the step passes to ISCC.
String _win(String path) => path.replaceAll('/', r'\');

void main() {
  late Directory root;
  late Directory work;
  late FakeRunner runner;
  late List<File> fetchedLocks;
  FetchException? fetchError;

  Directory releaseDir() => Directory('${work.path}/build/release');
  Directory compilerDir() => Directory(
    '${work.path}/.dart_tool/blackgrid_packaging/innosetup-$_installerSha',
  );

  void write(String path, String content) => File('${work.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  void commitAll(String subject) {
    _git(work, ['add', '-A']);
    _git(work, ['commit', '-m', subject]);
  }

  void setVersion(String version) {
    write('pubspec.yaml', 'name: demo\nversion: $version\n');
    commitAll('chore: version $version');
  }

  void stampHead({String? version, int buildNumber = 412}) {
    writeStamp(
      stampFile(work),
      BuildStamp(
        version:
            version ??
            RegExp(r'version: (\S+)')
                .firstMatch(
                  File('${work.path}/pubspec.yaml').readAsStringSync(),
                )!
                .group(1)!,
        buildNumber: buildNumber,
        commit: _git(work, ['rev-parse', 'HEAD']),
      ),
    );
  }

  Future<FetchResult> fakeFetch({
    required File lockFile,
    required Directory cacheDir,
  }) async {
    fetchedLocks.add(lockFile);
    if (fetchError != null) throw fetchError!;
    File('${cacheDir.path}/$_installerSha/$_installerName')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_installerBytes);
    return FetchResult(downloaded: ['inno-setup'], reused: []);
  }

  Future<void> runPackage() => package(
    repoDir: work,
    runner: runner,
    fetch: fakeFetch,
    out: StringBuffer(),
  );

  Future<ReleaseException> refusal() async {
    try {
      await runPackage();
    } on ReleaseException catch (e) {
      return e;
    }
    fail('expected ReleaseException');
  }

  /// An earlier run's complete output, which every refusal must clear.
  void seedEarlierOutput() {
    write('build/release/Blackgrid-0.0.1-windows-x64.zip', 'old zip');
    write('build/release/SHA256SUMS.txt', 'old sums\n');
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('blackgrid_package_');
    work = Directory('${root.path}/work')..createSync();
    _git(work, ['init', '-b', 'main']);
    write('.gitignore', '/build/\n/.dart_tool/\n');
    write('THIRD_PARTY_NOTICES.md', '# Notices\n');
    write('windows/installer/blackgrid.iss', '; fake script\n');
    write(
      'windows/installer/packaging.lock.json',
      jsonEncode({
        'format': 1,
        'inputs': [
          {
            'id': 'inno-setup',
            'name': _installerName,
            'version': '7.1.1',
            'urls': ['https://example.invalid/$_installerName'],
            'sha256': _installerSha,
            'size': _installerBytes.length,
            'license': 'Inno Setup License',
            'unpack': 'portable',
          },
        ],
      }),
    );
    setVersion('0.6.0');
    write('build/windows/x64/runner/Release/blackgrid.exe', 'exe');
    write('build/windows/x64/runner/Release/flutter_windows.dll', 'dll');
    write('build/windows/x64/runner/Release/data/app.so', 'so');
    stampHead();
    runner = FakeRunner(ProcessCommandRunner(environment: _identity));
    fetchedLocks = [];
    fetchError = null;
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('admission', () {
    test('a fresh stamp passes admission and re-runs bundle:check before packaging', () async {
      await runPackage();

      final lines = [
        for (final c in runner.external) c.executable.split('/').last,
      ];
      expect(runner.external.first.executable, 'mise');
      expect(runner.external.first.arguments, [
        'run',
        'bundle:check',
        '--',
        'build/windows/x64/runner/Release',
      ]);
      expect(lines.indexOf('mise'), lessThan(lines.length - 1));
      expect(runner.isccs, hasLength(1));
    });

    test(
      'a failing bundle:check re-run refuses and leaves no package',
      () async {
        seedEarlierOutput();
        runner.bundleCheckExit = 3;

        final e = await refusal();

        expect(e.exitCode, 1);
        expect(e.message, contains('bundle:check'));
        expect(e.message, contains('3'));
        expect(runner.unpacks, isEmpty);
        expect(runner.isccs, isEmpty);
        expect(releaseDir().existsSync(), isFalse);
      },
    );

    test('a stamp for another commit refuses naming both commits and clears earlier output', () async {
      final stamped = _git(work, ['rev-parse', 'HEAD']);
      write('later.txt', 'later\n');
      commitAll('feat: later');
      final head = _git(work, ['rev-parse', 'HEAD']);
      seedEarlierOutput();

      final e = await refusal();

      expect(e.exitCode, 1);
      expect(e.message, contains(stamped));
      expect(e.message, contains(head));
      expect(runner.external, isEmpty);
      expect(releaseDir().existsSync(), isFalse);
    });

    test('a stamp for another version refuses naming both versions', () async {
      stampHead(version: '0.5.0');

      final e = await refusal();

      expect(e.message, contains('0.5.0'));
      expect(e.message, contains('0.6.0'));
      expect(runner.external, isEmpty);
    });

    test('a missing stamp refuses and points to build:release', () async {
      stampFile(work).deleteSync();
      seedEarlierOutput();

      final e = await refusal();

      expect(e.exitCode, 1);
      expect(e.message, contains('mise run build:release'));
      expect(runner.external, isEmpty);
      expect(releaseDir().existsSync(), isFalse);
    });

    test('a malformed stamp refuses and points to build:release', () async {
      stampFile(work).writeAsStringSync('{"format":1');

      final e = await refusal();

      expect(e.message, contains('mise run build:release'));
      expect(runner.external, isEmpty);
    });

    test('a dirty tree refuses listing the files', () async {
      write('THIRD_PARTY_NOTICES.md', '# Changed\n');
      write('stray.txt', 'stray\n');
      seedEarlierOutput();

      final e = await refusal();

      expect(e.exitCode, 1);
      expect(e.message, contains('THIRD_PARTY_NOTICES.md'));
      expect(e.message, contains('stray.txt'));
      expect(runner.external, isEmpty);
      expect(releaseDir().existsSync(), isFalse);
    });
  });

  group('compiler', () {
    test('the pinned compiler is fetched, unpacked once with a complete marker and reused', () async {
      // A killed earlier unpack: no marker, so it must be redone.
      File('${compilerDir().path}/leftover.tmp')
        ..createSync(recursive: true)
        ..writeAsStringSync('partial');

      await runPackage();

      expect(fetchedLocks.single.path, endsWith('packaging.lock.json'));
      final unpack = runner.unpacks.single;
      expect(
        _win(unpack.executable),
        _win(
          '${work.absolute.path}/.dart_tool/blackgrid_packaging/downloads/'
          '$_installerSha/$_installerName',
        ),
      );
      expect(unpack.arguments, [
        '/PORTABLE=1',
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/SP-',
        '/NORESTART',
        '/CURRENTUSER',
        '/NOICONS',
        '/DIR=${_win(compilerDir().absolute.path)}',
        '/LOG=${_win(compilerDir().absolute.path)}.log',
      ]);
      expect(unpack.timeout, const Duration(minutes: 5));
      expect(File('${compilerDir().path}/.complete').existsSync(), isTrue);
      expect(File('${compilerDir().path}/leftover.tmp').existsSync(), isFalse);

      await runPackage();

      expect(fetchedLocks, hasLength(2));
      expect(runner.unpacks, hasLength(1));
      expect(runner.isccs, hasLength(2));
    });

    test(
      'a fetch hash mismatch fails naming both hashes and unpacks nothing',
      () async {
        fetchError = FetchException(
          'inno-setup',
          'sha256 mismatch',
          expected: 'a' * 64,
          actual: 'b' * 64,
        );
        seedEarlierOutput();

        final e = await refusal();

        expect(e.exitCode, 1);
        expect(e.message, contains('a' * 64));
        expect(e.message, contains('b' * 64));
        expect(runner.unpacks, isEmpty);
        expect(runner.isccs, isEmpty);
        expect(compilerDir().existsSync(), isFalse);
        expect(releaseDir().existsSync(), isFalse);
      },
    );

    test(
      'a failing unpack fails naming its log and leaves no marker',
      () async {
        runner.unpackExit = 5;

        final e = await refusal();

        expect(e.exitCode, 1);
        expect(e.message, contains('5'));
        expect(e.message, contains('.log'));
        expect(File('${compilerDir().path}/.complete').existsSync(), isFalse);
        expect(runner.isccs, isEmpty);
        expect(releaseDir().existsSync(), isFalse);
      },
    );

    test('ISCC runs only by absolute path from the packaging cache', () async {
      await runPackage();

      final iscc = runner.isccs.single;
      expect(File(iscc.executable).isAbsolute, isTrue);
      expect(
        _win(iscc.executable),
        _win('${compilerDir().absolute.path}/ISCC.exe'),
      );
    });
  });

  group('zip', () {
    test('the zip holds the bundle and notices under one versioned folder and nothing else', () async {
      setVersion('0.6.0-beta.1');
      stampHead();

      await runPackage();

      final zip = File(
        '${releaseDir().path}/Blackgrid-0.6.0-beta.1-windows-x64.zip',
      );
      final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
      final names = [
        for (final f in archive.files)
          if (f.isFile) f.name,
      ]..sort();
      expect(names, [
        'Blackgrid-0.6.0-beta.1/THIRD_PARTY_NOTICES.md',
        'Blackgrid-0.6.0-beta.1/blackgrid.exe',
        'Blackgrid-0.6.0-beta.1/data/app.so',
        'Blackgrid-0.6.0-beta.1/flutter_windows.dll',
      ]);
      expect(
        utf8.decode(
          archive.findFile('Blackgrid-0.6.0-beta.1/data/app.so')!.content,
        ),
        'so',
      );
    });

    test('missing notices fail and leave no zip', () async {
      File('${work.path}/THIRD_PARTY_NOTICES.md').deleteSync();
      commitAll('chore: drop notices');
      stampHead();

      final e = await refusal();

      expect(e.exitCode, 1);
      expect(e.message, contains('THIRD_PARTY_NOTICES.md'));
      expect(runner.isccs, isEmpty);
      expect(releaseDir().existsSync(), isFalse);
    });
  });

  group('installer', () {
    test('ISCC gets the display version, the numeric file version and absolute paths', () async {
      await runPackage();

      final iscc = runner.isccs.single;
      final abs = _win(work.absolute.path);
      expect(iscc.arguments, [
        '/Q',
        '/DAppVersion=0.6.0',
        '/DFileVersion=0.6.0.412',
        '/DSourceDir=$abs\\build\\windows\\x64\\runner\\Release',
        '/DNoticesFile=$abs\\THIRD_PARTY_NOTICES.md',
        '/DOutputDir=$abs\\build\\release',
        '/DOutputBaseFilename=Blackgrid-0.6.0-windows-x64-setup',
        '$abs\\windows\\installer\\blackgrid.iss',
      ]);
      expect(iscc.timeout, const Duration(minutes: 20));
      expect(iscc.stream, isTrue);
    });

    test('a beta version keeps its prerelease in the display version and drops it from the file version', () async {
      setVersion('0.6.0-beta.2');
      stampHead(buildNumber: 415);

      await runPackage();

      final args = runner.isccs.single.arguments;
      expect(args, contains('/DAppVersion=0.6.0-beta.2'));
      expect(args, contains('/DFileVersion=0.6.0.415'));
      expect(
        args,
        contains(
          '/DOutputBaseFilename=Blackgrid-0.6.0-beta.2-windows-x64-setup',
        ),
      );
    });
  });

  group('output set', () {
    test('a successful run leaves exactly the zip, the installer and matching SHA256SUMS.txt', () async {
      seedEarlierOutput();

      await runPackage();

      final names = [
        for (final f in releaseDir().listSync()) f.uri.pathSegments.last,
      ]..sort();
      expect(names, [
        'Blackgrid-0.6.0-windows-x64-setup.exe',
        'Blackgrid-0.6.0-windows-x64.zip',
        'SHA256SUMS.txt',
      ]);
      String hash(String name) => sha256
          .convert(File('${releaseDir().path}/$name').readAsBytesSync())
          .toString();
      expect(
        File('${releaseDir().path}/SHA256SUMS.txt').readAsStringSync(),
        '${hash('Blackgrid-0.6.0-windows-x64-setup.exe')}  '
        'Blackgrid-0.6.0-windows-x64-setup.exe\n'
        '${hash('Blackgrid-0.6.0-windows-x64.zip')}  '
        'Blackgrid-0.6.0-windows-x64.zip\n',
      );
    });

    test('a failing ISCC exits 1 naming the stage and its code and removes build/release', () async {
      runner.isccExit = 2;

      final e = await refusal();

      expect(e.exitCode, 1);
      expect(e.message, contains('installer'));
      expect(e.message, contains('exit code 2'));
      expect(releaseDir().existsSync(), isFalse);
    });

    test('a timed-out ISCC fails naming the timeout', () async {
      final timingOut = _TimingOutIscc(runner);

      Object? error;
      try {
        await package(
          repoDir: work,
          runner: timingOut,
          fetch: fakeFetch,
          out: StringBuffer(),
        );
      } on ReleaseException catch (e) {
        error = e;
      }

      expect(error, isA<ReleaseException>());
      expect('$error', contains('timed out'));
      expect(releaseDir().existsSync(), isFalse);
    });
  });
}

/// Delegates to [inner] but reports `ISCC.exe` as timed out.
class _TimingOutIscc implements CommandRunner {
  _TimingOutIscc(this.inner);

  final FakeRunner inner;

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool stream = false,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    if (executable.endsWith('ISCC.exe')) {
      return const CommandResult.timedOut('', '');
    }
    return inner.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      stream: stream,
      environment: environment,
      timeout: timeout,
    );
  }
}
