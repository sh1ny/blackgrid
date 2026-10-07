import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/vision/check_bundle.dart';
import '../../support/pe_builder.dart';

const _opencvUrl = 'https://example.test/opencv-4.13.0.zip';
const _nupkgUrl = 'https://example.test/Tesseract/5.2.0';
const _modelUrl = 'https://example.test/eng.traineddata';

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

/// A synthetic bundle plus the lock and notices that describe it.
class _Fixture {
  _Fixture() : root = Directory.systemTemp.createTempSync('bundle_check_') {
    bundle = Directory('${root.path}/bundle')..createSync();
    final vcVersion = [14, 51, 36247, 0];
    write('blackgrid.exe', _pe(['KERNEL32.dll', 'MSVCP140.dll']));
    write('flutter_windows.dll', _pe(['KERNEL32.dll']));
    write('sqlite3.dll', _pe(['KERNEL32.dll']));
    write('blackgrid_panel_ocr.dll', _pe(['KERNEL32.dll', 'VCRUNTIME140.dll']));
    write(
      'blackgrid_vision.dll',
      _pe(['KERNEL32.dll', 'api-ms-win-crt-runtime-l1-1-0.dll']),
    );
    write(
      'tesseract50.dll',
      _pe(['KERNEL32.dll', 'leptonica-1.82.0.dll', 'VCRUNTIME140_1.dll']),
    );
    write('leptonica-1.82.0.dll', _pe(['KERNEL32.dll']));
    for (final n in [
      'msvcp140.dll',
      'vcruntime140.dll',
      'vcruntime140_1.dll',
    ]) {
      write(n, _pe(['KERNEL32.dll'], vcVersion));
    }
    write('data/vision/tessdata/eng.traineddata', utf8.encode('model-bytes'));
    write('data/vision/self_check/title.gray', [1, 2, 3]);
    write('data/vision/self_check/title.json', utf8.encode('{}'));
    write(
      'blackgrid_panel_ocr.dll.sha256',
      utf8.encode(_sha(read('blackgrid_panel_ocr.dll'))),
    );
    writeManifest();
    writeLockAndNotices();
  }

  final Directory root;
  late final Directory bundle;
  late final String lockPath = '${root.path}/lock.json';
  late final String noticesPath = '${root.path}/NOTICES.md';
  late final String reportPath = '${root.path}/report.json';

  static Uint8List _pe(List<String> imports, [List<int>? version]) =>
      PeBuilder(imports: imports, version: version).build();

  void write(String rel, List<int> bytes) {
    final f = File('${bundle.path}/$rel')..createSync(recursive: true);
    f.writeAsBytesSync(bytes);
  }

  Uint8List read(String rel) => File('${bundle.path}/$rel').readAsBytesSync();

  void writeManifest() {
    const vision = [
      'blackgrid_vision.dll',
      'tesseract50.dll',
      'leptonica-1.82.0.dll',
      'data/vision/tessdata/eng.traineddata',
    ];
    final manifest = {
      'format': 1,
      'abi': 1,
      'engineVersion': '5.0.0',
      'files': [
        for (final p in vision)
          {'path': p, 'sha256': _sha(read(p)), 'size': read(p).length},
      ],
    };
    write(
      'data/vision/runtime.manifest.json',
      utf8.encode(jsonEncode(manifest)),
    );
  }

  String get tesseractSha => _sha(read('tesseract50.dll'));

