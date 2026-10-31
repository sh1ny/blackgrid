// Provenance records for the app icon: the candidates record under
// `docs/design/app-icon/candidates/` and the source record beside the icon
// sources in `windows/runner/resources/app_icon/` (design D2). Pure Dart (no
// `dart:ui`) so plain-Dart tools can import it.
//
// Parsing never throws on malformed input: every problem becomes a failure
// string that names the field, so a reader can fix the record from the text.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../markers/icon_set.dart' show IconCompiler, compileIconSvg;

/// The command that regenerates the icon artifacts and the source record. A
/// hash-binding failure names it so the fix is one copy away.
const String iconBuildCommand = 'mise run icon:build';

/// File name of the vector source whose hash the source record binds.
const String sourceSvgName = 'app_icon.svg';

/// File name of the optional small-size vector source.
const String smallSvgName = 'app_icon_small.svg';

/// File name of the generated Windows icon.
const String icoName = 'app_icon.ico';

/// File name of the compiled in-app vector, `assets/app_icon/app_icon.vec`.
const String vecName = 'app_icon.vec';

const _schemaVersion = 1;
const _methods = {'hand-authored', 'ai-assisted'};
const _candidateFields = {
  'file',
  'author',
  'method',
  'tools',
  'date',
  'prompt',
  'concept',
};
const _candidatesFields = {'schemaVersion', 'candidates'};
const _sourceFields = {
  'schemaVersion',
  'author',
  'method',
  'tools',
  'date',
  'pickedCandidate',
  'pickDate',
  'concept',
  'sha256',
};
const _hashFields = {sourceSvgName, smallSvgName, icoName, vecName};

final _conceptPath = RegExp(r'^concepts/[^/\\]+\.png$');
final _vectorPath = RegExp(r'^vector/[^/\\]+\.svg$');
final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// How a candidate or the picked icon was made.
enum ProvenanceMethod {
  /// Drawn by a person without a generative tool.
  handAuthored('hand-authored'),

  /// Produced with a generative tool.
  aiAssisted('ai-assisted');

  const ProvenanceMethod(this.wire);

  /// The spelling used in the JSON records.
  final String wire;
}

/// One recorded candidate: a concept PNG or a vector SVG.
class CandidateEntry {
  /// Creates an entry; use [parseCandidatesRecord] rather than calling this.
  const CandidateEntry({
    required this.file,
    required this.author,
    required this.method,
    required this.tools,
    required this.date,
    required this.prompt,
    required this.concept,
  });

  /// Path relative to the candidates folder, using `/`.
  final String file;

  /// Who made it.
  final String author;

  /// How it was made.
  final ProvenanceMethod method;

  /// The tools used, at least one.
  final List<String> tools;

  /// Creation date as `YYYY-MM-DD`.
  final String date;

  /// The prompt given to a generative tool, or null.
  final String? prompt;

  /// For a vector candidate, the recorded concept PNG it was traced from, or
  /// null (always null for a concept PNG).
  final String? concept;
}

/// Result of [parseCandidatesRecord].
sealed class CandidatesParseResult {
  const CandidatesParseResult();
}

/// A valid candidates record.
final class CandidatesParsed extends CandidatesParseResult {
  /// Wraps [candidates].
  CandidatesParsed(List<CandidateEntry> candidates)
    : candidates = List.unmodifiable(candidates);

  /// The entries, in record order.
  final List<CandidateEntry> candidates;
}

/// A candidates record with problems.
final class CandidatesInvalid extends CandidatesParseResult {
  /// Wraps [failures].
  CandidatesInvalid(List<String> failures)
    : failures = List.unmodifiable(failures);

  /// One line per problem, each naming the entry and field.
  final List<String> failures;

  @override
  String toString() => failures.join('; ');
}

