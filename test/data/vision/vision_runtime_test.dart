import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/data/vision/vision_native.dart';
import 'package:blackgrid/data/vision/vision_primitives.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const coreFiles = [
  'leptonica-1.82.0.dll',
  'tesseract50.dll',
  'blackgrid_vision.dll',
  'data/vision/tessdata/eng.traineddata',
];

class FakeEngine implements VisionEngine {
  FakeEngine(this.log);

  final List<String> log;
  int initResult = 0;
  int recogniseCalls = 0;
  int disposeCalls = 0;
  String? initDatapath;
  String? initLanguage;
  int? initOem;
  int? psm;

  @override
  int init(String datapath, String language, int oem) {
    log.add('engine.init');
    initDatapath = datapath;
    initLanguage = language;
    initOem = oem;
    return initResult;
  }

  @override
  void setPageSegMode(int mode) {
    log.add('engine.setPsm');
    psm = mode;
  }

  @override
  String get initLanguages => 'eng';

  @override
  int get oem => 1;

  @override
  int get pageSegMode => psm ?? 0;

  @override
  OcrText recognise(VisionImage image) {
    recogniseCalls++;
    return const OcrText('hello', truncated: false);
  }

  @override
  void dispose() {
    disposeCalls++;
    log.add('engine.dispose');
  }
}

class FakePrimitives implements VisionPrimitives {
  int calls = 0;

  /// When set, matchTemplateBest fails with this native status.
  int? matchStatus;

  @override
  Uint8List toGray(VisionImage src, {required bool rgbOrder}) {
    calls++;
    return Uint8List(src.width * src.height);
  }

  @override
  Uint8List resize(VisionImage src, int dw, int dh, int interp) {
    calls++;
    return Uint8List(dw * dh * src.channels);
  }

  @override
  Uint8List thresholdBinaryInv(VisionImage src, int thresh, int maxval) {
    calls++;
    return Uint8List(src.width * src.height);
  }

  @override
  TemplateMatch matchTemplateBest(VisionImage image, VisionImage template) {
    calls++;
    final status = matchStatus;
    if (status != null) throw VisionNativeError(status);
    return const TemplateMatch(0.5, 1, 2);
  }

  @override
  int? findInRangeRow(
    VisionImage src,
    int row,
    int startX,
    List<int> lo,
    List<int> hi,
  ) {
    calls++;
    return null;
  }
}

class FakeNative implements VisionNative {
  FakeNative(this.log) : engine = FakeEngine(log);

  final List<String> log;
  final FakeEngine engine;
  final primitivesFake = FakePrimitives();
  int abi = 1;
  String version = '5.0.0';
  int closeCalls = 0;

  @override
  int get visionAbi => abi;

  @override
  String get tessVersion => version;

  @override
  VisionEngine? createEngine() => engine;

  @override
  VisionPrimitives get primitives => primitivesFake;

  @override
  void close() {
    closeCalls++;
    log.add('native.close');
  }
}

String sha(List<int> bytes) => sha256.convert(bytes).toString();

class Fixture {
  Fixture() : dir = Directory.systemTemp.createTempSync('bgvision') {
    for (final path in coreFiles) {
      write(path, utf8.encode('content of $path'));
    }
  }

  final Directory dir;
  final log = <String>[];
  final opened = <List<String>>[];
  late final FakeNative native = FakeNative(log);

  String get root => dir.path.replaceAll('\\', '/');

  void write(String relative, List<int> bytes) {
    final file = File('$root/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  void writeManifest({
    List<String>? only,
    Map<String, String> overrides = const {},
    int abi = 1,
    String engineVersion = '5.0.0',
    List<String> extra = const [],
  }) {
    final files = <Map<String, Object>>[];
    for (final path in only ?? [...coreFiles, ...extra]) {
      final file = File('$root/$path');
      final digest = file.existsSync()
          ? sha(file.readAsBytesSync())
          : sha(utf8.encode(path));
      files.add({'path': path, 'sha256': overrides[path] ?? digest, 'size': 1});
    }
    write(
      'data/vision/runtime.manifest.json',
      utf8.encode(
        jsonEncode({
          'format': 1,
          'abi': abi,
          'engineVersion': engineVersion,
          'files': files,
        }),
      ),
    );
  }

  VisionRuntime open([String? directory]) => VisionRuntime.open(
    runtimeDirectory: directory ?? root,
    opener: (leptonica, tesseract, vision) {
      opened.add([leptonica, tesseract, vision]);
      log.add('opened');
      return native;
    },
  );

  void dispose() => dir.deleteSync(recursive: true);
}

