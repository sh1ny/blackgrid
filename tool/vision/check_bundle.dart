// Offline integrity check for a built Windows Release bundle (design D10).
// Runs the steps inventory, bindings, pins, imports, runtimeVersions, notices,
// map-marker-icons and app-icon (the executable carries the committed
// application icon), writes a JSON report and returns non-zero if any step failed.
// It uses no network and never starts the app.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:blackgrid/application/output_path_guard.dart';
import 'package:blackgrid/data/vision/marker_template.dart'
    show markerMetadataPath;

import '../markers/icon_set.dart';
import '../app_icon/ico.dart';
import 'make_marker_template.dart' show footprintFor;
import 'pe.dart';

const defaultInventoryPath = 'tool/vision/bundle_inventory.json';
const defaultLockPath = 'windows/vision/third_party.lock.json';
const defaultNoticesPath = 'THIRD_PARTY_NOTICES.md';
const defaultAllowListPath = 'tool/vision/system_allowlist.json';
const defaultMarkerManifestPath = 'assets/map_markers/manifest.json';
const defaultAppIconPath = 'windows/runner/resources/app_icon.ico';

/// The bundle-relative path of the executable whose icon group is checked.
const appExecutablePath = 'blackgrid.exe';

/// Where the Flutter build places the map marker assets in a bundle.
const bundledMarkerDirectory = 'data/flutter_assets/assets/map_markers';

const helpText =
    '''
Check a built Release bundle offline.

Usage: dart run tool/vision/check_bundle.dart <bundleDir> [options]
  mise run bundle:check -- build/windows/x64/runner/Release

Options:
  --report <path>     write the JSON report here
  --inventory <path>  default $defaultInventoryPath
  --lock <path>       default $defaultLockPath
  --notices <path>    default $defaultNoticesPath
  --allowlist <path>  default $defaultAllowListPath
  --marker-icons <path>  map marker manifest, default $defaultMarkerManifestPath
  --app-icon <path>   application icon, default $defaultAppIconPath

Steps: inventory, bindings, pins, imports, runtimeVersions, notices,
map-marker-icons, app-icon.
Exit codes: 0 all steps passed, 1 a step failed, 2 usage or input error.
''';

class StepResult {
  StepResult(this.name, this.failures, {this.details = const []});
  final String name;
  final List<String> failures;

  /// What a passing step verified, such as the icon sizes; may be empty.
  final List<String> details;
  bool get ok => failures.isEmpty;

  Map<String, Object?> toJson() => {
    'name': name,
    'ok': ok,
    'failures': failures,
    if (details.isNotEmpty) 'details': details,
  };
}

class BundleReport {
  BundleReport(this.bundle, this.steps, this.files);
  final String bundle;
  final List<StepResult> steps;
  final List<Map<String, Object?>> files;
  bool get passed => steps.every((s) => s.ok);

  Map<String, Object?> toJson() => {
    'format': 1,
    'bundle': bundle,
    'result': passed ? 'pass' : 'fail',
    'steps': [for (final s in steps) s.toJson()],
    'files': files,
  };
}

class _Entry {
  _Entry(Map<String, Object?> json)
    : path = json['path']! as String,
      role = json['role']! as String,
      minVersion = json['minVersion'] as String?,
      noticeAnchor = json['noticeAnchor'] as String?;
  final String path;
  final String role;
  final String? minVersion;
  final String? noticeAnchor;
}

/// Inventory role of files derived from game artwork (design D4).
const gameArtwork = 'game-artwork';

/// Sentence a game-artwork notices entry must contain, compared without case.
const gameArtworkStatement =
    "game UI artwork captured by the user, not covered by Blackgrid's licence";

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

/// Hashes are compared as lowercase hex, ignoring surrounding whitespace.
String _norm(String s) => s.trim().toLowerCase();

Object? _readJson(String path, String what) {
  final f = File(path);
  if (!f.existsSync()) throw FormatException('$what not found: $path');
  try {
    return jsonDecode(f.readAsStringSync());
  } on FormatException catch (e) {
    throw FormatException('$what is not valid JSON ($path): ${e.message}');
  }
}