/// Parses and validates the candidates record [text].
///
/// [fileExists] receives each entry's `file` (relative to the candidates
/// folder) and says whether it is on disk.
CandidatesParseResult parseCandidatesRecord(
  String text, {
  required bool Function(String file) fileExists,
}) {
  final failures = <String>[];
  final json = _decodeObject(text, 'candidates', failures);
  if (json == null) return CandidatesInvalid(failures);

  _rejectUnknown(json, _candidatesFields, 'candidates', failures);
  _checkSchemaVersion(json, 'candidates', failures);
  final raw = switch (json['candidates']) {
    final List<Object?> list when list.isNotEmpty => list,
    _ => null,
  };
  if (raw == null) {
    failures.add('candidates.candidates: must be a non-empty list');
    return CandidatesInvalid(failures);
  }

  final entries = <CandidateEntry>[];
  final seen = <String>{};
  final concepts = <String>{
    for (final item in raw)
      if (item is Map<String, Object?>)
        if (item['file'] case final String f when _conceptPath.hasMatch(f)) f,
  };
  for (var i = 0; i < raw.length; i++) {
    final at = 'candidates[$i]';
    if (raw[i] is! Map<String, Object?>) {
      failures.add('$at: must be an object');
      continue;
    }
    final item = raw[i]! as Map<String, Object?>;
    _rejectUnknown(item, _candidateFields, at, failures);
    final before = failures.length;

    final file = _string(item, 'file', at, failures);
    if (file != null) {
      if (!_conceptPath.hasMatch(file) && !_vectorPath.hasMatch(file)) {
        failures.add(
          '$at.file: "$file" must be concepts/<name>.png or '
          'vector/<name>.svg',
        );
      } else if (!seen.add(file)) {
        failures.add('$at.file: duplicate entry for "$file"');
      } else if (!fileExists(file)) {
        failures.add('$at.file: "$file" is missing from the candidates folder');
      }
    }
    final author = _string(item, 'author', at, failures);
    final method = _method(item, at, failures);
    final tools = _tools(item, at, failures);
    final date = _date(item, 'date', at, failures);
    final prompt = _nullableString(item, 'prompt', at, failures);
    final concept = _nullableString(item, 'concept', at, failures);
    if (concept != null && !concepts.contains(concept)) {
      failures.add(
        '$at.concept: "$concept" is not a concept PNG recorded in this '
        'record',
      );
    }
    if (failures.length == before) {
      entries.add(
        CandidateEntry(
          file: file!,
          author: author!,
          method: method!,
          tools: tools!,
          date: date!,
          prompt: prompt,
          concept: concept,
        ),
      );
    }
  }
  return failures.isEmpty
      ? CandidatesParsed(entries)
      : CandidatesInvalid(failures);
}

/// The parsed source record: who made the shipped icon, which candidate it
/// was picked from, and the hashes binding it to the files on disk.
class SourceRecord {
  /// Creates a record; use [parseSourceRecord] rather than calling this.
  SourceRecord({
    required this.author,
    required this.method,
    required List<String> tools,
    required this.date,
    required this.pickedCandidate,
    required this.pickDate,
    required this.concept,
    required Map<String, String> sha256,
  }) : tools = List.unmodifiable(tools),
       sha256 = Map.unmodifiable(sha256);

  /// Who made the icon.
  final String author;

  /// How it was made.
  final ProvenanceMethod method;

  /// The tools used, at least one.
  final List<String> tools;

  /// Creation date as `YYYY-MM-DD`.
  final String date;

  /// The picked candidate, `vector/<name>.svg` under the candidates folder.
  final String pickedCandidate;

  /// The date the candidate was picked, as `YYYY-MM-DD`.
  final String pickDate;

  /// The concept PNG the picked candidate came from, or null.
  final String? concept;

  /// Lowercase hex SHA-256 by file name (`app_icon.svg`, `app_icon.ico`, and
  /// optionally `app_icon_small.svg` and `app_icon.vec`).
  final Map<String, String> sha256;
}

/// Result of [parseSourceRecord].
sealed class SourceParseResult {
  const SourceParseResult();
}

/// A valid source record.
final class SourceParsed extends SourceParseResult {
  /// Wraps [record].
  const SourceParsed(this.record);

  /// The record.
  final SourceRecord record;
}

/// A source record with problems.
final class SourceInvalid extends SourceParseResult {
  /// Wraps [failures].
  SourceInvalid(List<String> failures) : failures = List.unmodifiable(failures);

  /// One line per problem, each naming the field.
  final List<String> failures;

  @override
  String toString() => failures.join('; ');
}

