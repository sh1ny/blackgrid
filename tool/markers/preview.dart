/// Renders one or more marker icon sets into a single self-contained HTML
/// contact sheet.
///
/// ```sh
/// mise exec -- dart run tool/markers/preview.dart <manifest>... [--out <path>]
/// ```
///
/// The default output is `build/marker-previews/index.html`. Every set is
/// validated with `checkIconSet` first; any failure prints the failures,
/// exits 1 and writes nothing. More than [maxPreviewSets] sets exit 1 before
/// anything is validated or written. A usage error exits 2.
///
/// The sheet is written to `<out>.tmp` and renamed onto `<out>`, so a failed
/// run never replaces a previous sheet. When either path resolves, through
/// symbolic links and `.`/`..` segments, to a manifest or icon file of an
/// input set, the run exits 1 and writes nothing. It inlines every glyph once as a
/// `<symbol>` and has no external URL, script or font.
///
/// Glyphs are tinted by alpha, the HTML equivalent of the app's `srcIn`
/// filter: an `feFlood` in the role colour composited `in` the glyph. The
/// white literal in the SVG files is never rewritten.
///
/// Each category row shows, per set, the badge at the manifest diameter and
/// at three times that size, in the states normal, selected, dimmed,
/// highlighted and a deuteranopia simulation, on three backgrounds.
library;

import 'dart:io';

import 'package:xml/xml.dart';

import 'icon_set.dart';

/// The most sets one sheet shows.
const maxPreviewSets = 4;

/// The default output path.
const defaultPreviewOut = 'build/marker-previews/index.html';

const _usage =
    'usage: dart run tool/markers/preview.dart <manifest>... [--out <path>]';

/// The map's dimmed opacity.
const _dimmedOpacity = '0.22';

/// The map's highlight colour; it wins over the role colour.
const _highlight = '#18FFFF';

/// The backgrounds a badge is shown on: the app background
/// (`GridColors.background`), a mid olive-grey like forest and shoreline
/// artwork, and a light sand like pale interchange and customs terrain.
const _backgrounds = <String>['#070D0B', '#5A6150', '#C9C2A8'];

/// The Machado, Oliveira and Fernandes (2009) deuteranopia matrix at full
/// severity, applied in linear RGB.
const _deuteranopia =
    '0.367322 0.860646 -0.227968 0 0  '
    '0.280085 0.672501 0.047413 0 0  '
    '-0.011820 0.042940 0.968881 0 0  '
    '0 0 0 1 0';

const _states = <String>[
  'normal',
  'selected',
  'dimmed',
  'highlighted',
  'deuteranopia',
];

/// Attributes of the root `<svg>` that describe the wrapper, not the paint.
const _wrapperAttributes = {
  'xmlns',
  'viewBox',
  'width',
  'height',
  'version',
  'id',
  'x',
  'y',
};

/// Runs the preview for [args] and returns the process exit code.
///
/// Writes failures and the result line to [out] (default stdout) and usage
/// and limit errors to [err] (default stderr).
int runCli(List<String> args, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final manifests = <String>[];
  var target = defaultPreviewOut;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--out':
        if (i + 1 >= args.length) {
          stderrSink.writeln(_usage);
          return 2;
        }
        target = args[++i];
      case final flag when flag.startsWith('-'):
        stderrSink.writeln(_usage);
        return 2;
      case final manifest:
        manifests.add(manifest);
    }
  }
  if (manifests.isEmpty) {
    stderrSink.writeln(_usage);
    return 2;
  }
  if (manifests.length > maxPreviewSets) {
    stderrSink.writeln(
      'too many sets: ${manifests.length} given, at most $maxPreviewSets '
      'per preview',
    );
    return 1;
  }

  final sets = <IconSet>[];
  var failed = false;
  for (final manifest in manifests) {
    switch (checkIconSet(manifest)) {
      case IconSetValid(:final set):
        sets.add(set);
      case IconSetInvalid(:final failures):
        failed = true;
        stdoutSink.writeln('invalid: $manifest');
        failures.map(formatFailure).forEach(stdoutSink.writeln);
    }
  }
  if (failed) return 1;

  final inputs = {
    for (final (index, set) in sets.indexed) ...[
      _realPath(manifests[index]),
      for (final icon in set.icons)
        _realPath('${set.directory.path}${Platform.pathSeparator}${icon.file}'),
    ],
  };
  for (final path in [target, '$target.tmp']) {
    if (inputs.contains(_realPath(path))) {
      stderrSink.writeln('refusing to write $path: it is an input file');
      return 1;
    }
  }

  final temporary = File('$target.tmp');
  temporary.parent.createSync(recursive: true);
  temporary.writeAsStringSync(renderPreview(sets));
  temporary.renameSync(target);
  stdoutSink.writeln('wrote $target (${sets.length} set(s))');
  return 0;
}

