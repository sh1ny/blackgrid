import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Why a skip is allowlisted.
enum SkipKind {
  /// The test needs private input the CI runner does not have.
  privateInput,

  /// The test needs a host setting a GitHub-hosted runner cannot provide.
  hostPlatform,
}

/// The CI-run test that covers what a host-platform skip leaves unrun.
class CoveredBy {
  /// Creates a covering-test reference.
  const CoveredBy({required this.file, required this.test});

  /// The repo-relative, forward-slash path of the covering test file.
  final String file;

  /// The exact name of the covering test.
  final String test;
}

/// One allowlisted skip: a test file that may skip for exactly [reason].
class AllowedSkip {
  /// Creates an allowlist entry.
  const AllowedSkip({
    required this.kind,
    this.coveredBy,
    required this.file,
    required this.reason,
    required this.why,
  });

  /// Why this skip is allowlisted.
  final SkipKind kind;

  /// The CI-run test covering a [SkipKind.hostPlatform] skip; `null` otherwise.
  final CoveredBy? coveredBy;

  /// The repo-relative, forward-slash path of the test file.
  final String file;

  /// The exact `skipReason` the test reports.
  final String reason;

  /// A one-line explanation of why this skip is acceptable.
  final String why;
}

/// A skipped test that matched the allowlist.
class AcceptedSkip {
  /// Creates a record of an accepted skip.
  const AcceptedSkip({
    required this.file,
    required this.reason,
    required this.testName,
  });

  /// The repo-relative path of the test file.
  final String file;

  /// The skip reason the test reported.
  final String reason;

  /// The name of the skipped test.
  final String testName;

  @override
  String toString() => '$file: "$testName" skipped ($reason)';
}

/// A reason the audit failed.
sealed class AuditFinding {
  const AuditFinding();
}

/// A test skipped for a file and reason pair that is not allowlisted.
final class UnlistedSkip extends AuditFinding {
  /// Creates a finding for an unlisted skip.
  const UnlistedSkip({
    required this.file,
    required this.reason,
    required this.testName,
  });

  /// The repo-relative path of the test file.
  final String file;

  /// The skip reason the test reported.
  final String reason;

  /// The name of the skipped test.
  final String testName;

  @override
  String toString() =>
      'Unlisted skip in $file: "$testName" skipped with reason "$reason".';
}

/// A report line that is not a JSON object.
final class MalformedLine extends AuditFinding {
  /// Creates a finding for the malformed line at [lineNumber] (1-based).
  const MalformedLine(this.lineNumber, this.text);

  /// The 1-based line number in the report.
  final int lineNumber;

  /// The offending line.
  final String text;

  @override
  String toString() => 'Malformed report line $lineNumber: $text';
}

/// The report ended without a `done` event.
final class MissingDone extends AuditFinding {
  /// Creates the finding.
  const MissingDone();

  @override
  String toString() => 'The report has no done event; the run did not finish.';
}

/// No visible test ran unskipped.
final class NoTestRan extends AuditFinding {
  /// Creates the finding.
  const NoTestRan();

  @override
  String toString() => 'No test ran unskipped.';
}

/// The report file was missing or unreadable.
final class MissingReport extends AuditFinding {
  /// Creates the finding.
  const MissingReport();

  @override
  String toString() => 'The test report is missing or unreadable.';
}

/// An accepted host-platform skip whose covering test did not run and pass.
final class CoveringTestNotRun extends AuditFinding {
  /// Creates a finding for the skip of [skippedFile] covered by [coveringTest]
  /// in [coveringFile].
  const CoveringTestNotRun({
    required this.skippedFile,
    required this.coveringFile,
    required this.coveringTest,
  });

  /// The repo-relative path of the file with the accepted host-platform skip.
  final String skippedFile;

  /// The repo-relative path of the file that should hold the covering test.
  final String coveringFile;

  /// The name of the covering test.
  final String coveringTest;

  @override
  String toString() =>
      'The host-platform skip in $skippedFile is covered by "$coveringTest" in '
      '$coveringFile, but that test did not run and pass on this report.';
}

/// The outcome of [auditReport].
class AuditResult {
  /// Creates a result.
  const AuditResult({required this.findings, required this.accepted});

  /// Everything that makes the audit fail; empty when it passes.
  final List<AuditFinding> findings;

  /// The skips that matched the allowlist.
  final List<AcceptedSkip> accepted;

  /// Whether the audit found nothing wrong.
  bool get passed => findings.isEmpty;
}

/// Parses the allowlist YAML: a list of entry maps.
///
/// Every entry has a `kind` (`private_input` or `host_platform`) and non-empty
/// string `file`, `reason` and `why` fields. A `host_platform` entry also has a
/// `covered_by` map of non-empty `file` and `test`; a `private_input` entry
/// must not have one.
///
/// Throws a [FormatException] when the document is not such a list or an
/// entry breaks these rules.
List<AllowedSkip> parseAllowlist(String source) {
  final Object? document;
  try {
    document = loadYaml(source);
  } on YamlException catch (e) {
    throw FormatException('Allowlist is not valid YAML: ${e.message}');
  }
  if (document is! YamlList) {
    throw const FormatException('Allowlist must be a YAML list of entries.');
  }
  return [for (final entry in document) _parseEntry(entry)];
}

