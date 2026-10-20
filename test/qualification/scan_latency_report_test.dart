import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qualification/scan_latency_report.dart';

// Synthetic timing log lines only; none of them comes from a real session.

const _inWindow = '2026-10-21T18:30:00.000Z';
final _since = DateTime.utc(2026, 10, 21, 18);

/// One timing log line. [fallbackStarted] or [fallbackCapture] makes the scan
/// a fallback-pass scan.
String line({
  int v = 3,
  String trigger = 'mouse',
  String end = 'accepted',
  String? pass = 'targeted',
  bool recording = false,
  String utc = _inWindow,
  num? published = 250,
  num? decided,
  num? targetedStarted,
  num? fallbackStarted,
  num? fallbackCapture,
  num? targetedLast,
}) {
  final targeted = {
    'started': ?targetedStarted,
    'captureRequested': 1,
    'matchFinished': ?targetedLast,
  };
  final fallback = {
    'started': ?fallbackStarted,
    'captureRequested': ?fallbackCapture,
  };
  return jsonEncode({
    'v': v,
    'utc': utc,
    'trigger': trigger,
    'end': end,
    'pass': ?pass,
    'ms': {
      'trigger': 0,
      'published': ?published,
      'decided': ?decided,
      'targeted': targeted,
      if (fallback.isNotEmpty) 'fallback': fallback,
    },
    if (v == 3) 'recording': recording,
    'droppedTriggers': 0,
    'supersededTriggers': 0,
  });
}

/// A targeted accept with a decision at [decided] ms.
String targetedAccept(num decided, {String trigger = 'mouse'}) =>
    line(trigger: trigger, decided: decided, published: decided - 1);

/// A scan that ran the fallback pass: started at [started], total [total].
String fallbackScan(
  num started,
  num total, {
  String trigger = 'mouse',
  String end = 'accepted',
  num? capture,
}) => line(
  trigger: trigger,
  end: end,
  pass: end == 'accepted' ? 'fallback' : null,
  fallbackStarted: started,
  fallbackCapture: capture ?? started + 5,
  decided: end == 'accepted' ? total : null,
  published: total,
);

List<String> series(int n, String Function(int i) make) => [
  for (var i = 1; i <= n; i++) make(i),
];

LatencyReport report(Iterable<String> lines) =>
    summarise(lines, since: _since, until: DateTime.utc(2026, 10, 22));

Map<String, Object?> figure(LatencyReport r, String trigger, String name) {
  final strata = r.toJson()['strata']! as Map<String, Object?>;
  final stratum = strata[trigger]! as Map<String, Object?>;
  return stratum[name]! as Map<String, Object?>;
}

