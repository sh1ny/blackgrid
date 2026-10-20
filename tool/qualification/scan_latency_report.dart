/// Turns scan timing log lines into the M4 latency figures and verdicts.
///
/// Everything here is pure: lines in, a [LatencyReport] out. File access and
/// output live in `scan_latency.dart`.
library;

import 'dart:convert';

import 'statistics.dart';

/// Targeted accepts over all accepts must be strictly above this share.
const targetedShareTarget = 0.5;

/// The p95 of trigger to decision of targeted accepts must not exceed this.
const targetedDecidedTargetMs = 300;

/// The p95 of trigger to the fallback pass starting must not exceed this.
const fallbackStartedTargetMs = 300;

/// The p95 of trigger to decision (else publication) of every published scan
/// that ran the fallback pass must not exceed this.
const totalTargetMs = 1500;

/// A verdict needs at least this many samples.
const minimumSamples = 20;

/// A line longer than this many characters is skipped as malformed.
const maxLineLength = 1024 * 1024;

/// Label of the informational fallback figure.
const fallbackWorkLabel = 'real fallback work began';

/// A figure's verdict against its target.
enum Verdict {
  /// At or under the target (above, for the targeted share).
  pass,

  /// Over the target.
  fail,

  /// Not enough evidence for a verdict.
  indeterminate,
}

/// Why a line was left out of every count except the skip counts.
enum SkipReason {
  /// Not a JSON object, or missing a trigger or end state.
  malformed,

  /// `v` is neither 2 nor 3.
  unsupportedVersion,

  /// `utc` is missing or not a timestamp.
  noValidUtc,
}

/// The result of reading one log line.
sealed class ParsedLine {
  const ParsedLine();
}

/// A line that was skipped for [reason].
final class SkippedLine extends ParsedLine {
  /// Creates a skipped line.
  const SkippedLine(this.reason);

  /// Why the line was skipped.
  final SkipReason reason;
}

/// The numeric content of one valid timing log line. It keeps no text,
/// candidates or item IDs.
final class ScanLine extends ParsedLine {
  /// Creates a scan line.
  const ScanLine({
    required this.version,
    required this.utc,
    required this.trigger,
    required this.end,
    required this.pass,
    required this.recording,
    required this.droppedTriggers,
    required this.published,
    required this.decided,
    required this.targeted,
    required this.fallback,
  });

  /// Log schema version, 2 or 3.
  final int version;

  /// When the scan ended.
  final DateTime utc;

  /// `mouse` or `hotkey`.
  final String trigger;

  /// `accepted`, `rejected`, `failed` or `superseded`.
  final String end;

  /// The winning pass, `targeted` or `fallback`, if any.
  final String? pass;

  /// Whether recording touched the scan. Always false for v2 lines, which do
  /// not carry it.
  final bool recording;

  /// Triggers dropped while this scan ran.
  final int droppedTriggers;

  /// Milliseconds from the trigger to publication.
  final double? published;

  /// Milliseconds from the trigger to the applied decision (v3).
  final double? decided;

  /// Stage milliseconds of the targeted pass, if it ran.
  final Map<String, double>? targeted;

  /// Stage milliseconds of the fallback pass, if it ran.
  final Map<String, double>? fallback;

  /// Whether the scan reached publication.
  bool get isPublished => end != 'superseded';
}

Map<String, double>? _stages(Object? value) => value is Map
    ? {
        for (final MapEntry(:key, value: stamp) in value.entries)
          if (key is String && stamp is num && stamp.isFinite)
            key: stamp.toDouble(),
      }
    : null;

double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

