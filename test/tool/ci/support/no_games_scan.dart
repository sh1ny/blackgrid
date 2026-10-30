import 'package:yaml/yaml.dart';

/// The environment variable that confirms no game is running.
const noGamesVariable = 'BLACKGRID_NO_GAMES_RUNNING';

/// Whether [path] is a kind of file that [findNoGamesSetters] reads.
bool isScannableKind(String path) {
  final lower = path.toLowerCase();
  return const [
    '.toml',
    '.ps1',
    '.cmd',
    '.bat',
    '.sh',
    '.yml',
    '.yaml',
  ].any(lower.endsWith);
}

/// Reports where [content] of the repository file at [path] sets
/// [noGamesVariable].
///
/// Returns one human-readable finding per setter, each starting with [path].
/// Comments, descriptions, reads and Markdown are not setters. The file kind
/// comes from [path]: `.toml` (including `mise.toml`), `.ps1`, `.cmd`, `.bat`,
/// `.sh`, `.yml` and `.yaml`. Any other kind yields no findings.
List<String> findNoGamesSetters(String path, String content) {
  final lower = path.toLowerCase();
  final lines = content.split(RegExp(r'\r?\n'));
  final v = RegExp.escape(noGamesVariable);

  List<String> scan(RegExp setter, RegExp comment) => [
    for (var i = 0; i < lines.length; i++)
      if (!comment.hasMatch(lines[i]) && setter.hasMatch(lines[i]))
        '$path:${i + 1}: ${lines[i].trim()}',
  ];

  final hashComment = RegExp(r'^\s*#');

  if (lower.endsWith('.toml')) {
    // A key at the line start, or a key inside an inline table.
    return scan(RegExp('(^\\s*|[{,]\\s*)["\']?$v["\']?\\s*='), hashComment);
  }
  if (lower.endsWith('.ps1')) {
    return scan(
      RegExp(
        '\\\$env:$v\\s*=(?!=)'
        '|Set-Item\\s+(-Path\\s+)?["\']?env:$v'
        '|SetEnvironmentVariable\\(\\s*["\']$v["\']',
        caseSensitive: false,
      ),
      hashComment,
    );
  }
  if (lower.endsWith('.cmd') || lower.endsWith('.bat')) {
    return scan(
      RegExp('^\\s*set\\s+"?$v=', caseSensitive: false),
      RegExp(r'^\s*(rem\b|::)', caseSensitive: false),
    );
  }
  if (lower.endsWith('.sh')) {
    return scan(
      RegExp('^\\s*(export\\s+)?$v=|^\\s*export\\s+$v\\b'),
      hashComment,
    );
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
    ];
  }
  return const [];
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

/// Converts parsed YAML into plain Dart maps and lists.
Object? toPlain(Object? node) => switch (node) {
  YamlMap() => {
    for (final MapEntry(:key, :value) in node.entries) '$key': toPlain(value),
  },
  YamlList() => [for (final item in node) toPlain(item)],
  _ => node,
};
