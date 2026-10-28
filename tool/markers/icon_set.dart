/// Validates a map marker icon set against the design-map-marker-icons rules.
///
/// An icon set is a directory holding a `manifest.json` (schema 1) and the
/// SVG files it lists, all beside the manifest. [checkIconSet] parses the
/// manifest, applies every rule and collects all failures instead of
/// stopping at the first.
///
/// Run the check from the command line with:
///
/// ```sh
/// mise exec -- dart run tool/markers/check.dart <manifest>
/// ```
///
/// The command prints one failure per line, prints the expected hash for
/// stale provenance records, and exits 1 on any failure, 0 when the set is
/// valid and 2 on a usage error.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart'
    as vector;

/// The 19 marker category keys that need an icon: `markerCategories` without
/// `Labels`.
const iconKeys = <String>[
  'QuestItems',
  'QuestObjectives',
  'PmcExtracts',
  'ScavExtracts',
  'SharedExtracts',
  'Transits',
  'Hazards',
  'HazardZones',
  'Switches',
  'PmcSpawns',
  'ScavSpawns',
  'BossSpawns',
  'CultistSpawns',
  'BtrStops',
  'lootContainers',
  'lootLoose',
  'locks',
  'stationaryWeapons',
  'CustomPins',
];

/// Whether a set must cover every key or may hold a subset.
enum IconSetScope {
  /// Full coverage of [iconKeys] is required.
  release,

  /// A subset of [iconKeys] is allowed.
  candidate,
}

/// One broken rule: which [rule], about which [subject] and the measured
/// [value].
final class IconSetFailure {
  /// Creates a failure.
  const IconSetFailure({
    required this.rule,
    required this.subject,
    required this.value,
  });

  /// The rule that failed, such as `coverage`, `form` or `palette`.
  final String rule;

  /// The marker key, file name, role or manifest field the failure is about.
  final String subject;

  /// What was found, in words.
  final String value;
}

/// Formats [failure] as one line: `rule: subject: value`.
String formatFailure(IconSetFailure failure) {
  final value = failure.value.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ');
  return '${failure.rule}: ${failure.subject}: $value';
}

/// The badge geometry of a set.
final class BadgeSpec {
  /// Creates a badge specification.
  const BadgeSpec({
    required this.diameter,
    required this.selectedDiameter,
    required this.glyph,
    required this.ring,
  });

  /// The badge diameter in logical pixels.
  final int diameter;

  /// The diameter of a selected badge.
  final int selectedDiameter;

  /// The glyph size inside the badge.
  final int glyph;

  /// The ring width.
  final int ring;
}

/// One valid icon of a set.
final class IconEntry {
  /// Creates an icon entry.
  const IconEntry({
    required this.key,
    required this.file,
    required this.role,
    required this.svg,
  });

  /// The marker category key.
  final String key;

  /// The SVG file name beside the manifest.
  final String file;

  /// The colour role name.
  final String role;

  /// The SVG source text.
  final String svg;
}

/// A set that passed every rule.
final class IconSet {
  /// Creates a valid set.
  const IconSet({
    required this.directory,
    required this.scope,
    required this.background,
    required this.badge,
    required this.roles,
    required this.icons,
  });

  /// The directory holding the manifest and the icons.
  final Directory directory;

  /// The scope of the set.
  final IconSetScope scope;

  /// The badge background colour as `#RRGGBB`.
  final String background;

  /// The badge geometry.
  final BadgeSpec badge;

  /// The role name to `#RRGGBB` colour map.
  final Map<String, String> roles;

  /// The icons in manifest order.
  final List<IconEntry> icons;

  /// The directory name, which names the set.
  String get name => _lastSegment(directory.path);
}

/// The outcome of [checkIconSet].
sealed class IconSetResult {
  const IconSetResult();
}

/// The set passed every rule.
final class IconSetValid extends IconSetResult {
  /// Creates a valid result.
  const IconSetValid(this.set);

  /// The validated set.
  final IconSet set;
}

/// The set broke at least one rule.
final class IconSetInvalid extends IconSetResult {
  /// Creates an invalid result.
  const IconSetInvalid(this.failures);

