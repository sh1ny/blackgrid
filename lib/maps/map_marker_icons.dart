import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:vector_graphics/vector_graphics.dart' as vg;

const _manifestPath = 'assets/map_markers/manifest.json';
const _compiledDirectory = 'assets/map_markers/compiled';
const _rasterSize = 64;

const _gold = ui.Color(0xFFDCC05A);
const _exitGreen = ui.Color(0xFF48D28B);
const _dangerRed = ui.Color(0xFFFF5252);
const _pinBlue = ui.Color(0xFF40C4FF);
const _highlightCyan = ui.Color(0xFF18FFFF);
const _defaultBackground = ui.Color(0xFF090F0D);

/// The opacity of a dimmed badge.
const dimmedMarkerOpacity = 0.22;

/// The sizes of a marker badge, in logical pixels.
final class MarkerBadgeGeometry {
  /// Creates a badge geometry.
  const MarkerBadgeGeometry({
    required this.diameter,
    required this.selectedDiameter,
    required this.glyph,
    required this.ring,
  });

  /// The geometry used until a manifest loads: 24, 30, 16 and 2.
  static const standard = MarkerBadgeGeometry(
    diameter: 24,
    selectedDiameter: 30,
    glyph: 16,
    ring: 2,
  );

  /// The diameter of a normal badge.
  final double diameter;

  /// The diameter of a selected or highlighted badge.
  final double selectedDiameter;

  /// The side of the square the glyph is drawn into.
  final double glyph;

  /// The ring stroke width.
  final double ring;
}

/// The look of one marker category: its role colour and, once decoded, its
/// rasterized glyph.
final class MarkerIcon {
  /// Creates a marker icon.
  const MarkerIcon({required this.colour, this.glyph});

  /// The role colour from the manifest.
  final ui.Color colour;

  /// The 64 × 64 px white glyph, or `null` when it failed to decode.
  ///
  /// The loader owns the image; callers must not dispose it.
  final ui.Image? glyph;
}

/// The fallback colour of [filterKey] used before a manifest is loaded.
///
/// Extract keys are green, hazard keys red, `CustomPins` light blue and every
/// other key gold.
ui.Color markerFallbackColour(String filterKey) => switch (filterKey) {
  'PmcExtracts' || 'ScavExtracts' || 'SharedExtracts' => _exitGreen,
  'Hazards' || 'HazardZones' => _dangerRed,
  'CustomPins' => _pinBlue,
  _ => _gold,
};

/// Resolves the colour, diameter and opacity of one marker badge.
///
/// Highlight wins over [role], which wins over gold. A selected or
/// highlighted badge uses [MarkerBadgeGeometry.selectedDiameter]. A dimmed
/// badge is drawn at [dimmedMarkerOpacity] on top of any other state.
({ui.Color colour, double diameter, double opacity}) markerBadgeStyle({
  required ui.Color? role,
  required bool selected,
  required bool highlighted,
  required bool dimmed,
  required MarkerBadgeGeometry geometry,
}) => (
  colour: highlighted ? _highlightCyan : (role ?? _gold),
  diameter: selected || highlighted
      ? geometry.selectedDiameter
      : geometry.diameter,
  opacity: dimmed ? dimmedMarkerOpacity : 1,
);

/// Loads the bundled marker icon set and serves it to the map painter.
///
/// Until [open] completes, and for every key the manifest or a decode
/// failure leaves out, callers draw a fallback badge. The loader never
/// throws from [open] and notifies its listeners once, when loading ends.
class MapMarkerIcons extends ChangeNotifier {
  /// Creates a loader that reads assets with [load], by default
  /// [rootBundle].
  MapMarkerIcons({Future<ByteData> Function(String assetPath)? load})
    : _load = load ?? rootBundle.load,
      _enabled = true;

  /// Creates a loader that never loads and always reports the fallback.
  MapMarkerIcons.disabled() : _load = _refuseLoad, _enabled = false;