  void writeLockAndNotices({String? noticesTesseractSha}) {
    final lock = {
      'format': 1,
      'inputs': [
        {
          'id': 'opencv-source',
          'name': 'opencv-4.13.0.zip',
          'version': '4.13.0',
          'urls': [_opencvUrl],
          'authoritativeUrl': _opencvUrl,
          'sha256': 'a' * 64,
          'size': 10,
          'noticeAnchor': 'opencv-4-13-0',
        },
        {
          'id': 'tesseract-nupkg',
          'name': 'tesseract.5.2.0.nupkg',
          'version': '5.2.0',
          'engineVersion': '5.0.0',
          'urls': [_nupkgUrl],
          'authoritativeUrl': _nupkgUrl,
          'sha256': 'b' * 64,
          'size': 10,
          'noticeAnchor': 'tesseract-5-0-0',
        },
        {
          'id': 'tesseract-dll',
          'name': 'tesseract50.dll',
          'version': '5.0.0',
          'engineVersion': '5.0.0',
          'extractFrom': 'tesseract-nupkg',
          'path': 'x64/tesseract50.dll',
          'bundlePath': 'tesseract50.dll',
          'sha256': tesseractSha,
          'size': read('tesseract50.dll').length,
          'noticeAnchor': 'tesseract-5-0-0',
        },
        {
          'id': 'leptonica-dll',
          'name': 'leptonica-1.82.0.dll',
          'version': '1.82.0',
          'extractFrom': 'tesseract-nupkg',
          'path': 'x64/leptonica-1.82.0.dll',
          'bundlePath': 'leptonica-1.82.0.dll',
          'sha256': _sha(read('leptonica-1.82.0.dll')),
          'size': read('leptonica-1.82.0.dll').length,
          'noticeAnchor': 'leptonica-1-82-0',
        },
        {
          'id': 'eng-traineddata',
          'name': 'eng.traineddata',
          'version': '4.1.0',
          'urls': [_modelUrl],
          'authoritativeUrl': _modelUrl,
          'bundlePath': 'data/vision/tessdata/eng.traineddata',
          'sha256': _sha(read('data/vision/tessdata/eng.traineddata')),
          'size': read('data/vision/tessdata/eng.traineddata').length,
          'noticeAnchor': 'tessdata-fast-4-1-0',
        },
      ],
    };
    File(lockPath).writeAsStringSync(jsonEncode(lock));
    final tessSha = noticesTesseractSha ?? tesseractSha;
    File(noticesPath).writeAsStringSync('''
# Notices

## M2 item vision runtime

<a id="opencv-4-13-0"></a>
### OpenCV 4.13.0

- **Source:** <$_opencvUrl>
- **SHA-256:** `${'a' * 64}`

<a id="tesseract-5-0-0"></a>
### Tesseract 5.0.0

- **Version:** 5.0.0 as built in package version 5.2.0
- **Source:** <$_nupkgUrl>
- **SHA-256:** package `${'b' * 64}`; dll `$tessSha`

<a id="leptonica-1-82-0"></a>
### Leptonica 1.82.0

- **Source:** <$_nupkgUrl>
- **SHA-256:** `${_sha(read('leptonica-1.82.0.dll'))}`

<a id="tessdata-fast-4-1-0"></a>
### tessdata_fast 4.1.0

- **Source:** <$_modelUrl>
- **SHA-256:** `${_sha(read('data/vision/tessdata/eng.traineddata'))}`

<a id="microsoft-visual-cpp-runtime"></a>
### Microsoft Visual C++ runtime (app-local)

- msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll
- **Terms:** Distributable Code under the Microsoft Software License Terms.

## Other section
''');
  }

  List<String> get args => [
    bundle.path,
    '--report',
    reportPath,
    '--lock',
    lockPath,
    '--notices',
    noticesPath,
  ];

  Future<({int code, Map<String, Object?>? report, String err})> run() async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(args, out: out, err: err);
    final f = File(reportPath);
    return (
      code: code,
      report: f.existsSync()
          ? jsonDecode(f.readAsStringSync()) as Map<String, Object?>
          : null,
      err: err.toString(),
    );
  }

  void dispose() => root.deleteSync(recursive: true);
}

Map<String, Object?> _step(Map<String, Object?> report, String name) =>
    ((report['steps']! as List).cast<Map<String, Object?>>()).firstWhere(
      (s) => s['name'] == name,
    );

String _failures(Map<String, Object?> report, String name) =>
    (_step(report, name)['failures']! as List).join('\n');