AllowedSkip _parseEntry(Object? entry) {
  FormatException invalid(String problem) =>
      FormatException('Allowlist entry $problem: $entry');
  if (entry
      case {
        'kind': final String kind,
        'file': final String file,
        'reason': final String reason,
        'why': final String why,
      }
      when file.isNotEmpty && reason.isNotEmpty && why.isNotEmpty) {
    final covered = (entry as Map).containsKey('covered_by')
        ? entry['covered_by']
        : null;
    final coveredBy = switch (covered) {
      null => null,
      {'file': final String f, 'test': final String t}
          when f.isNotEmpty && t.isNotEmpty =>
        CoveredBy(file: f, test: t),
      _ => throw invalid('has a malformed covered_by'),
    };
    return switch ((kind, coveredBy)) {
      ('private_input', null) => AllowedSkip(
        kind: SkipKind.privateInput,
        file: file,
        reason: reason,
        why: why,
      ),
      ('private_input', _) => throw invalid(
        'is a private_input and must not have covered_by',
      ),
      ('host_platform', final CoveredBy covering) => AllowedSkip(
        kind: SkipKind.hostPlatform,
        coveredBy: covering,
        file: file,
        reason: reason,
        why: why,
      ),
      ('host_platform', _) => throw invalid(
        'is a host_platform and needs covered_by',
      ),
      _ => throw invalid('has an unknown kind "$kind"'),
    };
  }
  throw invalid('needs kind, file, reason and why');
}

String _normalise(String path, String repoRoot) {
  String slash(String p) => p.replaceAll(r'\', '/');
  final root = slash(repoRoot).replaceAll(RegExp(r'/+$'), '');
  var result = slash(path);
  if (result.toLowerCase().startsWith('${root.toLowerCase()}/')) {
    result = result.substring(root.length + 1);
  }
  while (result.startsWith('./')) {
    result = result.substring(2);
  }
  return result;
}

/// Audits the lines of a `flutter test` JSON report against [allowlist].
///
/// [lines] is `null` when the report file was missing or unreadable, which
/// fails the audit. Test files are identified by the `suite.path` of the
/// test's suite, made relative to [repoRoot], never by the test `url`. A skip
/// is accepted only when its file and exact `skipReason` both appear in the
/// allowlist. Hidden tests, such as the `loading` entry before each suite and
/// `(setUpAll)`, are ignored.
///
/// Each accepted [SkipKind.hostPlatform] skip also needs its covering test: a
/// visible, unskipped test with `result` `success` in the suite
/// [CoveredBy.file] whose name equals [CoveredBy.test] or ends with a space
/// and [CoveredBy.test], because the reporter prefixes the names of enclosing
/// groups ("group test"). Otherwise the audit reports a [CoveringTestNotRun].
AuditResult auditReport(
  List<String>? lines,
  List<AllowedSkip> allowlist, {
  required String repoRoot,
}) {
  if (lines == null) {
    return const AuditResult(findings: [MissingReport()], accepted: []);
  }
  final findings = <AuditFinding>[];
  final accepted = <AcceptedSkip>[];
  final suitePaths = <int, String>{};
  final tests = <int, ({String name, int? suiteId, String reason})>{};
  var done = false;
  var ranUnskipped = 0;
  // Visible tests that finished, as (suite path, name, result, skipped).
  final finished =
      <({String file, String name, String result, bool skipped})>[];
  final coverageRequired = <AllowedSkip>{};

  for (var i = 0; i < lines.length; i++) {
    final text = lines[i];
    if (text.trim().isEmpty) continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      findings.add(MalformedLine(i + 1, text));
      continue;
    }
    if (decoded is! Map<String, Object?>) {
      findings.add(MalformedLine(i + 1, text));
      continue;
    }
    switch (decoded) {
      case {
        'type': 'suite',
        'suite': {'id': final int id, 'path': final String path},
      }:
        suitePaths[id] = _normalise(path, repoRoot);
      case {'type': 'testStart', 'test': final Map<String, Object?> test}:
        if (test['id'] case final int id) {
          final metadata = test['metadata'];
          tests[id] = (
            name: test['name'] as String? ?? '',
            suiteId: test['suiteID'] as int?,
            reason: metadata is Map
                ? metadata['skipReason'] as String? ?? ''
                : '',
          );
        }
      case {'type': 'testDone', 'testID': final int id}:
        if (decoded['hidden'] == true) continue;
        final test = tests[id];
        final file = suitePaths[test?.suiteId] ?? '';
        finished.add((
          file: file,
          name: test?.name ?? '',
          result: decoded['result'] as String? ?? '',
          skipped: decoded['skipped'] == true,
        ));
        if (decoded['skipped'] == true) {
          final reason = test?.reason ?? '';
          final name = test?.name ?? '';
          final entry = allowlist
              .where((a) => a.file == file && a.reason == reason)
              .firstOrNull;
          if (entry != null) {
            accepted.add(
              AcceptedSkip(file: file, reason: reason, testName: name),
            );
            if (entry.kind == SkipKind.hostPlatform) {
              coverageRequired.add(entry);
            }
          } else {
            findings.add(
              UnlistedSkip(file: file, reason: reason, testName: name),
            );
          }
        } else {
          ranUnskipped++;
        }
      case {'type': 'done'}:
        done = true;
      default:
        break;
    }
  }

  for (final entry in coverageRequired) {
    if (entry.coveredBy case final CoveredBy covering?) {
      final covered = finished.any(
        (t) =>
            t.file == covering.file &&
            !t.skipped &&
            t.result == 'success' &&
            (t.name == covering.test || t.name.endsWith(' ${covering.test}')),
      );
      if (!covered) {
        findings.add(
          CoveringTestNotRun(
            skippedFile: entry.file,
            coveringFile: covering.file,
            coveringTest: covering.test,
          ),
        );
      }
    }
  }
  if (!done) findings.add(const MissingDone());
  if (ranUnskipped == 0) findings.add(const NoTestRan());
  return AuditResult(findings: findings, accepted: accepted);
}