  static Future<ByteData> _refuseLoad(String assetPath) =>
      Future.error(StateError('Marker icons are disabled: $assetPath'));

  final Future<ByteData> Function(String assetPath) _load;
  final bool _enabled;
  Future<void>? _opening;
  bool _disposed = false;
  _Manifest? _manifest;
  Map<String, ui.Image> _glyphs = const {};
  int _liveImages = 0;
  final _failures = <String>[];

  /// The failures recorded by [open], one line each.
  List<String> get failures => List.unmodifiable(_failures);

  /// The number of rasterized images this loader has not disposed yet.
  @visibleForTesting
  int get debugLiveImageCount => _liveImages;

  /// The badge geometry from the manifest, or the default until it loads.
  MarkerBadgeGeometry get geometry =>
      _manifest?.geometry ?? MarkerBadgeGeometry.standard;

  /// The badge disc colour from the manifest, or the default until it loads.
  ui.Color get background => _manifest?.background ?? _defaultBackground;

  /// The icon of [filterKey], or `null` when the manifest has no entry for it
  /// or has not loaded.
  MarkerIcon? icon(String filterKey) {
    final colour = _manifest?.roleColours[filterKey];
    if (colour == null) return null;
    return MarkerIcon(colour: colour, glyph: _glyphs[filterKey]);
  }

  /// The colour of [filterKey] for a fallback badge: its manifest role colour
  /// when known, otherwise [markerFallbackColour].
  ui.Color colourFor(String filterKey) =>
      icon(filterKey)?.colour ?? markerFallbackColour(filterKey);

  /// Loads the manifest and every icon once.
  ///
  /// A second call returns the first call's future. Every failure is caught,
  /// recorded in [failures] and logged, so the future always completes
  /// normally.
  Future<void> open() => _opening ??= _open();

  Future<void> _open() async {
    if (!_enabled) return;
    switch (await _readManifest()) {
      case _ManifestFailed(:final reason):
        if (_disposed) return;
        _fail('Map marker icons unavailable: $reason');
        notifyListeners();
      case _ManifestRead(:final manifest):
        final images = await _decodeGlyphs(manifest);
        if (_disposed) {
          images.values.forEach(_discard);
          return;
        }
        _manifest = manifest;
        _glyphs = images;
        notifyListeners();
    }
  }

  Future<_ManifestResult> _readManifest() async {
    try {
      final data = await _load(_manifestPath);
      if (_disposed) return const _ManifestFailed('disposed');
      return _parseManifest(data);
    } catch (error) {
      return _ManifestFailed('$_manifestPath: $error');
    }
  }

  Future<Map<String, ui.Image>> _decodeGlyphs(_Manifest manifest) async {
    final images = <String, ui.Image>{};
    for (final entry in manifest.icons) {
      if (_disposed) break;
      try {
        final data = await _load('$_compiledDirectory/${entry.stem}.vec');
        if (_disposed) break;
        final info = await vg.vg.loadPicture(
          _PreparedVectorBytes(entry.file, data),
          null,
          clipViewbox: false,
          onError: (error, stack) =>
              Error.throwWithStackTrace(error, stack ?? StackTrace.current),
        );
        try {
          if (_disposed) break;
          images[entry.key] = _rasterize(info.picture, info.size);
        } finally {
          info.picture.dispose();
        }
      } catch (error) {
        if (_disposed) break;
        _fail('Map marker icon ${entry.file} failed: $error');
      }
    }
    return images;
  }

  ui.Image _rasterize(ui.Picture picture, ui.Size size) {
    if (size.isEmpty) throw const FormatException('empty picture');
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(_rasterSize / size.width, _rasterSize / size.height)
      ..drawPicture(picture);
    final scaled = recorder.endRecording();
    try {
      final image = scaled.toImageSync(_rasterSize, _rasterSize);
      _liveImages++;
      return image;
    } finally {
      scaled.dispose();
    }
  }

  void _discard(ui.Image image) {
    image.dispose();
    _liveImages--;
  }