/// Reads one log line.
ParsedLine parseLine(String line) {
  const malformed = SkippedLine(SkipReason.malformed);
  if (line.length > maxLineLength) return malformed;
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    return malformed;
  }
  if (decoded is! Map) return malformed;
  final version = decoded['v'];
  // A JSON 3.0 equals 3 but is a double, so check the type too.
  if (version is! int || (version != 2 && version != 3)) {
    return const SkippedLine(SkipReason.unsupportedVersion);
  }
  final utcText = decoded['utc'];
  final utc = utcText is String ? DateTime.tryParse(utcText) : null;
  if (utc == null) return const SkippedLine(SkipReason.noValidUtc);
  final trigger = decoded['trigger'];
  final end = decoded['end'];
  if ((trigger != 'mouse' && trigger != 'hotkey') || end is! String) {
    return malformed;
  }
  // A v3 line without its recording flag cannot be trusted as recording-off.
  if (version == 3 && decoded['recording'] is! bool) return malformed;
  final ms = decoded['ms'];
  final msMap = ms is Map ? ms : const {};
  final pass = decoded['pass'];
  final dropped = decoded['droppedTriggers'];
  return ScanLine(
    version: version,
    utc: utc.toUtc(),
    trigger: trigger as String,
    end: end,
    pass: pass is String ? pass : null,
    recording: decoded['recording'] == true,
    droppedTriggers: dropped is int ? dropped : 0,
    published: _number(msMap['published']),
    decided: _number(msMap['decided']),
    targeted: _stages(msMap['targeted']),
    fallback: _stages(msMap['fallback']),
  );
}

/// The scan population a figure is drawn from, kept as numbers only.
class _Stratum {
  int scans = 0;
  int dropped = 0;
  int acceptedWithoutDecision = 0;
  int accepts = 0;
  int targetedWins = 0;
  final byEnd = <String, int>{};
  final byPass = <String, int>{};
  final targetedDecided = <num>[];
  final fallbackStarted = <num>[];
  final total = <num>[];
  final fallbackWork = <num>[];
}

class _ProxyStratum {
  final decided = <num>[];
  final fallbackUnderway = <num>[];
  final total = <num>[];
}

/// Reads lines one at a time and builds a [LatencyReport].
class LatencyAccumulator {
  /// Creates an accumulator for the window [since] (inclusive) to [until]
  /// (exclusive); either bound may be null. [files] only labels the report.
  LatencyAccumulator({this.since, this.until, this.files = const []});

  /// Start of the window, inclusive.
  final DateTime? since;

  /// End of the window, exclusive.
  final DateTime? until;

  /// The input files, for the report.
  final List<String> files;

  final _skipped = {for (final r in SkipReason.values) r: 0};
  final _strata = {'mouse': _Stratum(), 'hotkey': _Stratum()};
  final _proxies = {'mouse': _ProxyStratum(), 'hotkey': _ProxyStratum()};
  int _inWindow = 0;
  int _outside = 0;
  int _excludedRecording = 0;
  int _v2 = 0;
  int _v3 = 0;

  /// Adds one line. Blank lines are ignored.
  void addLine(String raw) {
    if (raw.trim().isEmpty) return;
    switch (parseLine(raw)) {
      case SkippedLine(:final reason):
        _skipped[reason] = _skipped[reason]! + 1;
      case final ScanLine line:
        if ((since != null && line.utc.isBefore(since!.toUtc())) ||
            (until != null && !line.utc.isBefore(until!.toUtc()))) {
          _outside++;
          return;
        }
        _inWindow++;
        if (line.version == 2) {
          _v2++;
          _addProxy(line);
        } else if (line.recording) {
          _excludedRecording++;
        } else {
          _v3++;
          _addMeasured(line);
        }
    }
  }

  void _addProxy(ScanLine line) {
    if (!line.isPublished) return;
    final proxy = _proxies[line.trigger]!;
    final published = line.published;
    if (line.end == 'accepted' &&
        line.pass == 'targeted' &&
        published != null) {
      proxy.decided.add(published);
    }
    if (line.fallback != null) {
      final targeted = line.targeted;
      if (targeted != null && targeted.isNotEmpty) {
        proxy.fallbackUnderway.add(
          targeted.values.reduce((a, b) => a > b ? a : b),
        );
      }
      if (published != null) proxy.total.add(published);
    }
  }

  void _addMeasured(ScanLine line) {
    final s = _strata[line.trigger]!;
    s.scans++;
    s.dropped += line.droppedTriggers;
    s.byEnd.update(line.end, (n) => n + 1, ifAbsent: () => 1);
    if (line.pass case final String pass) {
      s.byPass.update(pass, (n) => n + 1, ifAbsent: () => 1);
    }
    if (!line.isPublished) return;
    if (line.end == 'accepted') {
      s.accepts++;
      if (line.pass == 'targeted') s.targetedWins++;
      final decided = line.decided;
      if (decided == null) {
        s.acceptedWithoutDecision++;
      } else if (line.pass == 'targeted') {
        s.targetedDecided.add(decided);
      }
    }
    final fallback = line.fallback;
    if (fallback != null) {
      if (fallback['started'] case final double started) {
        s.fallbackStarted.add(started);
      }
      if (fallback['captureRequested'] case final double capture) {
        s.fallbackWork.add(capture);
      }
      if (line.decided ?? line.published case final double total) {
        s.total.add(total);
      }
    }
  }