/// Runs every step over [bundleDir]. Throws [FormatException] when the
/// committed inputs (inventory, lock, notices, allow-list) are unreadable.
BundleReport checkBundle({
  required Directory bundleDir,
  String inventoryPath = defaultInventoryPath,
  String lockPath = defaultLockPath,
  String noticesPath = defaultNoticesPath,
  String allowListPath = defaultAllowListPath,
  String markerManifestPath = defaultMarkerManifestPath,
  String appIconPath = defaultAppIconPath,
}) {
  final inventory = _readJson(inventoryPath, 'inventory')! as Map;
  if (inventory['format'] != 1) {
    throw const FormatException('unsupported inventory format');
  }
  final entries = [
    for (final e in inventory['files']! as List)
      _Entry((e as Map).cast<String, Object?>()),
  ];
  final manifestPath = inventory['manifestPath']! as String;
  final sidecarSuffix = inventory['panelSidecarSuffix']! as String;
  final vcAnchor = inventory['vcRuntimeNoticeAnchor']! as String;
  final lock = _readJson(lockPath, 'lock')! as Map;
  final inputs = [
    for (final i in lock['inputs']! as List) (i as Map).cast<String, Object?>(),
  ];
  final noticesFile = File(noticesPath);
  if (!noticesFile.existsSync()) {
    throw FormatException('notices not found: $noticesPath');
  }
  final notices = noticesFile.readAsStringSync();
  final allow = SystemAllowList.load(allowListPath);

  final root = bundleDir.absolute.path;
  File fileOf(String rel) => File('$root/$rel');
  final bytesCache = <String, Uint8List?>{};
  Uint8List? bytesOf(String rel) => bytesCache.putIfAbsent(rel, () {
    final f = fileOf(rel);
    return f.existsSync() ? f.readAsBytesSync() : null;
  });

  final expected = {for (final e in entries) e.path: e};
  final steps = <StepResult>[];

  // Step 1: inventory.
  final inv = <String>[];
  for (final e in entries) {
    if (bytesOf(e.path) == null) {
      inv.add('${e.path} is missing (expected ${e.role} file)');
    }
  }
  final expectedLower = {for (final p in expected.keys) p.toLowerCase()};
  final bundleDlls = <String>{};
  final allFiles = bundleDir.listSync(recursive: true, followLinks: false);
  final prefix = root.replaceAll('\\', '/');
  for (final f in allFiles.whereType<File>()) {
    final rel = f.absolute.path
        .replaceAll('\\', '/')
        .substring(prefix.length + 1);
    final lower = rel.toLowerCase();
    final isDll = lower.endsWith('.dll');
    if (isDll) bundleDlls.add(lower.split('/').last);
    if ((isDll || lower.endsWith('.traineddata')) &&
        !expectedLower.contains(lower)) {
      inv.add('$rel is unexpected');
    }
  }
  steps.add(StepResult('inventory', inv));

  // Step 2: bindings (sidecars and vision manifest). Every library whose role
  // has a '<role>-binding' inventory entry (panel-ocr, capture) is bound to a
  // sha256 sidecar.
  final bind = <String>[];
  final sidecarBound = {
    for (final e in entries)
      if (e.role.endsWith('-binding') && e.role != 'vision-binding')
        e.role.substring(0, e.role.length - '-binding'.length),
  };
  for (final e in entries.where((e) => sidecarBound.contains(e.role))) {
    final dll = bytesOf(e.path);
    final sidecar = bytesOf('${e.path}$sidecarSuffix');
    if (dll == null || sidecar == null) {
      bind.add('${e.path}: library or its sidecar is missing');
      continue;
    }
    final bound = _norm(utf8.decode(sidecar, allowMalformed: true));
    final actual = _sha(dll);
    if (bound != actual) {
      bind.add(
        '${e.path}: sidecar sha256 $bound does not match file sha256 $actual',
      );
    }
  }
  final manifestBytes = bytesOf(manifestPath);
  final manifested = <String>{};
  if (manifestBytes == null) {
    bind.add('$manifestPath is missing');
  } else {
    try {
      final m = jsonDecode(utf8.decode(manifestBytes)) as Map;
      if (m['format'] != 1) bind.add('$manifestPath: unsupported format');
      if (m['abi'] is! int) bind.add('$manifestPath: abi is not an integer');
      final tess = inputs.where(
        (i) => i['engineVersion'] != null && i['bundlePath'] != null,
      );
      for (final t in tess) {
        if (m['engineVersion'] != t['engineVersion']) {
          bind.add(
            '$manifestPath: engineVersion ${m['engineVersion']} differs from '
            'lock ${t['engineVersion']} (${t['id']})',
          );
        }
      }
      for (final f in m['files'] as List) {
        final fm = (f as Map).cast<String, Object?>();
        final rel = fm['path'] as String;
        manifested.add(rel.toLowerCase());
        final data = bytesOf(rel);
        if (data == null) {
          bind.add('$rel: listed in manifest but missing from the bundle');
          continue;
        }
        final want = _norm(fm['sha256'] as String);
        final got = _sha(data);
        if (want != got) {
          bind.add(
            '$rel: manifest sha256 $want does not match file sha256 $got',
          );
        }
        if (fm['size'] != data.length) {
          bind.add(
            '$rel: manifest size ${fm['size']} does not match file size '
            '${data.length}',
          );
        }
      }
    } on Object catch (e) {
      bind.add('$manifestPath is unreadable: $e');
    }
  }
  for (final e in entries.where(
    (e) => e.role == 'vision' || e.role == 'model' || e.role == gameArtwork,
  )) {
    if (manifestBytes != null && !manifested.contains(e.path.toLowerCase())) {
      bind.add('${e.path}: not listed in $manifestPath');
    }
  }
  steps.add(StepResult('bindings', bind));

  // Step 3: pins.
  final pins = <String>[];
  for (final i in inputs.where((i) => i['bundlePath'] != null)) {
    final rel = i['bundlePath']! as String;
    final data = bytesOf(rel);
    if (data == null) {
      pins.add('$rel (${i['id']}) is missing; cannot compare with its pin');
      continue;
    }
    final want = _norm(i['sha256']! as String);
    final got = _sha(data);
    if (want != got) {
      pins.add(
        '$rel diverges from its pinned source (${i['id']}): lock sha256 '
        '$want, file sha256 $got',
      );
    }
  }
  steps.add(StepResult('pins', pins));

  // Step 4: imports.
  final imports = <String>[];
  final peFiles = <String, Uint8List>{};
  for (final e in entries) {
    final data = bytesOf(e.path);
    if (data == null) continue;
    if (e.path.toLowerCase().endsWith('.dll') ||
        e.path.toLowerCase().endsWith('.exe')) {
      peFiles[e.path] = data;
    }
  }
  for (final f in allFiles.whereType<File>()) {
    final rel = f.absolute.path
        .replaceAll('\\', '/')
        .substring(prefix.length + 1);
    if (rel.toLowerCase().endsWith('.dll') && !peFiles.containsKey(rel)) {
      final data = bytesOf(rel);
      if (data != null) peFiles[rel] = data;
    }
  }
  final importResult = checkImports(
    files: peFiles,
    bundleDllNames: bundleDlls,
    allow: allow,
  );
  imports.addAll(importResult.failures.map((f) => f.toString()));
  steps.add(StepResult('imports', imports));

  // Step 5: runtime versions.
  final minimums = {
    for (final e in entries)
      if (e.minVersion != null) e.path: e.minVersion!,
  };
  final vcFiles = {
    for (final p in minimums.keys)
      if (bytesOf(p) != null) p: bytesOf(p)!,
  };
  final versionResult = checkRuntimeVersions(
    files: vcFiles,
    minimumVersions: minimums,
  );
  steps.add(
    StepResult(
      'runtimeVersions',
      versionResult.failures.map((f) => f.toString()).toList(),
    ),
  );

  // Step 6: notices.
  final noteFailures = <String>[];
  final byId = {for (final i in inputs) i['id']! as String: i};
  for (final i in inputs) {
    final id = i['id']! as String;
    final anchor = i['noticeAnchor'] as String?;
    if (anchor == null) {
      noteFailures.add('$id: lock entry has no noticeAnchor');
      continue;
    }
    final section = _noticeSection(notices, anchor);
    if (section == null) {
      noteFailures.add('$id: no notices entry with anchor "$anchor"');
      continue;
    }
    final version = i['version'] as String?;
    if (version != null && !section.contains(version)) {
      noteFailures.add('$id: notices entry "$anchor" lacks version $version');
    }
    final url =
        (i['authoritativeUrl'] ?? byId[i['extractFrom']]?['authoritativeUrl'])
            as String?;
    if (url != null && !section.contains(url)) {
      noteFailures.add('$id: notices entry "$anchor" lacks url $url');
    }
    final sha = _norm(i['sha256']! as String);
    if (!section.toLowerCase().contains(sha)) {
      noteFailures.add(
        '$id: notices entry "$anchor" lacks sha256 $sha (stale or missing)',
      );
    }
  }
  final vcSection = _noticeSection(notices, vcAnchor);
  if (vcSection == null) {
    noteFailures.add(
      'Visual C++ runtime: no notices entry with anchor "$vcAnchor"',
    );
  } else {
    if (!vcSection.contains('Distributable Code')) {
      noteFailures.add(
        'Visual C++ runtime: notices entry does not name the Distributable '
        'Code terms',
      );
    }
    for (final e in entries.where((e) => e.role == 'vcruntime')) {
      if (!vcSection.contains(e.path)) {
        noteFailures.add(
          'Visual C++ runtime: notices entry does not name ${e.path}',
        );
      }
    }
  }
  noteFailures.addAll(
    gameArtworkNoticeFailures(
      [
        for (final e in entries)
          if (e.role == gameArtwork)
            (path: e.path, noticeAnchor: e.noticeAnchor),
      ],
      notices,
      bytesOf,
    ),
  );
  final markerMeta = bytesOf(markerMetadataPath);
  if (markerMeta != null) {
    noteFailures.addAll(markerProvenanceFailures(markerMeta));
  }
  steps.add(StepResult('notices', noteFailures));

  // Step 7: bundled map marker icons (design D5).
  steps.add(
    StepResult(
      'map-marker-icons',
      markerIconFailures(markerManifestPath, bundleDir),
    ),
  );

  // Step 8: the executable carries the committed application icon (design D5).
  steps.add(appIconStep(bytesOf(appExecutablePath), appIconPath));

  final files = <Map<String, Object?>>[
    for (final e in entries)
      if (bytesOf(e.path) != null)
        {
          'path': e.path,
          'role': e.role,
          'sha256': _sha(bytesOf(e.path)!),
          'size': bytesOf(e.path)!.length,
          if (versionResult.versions[e.path] != null)
            'version': versionResult.versions[e.path],
        },
  ];
  return BundleReport(root, steps, files);
}

