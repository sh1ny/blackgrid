@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/contracts.dart';

void main() {
  final repository = Directory.current.path;
  final manifestPath = '$repository/test/fixtures/m0/manifest.json';
  late Map<String, dynamic> manifest;
  late Directory temporary;

  setUp(() async {
    manifest = jsonDecode(
      await File(manifestPath).readAsString(),
    ) as Map<String, dynamic>;
    temporary = await Directory.systemTemp.createTemp('m0-fixture-integrity-');
    for (final value in manifest['files'] as List) {
      final row = value as Map<String, dynamic>;
      final target = File('${temporary.path}/${row['path']}');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(
        await File('$repository/${row['path']}').readAsBytes(),
      );
    }
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<ProcessResult> check() async {
    final path = '${temporary.path}/manifest.json';
    await File(path).writeAsString(jsonEncode(manifest));
    return Process.run('pwsh', [
      '-NoProfile',
      '-File',
      '$repository/tool/qualification/check_fixture_hashes.ps1',
      '-ManifestPath',
      path,
      '-FixtureRoot',
      temporary.path,
    ]);
  }

  test(
    'committed payload hashes and executable record linkage agree',
    () async {
      validateRecord(manifest);
      for (final value in manifest['files'] as List) {
        final row = value as Map<String, dynamic>;
        final bytes = await File('$repository/${row['path']}').readAsBytes();
        expect(sha256.convert(bytes).toString(), row['sha256']);
        expect(bytes.length, row['size_bytes']);
        validateRecord(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
      }
      final result = await check();
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final report =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(report['coverage'], {
        'actual_master_cases': 0,
        'native_display_cells': 0,
        'independent_map_controls': 0,
        'synthetic_geometry_cells': 16,
      });
    },
  );

  test('changed bytes fail before consumption', () async {
    final row = (manifest['files'] as List).first as Map<String, dynamic>;
    await File('${temporary.path}/${row['path']}').writeAsString('tampered');
    expect((await check()).exitCode, isNot(0));
  });

  test('missing declared payload fails', () async {
    final row = (manifest['files'] as List).first as Map<String, dynamic>;
    await File('${temporary.path}/${row['path']}').delete();
    expect((await check()).exitCode, isNot(0));
  });

  test(
    'altered transformation recipe cannot retain its frozen identity',
    () async {
      final row = (manifest['files'] as List).first as Map<String, dynamic>;
      (row['recipe'] as Map<String, dynamic>)['version'] = 2;
      expect((await check()).exitCode, isNot(0));
    },
  );

  test('unknown parents and altered parent hashes fail', () async {
    final rows = manifest['files'] as List;
    final first = rows[0] as Map<String, dynamic>;
    final second = rows[1] as Map<String, dynamic>;
    first['parent_ids'] = [second['id']];
    first['parent_bindings'] = [
      {'id': second['id'], 'sha256': second['sha256']},
    ];
    first['recipe'] = {'kind': 'derived', 'operation': 'copy', 'version': 1};
    first['recipe_sha256'] = sha256Json(first['recipe']);
    final valid = await check();
    expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');

    first['parent_ids'] = ['unknown-parent'];
    first['parent_bindings'] = [
      {'id': 'unknown-parent', 'sha256': second['sha256']},
    ];
    final unknown = await check();
    expect(unknown.exitCode, isNot(0));
    expect(unknown.stderr, contains('Unknown or duplicate parent'));

    first['parent_ids'] = [second['id']];
    first['parent_bindings'] = [
      {'id': second['id'], 'sha256': second['sha256']},
    ];
    expect((await check()).exitCode, 0);
    first['parent_bindings'] = [
      {'id': second['id'], 'sha256': '0' * 64},
    ];
    final altered = await check();
    expect(altered.exitCode, isNot(0));
    expect(altered.stderr, contains('Altered parent identity'));
  });

  test(
    'parent cycles fail even with correct declared byte identities',
    () async {
      final rows = manifest['files'] as List;
      final first = rows[0] as Map<String, dynamic>;
      final second = rows[1] as Map<String, dynamic>;
      for (final pair in [
        [first, second],
        [second, first],
      ]) {
        pair[0]['parent_ids'] = [pair[1]['id']];
        pair[0]['parent_bindings'] = [
          {'id': pair[1]['id'], 'sha256': pair[1]['sha256']},
        ];
        pair[0]['recipe'] = {
          'kind': 'derived',
          'operation': 'copy',
          'version': 1,
        };
        pair[0]['recipe_sha256'] = sha256Json(pair[0]['recipe']);
      }
      expect((await check()).exitCode, isNot(0));
    },
  );

  test(
    'synthetic or transformed inputs cannot inflate real coverage',
    () async {
      for (final field in [
        'actual_master_cases',
        'native_display_cells',
        'independent_map_controls',
      ]) {
        (manifest['coverage_claims'] as Map<String, dynamic>)[field] = 1;
        expect((await check()).exitCode, isNot(0));
        (manifest['coverage_claims'] as Map<String, dynamic>)[field] = 0;
      }
    },
  );

  test(
    'a copied derived input remains neither a master nor native evidence',
    () async {
      final source = (manifest['files'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((row) => row['id'] == 'm0-matcher-vectors');
      final copied = Map<String, dynamic>.from(source);
      copied['id'] = 'synthetic-derived-copy';
      copied['path'] = 'test/fixtures/m0/scanner/derived-copy.json';
      copied['parent_ids'] = [source['id']];
      copied['parent_bindings'] = [
        {'id': source['id'], 'sha256': source['sha256']},
      ];
      copied['recipe'] = {'kind': 'derived', 'operation': 'copy', 'version': 1};
      copied['recipe_sha256'] = sha256Json(copied['recipe']);
      final destination = File('${temporary.path}/${copied['path']}');
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(
        await File('${temporary.path}/${source['path']}').readAsBytes(),
      );
      (manifest['files'] as List).add(copied);
      final unchanged = await check();
      expect(
        unchanged.exitCode,
        0,
        reason: '${unchanged.stdout}\n${unchanged.stderr}',
      );
      final coverage = (jsonDecode(
        unchanged.stdout as String,
      ) as Map<String, dynamic>)['coverage'];
      expect(coverage['actual_master_cases'], 0);
      expect(coverage['native_display_cells'], 0);
      (manifest['coverage_claims']
              as Map<String, dynamic>)['actual_master_cases'] =
          1;
      expect((await check()).exitCode, isNot(0));
    },
  );

  test(
    'a rehashed incomplete matrix still cannot claim sixteen geometry cells',
    () async {
      final row = (manifest['files'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((row) => row['id'] == 'm0-display-matrix');
      final file = File('${temporary.path}/${row['path']}');
      final matrix =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      (matrix['cells'] as List).removeLast();
      final bytes = utf8.encode(jsonEncode(matrix));
      await file.writeAsBytes(bytes);
      row['sha256'] = sha256.convert(bytes).toString();
      row['size_bytes'] = bytes.length;
      expect((await check()).exitCode, isNot(0));
    },
  );

  test(
    'reclassified synthetic geometry is not native capture evidence',
    () async {
      final row = (manifest['files'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((row) => row['id'] == 'm0-display-matrix');
      final file = File('${temporary.path}/${row['path']}');
      final matrix =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final first = (matrix['cells'] as List).first as Map<String, dynamic>;
      first['evidence_class'] = 'live_user';
      first['evidence_ids'] = ['synthetic-not-a-native-observation'];
      final bytes = utf8.encode(jsonEncode(matrix));
      await file.writeAsBytes(bytes);
      row['sha256'] = sha256.convert(bytes).toString();
      row['size_bytes'] = bytes.length;
      (manifest['coverage_claims']
              as Map<String, dynamic>)['native_display_cells'] =
          1;
      expect((await check()).exitCode, isNot(0));
    },
  );

  test(
    'Unicode record-type aliases cannot bypass the evidence contract',
    () async {
      manifest['record_type'] = 'fixture_mani\uFEFFfest';
      expect((await check()).exitCode, isNot(0));
    },
  );

  test(
    'distinct Unicode source identities cannot alias frozen cases',
    () async {
      final first = (manifest['cases'] as List).first as Map<String, dynamic>;
      first['source_id'] = '${first['source_id']}\uFEFF';
      expect((await check()).exitCode, isNot(0));
    },
  );

  test(
    'embedded expectations cannot drift independently from hashed payloads',
    () async {
      final first = (manifest['cases'] as List).first as Map<String, dynamic>;
      (first['expected_effects'] as Map<String, dynamic>)['non_effects'] = [
        'changed expectation',
      ];
      expect((await check()).exitCode, isNot(0));
    },
  );
}
