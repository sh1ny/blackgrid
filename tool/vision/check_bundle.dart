// Offline integrity check for a built Windows Release bundle (design D10).
// Runs the steps inventory, bindings, pins, imports, runtimeVersions and
// notices, writes a JSON report and returns non-zero if any step failed.
// It uses no network and never starts the app.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:blackgrid/application/output_path_guard.dart';

import 'pe.dart';

const defaultInventoryPath = 'tool/vision/bundle_inventory.json';
const defaultLockPath = 'windows/vision/third_party.lock.json';
const defaultNoticesPath = 'THIRD_PARTY_NOTICES.md';
const defaultAllowListPath = 'tool/vision/system_allowlist.json';

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

Steps: inventory, bindings, pins, imports, runtimeVersions, notices.
Exit codes: 0 all steps passed, 1 a step failed, 2 usage or input error.
''';

class StepResult {
  StepResult(this.name, this.failures);
  final String name;
  final List<String> failures;
  bool get ok => failures.isEmpty;

  Map<String, Object?> toJson() => {
    'name': name,
    'ok': ok,
    'failures': failures,
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
      minVersion = json['minVersion'] as String?;
  final String path;
  final String role;
  final String? minVersion;
}

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

  // Step 2: bindings (panel sidecar and vision manifest).
  final bind = <String>[];
  for (final e in entries.where((e) => e.role == 'panel-ocr')) {
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
    (e) => e.role == 'vision' || e.role == 'model',
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
  steps.add(StepResult('notices', noteFailures));

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
  }
  if (report != null) {
    // The check is read-only over the bundle and its committed inputs.
    final unsafe = unsafeOutputReason(
      report,
      protectedFiles: [inventory, lock, notices, allow],
      protectedDirectories: [dir.path],
    );
    if (unsafe != null) {
      stderrSink.writeln('error: refusing report path: $unsafe');
      return 2;
    }
    final json = const JsonEncoder.withIndent('  ').convert(result.toJson());
    final tmp = File('$report.tmp')..writeAsStringSync('$json\n');
    tmp.renameSync(report);
  }
  stdoutSink.writeln(
    result.passed ? 'bundle check: all steps passed' : 'bundle check: FAILED',
  );
  return result.passed ? 0 : 1;
}

Future<void> main(List<String> args) async {
  exit(await runCli(args));
}
