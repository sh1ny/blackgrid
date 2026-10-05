import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/contracts.dart';

const _configPath = 'inputs/config.json';
const _payloadPath = 'inputs/payload.dat';
const _undeclaredPath = 'undeclared.txt';
const _categories = [
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
];
const _payloadBytes = [0, 255, 13, 10, 128, 65, 0, 66];

// Bound every child, including the collector's Git and Dart descendants. These
// processes operate exclusively on the disposable source, never an application.
Future<ProcessResult> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  await process.stdin.close();
  final output = utf8.decoder.bind(process.stdout).join();
  final errors = utf8.decoder.bind(process.stderr).join();
  final completed = () async {
    final code = await process.exitCode;
    return ProcessResult(process.pid, code, await output, await errors);
  }();
  try {
    return await completed.timeout(timeout);
  } on TimeoutException {
    try {
      final kill = await Process.start('taskkill.exe', [
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ]);
      final killOutput = kill.stdout.drain<void>();
      final killErrors = kill.stderr.drain<void>();
      try {
        await kill.exitCode.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        kill.kill();
      }
      await Future.wait([killOutput, killErrors])
          .timeout(const Duration(seconds: 10));
    } finally {
      process.kill();
      await completed.timeout(const Duration(seconds: 10));
    }
    throw TimeoutException(
      '$executable exceeded $timeout: ${arguments.join(' ')}',
      timeout,
    );
  }
}