  /// Every failure found, in discovery order.
  final List<IconSetFailure> failures;
}

/// Derives the icon file name for [key], such as `pmc_extracts.svg`.
String iconFileName(String key) {
  final snake = key.replaceAllMapped(
    RegExp(r'(?<=[a-z0-9])([A-Z])'),
    (m) => '_${m[1]}',
  );
  return '${snake.toLowerCase()}.svg';
}

String _lastSegment(String path) =>
    path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

final _fileNamePattern = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*\.svg$');
final _hexColour = RegExp(r'^#[0-9A-Fa-f]{6}$');

const _topFields = {
  'schemaVersion',
  'scope',
  'background',
  'badge',
  'roles',
  'icons',
};
const _badgeFields = {'diameter', 'selectedDiameter', 'glyph', 'ring'};
const _iconFields = {'key', 'file', 'role', 'sha256', 'provenance'};

/// Checks the icon set described by the manifest at [manifestPath].
///
/// Returns [IconSetValid] only when every rule passes; otherwise returns
/// [IconSetInvalid] with all failures found.
IconSetResult checkIconSet(
  String manifestPath, {
  IconCompiler compile = compileIconSvg,
}) {
  final failures = <IconSetFailure>[];
  void fail(String rule, String subject, String value) =>
      failures.add(IconSetFailure(rule: rule, subject: subject, value: value));

  final manifestFile = File(manifestPath);
  final Object? json;
  try {
    json = jsonDecode(manifestFile.readAsStringSync());
  } on FileSystemException catch (e) {
    return IconSetInvalid([
      IconSetFailure(
        rule: 'manifest',
        subject: manifestPath,
        value: 'cannot read: ${e.message}',
      ),
    ]);
  } on FormatException catch (e) {
    return IconSetInvalid([
      IconSetFailure(
        rule: 'manifest',
        subject: manifestPath,
        value: 'malformed JSON: ${e.message}',
      ),
    ]);
  }
  if (json is! Map<String, Object?>) {
    return IconSetInvalid([
      IconSetFailure(
        rule: 'manifest',
        subject: manifestPath,
        value: 'the manifest must be a JSON object',
      ),
    ]);
  }

  void rejectUnknown(Map<String, Object?> map, Set<String> known, String at) =>
      _rejectUnknown(map, known, at, fail);

  rejectUnknown(json, _topFields, 'manifest');
  if (json['schemaVersion'] != 1) {
    fail(
      'manifest',
      'schemaVersion',
      'must be 1, found ${jsonEncode(json['schemaVersion'])}',
    );
  }
  final scope = switch (json['scope']) {
    'release' => IconSetScope.release,
    'candidate' => IconSetScope.candidate,
    final other => () {
      fail(
        'manifest',
        'scope',
        'must be "release" or "candidate", found ${jsonEncode(other)}',
      );
      return null;
    }(),
  };
  final background = switch (json['background']) {
    final String s when _hexColour.hasMatch(s) => s,
    final other => () {
      fail(
        'manifest',
        'background',
        'must be #RRGGBB, found ${jsonEncode(other)}',
      );
      return null;
    }(),
  };

  BadgeSpec? badge;
  if (json['badge'] case final Map<String, Object?> raw) {
    rejectUnknown(raw, _badgeFields, 'badge');
    final values = <String, int>{};
    for (final field in _badgeFields) {
      if (raw[field] case final int v when v > 0) {
        values[field] = v;
      } else {
        fail(
          'manifest',
          'badge',
          'field "$field" must be a positive integer, '
              'found ${jsonEncode(raw[field])}',
        );
      }
    }
    if (values.length == _badgeFields.length) {
      badge = BadgeSpec(
        diameter: values['diameter']!,
        selectedDiameter: values['selectedDiameter']!,
        glyph: values['glyph']!,
        ring: values['ring']!,
      );
    }
  } else {
    fail('manifest', 'badge', 'must be an object');
  }

  final roles = <String, String>{};
  if (json['roles'] case final Map<String, Object?> raw) {
    for (final MapEntry(:key, :value) in raw.entries) {
      if (value is String && _hexColour.hasMatch(value)) {
        roles[key] = value;
      } else {
        fail(
          'manifest',
          'roles',
          'role "$key" must be #RRGGBB, found ${jsonEncode(value)}',
        );
      }
    }
  } else {
    fail('manifest', 'roles', 'must be an object');
  }

  final entries = <_RawIcon>[];
  if (json['icons'] case final List<Object?> raw) {
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      final at = 'icons[$i]';
      if (item is! Map<String, Object?>) {
        fail('manifest', at, 'must be an object');
        continue;
      }
      final key = item['key'];
      final label = key is String ? key : at;
      rejectUnknown(item, _iconFields, label);
      final file = item['file'];
      final role = item['role'];
      if (key is! String || file is! String || role is! String) {
        for (final field in ['key', 'file', 'role']) {
          if (item[field] is! String) {
            fail('manifest', label, 'missing string field "$field"');
          }
        }
        continue;
      }
      entries.add(_RawIcon(key, file, role, item));
    }
  } else {
    fail('manifest', 'icons', 'must be a list');
  }

  _checkCoverage(entries, scope, fail);
  if (background != null) _checkPalette(background, roles, entries, fail);

  final icons = <IconEntry>[];
  final seenFiles = <String>{};
  for (final entry in entries) {
    final nameOk = _checkFileName(entry.key, entry.file, fail);
    if (nameOk && !seenFiles.add(entry.file)) {
      fail('file-name', entry.file, 'listed by more than one icon');
    }
    if (!nameOk) continue;
    final bytes = _readFile(manifestFile.parent, entry.file, fail);
    if (bytes == null) continue;
    final svg = _checkForm(entry.file, bytes, compile, fail);
    _checkProvenance(entry, bytes, manifestFile.parent, fail);
    icons.add(
      IconEntry(key: entry.key, file: entry.file, role: entry.role, svg: svg),
    );
  }

  if (failures.isNotEmpty ||
      scope == null ||
      background == null ||
      badge == null) {
    return IconSetInvalid(failures);
  }
  return IconSetValid(
    IconSet(
      directory: manifestFile.parent.absolute,
      scope: scope,
      background: background,
      badge: badge,
      roles: Map.unmodifiable(roles),
      icons: List.unmodifiable(icons),
    ),
  );
}