  /// Builds the report from everything added so far.
  LatencyReport build() => LatencyReport._({
    'window': {
      'since': since?.toUtc().toIso8601String(),
      'until': until?.toUtc().toIso8601String(),
    },
    'files': files,
    'counts': {
      'inWindow': _inWindow,
      'outsideWindow': _outside,
      'skipped': {
        'malformed': _skipped[SkipReason.malformed],
        'unsupportedVersion': _skipped[SkipReason.unsupportedVersion],
        'noValidUtc': _skipped[SkipReason.noValidUtc],
      },
      'excludedRecording': _excludedRecording,
      'v3Lines': _v3,
      'v2Lines': _v2,
    },
    'targets': {
      'targetedSharePercent': targetedShareTarget * 100,
      'targetedDecidedMs': targetedDecidedTargetMs,
      'fallbackStartedMs': fallbackStartedTargetMs,
      'totalMs': totalTargetMs,
      'minimumSamples': minimumSamples,
    },
    'strata': {
      for (final MapEntry(:key, :value) in _strata.entries)
        key: _stratumJson(value),
    },
    'v2Proxy': {
      'proxy': true,
      'note':
          'Proxies from v2 lines; they never change a verdict. Decided is '
          'published; fallback underway is the targeted pass last stage.',
      'lines': _v2,
      for (final MapEntry(:key, :value) in _proxies.entries)
        key: {
          'decided': _proxyFigure(value.decided),
          'fallbackUnderway': _proxyFigure(value.fallbackUnderway),
          'total': _proxyFigure(value.total),
        },
    },
  });

  Map<String, Object?> _stratumJson(_Stratum s) {
    final noV3 = _v3 == 0;
    Map<String, Object?> latency(List<num> samples, int target) =>
        _figure(samples, target: target, noV3: noV3);
    final share = s.accepts == 0 ? null : s.targetedWins * 100 / s.accepts;
    final shareVerdict = _verdict(
      n: s.accepts,
      noV3: noV3,
      pass: s.targetedWins * 2 > s.accepts,
    );
    return {
      'scans': {
        'total': s.scans,
        'byEnd': s.byEnd,
        'byPass': s.byPass,
        'droppedTriggers': s.dropped,
      },
      'acceptedWithoutDecision': s.acceptedWithoutDecision,
      'targetedShare': {
        'n': s.accepts,
        'targetedAccepts': s.targetedWins,
        'percent': share,
        'target': targetedShareTarget * 100,
        ..._verdictJson(shareVerdict),
      },
      'targetedDecided': latency(s.targetedDecided, targetedDecidedTargetMs),
      'fallbackStarted': latency(s.fallbackStarted, fallbackStartedTargetMs),
      'total': latency(s.total, totalTargetMs),
      'fallbackWorkBegan': {
        'label': fallbackWorkLabel,
        ..._stats(s.fallbackWork),
      },
    };
  }
}

/// The figures of one run, as a JSON-ready map.
class LatencyReport {
  const LatencyReport._(this._json);

  final Map<String, Object?> _json;

  /// The report as JSON-encodable data.
  Map<String, Object?> toJson() => _json;