/// An icon image key: width, height and bit depth.
typedef _IconKey = (int, int, int);

String _keyLabel(_IconKey k) => '${k.$1}x${k.$2} ${k.$3}-bit';

int _compareKeys(_IconKey a, _IconKey b) {
  final w = a.$1.compareTo(b.$1);
  if (w != 0) return w;
  final h = a.$2.compareTo(b.$2);
  return h != 0 ? h : a.$3.compareTo(b.$3);
}

Map<_IconKey, List<Uint8List>> _indexIcons(
  Iterable<(int, int, int, Uint8List)> images,
) {
  final out = <_IconKey, List<Uint8List>>{};
  for (final (w, h, bpp, bytes) in images) {
    out.putIfAbsent((w, h, bpp), () => []).add(bytes);
  }
  return out;
}

/// Failures for keys that occur more than once in [keys], on [side].
List<String> _duplicateIconFailures(
  String side,
  Map<_IconKey, List<Uint8List>> keys,
) {
  final sizes = <(int, int), int>{};
  for (final MapEntry(key: k, value: v) in keys.entries) {
    sizes.update((k.$1, k.$2), (n) => n + v.length, ifAbsent: () => v.length);
  }
  final repeated = [
    for (final MapEntry(key: s, value: n) in sizes.entries)
      if (n > 1) s,
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [
    if (repeated.isNotEmpty)
      'duplicate sizes in the $side: '
          '${repeated.map((s) => s.$1 == s.$2 ? '${s.$1}' : '${s.$1}x${s.$2}').join(', ')}',
    for (final k in keys.keys.toList()..sort(_compareKeys))
      if (keys[k]!.length > 1)
        '$side icon ${_keyLabel(k)} appears more than once',
  ];
}

/// The `app-icon` step: compares the icon group of [exe] (the bundle's
/// `blackgrid.exe` bytes, or null when missing) with the `.ico` at
/// [icoPath].
///
/// Images are keyed by (width, height, bit depth), a stored 0 reading as 256.
/// The step fails for a key present twice on one side, a key present on one
/// side only, unequal bytes for a key, and an unreadable group or `.ico`. It
/// never throws. A pass lists the sizes in [StepResult.details].
StepResult appIconStep(Uint8List? exe, String icoPath) {
  const name = 'app-icon';
  const icoLabel = 'app_icon.ico';
  if (exe == null) {
    return StepResult(name, ['$appExecutablePath is missing']);
  }
  final List<PeIconImage> embedded;
  switch (readIconGroup(exe)) {
    case IconGroupReadable(:final images):
      embedded = images;
    case IconGroupUnreadable(:final reason):
      return StepResult(name, ['executable icon group is unreadable: $reason']);
  }
  final List<IcoImage> committed;
  try {
    final file = File(icoPath);
    final parsed = file.existsSync()
        ? parseIco(file.readAsBytesSync())
        : const IcoUnreadable('file not found');
    switch (parsed) {
      case IcoParsed(:final images):
        committed = images;
      case IcoUnreadable(:final reason):
        return StepResult(name, ['$icoLabel is unreadable: $reason']);
    }
  } on FileSystemException catch (e) {
    return StepResult(name, ['$icoLabel is unreadable: ${e.message}']);
  }

  final exeKeys = _indexIcons([
    for (final i in embedded) (i.width, i.height, i.bitCount, i.bytes),
  ]);
  final icoKeys = _indexIcons([
    for (final i in committed) (i.width, i.height, i.bitCount, i.bytes),
  ]);
  final failures = [
    ..._duplicateIconFailures('executable', exeKeys),
    ..._duplicateIconFailures(icoLabel, icoKeys),
  ];
  final allKeys = {...exeKeys.keys, ...icoKeys.keys}.toList()
    ..sort(_compareKeys);
  for (final k in allKeys) {
    final a = exeKeys[k];
    final b = icoKeys[k];
    if (a == null) {
      failures.add('${_keyLabel(k)} is missing from the executable');
    } else if (b == null) {
      failures.add('${_keyLabel(k)} is missing from $icoLabel');
    } else if (a.length == 1 &&
        b.length == 1 &&
        !_sameBytes(a.single, b.single)) {
      failures.add(
        '${_keyLabel(k)} differs between the executable and $icoLabel',
      );
    }
  }
  return StepResult(
    name,
    failures,
    details: [
      if (failures.isEmpty)
        for (final k in allKeys) _keyLabel(k),
    ],
  );
}

/// Failures of the bundled map marker icons.
///
/// The repository set at [markerManifestPath] must pass the set check as a
/// release set; otherwise its failures are the only ones reported. The
/// bundle's `assets/map_markers/` must then hold the same manifest bytes and
/// one compiled file per icon, each equal to compiling the icon's checked
/// SVG, and nothing else. Each icon is compiled once.
List<String> markerIconFailures(
  String markerManifestPath,
  Directory bundleDir,
) {
  final compiled = <(String, String), Uint8List>{};
  Uint8List compile(String xml, String name) =>
      compiled.putIfAbsent((name, xml), () => compileIconSvg(xml, name));

  final IconSet set;
  switch (checkIconSet(markerManifestPath, compile: compile)) {
    case IconSetInvalid(:final failures):
      return [for (final f in failures) formatFailure(f)];
    case IconSetValid(set: final valid)
        when valid.scope != IconSetScope.release:
      return ['$markerManifestPath: scope must be release for a bundle'];
    case IconSetValid(set: final valid):
      set = valid;
  }

  final root = bundleDir.absolute.path.replaceAll(r'\', '/');
  final markerDir = Directory('$root/$bundledMarkerDirectory');
  if (!markerDir.existsSync()) return ['$bundledMarkerDirectory is missing'];

  final failures = <String>[];
  final expected = <String>{'manifest.json', 'compiled'};
  final manifest = '$bundledMarkerDirectory/manifest.json';
  final bundledManifest = File('${markerDir.path}/manifest.json');
  if (!bundledManifest.existsSync()) {
    failures.add('$manifest is missing');
  } else if (!_sameBytes(
    bundledManifest.readAsBytesSync(),
    File(markerManifestPath).readAsBytesSync(),
  )) {
    failures.add('$manifest differs from the repository manifest');
  }
  for (final icon in set.icons) {
    final name =
        'compiled/${icon.file.replaceFirst(RegExp(r'\.svg$'), '.vec')}';
    expected.add(name);
    final path = '$bundledMarkerDirectory/$name';
    final file = File('${markerDir.path}/$name');
    if (!file.existsSync()) {
      failures.add('$path is missing');
    } else if (!_sameBytes(
      file.readAsBytesSync(),
      compile(icon.svg, icon.file),
    )) {
      failures.add('$path differs from compiling ${icon.file}');
    }
  }
  final prefix = markerDir.path.replaceAll(r'\', '/').length + 1;
  for (final entity in markerDir.listSync(
    recursive: true,
    followLinks: false,
  )) {
    final rel = entity.path.replaceAll(r'\', '/').substring(prefix);
    if (!expected.contains(rel)) {
      failures.add('$bundledMarkerDirectory/$rel is unexpected');
    }
  }
  return failures;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Failures of the marker template's provenance in its metadata [bytes]: the
/// source screenshot SHA-256 (64 hex digits), the source client size, and a
/// footprint and origin consistent with that size, as the regeneration tool
/// records them. Missing bytes are the inventory step's failure, not this.
List<String> markerProvenanceFailures(Uint8List bytes) {
  const where = markerMetadataPath;
  final Object? meta;
  try {
    meta = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return ['$where: metadata is not valid JSON'];
  }
  if (meta is! Map) return ['$where: metadata is not an object'];
  final failures = <String>[];
  final sha = meta['sourceSha256'];
  if (sha is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) {
    failures.add('$where: sourceSha256 is not a 64-digit hex SHA-256');
  }
  final (width, height) = (meta['sourceWidth'], meta['sourceHeight']);
  if (width is! int || height is! int || width <= 0 || height <= 0) {
    failures.add('$where: sourceWidth and sourceHeight must be positive');
    return failures;
  }
  // The regeneration tool refuses any source below 1080p scale (s < 1).
  if (width < 1920 || height < 1080) {
    failures.add(
      '$where: source ${width}x$height is below 1080p scale, which the '
      'regeneration tool refuses',
    );
    return failures;
  }
  // No display is this large; the bound keeps the footprint arithmetic exact.
  const maxSource = 1 << 16;
  if (width > maxSource || height > maxSource) {
    failures.add(
      '$where: source ${width}x$height exceeds the maximum of $maxSource',
    );
    return failures;
  }
  final footprint = meta['footprint'];
  final expected = footprintFor(width, height);
  if (footprint != expected) {
    failures.add(
      '$where: footprint $footprint does not match ${width}x$height '
      '(expected $expected)',
    );
    return failures;
  }
  final origin = meta['origin'];
  final (x, y) = origin is Map ? (origin['x'], origin['y']) : (null, null);
  if (x is! int ||
      y is! int ||
      x < 0 ||
      y < 0 ||
      // Subtracted, not added, so a huge origin cannot wrap past the bound.
      x > width - expected ||
      y > height - expected) {
    failures.add(
      '$where: origin must place the ${expected}px footprint inside '
      '${width}x$height',
    );
  }
  return failures;
}

/// A game-artwork file as the notices check sees it: its bundle path and the
/// inventory `noticeAnchor` of its notices entry.
typedef GameArtworkEntry = ({String path, String? noticeAnchor});

/// Failures of the game-artwork notices check: each game-artwork file needs a
/// notices entry (found by its inventory `noticeAnchor`) that names the file,
/// its current SHA-256, the source screenshot SHA-256 and the recipe recorded
/// in that artwork's own metadata, and states the artwork's rights status.
///
/// An artwork's metadata is the `.json` file with the same stem, so
/// `marker.gray` and `marker.json` share `marker.json`'s provenance. Paths,
/// hashes, recipes and the statement are compared without case.
List<String> gameArtworkNoticeFailures(
  Iterable<GameArtworkEntry> artwork,
  String notices,
  Uint8List? Function(String rel) bytesOf,
) {
  final failures = <String>[];
  String stem(String path) {
    final dot = path.lastIndexOf('.');
    return dot > path.lastIndexOf('/') ? path.substring(0, dot) : path;
  }

  // Provenance per artwork stem, from that artwork's own metadata file.
  final provenance = <String, ({String? sourceSha, String? recipe})>{};
  for (final e in artwork.where((e) => e.path.endsWith('.json'))) {
    final data = bytesOf(e.path);
    if (data == null) continue;
    try {
      final meta = jsonDecode(utf8.decode(data));
      if (meta is Map) {
        // A field of another type is reported here and then counts as absent.
        String? text(String name) => switch (meta[name]) {
          null => null,
          final String value => value.trim(),
          _ => () {
            failures.add('${e.path}: metadata $name is not a string');
            return null;
          }(),
        };
        provenance[stem(e.path)] = (
          sourceSha: text('sourceSha256')?.toLowerCase(),
          recipe: text('recipe'),
        );
      }
    } on FormatException {
      failures.add('${e.path}: metadata is not valid JSON');
    }
  }
  for (final e in artwork) {
    final anchor = e.noticeAnchor;
    if (anchor == null) {
      failures.add('${e.path}: inventory entry has no noticeAnchor');
      continue;
    }
    final section = _noticeSection(notices, anchor);
    if (section == null) {
      failures.add('${e.path}: no notices entry with anchor "$anchor"');
      continue;
    }
    final lower = section.toLowerCase();
    if (!lower.contains(e.path.toLowerCase())) {
      failures.add('${e.path}: notices entry "$anchor" does not name the file');
    }
    final data = bytesOf(e.path);
    if (data == null) {
      failures.add('${e.path}: file bytes unavailable, sha256 not verified');
    } else {
      final sha = _sha(data);
      if (!lower.contains(sha)) {
        failures.add(
          '${e.path}: notices entry "$anchor" lacks sha256 $sha '
          '(stale or missing)',
        );
      }
    }
    final own = provenance[stem(e.path)];
    final sourceSha = own?.sourceSha;
    final recipe = own?.recipe;
    if (sourceSha == null || sourceSha.isEmpty) {
      failures.add('${e.path}: metadata has no sourceSha256');
    } else if (!lower.contains(sourceSha)) {
      failures.add(
        '${e.path}: notices entry "$anchor" lacks source screenshot sha256 '
        '$sourceSha (stale or missing)',
      );
    }
    if (recipe == null || recipe.isEmpty) {
      failures.add('${e.path}: metadata has no recipe');
    } else if (!lower.contains(recipe.toLowerCase())) {
      failures.add('${e.path}: notices entry "$anchor" lacks recipe $recipe');
    }
    if (!lower.contains(gameArtworkStatement.toLowerCase())) {
      failures.add(
        '${e.path}: notices entry "$anchor" lacks the statement "'
        '$gameArtworkStatement"',
      );
    }
  }
  return failures;
}

/// Text from the `<a id="anchor">` line up to the next anchor or `## `
/// heading, or null when the anchor does not exist.
String? _noticeSection(String notices, String anchor) {
  final marker = '<a id="$anchor"></a>';
  final start = notices.indexOf(marker);
  if (start < 0) return null;
  final rest = notices.substring(start + marker.length);
  final end = RegExp(r'^(<a id="|## )', multiLine: true).firstMatch(rest);
  return end == null ? rest : rest.substring(0, end.start);
}

Future<int> runCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  String? bundle;
  String? report;
  var inventory = defaultInventoryPath;
  var lock = defaultLockPath;
  var notices = defaultNoticesPath;
  var allow = defaultAllowListPath;
  var markerIcons = defaultMarkerManifestPath;
  var appIcon = defaultAppIconPath;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String value() {
      if (i + 1 >= args.length) throw FormatException('$a needs a value');
      return args[++i];
    }

    try {
      switch (a) {
        case '--help' || '-h':
          stdoutSink.writeln(helpText);
          return 0;
        case '--report':
          report = value();
        case '--inventory':
          inventory = value();
        case '--lock':
          lock = value();
        case '--notices':
          notices = value();
        case '--allowlist':
          allow = value();
        case '--marker-icons':
          markerIcons = value();
        case '--app-icon':
          appIcon = value();
        default:
          if (a.startsWith('--') || bundle != null) {
            throw FormatException('unexpected argument $a');
          }
          bundle = a;
      }
    } on FormatException catch (e) {
      stderrSink.writeln('error: ${e.message}\n$helpText');
      return 2;
    }
  }
  if (bundle == null) {
    stderrSink.writeln('error: bundle directory required\n$helpText');
    return 2;
  }
  final dir = Directory(bundle);
  if (!dir.existsSync()) {
    stderrSink.writeln('error: bundle directory does not exist: $bundle');
    return 2;
  }
  final BundleReport result;
  try {
    result = checkBundle(
      bundleDir: dir,
      inventoryPath: inventory,
      lockPath: lock,
      noticesPath: notices,
      allowListPath: allow,
      markerManifestPath: markerIcons,
      appIconPath: appIcon,
    );
  } on FormatException catch (e) {
    stderrSink.writeln('error: ${e.message}');
    return 2;
  } on FileSystemException catch (e) {
    stderrSink.writeln('error: ${e.message} ${e.path ?? ''}');
    return 2;
  }
  for (final s in result.steps) {
    stdoutSink.writeln('${s.ok ? 'PASS' : 'FAIL'} ${s.name}');
    for (final f in s.failures) {
      stdoutSink.writeln('  - $f');
    }
    if (s.ok && s.details.isNotEmpty) {
      stdoutSink.writeln('  ${s.details.join(', ')}');
    }
  }
  if (report != null) {
    // The check is read-only over the bundle and its committed inputs.
    final unsafe = unsafeOutputReason(
      report,
      protectedFiles: [inventory, lock, notices, allow, markerIcons, appIcon],
      protectedDirectories: [dir.path],
    );
    if (unsafe != null) {
      stderrSink.writeln('error: refusing report path: $unsafe');
      return 2;
    }
    final json = const JsonEncoder.withIndent('  ').convert(result.toJson());
    writeViaTemp(report, '$json\n');
  }
  stdoutSink.writeln(
    result.passed ? 'bundle check: all steps passed' : 'bundle check: FAILED',
  );
  return result.passed ? 0 : 1;
}

Future<void> main(List<String> args) async {
  exit(await runCli(args));
}