VisionImage gray(int w, int h) =>
    VisionImage(Uint8List(w * h), width: w, height: h, stride: w, channels: 1);

void main() {
  late Fixture fixture;
  setUp(() => fixture = Fixture());
  tearDown(() => fixture.dispose());

  VisionFailure failureOf(VisionRuntime runtime) {
    final status = runtime.status;
    expect(status, isA<VisionUnavailable>());
    return (status as VisionUnavailable).failure;
  }

  test('ready runtime initialises in order and reports identity', () {
    fixture.write('data/vision/self_check/title.gray', [1, 2, 3]);
    fixture.writeManifest(extra: ['data/vision/self_check/title.gray']);
    final runtime = fixture.open();
    final status = runtime.status;
    expect(status, isA<VisionReady>());
    final identity = (status as VisionReady).identity;
    expect(identity.tesseractVersion, '5.0.0');
    expect(identity.visionAbi, 1);
    expect(identity.language, 'eng');
    expect(identity.oem, 1);
    expect(identity.files.map((f) => f.path), contains('tesseract50.dll'));
    expect(identity.files.length, 5);
    expect(fixture.opened.single.map((p) => p.split('/').last), [
      'leptonica-1.82.0.dll',
      'tesseract50.dll',
      'blackgrid_vision.dll',
    ]);
    expect(fixture.native.engine.initOem, 1);
    expect(fixture.native.engine.initLanguage, 'eng');
    expect(
      fixture.native.engine.initDatapath,
      '${fixture.root}/data/vision/tessdata',
    );
    expect(fixture.native.engine.psm, 13);
    runtime.dispose();
  });

  test('hash mismatch reports hashMismatch and never opens a library', () {
    fixture.writeManifest(
      overrides: {
        'tesseract50.dll': sha([1, 2, 3]),
      },
    );
    final failure = failureOf(fixture.open());
    expect(failure, isA<VisionHashMismatch>());
    final mismatch = failure as VisionHashMismatch;
    expect(mismatch.path, endsWith('tesseract50.dll'));
    expect(mismatch.expected, sha([1, 2, 3]));
    expect(mismatch.actual, isNot(mismatch.expected));
    expect(fixture.opened, isEmpty);
  });

  test('missing model reports missingFile', () {
    fixture.writeManifest();
    File('${fixture.root}/data/vision/tessdata/eng.traineddata').deleteSync();
    final failure = failureOf(fixture.open());
    expect(failure, isA<VisionMissingFile>());
    expect((failure as VisionMissingFile).path, endsWith('eng.traineddata'));
    expect(fixture.opened, isEmpty);
  });

  test('model absent from the manifest reports missingFile', () {
    fixture.writeManifest(only: coreFiles.take(3).toList());
    final failure = failureOf(fixture.open());
    expect((failure as VisionMissingFile).path, endsWith('eng.traineddata'));
    expect(fixture.opened, isEmpty);
  });

  test('missing manifest reports missingFile naming binding', () {
    final failure = failureOf(fixture.open());
    expect(failure, isA<VisionMissingFile>());
    expect(
      (failure as VisionMissingFile).path,
      endsWith('data/vision/runtime.manifest.json'),
    );
    expect(fixture.opened, isEmpty);
  });

  test('malformed manifest reports missingFile naming binding', () {
    fixture.write('data/vision/runtime.manifest.json', utf8.encode('{nope'));
    final failure = failureOf(fixture.open());
    expect(
      (failure as VisionMissingFile).path,
      endsWith('runtime.manifest.json'),
    );
  });

  test('relative runtime directory reports invalidPath', () {
    fixture.writeManifest();
    final failure = failureOf(fixture.open('relative/runtime'));
    expect(failure, isA<VisionInvalidPath>());
    expect(fixture.opened, isEmpty);
  });

  test('abi mismatch reports expected and actual and closes libraries', () {
    fixture.writeManifest();
    fixture.native.abi = 7;
    final failure = failureOf(fixture.open());
    expect(failure, isA<VisionAbiMismatch>());
    final mismatch = failure as VisionAbiMismatch;
    expect(mismatch.component, 'blackgrid_vision');
    expect(mismatch.expected, '1');
    expect(mismatch.actual, '7');
    expect(fixture.native.closeCalls, 1);
  });

  test('engine version mismatch reports abiMismatch for OCR engine', () {
    fixture.writeManifest();
    fixture.native.version = '5.3.0';
    final failure = failureOf(fixture.open());
    final mismatch = failure as VisionAbiMismatch;
    expect(mismatch.component, 'tesseract');
    expect(mismatch.expected, '5.0.0');
    expect(mismatch.actual, '5.3.0');
    expect(fixture.native.closeCalls, 1);
  });

  test('manifest abi differing from the expected abi is abiMismatch', () {
    fixture.writeManifest(abi: 2);
    final failure = failureOf(fixture.open());
    expect(failure, isA<VisionAbiMismatch>());
    expect(fixture.native.closeCalls, 1);
  });

  test('opener failure reports loadFailed', () {
    fixture.writeManifest();
    final runtime = VisionRuntime.open(
      runtimeDirectory: fixture.root,
      opener: (a, b, c) => throw VisionLoadException(b, 'error 126'),
    );
    final failure = failureOf(runtime);
    expect(failure, isA<VisionLoadFailed>());
    expect((failure as VisionLoadFailed).osError, 'error 126');
    expect(failure.path, endsWith('tesseract50.dll'));
  });

  test('corrupt model reports engineInitFailed and releases the handle', () {
    fixture.writeManifest();
    fixture.native.engine.initResult = -1;
    final failure = failureOf(fixture.open());
    expect(failure, isA<VisionEngineInitFailed>());
    expect(
      (failure as VisionEngineInitFailed).datapath,
      endsWith('data/vision/tessdata'),
    );
    expect(fixture.native.engine.disposeCalls, 1);
    expect(fixture.native.closeCalls, 1);
    expect(
      fixture.log.indexOf('engine.dispose'),
      lessThan(fixture.log.indexOf('native.close')),
    );
  });

  test('malformed image is invalidImage without a native call', () {
    fixture.writeManifest();
    final runtime = fixture.open();
    final bad = VisionImage(
      Uint8List(3),
      width: 4,
      height: 4,
      stride: 4,
      channels: 1,
    );
    final result = runtime.recognise(bad);
    expect(
      (result as VisionFailed<OcrText>).failure,
      isA<VisionInvalidImage>(),
    );
    final match = runtime.matchTemplate(gray(4, 4), gray(5, 5));
    expect(
      (match as VisionFailed<TemplateMatch>).failure,
      isA<VisionInvalidImage>(),
    );
    expect(fixture.native.engine.recogniseCalls, 0);
    expect(fixture.native.primitivesFake.calls, 0);
    runtime.dispose();
  });

  test('ready runtime recognises and runs primitives', () {
    fixture.writeManifest();
    final runtime = fixture.open();
    final text = runtime.recognise(gray(4, 4));
    expect((text as VisionOk<OcrText>).value.text, 'hello');
    final match = runtime.matchTemplate(gray(4, 4), gray(2, 2));
    expect((match as VisionOk<TemplateMatch>).value.x, 1);
    expect(fixture.native.primitivesFake.calls, 1);
    runtime.dispose();
  });

  test('native error status is nativeFailure, not invalidImage', () {
    fixture.writeManifest();
    final runtime = fixture.open();
    fixture.native.primitivesFake.matchStatus = -3;
    final match = runtime.matchTemplate(gray(4, 4), gray(2, 2));
    final failure = (match as VisionFailed<TemplateMatch>).failure;
    expect(failure, isA<VisionNativeFailure>());
    expect((failure as VisionNativeFailure).status, -3);
    expect(fixture.native.primitivesFake.calls, 1);
    runtime.dispose();
  });

  test('recognise after dispose returns disposed without native call', () {
    fixture.writeManifest();
    final runtime = fixture.open();
    runtime.dispose();
    final result = runtime.recognise(gray(4, 4));
    expect(
      (result as VisionFailed<OcrText>).failure,
      isA<VisionDisposedFailure>(),
    );
    final match = runtime.matchTemplate(gray(4, 4), gray(2, 2));
    expect(
      (match as VisionFailed<TemplateMatch>).failure,
      isA<VisionDisposedFailure>(),
    );
    expect(fixture.native.engine.recogniseCalls, 0);
    expect(fixture.native.primitivesFake.calls, 0);
  });

  test('dispose deletes engine and later calls return disposed', () {
    fixture.writeManifest();
    final runtime = fixture.open();
    runtime.dispose();
    expect(runtime.status, isA<VisionDisposed>());
    expect(fixture.native.engine.disposeCalls, 1);
    expect(fixture.native.closeCalls, 1);
    expect(
      (runtime.toGray(gray(2, 2)) as VisionFailed<VisionImage>).failure,
      isA<VisionDisposedFailure>(),
    );
  });

  test('second dispose is a no-op and delete ran once', () {
    fixture.writeManifest();
    final runtime = fixture.open();
    runtime.dispose();
    runtime.dispose();
    expect(fixture.native.engine.disposeCalls, 1);
    expect(fixture.native.closeCalls, 1);
  });
}