void main() {
  late _Fixture fx;
  setUp(() => fx = _Fixture());
  tearDown(() => fx.dispose());

  test('inventory passes on synthetic complete bundle', () async {
    final r = await fx.run();
    expect(r.code, 0, reason: '${r.err}\n${r.report}');
    final report = r.report!;
    expect(report['result'], 'pass');
    expect((report['steps']! as List).map((s) => (s as Map)['name']), [
      'inventory',
      'bindings',
      'pins',
      'imports',
      'runtimeVersions',
      'notices',
    ]);
    expect(_step(report, 'inventory')['ok'], isTrue);
    final files = (report['files']! as List).cast<Map<String, Object?>>();
    final tess = files.firstWhere((f) => f['path'] == 'tesseract50.dll');
    expect(tess['sha256'], fx.tesseractSha);
    final vc = files.firstWhere((f) => f['path'] == 'vcruntime140.dll');
    expect(vc['version'], '14.51.36247.0');
  });

  test('inventory fails naming unexpected dll', () async {
    fx.write('plugins/stray_helper.dll', [0]);
    final r = await fx.run();
    expect(r.code, isNot(0));
    expect(_step(r.report!, 'inventory')['ok'], isFalse);
    expect(r.report!['result'], 'fail');
    expect(
      _failures(r.report!, 'inventory'),
      contains('plugins/stray_helper.dll'),
    );
    expect(_failures(r.report!, 'inventory'), contains('unexpected'));
  });

  test('inventory fails naming missing model', () async {
    File('${fx.bundle.path}/data/vision/tessdata/eng.traineddata').deleteSync();
    final r = await fx.run();
    expect(r.code, isNot(0));
    final text = _failures(r.report!, 'inventory');
    expect(text, contains('data/vision/tessdata/eng.traineddata'));
    expect(text, contains('missing'));
  });

  test('hash step passes when manifest, sidecar and lock agree', () async {
    final r = await fx.run();
    expect(_step(r.report!, 'bindings')['ok'], isTrue);
    expect(_step(r.report!, 'pins')['ok'], isTrue);
  });

  test('hash step fails naming file and both hashes', () async {
    final expected = _sha(fx.read('blackgrid_vision.dll'));
    final changed = [...fx.read('blackgrid_vision.dll'), 0];
    fx.write('blackgrid_vision.dll', changed);
    final r = await fx.run();
    expect(r.code, isNot(0));
    final text = _failures(r.report!, 'bindings');
    expect(text, contains('blackgrid_vision.dll'));
    expect(text, contains(expected));
    expect(text, contains(_sha(changed)));

    // The panel OCR sidecar is checked the same way.
    fx.write('blackgrid_panel_ocr.dll.sha256', utf8.encode('0' * 64));
    final r2 = await fx.run();
    final text2 = _failures(r2.report!, 'bindings');
    expect(text2, contains('blackgrid_panel_ocr.dll'));
    expect(text2, contains('0' * 64));
    expect(text2, contains(_sha(fx.read('blackgrid_panel_ocr.dll'))));
  });

  test('pin step fails when bound file diverges from lock', () async {
    final changed = [...fx.read('tesseract50.dll'), 7];
    final pinned = fx.tesseractSha;
    fx.write('tesseract50.dll', changed);
    fx.writeManifest(); // binding is valid for the new bytes
    final r = await fx.run();
    expect(r.code, isNot(0));
    expect(_step(r.report!, 'bindings')['ok'], isTrue);
    final text = _failures(r.report!, 'pins');
    expect(text, contains('tesseract50.dll'));
    expect(text, contains('pinned source'));
    expect(text, contains(pinned));
    expect(text, contains(_sha(changed)));
  });

  test('notices step passes with version url and sha per lock entry', () async {
    final r = await fx.run();
    expect(_step(r.report!, 'notices')['ok'], isTrue);
  });

  test('notices step fails naming component with stale sha', () async {
    fx.writeLockAndNotices(noticesTesseractSha: 'c' * 64);
    final r = await fx.run();
    expect(r.code, isNot(0));
    final text = _failures(r.report!, 'notices');
    expect(text, contains('tesseract-dll'));
    expect(text, contains(fx.tesseractSha));
    expect(_step(r.report!, 'inventory')['ok'], isTrue);
  });

  test('absent bundle dir exits non-zero without pass report', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final missing = '${fx.root.path}/no_such_bundle';
    final code = await runCli(
      [
        missing,
        '--report',
        fx.reportPath,
        '--lock',
        fx.lockPath,
        '--notices',
        fx.noticesPath,
      ],
      out: out,
      err: err,
    );
    expect(code, isNot(0));
    expect(err.toString(), contains('no_such_bundle'));
    expect(out.toString(), isNot(contains('pass')));
    expect(File(fx.reportPath).existsSync(), isFalse);
  });

  Future<({int code, String err})> runWithReport(String report) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
      [
        fx.bundle.path,
        '--report',
        report,
        '--lock',
        fx.lockPath,
        '--notices',
        fx.noticesPath,
      ],
      out: out,
      err: err,
    );
    return (code: code, err: err.toString());
  }

  test('report path equal to the lock is refused unchanged', () async {
    final before = File(fx.lockPath).readAsStringSync();
    final r = await runWithReport(fx.lockPath);
    expect(r.code, 2);
    expect(r.err, contains('refusing report path'));
    expect(File(fx.lockPath).readAsStringSync(), before);
  });

  test('report path inside the bundle is refused', () async {
    final inside = '${fx.bundle.path}/data/report.json';
    final r = await runWithReport(inside);
    expect(r.code, 2);
    expect(r.err, contains('refusing report path'));
    expect(File(inside).existsSync(), isFalse);
  });

  test('report path under a linked directory is refused', () async {
    final target = Directory('${fx.root.path}/real')..createSync();
    // A junction on Windows, a symbolic link elsewhere.
    final link = '${fx.root.path}/linked';
    Link(link).createSync(target.path);
    final r = await runWithReport('$link/report.json');
    expect(r.code, 2);
    expect(r.err, contains('symbolic link or junction'));
    expect(File('${target.path}/report.json').existsSync(), isFalse);
  });

  test(
    'stale report temp hard-linked to the lock is not written through',
    () async {
      final before = File(fx.lockPath).readAsStringSync();
      final temp = '${fx.reportPath}.tmp';
      final made = Platform.isWindows
          ? Process.runSync('fsutil', [
              'hardlink',
              'create',
              File(temp).absolute.path.replaceAll('/', r'\'),
              File(fx.lockPath).absolute.path.replaceAll('/', r'\'),
            ])
          : Process.runSync('ln', [fx.lockPath, temp]);
      expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');
      await fx.run();
      expect(File(fx.lockPath).readAsStringSync(), before);
      expect(File(fx.reportPath).existsSync(), isTrue);
    },
  );
}