  void _fail(String message) {
    _failures.add(message);
    debugPrint(message);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _glyphs.values.forEach(_discard);
    _glyphs = const {};
    super.dispose();
  }
}

class _PreparedVectorBytes extends vg.BytesLoader {
  const _PreparedVectorBytes(this.name, this.bytes);
  final String name;
  final ByteData bytes;
  @override
  Future<ByteData> loadBytes(BuildContext? context) async => bytes;
  @override
  String toString() => 'MarkerIconBytes($name)';
}

final class _IconEntry {
  const _IconEntry(this.key, this.file, this.stem);
  final String key;
  final String file;
  final String stem;
}

final class _Manifest {
  const _Manifest({
    required this.background,
    required this.geometry,
    required this.roleColours,
    required this.icons,
  });
  final ui.Color background;
  final MarkerBadgeGeometry geometry;

  /// The role colour per filter key.
  final Map<String, ui.Color> roleColours;
  final List<_IconEntry> icons;
}

sealed class _ManifestResult {
  const _ManifestResult();
}

final class _ManifestRead extends _ManifestResult {
  const _ManifestRead(this.manifest);
  final _Manifest manifest;
}

final class _ManifestFailed extends _ManifestResult {
  const _ManifestFailed(this.reason);
  final String reason;
}

final _hexColour = RegExp(r'^#[0-9A-Fa-f]{6}$');

ui.Color? _colour(Object? value) => switch (value) {
  final String s when _hexColour.hasMatch(s) => ui.Color(
    0xFF000000 | int.parse(s.substring(1), radix: 16),
  ),
  _ => null,
};

_ManifestResult _parseManifest(ByteData data) {
  _ManifestFailed bad(String why) => _ManifestFailed('$_manifestPath: $why');
  final Object? json;
  try {
    json = jsonDecode(
      utf8.decode(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
    );
  } on FormatException catch (e) {
    return bad('not valid JSON: ${e.message}');
  }
  if (json is! Map<String, Object?>) return bad('not a JSON object');
  if (json['schemaVersion'] != 1) {
    return bad('schemaVersion must be 1, found ${json['schemaVersion']}');
  }
  final background = _colour(json['background']);
  if (background == null) return bad('background must be #RRGGBB');

  final MarkerBadgeGeometry geometry;
  switch (json['badge']) {
    case {
          'diameter': final int diameter,
          'selectedDiameter': final int selected,
          'glyph': final int glyph,
          'ring': final int ring,
        }
        when diameter > 0 && selected > 0 && glyph > 0 && ring > 0:
      geometry = MarkerBadgeGeometry(
        diameter: diameter.toDouble(),
        selectedDiameter: selected.toDouble(),
        glyph: glyph.toDouble(),
        ring: ring.toDouble(),
      );
    default:
      return bad('badge must hold four positive integers');
  }

  final roles = <String, ui.Color>{};
  if (json['roles'] case final Map<String, Object?> raw) {
    for (final MapEntry(:key, :value) in raw.entries) {
      final colour = _colour(value);
      if (colour == null) return bad('role "$key" must be #RRGGBB');
      roles[key] = colour;
    }
  } else {
    return bad('roles must be an object');
  }

  final colours = <String, ui.Color>{};
  final icons = <_IconEntry>[];
  if (json['icons'] case final List<Object?> raw) {
    for (final item in raw) {
      switch (item) {
        case {
              'key': final String key,
              'file': final String file,
              'role': final String role,
            }
            when file.endsWith('.svg') && roles.containsKey(role):
          if (colours.containsKey(key)) return bad('duplicate icon "$key"');
          colours[key] = roles[role]!;
          icons.add(_IconEntry(key, file, file.substring(0, file.length - 4)));
        default:
          return bad('invalid icon entry: $item');
      }
    }
  } else {
    return bad('icons must be a list');
  }

  return _ManifestRead(
    _Manifest(
      background: background,
      geometry: geometry,
      roleColours: Map.unmodifiable(colours),
      icons: List.unmodifiable(icons),
    ),
  );
}