/// Resolves [path] through symbolic links, including those of its nearest
/// existing ancestor when [path] does not exist yet, for comparison only.
///
/// `..` follows the platform: Windows collapses it lexically before any
/// link is followed, while POSIX applies it to the directory a link
/// resolved to, so there each existing segment is resolved before the next
/// one is applied.
String _realPath(String path) {
  final absolute = File(path).absolute.path;
  if (Platform.isWindows) {
    final normal = Uri.file(absolute).normalizePath().toFilePath();
    return _resolveExisting(normal).toLowerCase();
  }
  var current = '/';
  for (final segment in absolute.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      current = File(current).parent.path;
      continue;
    }
    final next = current == '/' ? '/$segment' : '$current/$segment';
    try {
      current = File(next).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Missing, or a dangling link: nothing to follow from here on.
      current = next;
    }
  }
  return current;
}

/// Resolves the longest existing prefix of the normalised [path] through
/// symbolic links and appends the segments that do not exist yet.
String _resolveExisting(String path) {
  final separators = RegExp(r'[\\/]');
  var rest = <String>[];
  var current = path;
  while (FileSystemEntity.typeSync(current) == FileSystemEntityType.notFound) {
    final parent = File(current).parent.path;
    if (parent == current) break;
    final name = current.substring(parent.length).replaceAll(separators, '');
    rest = [name, ...rest];
    current = parent;
  }
  final resolved =
      FileSystemEntity.typeSync(current) == FileSystemEntityType.notFound
      ? current
      : File(current).resolveSymbolicLinksSync();
  return [resolved, ...rest].join(Platform.pathSeparator);
}

/// Renders the contact sheet for [sets] as one HTML document.
String renderPreview(List<IconSet> sets) {
  final names = [for (final set in sets) set.name];
  final colours = <String>{
    _highlight,
    for (final set in sets) ...set.roles.values,
  };
  final html = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="en"><head><meta charset="utf-8">')
    ..writeln('<title>Marker icon preview</title>')
    ..writeln(_style)
    ..writeln('</head><body>')
    ..writeln('<h1>Marker icon preview</h1>')
    ..writeln(_definitions(sets, colours));

  html.writeln('<section class="legend">');
  for (final (i, set) in sets.indexed) {
    html
      ..writeln('<div class="legend-set">')
      ..writeln('<h2>${_esc(names[i])}</h2>')
      ..writeln(
        '<p>${_esc(set.scope.name)}, badge ${set.badge.diameter}px, '
        'selected ${set.badge.selectedDiameter}px, glyph '
        '${set.badge.glyph}px, ring ${set.badge.ring}px</p><ul>',
      );
    for (final MapEntry(:key, :value) in set.roles.entries) {
      html.writeln(
        '<li><span class="sw" style="background:${_esc(value)}"></span>'
        '${_esc(key)} ${_esc(value)}</li>',
      );
    }
    html.writeln('</ul></div>');
  }
  html.writeln('</section>');

  final covered = {for (final set in sets) ...set.icons.map((e) => e.key)};
  for (final key in iconKeys.where(covered.contains)) {
    html
      ..writeln('<section class="key" data-key="${_esc(key)}">')
      ..writeln('<h3>${_esc(key)}</h3><div class="sets">');
    for (final (i, set) in sets.indexed) {
      final icon = set.icons.where((e) => e.key == key).firstOrNull;
      html.writeln('<div class="set"><h4>${_esc(names[i])}</h4>');
      if (icon == null) {
        html.writeln('<p class="missing">no icon</p>');
      } else {
        for (final background in _backgrounds) {
          for (final state in _states) {
            html.writeln(_cell(i, set, icon, state, background));
          }
        }
      }
      html.writeln('</div>');
    }
    html.writeln('</div></section>');
  }
  html.writeln('</body></html>');
  return html.toString();
}