void main() {
  test('two files are read over one window', () {
    final accumulator = LatencyAccumulator(
      since: _since,
      files: ['scan-timings.jsonl', 'scan-timings.1.jsonl'],
    );
    for (final l in series(20, (i) => targetedAccept(100))) {
      accumulator.addLine(l);
    }
    for (final l in series(20, (i) => targetedAccept(100))) {
      accumulator.addLine(l);
    }
    for (var i = 0; i < 900; i++) {
      accumulator.addLine(line(utc: '2026-10-21T17:59:59.999Z'));
    }
    final json = accumulator.build().toJson();
    final counts = json['counts']! as Map<String, Object?>;
    expect(counts['inWindow'], 40);
    expect(counts['outsideWindow'], 900);
    expect(json['files'], ['scan-timings.jsonl', 'scan-timings.1.jsonl']);
  });

  test('the window is inclusive of since and exclusive of until', () {
    final r = summarise(
      [
        line(utc: '2026-10-21T18:00:00.000Z'),
        line(utc: '2026-10-22T00:00:00.000Z'),
      ],
      since: _since,
      until: DateTime.utc(2026, 10, 22),
    );
    final counts = r.toJson()['counts']! as Map<String, Object?>;
    expect(counts['inWindow'], 1);
    expect(counts['outsideWindow'], 1);
  });

  test('malformed and unsupported lines are skipped by reason', () {
    final r = report([
      '{"v":3,"utc":"2026-10-21T18:3',
      jsonEncode({'v': 1, 'utc': _inWindow}),
      jsonEncode({'v': 3, 'utc': 'yesterday', 'trigger': 'mouse'}),
      '[1,2]',
      '',
      ...series(30, (i) => targetedAccept(100)),
    ]);
    final counts = r.toJson()['counts']! as Map<String, Object?>;
    expect(counts['inWindow'], 30);
    expect(counts['skipped'], {
      'malformed': 2,
      'unsupportedVersion': 1,
      'noValidUtc': 1,
    });
  });

  test('a non-integer version is skipped as unsupported', () {
    final asDouble = targetedAccept(100).replaceFirst('"v":3', '"v":3.0');
    expect(asDouble, contains('"v":3.0'));
    final r = report([asDouble, targetedAccept(100)]);
    final counts = r.toJson()['counts']! as Map<String, Object?>;
    expect(counts['inWindow'], 1);
    expect((counts['skipped']! as Map)['unsupportedVersion'], 1);
  });

  test('a v3 line without a recording flag is skipped as malformed', () {
    final withoutFlag = jsonDecode(targetedAccept(100)) as Map<String, Object?>
      ..remove('recording');
    final r = report([jsonEncode(withoutFlag), targetedAccept(100)]);
    final counts = r.toJson()['counts']! as Map<String, Object?>;
    expect(counts['inWindow'], 1);
    expect((counts['skipped']! as Map)['malformed'], 1);
  });

  test('recording-on lines are excluded and counted', () {
    final r = report([
      ...series(50, (i) => targetedAccept(100)),
      ...series(12, (i) => line(recording: true, decided: 900)),
    ]);
    final counts = r.toJson()['counts']! as Map<String, Object?>;
    expect(counts['excludedRecording'], 12);
    final decided = figure(r, 'mouse', 'targetedDecided');
    expect(decided['n'], 50);
    expect(decided['max'], 100);
  });

  test('v2 lines give proxies and indeterminate verdicts', () {
    final r = report([
      ...series(
        3,
        (i) => line(v: 2, published: 120, targetedLast: 100, decided: null),
      ),
      line(v: 2, end: 'rejected', pass: null, published: 700, targetedLast: 90),
    ]);
    final json = r.toJson();
    final mouse = figure(r, 'mouse', 'targetedDecided');
    expect(mouse['verdict'], 'indeterminate');
    expect(mouse['reason'], 'no v3 lines');
    expect(figure(r, 'mouse', 'targetedShare')['verdict'], 'indeterminate');
    final proxy = json['v2Proxy']! as Map<String, Object?>;
    expect(proxy['proxy'], isTrue);
    final mouseProxy = proxy['mouse']! as Map<String, Object?>;
    final decidedProxy = mouseProxy['decided']! as Map<String, Object?>;
    expect(decidedProxy['proxy'], isTrue);
    expect(decidedProxy['n'], 3);
    expect(decidedProxy['p95'], 120);
    expect(decidedProxy.containsKey('verdict'), isFalse);
  });

  test('v2 fallback proxy uses the targeted pass last stage', () {
    final r = report([
      line(
        v: 2,
        end: 'rejected',
        pass: null,
        published: 700,
        targetedLast: 90,
        fallbackCapture: 400,
      ),
    ]);
    final proxy =
        ((r.toJson()['v2Proxy']! as Map<String, Object?>)['mouse']!
                as Map<String, Object?>)['fallbackUnderway']!
            as Map<String, Object?>;
    expect(proxy['n'], 1);
    expect(proxy['max'], 90);
    expect(proxy['proxy'], isTrue);
  });

  test('nearest-rank p50, p95 and max over twenty samples', () {
    final r = report(series(20, (i) => targetedAccept(i * 10)));
    final f = figure(r, 'mouse', 'targetedDecided');
    expect(f['n'], 20);
    expect(f['p50'], 100);
    expect(f['p95'], 190);
    expect(f['max'], 200);
  });

  test('superseded scans are counted, not sampled', () {
    final r = report([
      ...series(30, (i) => targetedAccept(100)),
      ...series(5, (i) => line(end: 'superseded', pass: null, published: null)),
    ]);
    final mouse =
        (r.toJson()['strata']! as Map<String, Object?>)['mouse']!
            as Map<String, Object?>;
    final scans = mouse['scans']! as Map<String, Object?>;
    expect((scans['byEnd']! as Map<String, Object?>)['superseded'], 5);
    expect(figure(r, 'mouse', 'targetedDecided')['n'], 30);
    expect(figure(r, 'mouse', 'targetedShare')['n'], 30);
  });

  test('an empty hotkey stratum is indeterminate', () {
    final r = report(series(25, (i) => targetedAccept(100)));
    for (final name in [
      'targetedShare',
      'targetedDecided',
      'fallbackStarted',
      'total',
    ]) {
      final f = figure(r, 'hotkey', name);
      expect(f['n'], 0, reason: name);
      expect(f['verdict'], 'indeterminate', reason: name);
      expect(f['reason'], 'no samples', reason: name);
    }
  });

  test('targeted share above half passes', () {
    final r = report([
      ...series(24, (i) => targetedAccept(100)),
      ...series(6, (i) => fallbackScan(200, 900)),
    ]);
    final f = figure(r, 'mouse', 'targetedShare');
    expect(f['n'], 30);
    expect(f['percent'], 80);
    expect(f['verdict'], 'pass');
  });

  test('targeted share of exactly half fails', () {
    final r = report([
      ...series(20, (i) => targetedAccept(100)),
      ...series(20, (i) => fallbackScan(200, 900)),
    ]);
    final f = figure(r, 'mouse', 'targetedShare');
    expect(f['percent'], 50);
    expect(f['verdict'], 'fail');
  });

  test('all latency figures pass under target', () {
    final r = report([
      ...series(24, (i) => targetedAccept(i == 24 ? 240 : 100)),
      ...series(
        20,
        (i) => fallbackScan(i == 20 ? 280 : 100, i == 20 ? 900 : 500),
      ),
    ]);
    final decided = figure(r, 'mouse', 'targetedDecided');
    expect(decided['p95'], 100);
    expect(decided['verdict'], 'pass');
    final started = figure(r, 'mouse', 'fallbackStarted');
    expect(started['n'], 20);
    expect(started['verdict'], 'pass');
    final total = figure(r, 'mouse', 'total');
    expect(total['p95'], 500);
    expect(total['target'], 1500);
    expect(total['verdict'], 'pass');
  });

  test('slow targeted decision fails', () {
    final r = report(series(25, (i) => targetedAccept(i <= 20 ? 200 : 340)));
    final f = figure(r, 'mouse', 'targetedDecided');
    expect(f['p95'], 340);
    expect(f['target'], 300);
    expect(f['verdict'], 'fail');
  });

  test('a failed fallback scan is a total sample', () {
    final r = report(series(20, (i) => fallbackScan(100, 1650, end: 'failed')));
    final f = figure(r, 'mouse', 'total');
    expect(f['n'], 20);
    expect(f['max'], 1650);
    expect(f['verdict'], 'fail');
  });

  test('an accept without decided is counted, not sampled', () {
    final r = report([
      ...series(20, (i) => targetedAccept(100)),
      line(published: 300),
    ]);
    final mouse =
        (r.toJson()['strata']! as Map<String, Object?>)['mouse']!
            as Map<String, Object?>;
    expect(mouse['acceptedWithoutDecision'], 1);
    expect(figure(r, 'mouse', 'targetedDecided')['n'], 20);
  });

  test('fewer than twenty samples is indeterminate', () {
    final r = report(series(8, (i) => targetedAccept(210, trigger: 'hotkey')));
    final f = figure(r, 'hotkey', 'targetedDecided');
    expect(f['n'], 8);
    expect(f['p95'], 210);
    expect(f['verdict'], 'indeterminate');
    expect(f['reason'], 'fewer than 20 samples');
  });

  test('exactly twenty samples gives a verdict', () {
    final r = report(series(20, (i) => targetedAccept(250)));
    expect(figure(r, 'mouse', 'targetedDecided')['verdict'], 'pass');
  });

  test('fallback captureRequested p95 is informational per trigger', () {
    final r = report([
      ...series(20, (i) => fallbackScan(100, 500, capture: i * 10)),
      ...series(
        3,
        (i) => fallbackScan(100, 500, trigger: 'hotkey', capture: 700),
      ),
    ]);
    final mouse = figure(r, 'mouse', 'fallbackWorkBegan');
    expect(mouse['n'], 20);
    expect(mouse['p95'], 190);
    expect(mouse['label'], 'real fallback work began');
    expect(mouse.containsKey('verdict'), isFalse);
    final hotkey = figure(r, 'hotkey', 'fallbackWorkBegan');
    expect(hotkey['p95'], 700);
    expect(hotkey['n'], 3);
  });

  test('json carries no text, candidates or item ids', () {
    final r = report([targetedAccept(100)]);
    final text = jsonEncode(r.toJson());
    expect(text, isNot(contains('"item"')));
    expect(text, isNot(contains('candidates')));
    expect(text, isNot(contains('"text"')));
  });
}