final class _RawIcon {
  const _RawIcon(this.key, this.file, this.role, this.json);
  final String key;
  final String file;
  final String role;
  final Map<String, Object?> json;
}

void _checkCoverage(
  List<_RawIcon> entries,
  IconSetScope? scope,
  void Function(String rule, String subject, String value) fail,
) {
  final seen = <String>{};
  for (final entry in entries) {
    if (!iconKeys.contains(entry.key)) {
      fail('coverage', entry.key, 'unknown key; it is not a marker category');
    } else if (!seen.add(entry.key)) {
      fail('coverage', entry.key, 'duplicate key; it has more than one icon');
    }
  }
  if (scope == IconSetScope.release) {
    for (final key in iconKeys.where((k) => !seen.contains(k))) {
      fail('coverage', key, 'missing; a release set needs an icon for it');
    }
  }
}

bool _checkFileName(
  String key,
  String file,
  void Function(String rule, String subject, String value) fail,
) {
  if (file.contains('/') || file.contains(r'\') || file.contains('..')) {
    fail('file-name', file, 'must sit beside the manifest: no subpath or ..');
    return false;
  }
  if (!_fileNamePattern.hasMatch(file)) {
    fail('file-name', file, 'must be lower snake case ending in .svg');
    return false;
  }
  if (iconKeys.contains(key) && file != iconFileName(key)) {
    fail('file-name', file, 'must be ${iconFileName(key)}, derived from $key');
    return false;
  }
  return true;
}

Uint8List? _readFile(
  Directory dir,
  String name,
  void Function(String rule, String subject, String value) fail,
) {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  try {
    return file.readAsBytesSync();
  } on FileSystemException {
    fail('form', name, 'file not found beside the manifest');
    return null;
  }
}

/// The lowercase hex SHA-256 of [bytes].
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Compiles SVG source to vector graphics bytes; throws on any rejection.
typedef IconCompiler = Uint8List Function(String xml, String debugName);

/// Compiles [xml] exactly as the map pack tool does, with warnings as errors
/// and the masking, clipping and overdraw optimizers off.
Uint8List compileIconSvg(String xml, String debugName) => vector.encodeSvg(
  xml: xml,
  debugName: debugName,
  warningsAsErrors: true,
  enableMaskingOptimizer: false,
  enableClippingOptimizer: false,
  enableOverdrawOptimizer: false,
);

const _svgNamespace = 'http://www.w3.org/2000/svg';
const _maxSvgBytes = 8192;

const _shapeAttributes = <String, Set<String>>{
  'path': {'d'},
  'circle': {'cx', 'cy', 'r'},
  'ellipse': {'cx', 'cy', 'rx', 'ry'},
  'rect': {'x', 'y', 'width', 'height', 'rx', 'ry'},
  'polygon': {'points'},
  'polyline': {'points'},
  'line': {'x1', 'y1', 'x2', 'y2'},
};

const _elementAttributes = <String, Set<String>>{
  'svg': {'xmlns', 'viewBox', 'width', 'height'},
  'g': {},
  ..._shapeAttributes,
};

const _commonAttributes = {
  'transform',
  'fill',
  'stroke',
  'stroke-width',
  'stroke-linecap',
  'stroke-linejoin',
  'stroke-miterlimit',
  'fill-rule',
  'clip-rule',
  'opacity',
};

const _tints = {'#ffffff', '#fff', 'white', 'none'};

typedef _Fail = void Function(String rule, String subject, String value);

/// Applies the form rule to one file and returns its decoded text.
String _checkForm(
  String file,
  Uint8List bytes,
  IconCompiler compile,
  _Fail fail,
) {
  final problems = <String>[];
  if (bytes.length > _maxSvgBytes) {
    problems.add('size ${bytes.length} bytes exceeds the $_maxSvgBytes limit');
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    fail('form', file, 'not valid UTF-8');
    return utf8.decode(bytes, allowMalformed: true);
  }
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlException catch (e) {
    fail('form', file, 'malformed XML: ${e.message}');
    return text;
  }
  if (document.doctypeElement != null) {
    problems.add('DOCTYPE declarations are not allowed');
  }
  for (final node in document.children.whereType<XmlProcessing>()) {
    problems.add('processing instruction <?${node.target}?> is not allowed');
  }
  _checkRoot(document.rootElement, problems);
  for (final problem in problems) {
    fail('form', file, problem);
  }
  if (problems.isNotEmpty) return text;

  try {
    if (compile(text, file).isEmpty) {
      fail('form', file, 'compiler produced empty output');
    }
  } on Object catch (e) {
    fail('form', file, 'compiler rejected the file: $e');
  }
  return text;
}

void _checkRoot(XmlElement root, List<String> problems) {
  if (root.name.qualified != 'svg' || root.namespaceUri != _svgNamespace) {
    problems.add(
      'root element <${root.name.qualified}> must be <svg> in the '
      '$_svgNamespace namespace',
    );
  }
  final viewBox = root.getAttribute('viewBox');
  final numbers = viewBox?.trim().split(RegExp(r'[\s,]+')).map(num.tryParse);
  if (numbers == null || !_isTileViewBox(numbers.toList())) {
    problems.add('viewBox ${jsonEncode(viewBox)} must be "0 0 24 24"');
  }
  for (final size in ['width', 'height']) {
    final value = root.getAttribute(size);
    if (value != null && value.trim() != '24') {
      problems.add('$size ${jsonEncode(value)} on <svg> must be 24');
    }
  }
  _checkElement(root, null, null, problems);
}

bool _isTileViewBox(List<num?> n) =>
    n.length == 4 && n[0] == 0 && n[1] == 0 && n[2] == 24 && n[3] == 24;

/// Walks [element], tracking the paint declared by its ancestors.
///
/// [fill] and [stroke] are the nearest declared values, or `null` when the
/// SVG default (black fill, no stroke) applies.
void _checkElement(
  XmlElement element,
  String? fill,
  String? stroke,
  List<String> problems,
) {
  final name = element.name.qualified;
  final allowed = _elementAttributes[name];
  if (allowed == null) {
    problems.add('element <$name> is not allowed');
    return;
  }
  var ownFill = fill;
  var ownStroke = stroke;
  for (final attribute in element.attributes) {
    final attr = attribute.name.qualified;
    if (!allowed.contains(attr) && !_commonAttributes.contains(attr)) {
      problems.add('attribute "$attr" on <$name> is not allowed');
      continue;
    }
    final value = attribute.value.trim();
    if (attr == 'fill' || attr == 'stroke') {
      if (!_tints.contains(value.toLowerCase())) {
        problems.add(
          '$attr "$value" on <$name> is not the tint; use #FFFFFF, #fff, '
          'white or none',
        );
      }
      if (attr == 'fill') {
        ownFill = value.toLowerCase();
      } else {
        ownStroke = value.toLowerCase();
      }
    }
  }
  if (_shapeAttributes.containsKey(name) && ownFill == null) {
    problems.add(
      'effective fill of <$name> is black (#000000): no fill is set on it or '
      'an ancestor',
    );
  }
  for (final child in element.children) {
    switch (child) {
      case XmlElement():
        _checkElement(child, ownFill, ownStroke, problems);
      case XmlText(:final value) when value.trim().isNotEmpty:
        problems.add('text content in <$name> is not allowed');
      case XmlCDATA():
        problems.add('CDATA in <$name> is not allowed');
      case XmlProcessing(:final target):
        problems.add('processing instruction <?$target?> is not allowed');
      default:
    }
  }
}

void _rejectUnknown(
  Map<String, Object?> map,
  Set<String> known,
  String at,
  _Fail fail,
) {
  for (final field in map.keys.where((k) => !known.contains(k))) {
    fail('manifest', at, 'unknown field "$field"');
  }
}

const _provenanceFields = {
  'author',
  'origin',
  'method',
  'tools',
  'concept',
  'date',
};
const _conceptFields = {'source', 'promptRecord'};
const _methods = {'hand-authored', 'ai-assisted'};
final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Applies the provenance and origin rules to one icon.
void _checkProvenance(
  _RawIcon entry,
  Uint8List bytes,
  Directory directory,
  _Fail fail,
) {
  final file = entry.file;
  final record = entry.json['provenance'];
  final recorded = entry.json['sha256'];
  final actual = sha256Hex(bytes);
  if (record is! Map<String, Object?>) {
    fail(
      'provenance',
      file,
      record == null
          ? 'missing provenance record'
          : 'provenance record must be an object',
    );
  }
  if (recorded is! String) {
    fail('provenance', file, 'missing sha256 record; expected sha256 $actual');
  } else if (recorded.toLowerCase() != actual) {
    fail(
      'provenance',
      file,
      'stale: recorded sha256 $recorded but the file hashes to $actual; '
          'expected sha256 $actual',
    );
  }
  if (record is! Map<String, Object?>) return;

  _rejectUnknown(record, _provenanceFields, file, fail);
  String? text(Map<String, Object?> map, String field) => switch (map[field]) {
    final String s when s.trim().isNotEmpty => s,
    _ => null,
  };
  void missing(String field) =>
      fail('provenance', file, 'missing field $field');

  if (text(record, 'author') == null) missing('author');

  switch (text(record, 'origin')) {
    case null:
      missing('origin');
    case 'project':
      break;
    case final other:
      fail('origin', file, 'origin "$other" is rejected; it must be "project"');
  }
  final method = text(record, 'method');
  switch (method) {
    case null:
      missing('method');
    case final m when _methods.contains(m):
      break;
    case final other:
      fail(
        'origin',
        file,
        'method "$other" is rejected; it must be hand-authored or '
            'ai-assisted',
      );
  }
  final tools = record['tools'];
  if (method == 'ai-assisted' &&
      !(tools is List<Object?> &&
          tools.isNotEmpty &&
          tools.every((t) => t is String && t.trim().isNotEmpty))) {
    fail(
      'provenance',
      file,
      'missing field tools; ai-assisted needs a non-empty list',
    );
  }

  final date = text(record, 'date');
  if (date == null) {
    missing('date');
  } else if (!_datePattern.hasMatch(date) || DateTime.tryParse(date) == null) {
    fail('provenance', file, 'date "$date" must be YYYY-MM-DD');
  }

  final concept = record['concept'];
  if (concept is! Map<String, Object?>) {
    missing('concept');
    return;
  }
  _rejectUnknown(concept, _conceptFields, file, fail);
  final source = text(concept, 'source');
  if (source == null) {
    missing('concept.source');
  } else if (source != 'none') {
    final prompt = text(concept, 'promptRecord');
    if (prompt == null) {
      missing('concept.promptRecord');
    } else if (_promptRecordProblem(directory, prompt) case final problem?) {
      fail('provenance', file, 'concept.promptRecord "$prompt" $problem');
    }
  }
}

/// Describes why [relative] is not a usable prompt record inside
/// [directory], or returns `null` when it is.
String? _promptRecordProblem(Directory directory, String relative) {
  final segments = relative.split(RegExp(r'[\\/]'));
  if (relative.startsWith('/') ||
      relative.startsWith(r'\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(relative) ||
      segments.contains('..')) {
    return 'must be a path inside the set directory';
  }
  final record = File('${directory.path}${Platform.pathSeparator}$relative');
  if (!record.existsSync()) return 'does not exist';
  String normalise(String p) => Platform.isWindows ? p.toLowerCase() : p;
  final root = normalise(directory.resolveSymbolicLinksSync());
  final resolved = normalise(record.resolveSymbolicLinksSync());
  if (!resolved.startsWith('$root${Platform.pathSeparator}')) {
    return 'resolves outside the set directory';
  }
  return null;
}

const _contrastFloor = 3.0;
const _reservedHue = (low: 170.0, high: 190.0);
const _greySaturation = 0.10;

/// Applies the palette rule: contrast, the reserved hue band and the roles
/// that carry meaning.
void _checkPalette(
  String background,
  Map<String, String> roles,
  List<_RawIcon> entries,
  _Fail fail,
) {
  final backgroundLuminance = _luminance(background);
  for (final MapEntry(key: role, value: colour) in roles.entries) {
    final ratio = _contrast(_luminance(colour), backgroundLuminance);
    if (ratio < _contrastFloor) {
      fail(
        'palette',
        role,
        '$colour has contrast ${ratio.toStringAsFixed(2)}:1 against '
            '$background; it needs at least 3:1',
      );
    }
    final (:hue, :saturation) = _hueSaturation(colour);
    if (saturation >= _greySaturation &&
        hue >= _reservedHue.low &&
        hue <= _reservedHue.high) {
      fail(
        'palette',
        role,
        '$colour has hue ${hue.toStringAsFixed(1)} degrees at '
            '${(saturation * 100).round()}% saturation, inside the reserved '
            '170-190 degree band',
      );
    }
  }
  for (final entry in entries) {
    if (!roles.containsKey(entry.role)) {
      fail('palette', entry.key, 'role "${entry.role}" is not defined');
    }
    final required = switch (entry.key) {
      final k when k.contains('Extract') => 'exit',
      'Hazards' || 'HazardZones' => 'danger',
      'CustomPins' => 'pin',
      _ => null,
    };
    if (required != null && entry.role != required) {
      fail(
        'palette',
        entry.key,
        'has role "${entry.role}" but must use the "$required" role',
      );
    }
  }
}

List<double> _channels(String hex) => [
  for (var i = 1; i < 7; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16) / 255,
];

double _luminance(String hex) {
  final [r, g, b] = [
    for (final c in _channels(hex))
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble(),
  ];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrast(double a, double b) =>
    (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

({double hue, double saturation}) _hueSaturation(String hex) {
  final [r, g, b] = _channels(hex);
  final high = math.max(r, math.max(g, b));
  final low = math.min(r, math.min(g, b));
  final delta = high - low;
  if (delta == 0) return (hue: 0, saturation: 0);
  final lightness = (high + low) / 2;
  final saturation = delta / (1 - (2 * lightness - 1).abs());
  final sector = high == r
      ? ((g - b) / delta) % 6
      : high == g
      ? (b - r) / delta + 2
      : (r - g) / delta + 4;
  return (hue: sector * 60, saturation: saturation);
}
