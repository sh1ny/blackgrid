import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/scan_latency.dart';

String _accept(int decided) => jsonEncode({
  'v': 3,
  'utc': '2026-10-21T18:30:00.000Z',
  'trigger': 'mouse',
  'end': 'accepted',
  'pass': 'targeted',
  'ms': {
    'trigger': 0,
    'published': decided - 1,
    'decided': decided,
    'targeted': {'started': 0.5},
  },
  'recording': false,
});

void main() {
  late Directory directory;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('scan-latency-');
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() => directory.delete(recursive: true));

  Future<int> run(List<String> arguments) =>
      runScanLatency(arguments, out: out, err: err);

  test('a missing input exits non-zero and writes nothing', () async {
    final missing = '${directory.path}/absent.jsonl';
    final report = File('${directory.path}/report.json');

    final code = await run([missing, '--out', report.path]);

    expect(code, isNot(0));
    expect(err.toString(), contains('absent.jsonl'));
    expect(report.existsSync(), isFalse);
  });

  test('report json and console table carry the verdicts', () async {
    final input = File('${directory.path}/scan-timings.jsonl');
    await input.writeAsString(
      '${List.generate(20, (i) => _accept(100)).join('\n')}\n',
    );
    final report = File('${directory.path}/report.json');

    final code = await run([
      '--since',
      '2026-10-21T18:00:00Z',
      '--until',
      '2026-10-22T00:00:00Z',
      '--out',
      report.path,
      input.path,
    ]);

    expect(code, 0, reason: err.toString());
    final json = jsonDecode(await report.readAsString()) as Map;
    final mouse = (json['strata'] as Map)['mouse'] as Map;
    expect((mouse['targetedDecided'] as Map)['verdict'], 'pass');
    expect((mouse['targetedShare'] as Map)['verdict'], 'pass');
    expect(
      ((json['strata'] as Map)['hotkey'] as Map)['total'],
      containsPair('verdict', 'indeterminate'),
    );
    expect(out.toString(), contains('targeted decided'));
    expect(out.toString(), contains('pass'));
    expect(out.toString(), contains('indeterminate'));
  });

  test('an existing output is kept without --force', () async {
    final input = File('${directory.path}/scan-timings.jsonl');
    await input.writeAsString('${_accept(100)}\n');
    final report = File('${directory.path}/report.json');
    await report.writeAsString('keep me');

    final refused = await run([input.path, '--out', report.path]);

    expect(refused, isNot(0));
    expect(err.toString(), contains('report.json'));
    expect(await report.readAsString(), 'keep me');

    final forced = await run([input.path, '--out', report.path, '--force']);

    expect(forced, 0, reason: err.toString());
    expect(await report.readAsString(), isNot('keep me'));
  });

  test('--out naming an input log is refused even with --force', () async {
    final input = File('${directory.path}/scan-timings.jsonl');
    await input.writeAsString('${_accept(100)}\n');

    final code = await run([
      input.path,
      '--out',
      '${directory.path}/./scan-timings.jsonl',
      '--force',
    ]);

    expect(code, 1);
    expect(err.toString(), contains('log file'));
    expect(await input.readAsString(), '${_accept(100)}\n');
  });

  test('a usage error exits non-zero', () async {
    expect(await run(['--since', 'nonsense', 'a.jsonl']), isNot(0));
    expect(await run([]), isNot(0));
    expect(await run(['--bogus']), isNot(0));
  });

  test('a bound without Z or an offset is a usage error', () async {
    final input = File('${directory.path}/scan-timings.jsonl');
    await input.writeAsString('${_accept(100)}\n');

    expect(await run(['--since', '2026-10-21T18:00:00', input.path]), 2);
    expect(err.toString(), contains('UTC'));
    expect(await run(['--until', '2026-10-21T20:00:00+02:00', input.path]), 0);
  });
}
