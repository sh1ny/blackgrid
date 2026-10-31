import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _scriptPath = 'windows/installer/blackgrid.iss';
const _adrPath = 'docs/adr/0025-release-packaging.md';

/// One `[Section]` of an Inno Setup script, with its entries in order.
class _Section {
  _Section(this.name);

  final String name;

  /// The `key=value` directives (`[Setup]`), keyed by lowercase key.
  final Map<String, String> directives = {};

  /// The `Name: value; Name: value` entries (`[Files]`, `[Icons]`, ...),
  /// each keyed by lowercase parameter name.
  final List<Map<String, String>> entries = [];
}

/// Parses [source] into sections, skipping comments and preprocessor lines.
Map<String, _Section> _parse(String source) {
  final sections = <String, _Section>{};
  _Section? current;
  for (final raw in source.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) {
      continue;
    }
    final header = RegExp(r'^\[([^\]]+)\]$').firstMatch(line);
    if (header != null) {
      final name = header.group(1)!.toLowerCase();
      current = sections.putIfAbsent(name, () => _Section(name));
      continue;
    }
    if (current == null) fail('content before any section: $line');
    if (current.name == 'setup') {
      final eq = line.indexOf('=');
      if (eq < 0) fail('[Setup] line without "=": $line');
      current.directives[line.substring(0, eq).trim().toLowerCase()] = line
          .substring(eq + 1)
          .trim();
      continue;
    }
    final entry = <String, String>{};
    for (final part in line.split(';')) {
      if (part.trim().isEmpty) continue;
      final colon = part.indexOf(':');
      if (colon < 0) fail('entry parameter without ":": $line');
      entry[part.substring(0, colon).trim().toLowerCase()] = part
          .substring(colon + 1)
          .trim();
    }
    current.entries.add(entry);
  }
  return sections;
}

/// The committed application icon `SetupIconFile` must resolve to.
const _iconPath = 'windows/runner/resources/app_icon.ico';

/// Resolves [value], a path relative to the script's folder, to a
/// repository-relative path with `/` separators.
String _resolveFromScript(String value) {
  final parts = _scriptPath.split('/')..removeLast();
  for (final part in value.split(RegExp(r'[\\/]'))) {
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (part.isNotEmpty && part != '.') {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// Returns a failure, naming the setting, for each icon directive of
/// [setup] that does not point at the committed icon or the installed exe.
List<String> _iconWiringFailures(Map<String, String> setup) {
  final failures = <String>[];
  final setupIcon = setup['setupiconfile'];
  if (setupIcon == null) {
    failures.add('SetupIconFile is missing; it must name $_iconPath');
  } else if (_resolveFromScript(setupIcon) != _iconPath) {
    failures.add(
      'SetupIconFile resolves to ${_resolveFromScript(setupIcon)}, '
      'not $_iconPath',
    );
  }
  final uninstallIcon = setup['uninstalldisplayicon'];
  if (uninstallIcon != r'{app}\blackgrid.exe') {
    failures.add(
      r'UninstallDisplayIcon is '
      '${uninstallIcon ?? 'missing'}, '
      r'not {app}\blackgrid.exe',
    );
  }
  return failures;
}

void main() {
  late Map<String, _Section> sections;
  late Map<String, String> setup;

  setUp(() {
    sections = _parse(File(_scriptPath).readAsStringSync());
    setup = sections['setup']?.directives ?? fail('no [Setup] section');
  });

  test('the script requests lowest privileges, the per-user folder and the committed AppId', () {
    final adr = File(_adrPath).readAsStringSync();
    final guid = RegExp(
      r'`AppId` is `\{([0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12})\}`',
    ).firstMatch(adr)?.group(1);
    expect(guid, isNotNull, reason: 'ADR-0025 must record the AppId');

    expect(setup['privilegesrequired'], 'lowest');
    expect(setup.containsKey('privilegesrequiredoverridesallowed'), isFalse);
    expect(setup['defaultdirname'], r'{autopf}\Blackgrid');
    // `{{` is Inno Setup's escape for a literal `{`.
    expect(setup['appid'], '{{$guid}');
    expect(setup['versioninfoversion'], '{#FileVersion}');
    expect(setup['appversion'], '{#AppVersion}');
  });

  test('the script has no install-delete, uninstall-delete, uninstall-run or code section', () {
    // Section names are case-insensitive in Inno Setup; _parse lowercases.
    for (final forbidden in [
      'installdelete',
      'uninstalldelete',
      'uninstallrun',
      'code',
    ]) {
      expect(sections.keys, isNot(contains(forbidden)));
    }
  });

  test('every files entry carries ignoreversion', () {
    final files = sections['files']?.entries ?? fail('no [Files] section');
    expect(files, isNotEmpty);
    for (final entry in files) {
      final flags = (entry['flags'] ?? '').toLowerCase().split(RegExp(r'\s+'));
      expect(flags, contains('ignoreversion'), reason: '$entry');
    }
  });

  test('SetupIconFile resolves to the committed ico and UninstallDisplayIcon is the installed exe', () {
    expect(_iconWiringFailures(setup), isEmpty);
  });

  test(
    'a script naming another setup icon or none fails naming the setting',
    () {
      final source = File(_scriptPath).readAsStringSync();
      final setupIconLine = RegExp(r'^SetupIconFile=.*$', multiLine: true);
      expect(source, contains(setupIconLine));
      Map<String, String> mutated(String replacement) => _parse(
        source.replaceFirst(setupIconLine, replacement),
      )['setup']!.directives;

      expect(
        _iconWiringFailures(mutated(r'SetupIconFile=..\assets\other.ico')),
        [contains('SetupIconFile resolves to windows/assets/other.ico')],
      );
      expect(_iconWiringFailures(mutated('')), [
        contains('SetupIconFile is missing'),
      ]);
      expect(
        _iconWiringFailures({
          ...setup,
          'uninstalldisplayicon': r'{app}\other.exe',
        }),
        [contains('UninstallDisplayIcon')],
      );
    },
  );
}
