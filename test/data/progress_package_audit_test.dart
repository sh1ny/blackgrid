import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

typedef _Token = ({String text, bool string});

final _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

// Tokenize enough Dart to distinguish directives from comments and strings.
// Nested block comments and raw, multiline, and escaped strings are supported.
List<_Token> _tokens(String source) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i + 2);
      i = end < 0 ? source.length : end + 1;
      continue;
    }
    if (source.startsWith('/*', i)) {
      var depth = 1;
      i += 2;
      while (i < source.length && depth > 0) {
        if (source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      continue;
    }
    final raw =
        source[i] == 'r' &&
        i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"');
    if (raw) i++;
    if (source[i] == "'" || source[i] == '"') {
      final quote = source[i];
      final delimiter = source.startsWith(quote * 3, i) ? quote * 3 : quote;
      i += delimiter.length;
      final text = StringBuffer();
      while (i < source.length && !source.startsWith(delimiter, i)) {
        if (!raw && source[i] == r'\' && i + 1 < source.length) {
          i++;
          if ((source[i] == 'x' || source[i] == 'u') && i + 1 < source.length) {
            final unicode = source[i] == 'u';
            i++;
            if (unicode && source[i] == '{') {
              final end = source.indexOf('}', i + 1);
              if (end >= 0) {
                final value = int.tryParse(
                  source.substring(i + 1, end),
                  radix: 16,
                );
                if (value != null && value <= 0x10ffff) {
                  text.writeCharCode(value);
                  i = end + 1;
                  continue;
                }
              }
            } else {
              final length = unicode ? 4 : 2;
              if (i + length <= source.length) {
                final value = int.tryParse(
                  source.substring(i, i + length),
                  radix: 16,
                );
                if (value != null) {
                  text.writeCharCode(value);
                  i += length;
                  continue;
                }
              }
            }
          }
        }
        text.write(source[i++]);
      }
      if (i < source.length) i += delimiter.length;
      tokens.add((text: text.toString(), string: true));
      continue;
    }
    final word = _identifier.matchAsPrefix(source, i);
    if (word != null) {
      tokens.add((text: word.group(0)!, string: false));
      i = word.end;
    } else {
      if (!RegExp(r'\s').hasMatch(source[i])) {
        tokens.add((text: source[i], string: false));
      }
      i++;
    }
  }
  return tokens;
}

bool _forbiddenUri(String text) {
  final uri = Uri.tryParse(text);
  if (uri == null) return false;
  if (uri.scheme == 'dart') {
    return const {'ui', 'ffi', 'io', 'isolate'}.contains(uri.path);
  }
  return uri.scheme == 'package' &&
      uri.pathSegments.isNotEmpty &&
      const {'flutter', 'win32'}.contains(uri.pathSegments.first);
}

List<String> _forbiddenImports(String source) {
  final tokens = _tokens(source);
  final found = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].string ||
        (tokens[i].text != 'import' && tokens[i].text != 'export')) {
      continue;
    }
    // All URI literals in a directive include its conditional alternatives.
    for (i++; i < tokens.length && tokens[i].text != ';'; i++) {
      if (tokens[i].string && _forbiddenUri(tokens[i].text)) {
        found.add(tokens[i].text);
      }
    }
  }
  return found;
}

List<File> _filesUnder(Directory directory, {bool dartOnly = false}) {
  expect(
    directory.existsSync(),
    isTrue,
    reason: '${directory.path} must exist',
  );
  final files = directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => !dartOnly || file.path.endsWith('.dart'))
      .toList();
  expect(files, isNotEmpty, reason: '${directory.path} must not be empty');
  return files;
}

void main() {
  test('package declares and imports nothing Flutter, Windows or IO', () {
    final pubspec = File('packages/blackgrid_progress/pubspec.yaml');
    expect(pubspec.existsSync(), isTrue);
    final document = loadYaml(pubspec.readAsStringSync()) as YamlMap;
    final sdkDependencies = <String>[];
    for (final section in [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ]) {
      final dependencies = document[section];
      if (dependencies is! YamlMap) continue;
      for (final entry in dependencies.entries) {
        final value = entry.value;
        if (value is YamlMap && value['sdk'] == 'flutter') {
          sdkDependencies.add('$section: ${entry.key}');
        }
      }
    }
    expect(
      sdkDependencies,
      isEmpty,
      reason: 'Flutter SDK dependencies are forbidden',
    );

    final offenders = <String>[];
    for (final file in _filesUnder(
      Directory('packages/blackgrid_progress/lib'),
      dartOnly: true,
    )) {
      for (final uri in _forbiddenImports(file.readAsStringSync())) {
        offenders.add('${file.path}: $uri');
      }
    }
    expect(offenders, isEmpty);
  });

  test('no UI or application code reads the task catalog yet', () {
    final offenders = <String>[];
    for (final root in ['lib/ui', 'lib/application']) {
      for (final file in _filesUnder(Directory(root))) {
        final source = file.readAsStringSync();
        for (final reference in [
          'progressCatalog',
          'package:blackgrid_progress',
        ]) {
          if (source.contains(reference)) {
            offenders.add('${file.path}: $reference');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test(
    'import audit recognizes directives without matching comments or strings',
    () {
      const clean = '''
// import 'dart:io';
/* export 'package:flutter/material.dart'; /* import 'dart:ffi'; */ */
const example = "import 'dart:isolate';";
import 'dart:convert'; // export 'dart:ui';
''';
      expect(_forbiddenImports(clean), isEmpty);
      const bad = '''
import /* comment */ 'dart:io';
export 'safe.dart' if (dart.library.ui) 'dart:ui';
import 'safe.dart' if (dart.library.ffi) 'dart:ffi';
export "dart:isolate";
import 'package:flutter/widgets.dart';
export 'package:win32/win32.dart';
''';
      expect(_forbiddenImports(bad), [
        'dart:io',
        'dart:ui',
        'dart:ffi',
        'dart:isolate',
        'package:flutter/widgets.dart',
        'package:win32/win32.dart',
      ]);
    },
  );
}
