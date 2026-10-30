import 'package:yaml/yaml.dart';

/// The environment variable that confirms no game is running.
const noGamesVariable = 'BLACKGRID_NO_GAMES_RUNNING';

/// Whether [path] is a kind of file that [findNoGamesSetters] reads.
bool isScannableKind(String path) {
  final lower = path.toLowerCase();
  return lower == 'cmakelists.txt' ||
      lower.endsWith('/cmakelists.txt') ||
      const [
        '.toml',
        '.ps1',
        '.psm1',
        '.psd1',
        '.cmd',
        '.bat',
        '.sh',
        '.yml',
        '.yaml',
        '.json',
        '.dart',
        '.c',
        '.cc',
        '.cpp',
        '.h',
        '.hpp',
        '.cmake',
        '.py',
      ].any(lower.endsWith);
}

/// The name of the constant that holds [noGamesVariable] in the guard code.
const _noGamesIdentifier = 'noGamesRunningVariable';

/// Dart files under `test/` that may name [noGamesVariable], each with why.
///
/// An exemption holds only while the file starts no process and imports only
/// [_exemptImports] or another exempt file, so none of them can hand the
/// confirmation to a child process, directly or through a helper.
const _testDartExemptions = {
  'test/data/capture/support/native_guard.dart':
      'defines the constant and reads it in the pure guard',
  'test/data/capture/native_guard_test.dart':
      'fake environments for the pure guard, with a fake process listing',
  'test/tool/ci/qualification_audit_test.dart':
      'fake guard inputs that build the forbidden skip reasons',
  'test/tool/ci/support/no_games_scan.dart': 'this scanner',
  'test/tool/ci/no_games_scan_test.dart': 'the fixtures of this scanner',
};

/// What an exempt file may import besides another exempt file: libraries
/// that start no process, so no helper can hand the confirmation to a child.
const _exemptImports = {
  'dart:convert',
  'dart:io',
  'package:flutter_test/flutter_test.dart',
  'package:yaml/yaml.dart',
  'tool/ci/src/audit.dart',
};

final _import = RegExp(r'''^\s*(import|export|part)\s+['"]([^'"]+)['"]''');

final _v = RegExp.escape(noGamesVariable);

final _hashComment = RegExp(r'^\s*#');
final _slashComment = RegExp(r'^\s*//');
final _cComment = RegExp(r'^\s*(//|/\*|\*)');
final _cmdComment = RegExp(r'^\s*(rem\b|::)', caseSensitive: false);

final _powerShellSetter = RegExp(
  '\\\$env:$_v\\s*=(?!=)'
  '|Set-Item\\s+(-Path\\s+)?["\']?env:$_v'
  '|SetEnvironmentVariable\\(\\s*["\']$_v["\']',
  caseSensitive: false,
);
final _cmdSetter = RegExp('^\\s*set\\s+"?$_v=', caseSensitive: false);
final _shSetter = RegExp('^\\s*(export\\s+)?$_v=|^\\s*export\\s+$_v\\b');