/// Parses and validates the source record [text].
SourceParseResult parseSourceRecord(String text) {
  const at = 'source';
  final failures = <String>[];
  final json = _decodeObject(text, at, failures);
  if (json == null) return SourceInvalid(failures);

  _rejectUnknown(json, _sourceFields, at, failures);
  _checkSchemaVersion(json, at, failures);
  final author = _string(json, 'author', at, failures);
  final method = _method(json, at, failures);
  final tools = _tools(json, at, failures);
  final date = _date(json, 'date', at, failures);
  final picked = _string(json, 'pickedCandidate', at, failures);
  if (picked != null && !_vectorPath.hasMatch(picked)) {
    failures.add('$at.pickedCandidate: "$picked" must be vector/<name>.svg');
  }
  final pickDate = _date(json, 'pickDate', at, failures);
  final concept = _nullableString(json, 'concept', at, failures);
  if (concept != null && !_conceptPath.hasMatch(concept)) {
    failures.add('$at.concept: "$concept" must be concepts/<name>.png');
  }

  final hashes = <String, String>{};
  switch (json['sha256']) {
    case final Map<String, Object?> raw:
      _rejectUnknown(raw, _hashFields, '$at.sha256', failures);
      for (final name in [sourceSvgName, smallSvgName, icoName, vecName]) {
        switch (raw[name]) {
          case final String h when _hex64.hasMatch(h):
            hashes[name] = h;
          // Optional: a record from before the vector has no `.vec` hash, and
          // the rebuild command is what adds it.
          case null when name == smallSvgName || name == vecName:
            break;
          case null:
            failures.add('$at.sha256.$name: is missing');
          default:
            failures.add(
              '$at.sha256.$name: must be 64 lowercase hex characters',
            );
        }
      }
    case null:
      failures.add('$at.sha256: is missing');
    default:
      failures.add('$at.sha256: must be an object');
  }

  if (failures.isNotEmpty) return SourceInvalid(failures);
  return SourceParsed(
    SourceRecord(
      author: author!,
      method: method!,
      tools: tools!,
      date: date!,
      pickedCandidate: picked!,
      pickDate: pickDate!,
      concept: concept,
      sha256: hashes,
    ),
  );
}

/// Compares [record]'s hashes with the actual bytes.
///
/// [smallSvg] is null when `app_icon_small.svg` is not on disk and [vec] is
/// null when `app_icon.vec` is not; each file must be on disk exactly when the
/// record has a hash for it. Returns one failure per mismatch, each naming the
/// file and [iconBuildCommand]; empty when the record binds the files.
List<String> checkHashBinding(
  SourceRecord record, {
  required Uint8List svg,
  Uint8List? smallSvg,
  required Uint8List ico,
  required Uint8List? vec,
}) {
  final failures = <String>[];
  void differs(String name, String why) => failures.add(
    '$name: its hash differs from the record ($why); run $iconBuildCommand',
  );

  void compare(String name, Uint8List? bytes) {
    final recorded = record.sha256[name];
    switch ((bytes, recorded)) {
      case (null, null):
        break;
      case (null, _):
        differs(name, 'the record has a hash but the file is missing');
      case (_, null):
        differs(name, 'the file exists but the record has no hash for it');
      case (final b?, final r?) when sha256.convert(b).toString() != r:
        differs(name, 'the file has changed since the record was written');
      default:
        break;
    }
  }

  compare(sourceSvgName, svg);
  compare(smallSvgName, smallSvg);
  compare(icoName, ico);
  compare(vecName, vec);
  return failures;
}