void _succeeds(ProcessResult result) {
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

void _refuses(ProcessResult result, String reason) {
  expect(
    result.exitCode,
    isNot(0),
    reason: '${result.stdout}\n${result.stderr}',
  );
  expect('${result.stdout}\n${result.stderr}', contains(reason));
}

Future<Map<String, dynamic>> _readRecord(String path) async =>
    jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;

Future<void> _noOutput(String output, {String? target}) async {
  expect(await File(output).exists(), isFalse);
  expect(await File('$output.local.json').exists(), isFalse);
  expect(await File(output).parent.exists(), isFalse);
  if (target != null) expect(await Directory(target).exists(), isFalse);
}

void main() {
  final repository = Directory.current.path;
  late String dartExecutable;
  late Map<String, String> environment;
  late Directory temporary;
  late Directory source;
  late String manifestPath;
  late Map<String, dynamic> manifest;

  group('synthetic freeze collector', () {
    setUpAll(() async {
      final baseEnvironment = <String, String>{
        'DART_DATA_HOME': '$repository/.dart_tool/dart-data',
      };
      final installation = await _run(
        'mise',
        ['where', 'flutter'],
        workingDirectory: repository,
        environment: baseEnvironment,
        timeout: const Duration(seconds: 30),
      );
      _succeeds(installation);
      final flutterRoot = (installation.stdout as String).trim();
      final dartBin = '$flutterRoot/bin/cache/dart-sdk/bin';
      dartExecutable = '$dartBin/dart.exe';
      expect(await File(dartExecutable).exists(), isTrue);
      environment = {
        ...baseEnvironment,
        // Collector resolves its own `dart` command from this pinned SDK.
        'PATH': '$dartBin;${Platform.environment['PATH'] ?? ''}',
        'GIT_AUTHOR_NAME': 'Nikolay Bochev',
        'GIT_AUTHOR_EMAIL': '309868+sh1ny@users.noreply.github.com',
        'GIT_COMMITTER_NAME': 'Nikolay Bochev',
        'GIT_COMMITTER_EMAIL': '309868+sh1ny@users.noreply.github.com',
        'GIT_AUTHOR_DATE': '2026-10-05T00:00:00Z',
        'GIT_COMMITTER_DATE': '2026-10-05T00:00:00Z',
      };
    });

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('m0-collector-');
      addTearDown(() => temporary.delete(recursive: true));
      source = await Directory('${temporary.path}/synthetic source').create();
      await File('${source.path}/$_configPath').parent.create(recursive: true);
      await File('${source.path}/$_configPath').writeAsString('{"scale":1}\n');
      await File('${source.path}/$_payloadPath').writeAsBytes(_payloadBytes);
      await File('${source.path}/$_undeclaredPath')
          .writeAsString('Synthetic file deliberately outside the closure.\n');
      Future<void> git(List<String> arguments) async {
        _succeeds(
          await _run(
            'git',
            [
              '-c',
              'core.autocrlf=false',
              '-c',
              'core.hooksPath=',
              '-c',
              'commit.gpgSign=false',
              '-C',
              source.path,
              ...arguments,
            ],
            workingDirectory: temporary.path,
            environment: environment,
            timeout: const Duration(seconds: 30),
          ),
        );
      }

      await git(['init', '--template=']);
      await git(['add', '--', _configPath, _payloadPath, _undeclaredPath]);
      await git([
        'commit',
        '-m',
        'Create disposable synthetic collector source',
        '-m',
        'Co-authored-by: KintsugiBot <296966193+KintsugiBot@users.noreply.github.com>',
      ]);
      manifestPath = '${temporary.path}/synthetic-manifest.json';
      manifest = {
        'schema_version': 1,
        'id': 'synthetic-collector-source',
        'files': [
          {'path': _payloadPath, 'role': 'synthetic-bytes'},
          {'path': _configPath, 'role': 'synthetic-config'},
        ],
        // These are invented identities, not DLLs/models or a real reference.
        'effective_inputs': <String, dynamic>{
          for (final category in _categories)
            category: [
              {
                'id': 'synthetic-$category',
                'path': category == 'config' ? _configPath : _payloadPath,
                'version': 'synthetic-1',
                'locator': 'synthetic/$category',
              },
            ],
        },
        'closure_complete': true,
        'closure_declaration':
            'All inputs of this synthetic recipe are declared.',
        'permission': {
          'use': 'private_reference',
          'status': 'cleared',
          'reviewer': 'synthetic-reviewer',
          'reviewed_at': '2026-10-05',
          'evidence_ids': ['synthetic-grant'],
          'scope_paths': [_configPath, _payloadPath],
        },
      };
    });

    Future<ProcessResult> collect(
      String mode,
      String output, {
      String? lock,
      String? target,
      bool allowMaterialization = false,
    }) async {
      await File(manifestPath).writeAsString(jsonEncode(manifest));
      return _run(
        'pwsh',
        [
          '-NoProfile',
          '-NonInteractive',
          '-File',
          '$repository/tool/qualification/freeze_reference.ps1',
          '-SourceRoot',
          source.path,
          '-OutputPath',
          output,
          '-InputManifestPath',
          manifestPath,
          '-Mode',
          mode,
          if (lock != null) ...['-LockPath', lock],
          if (target != null) ...['-MaterializePath', target],
          if (allowMaterialization) '-AllowMaterialization',
        ],
        workingDirectory: repository,
        environment: environment,
      );
    }

    String output(String name) => '${temporary.path}/$name/record.json';

    test(
      'incomplete closure stays nullable intake and refuses final lock',
      () async {
        manifest['closure_complete'] = false;
        const reason =
            'Synthetic native identity has deliberately not been declared.';
        final effective = manifest['effective_inputs'] as Map<String, dynamic>;
        effective['native'] = null;
        effective['native_reason'] = reason;
        final intakePath = output('intake');
        _succeeds(await collect('Intake', intakePath));
        final intake = await _readRecord(intakePath);
        validateRecord(intake);
        expect(intake['record_type'], 'source_intake');
        expect(intake['closure_complete'], isFalse);
        expect(intake['freeze_id'], isNull);
        expect(intake['freeze_id_reason'], isNotEmpty);
        expect(intake['effective_inputs']['native'], isNull);
        expect(intake['effective_inputs']['native_reason'], reason);
        await verifySourceIntegrity(intake, source.path);
        final finalPath = output('refused-final');
        _refuses(
          await collect('Lock', finalPath),
          'complete closure declaration',
        );
        await _noOutput(finalPath);
        expect(await _readRecord(intakePath), intake);
      },
    );

    test(
      'same HEAD changed included bytes produce a different collector freeze',
      () async {
        final config = File('${source.path}/$_configPath');
        // Both snapshots are equally dirty at the same HEAD and closure status.
        await config.writeAsString('{"scale":2}\n');
        final beforePath = output('before');
        _succeeds(await collect('Lock', beforePath));
        final before = await _readRecord(beforePath);
        validateRecord(before);
        await config.writeAsString('{"scale":3}\n');
        final afterPath = output('after');
        _succeeds(await collect('Lock', afterPath));
        final after = await _readRecord(afterPath);
        validateRecord(after);
        expect(after['reference'], before['reference']);
        expect(before['reference']['dirty'], isTrue);
        expect(after['freeze_id'], isNot(before['freeze_id']));
        final beforeConfig = (before['files'] as List).singleWhere(
          (dynamic file) => file['path'] == _configPath,
        );
        final afterConfig = (after['files'] as List).singleWhere(
          (dynamic file) => file['path'] == _configPath,
        );
        expect(afterConfig['size_bytes'], beforeConfig['size_bytes']);
        expect(afterConfig['sha256'], isNot(beforeConfig['sha256']));
        await verifySourceIntegrity(after, source.path);
      },
    );

    test(
      'Verify rejects changed included bytes without writing evidence',
      () async {
        final lockPath = output('lock');
        _succeeds(await collect('Lock', lockPath));
        final lockBytes = await File(lockPath).readAsBytes();
        final verifiedPath = output('verified');
        _succeeds(await collect('Verify', verifiedPath, lock: lockPath));
        await _noOutput(verifiedPath);
        await File(
          '${source.path}/$_payloadPath',
        ).writeAsBytes([..._payloadBytes.take(_payloadBytes.length - 1), 67]);
        final refusedPath = output('refused-byte-drift');
        _refuses(
          await collect('Verify', refusedPath, lock: lockPath),
          'Integrity drift',
        );
        await _noOutput(refusedPath);
        expect(await File(lockPath).readAsBytes(), lockBytes);
      },
    );

    test(
      'Verify rejects an equal-sized but different declared closure',
      () async {
        final lockPath = output('lock');
        _succeeds(await collect('Lock', lockPath));
        final lockBytes = await File(lockPath).readAsBytes();
        final includes = manifest['files'] as List;
        (includes.first as Map<String, dynamic>)['path'] = _undeclaredPath;
        final refusedPath = output('refused-closure-drift');
        _refuses(
          await collect('Verify', refusedPath, lock: lockPath),
          'Input manifest closure differs from recorded closure',
        );
        await _noOutput(refusedPath);
        expect(await File(lockPath).readAsBytes(), lockBytes);
      },
    );

    test('unknown private clearance refuses lock and materialization before creation', () async {
      manifest['permission']['status'] = 'unknown';
      final lockPath = output('refused-clearance-lock');
      _refuses(
        await collect('Lock', lockPath),
        'private_reference clearance is required',
      );
      await _noOutput(lockPath);
      final materializedLock = output('refused-clearance-materialize');
      final target = '${temporary.path}/not-created-unknown-clearance';
      _refuses(
        await collect(
          'Materialize',
          materializedLock,
          target: target,
          allowMaterialization: true,
        ),
        'private_reference clearance is required',
      );
      await _noOutput(materializedLock, target: target);
    });

    test(
      'materialization without explicit allow flag refuses before creation',
      () async {
        final lockPath = output('refused-flag');
        final target = '${temporary.path}/not-created-without-flag';
        _refuses(
          await collect('Materialize', lockPath, target: target),
          'Materialize requires -AllowMaterialization and -MaterializePath',
        );
        await _noOutput(lockPath, target: target);
      },
    );

    test('cleared materialization copies exactly declared bytes and validates in Dart', () async {
      final lockPath = output('materialized');
      final target = '${temporary.path}/materialized source';
      _succeeds(
        await collect(
          'Materialize',
          lockPath,
          target: target,
          allowMaterialization: true,
        ),
      );
      final record = await _readRecord(lockPath);
      validateRecord(record);
      expect(record['record_type'], 'source_lock');
      expect(record['freeze_id'], matches(RegExp(r'^[a-f0-9]{64}$')));
      final paths = (record['files'] as List)
          .map((dynamic row) => row['path'] as String)
          .toList();
      expect(paths, [_configPath, _payloadPath]);
      for (final dynamic row in record['files'] as List) {
        final path = row['path'] as String;
        final original = await File('${source.path}/$path').readAsBytes();
        final copied = await File('$target/$path').readAsBytes();
        expect(copied, original, reason: 'Exact declared bytes: $path');
        expect(row['sha256'], sha256.convert(copied).toString());
        expect(row['size_bytes'], copied.length);
      }
      expect(await File('$target/$_payloadPath').readAsBytes(), _payloadBytes);
      final copiedPaths = await Directory(target)
          .list(recursive: true)
          .where((entity) => entity is File)
          .map(
            (entity) =>
                entity.path.substring(target.length + 1).replaceAll('\\', '/'),
          )
          .toList();
      copiedPaths.sort();
      expect(copiedPaths, paths);
      expect(await File('$target/$_undeclaredPath').exists(), isFalse);
      expect(await Directory('$target/.git').exists(), isFalse);
      await verifySourceIntegrity(record, target);
      // Invoke the pinned consumer directly, without `dart run` cache discovery.
      final validated = await _run(
        dartExecutable,
        [
          '$repository/tool/qualification/m0.dart',
          'validate',
          lockPath,
          '--source-root',
          target,
        ],
        workingDirectory: repository,
        environment: environment,
      );
      _succeeds(validated);
      expect(
        jsonDecode(validated.stdout as String),
        containsPair('valid', true),
      );
      expect(
        jsonDecode(validated.stdout as String),
        containsPair('integrity_checked', true),
      );
    });
  }, skip: !Platform.isWindows);
}