/// Reports where [content] of the repository file at [path] sets
/// [noGamesVariable].
///
/// Returns one human-readable finding per setter, each starting with [path].
/// Comments, descriptions, reads and Markdown are not setters. The file kind
/// comes from [path]; [isScannableKind] lists the kinds read, and any other
/// kind yields no findings.
///
/// - Shell and config files: an assignment in the file's own syntax.
/// - YAML: an `env` map key, or a sh, PowerShell or cmd setter inside a `run`
///   or `script` block.
/// - `.json`: a key named [noGamesVariable].
/// - C and C++: a `putenv`, `setenv` or `SetEnvironmentVariable` call.
/// - CMake: `set(ENV{...})`, or `-E env` with an assignment.
/// - Python: an `os.environ` assignment or update, `putenv`, or a dict key.
/// - Dart: any non-comment mention of [noGamesVariable] or of the
///   `noGamesRunningVariable` identifier, since code has no reason to name
///   it. The exceptions are the named files under `test/` that use it as fake
///   input to the pure guard `nativeCaptureSkipReason`, and only while they
///   start no process and import nothing but [_exemptImports] and each other.
List<String> findNoGamesSetters(String path, String content) {
  final lower = path.toLowerCase();
  final lines = content.split(RegExp(r'\r?\n'));

  List<String> scan(RegExp setter, RegExp comment) => [
    for (var i = 0; i < lines.length; i++)
      if (!comment.hasMatch(lines[i]) && setter.hasMatch(lines[i]))
        '$path:${i + 1}: ${lines[i].trim()}',
  ];

  if (lower.endsWith('.toml')) {
    // A key at the line start, or a key inside an inline table.
    return scan(RegExp('(^\\s*|[{,]\\s*)["\']?$_v["\']?\\s*='), _hashComment);
  }
  if (const ['.ps1', '.psm1', '.psd1'].any(lower.endsWith)) {
    return scan(_powerShellSetter, _hashComment);
  }
  if (lower.endsWith('.cmd') || lower.endsWith('.bat')) {
    return scan(_cmdSetter, _cmdComment);
  }
  if (lower.endsWith('.sh')) {
    return scan(_shSetter, _hashComment);
  }
  if (lower.endsWith('.json')) {
    return scan(RegExp('"$_v"\\s*:'), _slashComment);
  }
  if (const ['.c', '.cc', '.cpp', '.h', '.hpp'].any(lower.endsWith)) {
    return scan(
      RegExp(
        '(SetEnvironmentVariable[AW]?|_w?putenv(_s)?|\\bputenv|\\bsetenv)'
        '\\s*\\(.*$_v',
      ),
      _cComment,
    );
  }
  if (lower.endsWith('.cmake') || lower.endsWith('cmakelists.txt')) {
    return scan(
      RegExp(
        'set\\s*\\(\\s*ENV\\{$_v\\}|-E\\s+env\\b.*\\b$_v=',
        caseSensitive: false,
      ),
      _hashComment,
    );
  }
  if (lower.endsWith('.py')) {
    return scan(
      RegExp(
        'environ\\[\\s*["\']$_v["\']\\s*\\]\\s*=(?!=)'
        '|environ\\.(setdefault|update)\\(.*$_v'
        '|putenv\\(.*$_v'
        '|["\']$_v["\']\\s*:',
      ),
      _hashComment,
    );
  }
  if (lower.endsWith('.dart')) {
    final mentions = scan(
      RegExp('$_v|\\b$_noGamesIdentifier\\b'),
      _slashComment,
    );
    final normalized = path.replaceAll(r'\', '/');
    final exempt = _testDartExemptions.containsKey(normalized);
    if (mentions.isEmpty || !exempt) return mentions;
    return [
      for (final line in scan(RegExp(r'\bProcess\.(run|start)'), _slashComment))
        '$line (exempt file starts a process)',
      for (var i = 0; i < lines.length; i++)
        if (_import.firstMatch(lines[i]) case final match?)
          if (!_isPureImport(normalized, match.group(2)!))
            '$path:${i + 1}: ${lines[i].trim()} '
                '(exempt file imports ${match.group(2)})',
    ];
  }
  if (lower.endsWith('.yml') || lower.endsWith('.yaml')) {
    final Object? doc;
    try {
      doc = loadYaml(content);
    } on YamlException catch (e) {
      return ['$path: unparsable YAML: ${e.message}'];
    }
    return [
      for (final location in _yamlEnvSetters(doc, 'root'))
        '$path: `env` sets $noGamesVariable at $location',
      for (final (location, script) in _yamlScripts(doc, 'root'))
        for (final line in script.split(RegExp(r'\r?\n')))
          if (_isShellSetter(line))
            '$path: `run` at $location sets $noGamesVariable: ${line.trim()}',
    ];
  }
  return const [];
}

/// Whether [uri], imported by the exempt file at [from], is in
/// [_exemptImports] or is another exempt file. A relative [uri] is resolved
/// against the directory of [from].
bool _isPureImport(String from, String uri) {
  if (_exemptImports.contains(uri)) return true;
  if (uri.contains(':')) return false;
  final resolved = Uri.parse(from).resolve(uri).path;
  return _exemptImports.contains(resolved) ||
      _testDartExemptions.containsKey(resolved);
}

/// Whether one line of a YAML `run` or `script` block sets [noGamesVariable]
/// in sh, PowerShell or cmd syntax.
bool _isShellSetter(String line) {
  if (_hashComment.hasMatch(line) || _cmdComment.hasMatch(line)) return false;
  return _powerShellSetter.hasMatch(line) ||
      _cmdSetter.hasMatch(line) ||
      _shSetter.hasMatch(line);
}

Iterable<String> _yamlEnvSetters(Object? node, String location) sync* {
  switch (node) {
    case YamlMap():
      for (final MapEntry(:key, :value) in node.entries) {
        final here = '$location.$key';
        if (key == 'env' &&
            value is YamlMap &&
            value.containsKey(noGamesVariable)) {
          yield here;
        }
        yield* _yamlEnvSetters(value, here);
      }
    case YamlList():
      for (var i = 0; i < node.length; i++) {
        yield* _yamlEnvSetters(node[i], '$location[$i]');
      }
    default:
      break;
  }
}

/// Every string under a `run` or `script` key, with its location. A list
/// under the key contributes each of its strings.
Iterable<(String, String)> _yamlScripts(Object? node, String location) sync* {
  switch (node) {
    case YamlMap():
      for (final MapEntry(:key, :value) in node.entries) {
        final here = '$location.$key';
        if (key == 'run' || key == 'script') {
          switch (value) {
            case String():
              yield (here, value);
            case YamlList():
              for (var i = 0; i < value.length; i++) {
                if (value[i] case final String s) yield ('$here[$i]', s);
              }
            default:
              break;
          }
        }
        yield* _yamlScripts(value, here);
      }
    case YamlList():
      for (var i = 0; i < node.length; i++) {
        yield* _yamlScripts(node[i], '$location[$i]');
      }
    default:
      break;
  }
}

/// Converts parsed YAML into plain Dart maps and lists.
Object? toPlain(Object? node) => switch (node) {
  YamlMap() => {
    for (final MapEntry(:key, :value) in node.entries) '$key': toPlain(value),
  },
  YamlList() => [for (final item in node) toPlain(item)],
  _ => node,
};