/// Checks that [vec] is what compiling the source [svg] produces.
///
/// Compiles through [compile], by default the marker compiler that
/// `compileSources` uses. Returns a failure naming [vecName] and
/// [iconBuildCommand] when the bytes differ, or naming [sourceSvgName] when the
/// compiler rejects the source; empty when [vec] is in step with [svg].
List<String> checkCompiledVec(
  Uint8List svg,
  Uint8List vec, {
  IconCompiler compile = compileIconSvg,
}) {
  final Uint8List expected;
  try {
    expected = compile(utf8.decode(svg), sourceSvgName);
  } on Object catch (e) {
    return [
      '$sourceSvgName: cannot compile it to check $vecName ($e); fix the '
          'source, then run $iconBuildCommand',
    ];
  }
  if (_sameBytes(expected, vec)) return const [];
  return [
    '$vecName: it differs from the compiled $sourceSvgName; run '
        '$iconBuildCommand',
  ];
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Checks [record] against the candidates record: `pickedCandidate` must be a
/// recorded vector entry and a non-null `concept` a recorded concept PNG.
///
/// Returns one failure per problem; empty when both exist.
List<String> checkSourceAgainstCandidates(
  SourceRecord record,
  CandidatesParsed candidates,
) {
  final files = {for (final c in candidates.candidates) c.file};
  return [
    if (!files.contains(record.pickedCandidate))
      'source.pickedCandidate: "${record.pickedCandidate}" is not in the '
          'candidates record',
    if (record.concept case final c? when !files.contains(c))
      'source.concept: "$c" is not in the candidates record',
  ];
}

/// The JSON text of [record] with its hashes recomputed from the given bytes.
///
/// The human fields are copied unchanged. [smallSvg] is null when
/// `app_icon_small.svg` does not exist, which drops its hash. [vec] is the
/// compiled in-app vector whose hash is written under [vecName]. The text uses
/// a 2-space indent and ends with a newline.
String renderSourceRecord(
  SourceRecord record, {
  required Uint8List svg,
  Uint8List? smallSvg,
  required Uint8List ico,
  required Uint8List vec,
}) {
  String hash(Uint8List b) => sha256.convert(b).toString();
  final json = <String, Object?>{
    'schemaVersion': _schemaVersion,
    'author': record.author,
    'method': record.method.wire,
    'tools': record.tools,
    'date': record.date,
    'pickedCandidate': record.pickedCandidate,
    'pickDate': record.pickDate,
    'concept': record.concept,
    'sha256': {
      sourceSvgName: hash(svg),
      if (smallSvg != null) smallSvgName: hash(smallSvg),
      icoName: hash(ico),
      vecName: hash(vec),
    },
  };
  return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
}

Map<String, Object?>? _decodeObject(
  String text,
  String at,
  List<String> failures,
) {
  try {
    if (jsonDecode(text) case final Map<String, Object?> map) return map;
    failures.add('$at: the JSON document must be an object');
  } on FormatException catch (e) {
    failures.add('$at: not valid JSON (${e.message})');
  }
  return null;
}

void _rejectUnknown(
  Map<String, Object?> map,
  Set<String> known,
  String at,
  List<String> failures,
) {
  for (final field in map.keys.where((k) => !known.contains(k))) {
    failures.add('$at: unknown field "$field"');
  }
}

void _checkSchemaVersion(
  Map<String, Object?> map,
  String at,
  List<String> failures,
) {
  if (map['schemaVersion'] != _schemaVersion) {
    failures.add('$at.schemaVersion: must be $_schemaVersion');
  }
}

String? _string(
  Map<String, Object?> map,
  String field,
  String at,
  List<String> failures,
) {
  switch (map[field]) {
    case final String s when s.trim().isNotEmpty:
      return s;
    case null when !map.containsKey(field):
      failures.add('$at.$field: is missing');
    default:
      failures.add('$at.$field: must be a non-empty string');
  }
  return null;
}

/// A required key whose value is a string or null.
String? _nullableString(
  Map<String, Object?> map,
  String field,
  String at,
  List<String> failures,
) {
  switch (map[field]) {
    case final String s when s.trim().isNotEmpty:
      return s;
    case null when map.containsKey(field):
      return null;
    case null:
      failures.add('$at.$field: is missing (use null for none)');
    default:
      failures.add('$at.$field: must be a non-empty string or null');
  }
  return null;
}

ProvenanceMethod? _method(
  Map<String, Object?> map,
  String at,
  List<String> failures,
) {
  switch (map['method']) {
    case final String s when _methods.contains(s):
      return ProvenanceMethod.values.firstWhere((m) => m.wire == s);
    case null when !map.containsKey('method'):
      failures.add('$at.method: is missing');
    default:
      failures.add('$at.method: must be one of ${_methods.join(', ')}');
  }
  return null;
}

List<String>? _tools(
  Map<String, Object?> map,
  String at,
  List<String> failures,
) {
  switch (map['tools']) {
    case final List<Object?> list
        when list.isNotEmpty &&
            list.every((t) => t is String && t.trim().isNotEmpty):
      return list.cast<String>();
    case null when !map.containsKey('tools'):
      failures.add('$at.tools: is missing');
    default:
      failures.add('$at.tools: must be a non-empty list of non-empty strings');
  }
  return null;
}

String? _date(
  Map<String, Object?> map,
  String field,
  String at,
  List<String> failures,
) {
  final text = _string(map, field, at, failures);
  if (text == null) return null;
  if (_isoDate.firstMatch(text) case final m?) {
    final y = int.parse(m[1]!);
    final mo = int.parse(m[2]!);
    final d = int.parse(m[3]!);
    final parsed = DateTime.utc(y, mo, d);
    if (parsed.year == y && parsed.month == mo && parsed.day == d) {
      return text;
    }
  }
  failures.add('$at.$field: "$text" must be a real date as YYYY-MM-DD');
  return null;
}
