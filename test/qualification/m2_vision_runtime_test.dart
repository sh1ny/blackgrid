@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/application/vision_self_check.dart'
    show windowsLoadedModulePaths;
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

final _p = _Paths();

/// Windows path helpers; bundle-relative paths use forward slashes.
final class _Paths {
  String join(String root, String relative, [String? more]) {
    final tail = more == null ? relative : '$relative/$more';
    return '$root\\${tail.replaceAll('/', '\\')}';
  }

  String dirname(String path) => File(path).parent.path;

  bool equals(String a, String b) =>
      a.replaceAll('/', '\\').toLowerCase() ==
      b.replaceAll('/', '\\').toLowerCase();
}

/// Loads the real Release bundle's vision runtime in the test process; no app
/// is launched. Each test disposes before the next opens, so a module name is
/// never loaded from two directories at once.
void main() {
  // e.g. build/windows/x64/runner/Release
  final bundleEnv = Platform.environment['BLACKGRID_RELEASE_BUNDLE'];
  final skip = bundleEnv == null
      ? 'Requires BLACKGRID_RELEASE_BUNDLE (a built Release bundle).'
      : false;
  final bundle = bundleEnv == null
      ? ''
      : Directory(bundleEnv).resolveSymbolicLinksSync();

  Map<String, Object?> manifestOf(String root) => jsonDecode(
    File(_p.join(root, 'data/vision/runtime.manifest.json')).readAsStringSync(),
  ) as Map<String, Object?>;

  List<String> manifestPaths(String root) => [
    for (final entry in manifestOf(root)['files']! as List<Object?>)
      (entry! as Map<String, Object?>)['path']! as String,
  ];

  /// Copies the manifest and every file it binds into [target].
  void copyVisionFiles(String target) {
    final paths = [
      ...manifestPaths(bundle),
      'data/vision/runtime.manifest.json',
    ];
    for (final path in paths) {
      final destination = File(_p.join(target, path));
      destination.parent.createSync(recursive: true);
      File(_p.join(bundle, path)).copySync(destination.path);
    }
  }

  /// Rewrites the manifest of [root] to bind the files as they are now.
  void rebindManifest(String root) {
    final manifest = manifestOf(root);
    manifest['files'] = [
      for (final path in manifestPaths(root))
        {
          'path': path,
          'sha256': sha256
              .convert(File(_p.join(root, path)).readAsBytesSync())
              .toString(),
          'size': File(_p.join(root, path)).lengthSync(),
        },
    ];
    File(_p.join(root, 'data/vision/runtime.manifest.json'))
        .writeAsStringSync(jsonEncode(manifest));
  }

  T withRuntime<T>(String root, T Function(VisionRuntime runtime) body) {
    final runtime = VisionRuntime.open(runtimeDirectory: root);
    try {
      return body(runtime);
    } finally {
      runtime.dispose();
    }
  }

  VisionIdentity readyIdentity(VisionRuntime runtime) {
    final status = runtime.status;
    if (status is VisionUnavailable) {
      fail('runtime unavailable: ${status.failure.message}');
    }
    return (status as VisionReady).identity;
  }

  T ok<T>(VisionResult<T> result) => switch (result) {
    VisionOk<T>(:final value) => value,
    VisionFailed<T>(:final failure) => fail(failure.message),
  };

  Future<Directory> tempDir(String prefix) =>
      Directory.systemTemp.createTemp(prefix);

  ({VisionImage image, Map<String, Object?> sample}) selfCheckSample() {
    final sample = jsonDecode(
      File(_p.join(bundle, 'data/vision/self_check/title.json'))
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final bytes = File(_p.join(bundle, 'data/vision/self_check/title.gray'))
        .readAsBytesSync();
    return (
      image: VisionImage(
        bytes,
        width: sample['width']! as int,
        height: sample['height']! as int,
        stride: sample['stride']! as int,
        channels: 1,
      ),
      sample: sample,
    );
  }

  test('intact bundle opens ready with file identities', () {
    withRuntime(bundle, (runtime) {
      final identity = readyIdentity(runtime);
      final manifest = {
        for (final entry in manifestOf(bundle)['files']! as List<Object?>)
          (entry! as Map<String, Object?>)['path']! as String:
              (entry as Map<String, Object?>)['sha256']! as String,
      };
      expect({
        for (final file in identity.files) file.path: file.sha256,
      }, manifest);
    });
  }, skip: skip);

  test('loaded module paths are inside the bundle', () {
    withRuntime(bundle, (runtime) {
      readyIdentity(runtime);
      final paths = windowsLoadedModulePaths();
      expect(paths, hasLength(3));
      for (final path in paths) {
        expect(
          _p.equals(_p.dirname(path), bundle),
          isTrue,
          reason: '$path is outside $bundle',
        );
      }
    });
  }, skip: skip);

  test('TESSDATA_PREFIX model is ignored when bundle model missing', () async {
    final root = await tempDir('m2-vision-tessdata-');
    final prefix = await tempDir('m2-vision-prefix-');
    final putenv = DynamicLibrary.open('ucrtbase.dll')
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)
        >('_wputenv_s');
    void setEnv(String name, String value) {
      final n = name.toNativeUtf16();
      final v = value.toNativeUtf16();
      try {
        expect(putenv(n, v), 0);
      } finally {
        calloc.free(n);
        calloc.free(v);
      }
    }

    try {
      copyVisionFiles(root.path);
      // A complete, valid model the engine could use if it consulted the
      // environment: both the 4.x and 5.x TESSDATA_PREFIX layouts.
      final model = File(
        _p.join(bundle, 'data/vision/tessdata/eng.traineddata'),
      );
      model.copySync(_p.join(prefix.path, 'eng.traineddata'));
      Directory(_p.join(prefix.path, 'tessdata')).createSync();
      model.copySync(_p.join(prefix.path, 'tessdata', 'eng.traineddata'));
      final missing = _p.join(
        root.path,
        'data/vision/tessdata/eng.traineddata',
      );
      File(missing).deleteSync();
      setEnv('TESSDATA_PREFIX', prefix.path);
      withRuntime(root.path, (runtime) {
        final status = runtime.status;
        expect(status, isA<VisionUnavailable>());
        final failure = (status as VisionUnavailable).failure;
        expect(failure, isA<VisionMissingFile>());
        expect(_p.equals((failure as VisionMissingFile).path, missing), isTrue);
      });
    } finally {
      setEnv('TESSDATA_PREFIX', '');
      await root.delete(recursive: true);
      await prefix.delete(recursive: true);
    }
  }, skip: skip);

  test('identity reports vision abi and pinned engine version', () {
    final lock = jsonDecode(
      File('windows/vision/third_party.lock.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final nupkg =
        (lock['inputs']! as List<Object?>).firstWhere(
              (e) => (e! as Map<String, Object?>)['id'] == 'tesseract-nupkg',
            )!
            as Map<String, Object?>;
    withRuntime(bundle, (runtime) {
      final identity = readyIdentity(runtime);
      expect(identity.visionAbi, visionExpectedAbi);
      expect(identity.tesseractVersion, nupkg['engineVersion']);
      expect(manifestOf(bundle)['engineVersion'], nupkg['engineVersion']);
    });
  }, skip: skip);

  test('engine reports eng, LSTM-only and raw-line', () {
    withRuntime(bundle, (runtime) {
      final identity = readyIdentity(runtime);
      expect(identity.language, 'eng');
      expect(identity.oem, 1); // OEM_LSTM_ONLY
      expect(identity.psm, 13); // PSM_RAW_LINE
    });
  }, skip: skip);

  // The test process has no UTF-8 activeCodePage, so Tesseract's narrow
  // datapath cannot carry Cyrillic here unless the system code page is
  // UTF-8. blackgrid.exe has the manifest; task 5.5 covers that path.
  final acp = Platform.isWindows
      ? DynamicLibrary.open('kernel32.dll')
            .lookupFunction<Uint32 Function(), int Function()>('GetACP')()
      : 0;
  test(
    'bundle copied under Cyrillic path opens ready',
    () async {
      final parent = await tempDir('m2-vision-');
      try {
        final root = _p.join(parent.path, 'Блэкгрид тест');
        copyVisionFiles(root);
        withRuntime(root, readyIdentity);
      } finally {
        await parent.delete(recursive: true);
      }
    },
    skip: skip != false
        ? skip
        : acp != 65001
        ? 'ANSI code page $acp is not UTF-8; covered by the blackgrid.exe '
              'self-check under a Cyrillic path (m2_vision_self_check_test).'
        : false,
  );

  test('bound truncated model reports engineInitFailed', () async {
    final root = await tempDir('m2-vision-truncated-');
    try {
      copyVisionFiles(root.path);
      final model = File(
        _p.join(root.path, 'data/vision/tessdata/eng.traineddata'),
      );
      final bytes = model.readAsBytesSync();
      model.writeAsBytesSync(Uint8List.sublistView(bytes, 0, 4096));
      rebindManifest(root.path);
      withRuntime(root.path, (runtime) {
        final status = runtime.status;
        expect(status, isA<VisionUnavailable>());
        final failure = (status as VisionUnavailable).failure;
        expect(failure, isA<VisionEngineInitFailed>());
        expect(
          (failure as VisionEngineInitFailed).datapath,
          contains('tessdata'),
        );
      });
    } finally {
      await root.delete(recursive: true);
    }
  }, skip: skip);

  test('template crop matches at its location with score >= 0.99', () {
    final (:image, :sample) = selfCheckSample();
    final rect = sample['template']! as Map<String, Object?>;
    final x = rect['x']! as int;
    final y = rect['y']! as int;
    final w = rect['width']! as int;
    final h = rect['height']! as int;
    final crop = Uint8List(w * h);
    for (var row = 0; row < h; row++) {
      final start = (y + row) * image.stride + x;
      crop.setRange(row * w, (row + 1) * w, image.bytes, start);
    }
    withRuntime(bundle, (runtime) {
      readyIdentity(runtime);
      final match = ok(
        runtime.matchTemplate(
          image,
          VisionImage(crop, width: w, height: h, stride: w, channels: 1),
        ),
      );
      expect(match.score, greaterThanOrEqualTo(0.99));
      expect((match.x, match.y), (x, y));
    });
  }, skip: skip);

  test('uniform template is rejected rather than matched', () {
    final (:image, sample: _) = selfCheckSample();
    final flat = Uint8List(16 * 16)..fillRange(0, 16 * 16, 235);
    withRuntime(bundle, (runtime) {
      readyIdentity(runtime);
      final result = runtime.matchTemplate(
        image,
        VisionImage(flat, width: 16, height: 16, stride: 16, channels: 1),
      );
      final failure = (result as VisionFailed<TemplateMatch>).failure;
      expect(failure, isA<VisionNativeFailure>());
      expect((failure as VisionNativeFailure).status, -2); // BGV_ERR_IMAGE
    });
  }, skip: skip);

  test('row scan without match returns none', () {
    const width = 64;
    final black = Uint8List(width * 4 * 2);
    withRuntime(bundle, (runtime) {
      readyIdentity(runtime);
      final found = ok(
        runtime.findInRangeRow(
          VisionImage(
            black,
            width: width,
            height: 2,
            stride: width * 4,
            channels: 4,
          ),
          1,
          0,
          [200, 200, 200],
          [255, 255, 255],
        ),
      );
      expect(found, isNull);
    });
  }, skip: skip);

  test('self-check title OCR equals expected text', () {
    final (:image, :sample) = selfCheckSample();
    withRuntime(bundle, (runtime) {
      readyIdentity(runtime);
      final text = ok(runtime.recognise(image));
      expect(text.truncated, isFalse);
      expect(text.text.trim(), sample['text']);
    });
  }, skip: skip);

  test('white image OCR returns without failure', () {
    const width = 320;
    const height = 48;
    final white = Uint8List(width * height)..fillRange(0, width * height, 255);
    withRuntime(bundle, (runtime) {
      readyIdentity(runtime);
      final text = ok(
        runtime.recognise(
          VisionImage(
            white,
            width: width,
            height: height,
            stride: width,
            channels: 1,
          ),
        ),
      );
      // Raw-line mode can return short noise for a blank line, as in the
      // reference; only a failure-free, untruncated result is required.
      expect(text.text.trim().length, lessThan(8));
      expect(text.truncated, isFalse);
    });
  }, skip: skip);
}