/// The hidden `<svg>` holding the symbols and the filters.
String _definitions(List<IconSet> sets, Set<String> colours) {
  final buffer = StringBuffer(
    '<svg width="0" height="0" style="position:absolute" '
    'aria-hidden="true"><defs>',
  );
  for (final (i, set) in sets.indexed) {
    for (final icon in set.icons) {
      buffer.write(_symbol(i, icon));
    }
  }
  for (final colour in colours) {
    // Alpha tint: the flood colour kept where the glyph has coverage.
    buffer.write(
      '<filter id="${_tintId(colour)}" color-interpolation-filters="sRGB">'
      '<feFlood flood-color="${_esc(colour)}" result="flood"/>'
      '<feComposite in="flood" in2="SourceGraphic" operator="in"/></filter>',
    );
  }
  buffer.write(
    '<filter id="deuteranopia" color-interpolation-filters="linearRGB">'
    '<feColorMatrix type="matrix" values="$_deuteranopia"/></filter>'
    '</defs></svg>',
  );
  return buffer.toString();
}

/// One glyph as a `<symbol>`: the children of the file's `<svg>` inside a
/// `<g>` that carries the root's paint attributes so inheritance holds.
String _symbol(int setIndex, IconEntry icon) {
  final root = XmlDocument.parse(icon.svg).rootElement;
  final paint = StringBuffer();
  for (final attribute in root.attributes) {
    final name = attribute.name.qualified;
    if (_wrapperAttributes.contains(name) || name.startsWith('xmlns')) continue;
    paint.write(' $name="${_esc(attribute.value)}"');
  }
  final body = root.children
      .whereType<XmlElement>()
      .map((e) => e.toXmlString())
      .join();
  return '<symbol id="${_symbolId(setIndex, icon.key)}" '
      'viewBox="0 0 24 24"><g$paint>$body</g></symbol>';
}

String _symbolId(int setIndex, String key) =>
    'g$setIndex-${key.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_')}';

String _tintId(String colour) => 'tint-${colour.substring(1).toUpperCase()}';

/// A labelled cell: the badge at 1x and 3x in [state] on [background].
String _cell(
  int setIndex,
  IconSet set,
  IconEntry icon,
  String state,
  String background,
) {
  final role = set.roles[icon.role] ?? '#FFFFFF';
  final badge = set.badge;
  final size = state == 'selected' ? badge.selectedDiameter : badge.diameter;
  final colour = state == 'highlighted' ? _highlight : role;
  final symbol = _symbolId(setIndex, icon.key);
  String draw(int scale) {
    final inset = (size - badge.glyph) / 2;
    final radius = size / 2;
    final inner = StringBuffer()
      ..write(
        '<circle cx="$radius" cy="$radius" r="${radius - badge.ring / 2}" '
        'fill="${_esc(set.background)}" stroke="${_esc(colour)}" '
        'stroke-width="${badge.ring}"/>',
      )
      ..write(
        '<use href="#$symbol" x="$inset" y="$inset" '
        'width="${badge.glyph}" height="${badge.glyph}" '
        'filter="url(#${_tintId(colour)})"/>',
      );
    final wrapped = switch (state) {
      'dimmed' => '<g opacity="$_dimmedOpacity">$inner</g>',
      'deuteranopia' => '<g filter="url(#deuteranopia)">$inner</g>',
      _ => '<g>$inner</g>',
    };
    return '<svg class="badge" width="${size * scale}" height="${size * scale}" '
        'viewBox="0 0 $size $size">$wrapped</svg>';
  }

  return '<div class="cell" data-set="${_esc(set.name)}" '
      'data-key="${_esc(icon.key)}" data-state="$state" '
      'data-bg="${_esc(background)}" style="background:${_esc(background)}">'
      '${draw(1)}${draw(3)}<span class="label">$state</span></div>';
}

const _style =
    '<style>'
    'body{font:13px sans-serif;background:#222;color:#ddd;margin:16px}'
    '.legend,.sets{display:flex;gap:16px;flex-wrap:wrap}'
    '.set{flex:1;min-width:300px}'
    '.cell{display:inline-flex;align-items:center;gap:6px;padding:6px;'
    'margin:2px;color:#fff;text-shadow:0 0 2px #000}'
    '.sw{display:inline-block;width:12px;height:12px;margin-right:4px}'
    '.label{font-size:10px}'
    'ul{list-style:none;padding:0}'
    '</style>';

String _esc(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

void main(List<String> args) {
  exit(runCli(args));
}