  /// The readable table of the same figures.
  String toTable() {
    final out = StringBuffer();
    final counts = _json['counts']! as Map<String, Object?>;
    final window = _json['window']! as Map<String, Object?>;
    out
      ..writeln(
        'Window: ${window['since'] ?? 'open'} to ${window['until'] ?? 'open'}',
      )
      ..writeln(
        'Lines: ${counts['inWindow']} in window, ${counts['outsideWindow']} '
        'outside, ${counts['excludedRecording']} excluded for recording, '
        '${counts['v2Lines']} v2, ${counts['v3Lines']} v3 used',
      )
      ..writeln('Skipped: ${counts['skipped']}');
    final strata = _json['strata']! as Map<String, Object?>;
    for (final MapEntry(:key, :value) in strata.entries) {
      final s = value! as Map<String, Object?>;
      out
        ..writeln()
        ..writeln('[$key] scans ${s['scans']}')
        ..writeln(
          '  accepted without decision: ${s['acceptedWithoutDecision']}',
        );
      final share = s['targetedShare']! as Map<String, Object?>;
      out.writeln(
        '  ${'targeted share'.padRight(22)} n=${share['n']} '
        '${_fmt(share['percent'])}% (target >${_fmt(share['target'])}%) '
        '${_verdictText(share)}',
      );
      for (final (name, label) in [
        ('targetedDecided', 'targeted decided'),
        ('fallbackStarted', 'fallback started'),
        ('total', 'total'),
      ]) {
        final f = s[name]! as Map<String, Object?>;
        out.writeln(
          '  ${label.padRight(22)} ${_statsText(f)} '
          '(target <=${f['target']} ms) ${_verdictText(f)}',
        );
      }
      final work = s['fallbackWorkBegan']! as Map<String, Object?>;
      out.writeln(
        '  ${'captureRequested'.padRight(22)} ${_statsText(work)} '
        '(info: ${work['label']})',
      );
    }
    final proxy = _json['v2Proxy']! as Map<String, Object?>;
    out
      ..writeln()
      ..writeln('v2 proxies (${proxy['lines']} lines; never a verdict)');
    for (final trigger in ['mouse', 'hotkey']) {
      final p = proxy[trigger]! as Map<String, Object?>;
      for (final name in ['decided', 'fallbackUnderway', 'total']) {
        out.writeln(
          '  [$trigger] ${name.padRight(18)} '
          '${_statsText(p[name]! as Map<String, Object?>)} (proxy)',
        );
      }
    }
    return out.toString();
  }
}

String _fmt(Object? value) => value is num
    ? (value == value.roundToDouble()
          ? value.round().toString()
          : value.toStringAsFixed(1))
    : '-';

String _statsText(Map<String, Object?> f) =>
    'n=${f['n']} p50=${_fmt(f['p50'])} p95=${_fmt(f['p95'])} '
    'max=${_fmt(f['max'])} ms';

String _verdictText(Map<String, Object?> f) => f['reason'] == null
    ? '${f['verdict']}'
    : '${f['verdict']} (${f['reason']})';

Map<String, Object?> _stats(List<num> samples) => {
  'n': samples.length,
  'p50': nearestRankQuantile(samples, quantile: 0.5),
  'p95': nearestRankQuantile(samples),
  'max': samples.isEmpty ? null : samples.reduce((a, b) => a > b ? a : b),
};

Map<String, Object?> _proxyFigure(List<num> samples) => {
  'proxy': true,
  ..._stats(samples),
};

(Verdict, String?) _verdict({
  required int n,
  required bool noV3,
  required bool pass,
}) {
  if (noV3) return (Verdict.indeterminate, 'no v3 lines');
  if (n == 0) return (Verdict.indeterminate, 'no samples');
  if (n < minimumSamples) {
    return (Verdict.indeterminate, 'fewer than $minimumSamples samples');
  }
  return (pass ? Verdict.pass : Verdict.fail, null);
}

Map<String, Object?> _verdictJson((Verdict, String?) result) {
  final (verdict, reason) = result;
  return {'verdict': verdict.name, 'reason': ?reason};
}

Map<String, Object?> _figure(
  List<num> samples, {
  required int target,
  required bool noV3,
}) {
  final stats = _stats(samples);
  final p95 = stats['p95'] as num?;
  return {
    ...stats,
    'target': target,
    ..._verdictJson(
      _verdict(
        n: samples.length,
        noV3: noV3,
        pass: p95 != null && p95 <= target,
      ),
    ),
  };
}

/// Summarises [lines] (all from one window) into a report.
LatencyReport summarise(
  Iterable<String> lines, {
  DateTime? since,
  DateTime? until,
  List<String> files = const [],
}) {
  final accumulator = LatencyAccumulator(
    since: since,
    until: until,
    files: files,
  );
  lines.forEach(accumulator.addLine);
  return accumulator.build();
}
