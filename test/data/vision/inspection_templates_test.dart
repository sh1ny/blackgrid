import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_failure.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const markerGray = 'data/vision/marker/inspection_marker.gray';
const markerJson = 'data/vision/marker/inspection_marker.json';
const firGray = 'data/vision/fir/inspection_fir.gray';
const firJson = 'data/vision/fir/inspection_fir.json';
const paths = [markerGray, markerJson, firGray, firJson];

class _Runtime {
  _Runtime() : directory = Directory.systemTemp.createTempSync('bg_fir_load') {
    final pixels = [for (var i = 0; i < 784; i++) i % 251];
    write(markerGray, pixels);
    write(firGray, pixels.reversed.toList());
    write(markerJson, utf8.encode(jsonEncode({
      'format': 1, 'width': 28, 'height': 28, 'stride': 28,
    })));
    write(firJson, utf8.encode(jsonEncode({
      'format': 1, 'width': 28, 'height': 28, 'stride': 28,
      'sourceWidth': 3440, 'sourceHeight': 1440,
      'client': {'width': 3440, 'height': 1440},
      'crop': {'x': 1199, 'y': 732, 'width': 28, 'height': 28},
      'sourceSha256': '0d5fbdccd97c07c5b9a82c97633059325c9142cbab27953c024c868c93e2169b',
      'grayscale': 'opencv-bgr2gray-fixed-point',
      'recipe': 'inspection-fir-v1',
    })));
    bind();
  }

  final Directory directory;
  String get root => directory.path.replaceAll(r'\', '/');
  File file(String path) => File('$root/$path');
  void write(String path, List<int> bytes) {
    final target = file(path)..parent.createSync(recursive: true);
    target.writeAsBytesSync(bytes);
  }
  void bind({List<String> included = paths}) {
    write('data/vision/runtime.manifest.json', utf8.encode(jsonEncode({
      'format': 1, 'abi': 2, 'engineVersion': '5.0.0',
      'files': [
        for (final path in included)
          if (file(path).existsSync())
            {'path': path, 'sha256': sha256.convert(file(path).readAsBytesSync()).toString()},
      ],
    })));
  }
}

void main() {
  late _Runtime runtime;
  setUp(() => runtime = _Runtime());
  tearDown(() => runtime.directory.deleteSync(recursive: true));

  test('both verified templates reach ready', () {
    final result = loadInspectionTemplates(runtime.root);
    expect(result, isA<InspectionTemplatesLoaded>());
    final templates = (result as InspectionTemplatesLoaded).templates;
    expect(templates.map((template) => template.name),
        unorderedEquals(['inspectionMarker', 'inspectionFir']));
    for (final template in templates) {
      expect(template.image.bytes, hasLength(784));
      expect(template.image.bytes.toSet().length, greaterThan(1));
    }
  });

  test('missing altered and invalid check assets block activation', () {
    for (final path in [firGray, firJson]) {
      final original = runtime.file(path).readAsBytesSync();
      runtime.file(path).deleteSync();
      var result = loadInspectionTemplates(runtime.root);
      expect(result, isA<InspectionTemplatesUnavailable>(), reason: 'missing $path');
      final missing = (result as InspectionTemplatesUnavailable).failure;
      expect(missing, isA<VisionMissingFile>());
      expect((missing as VisionMissingFile).path, endsWith(path));
      runtime.write(path, original);
      runtime.write(path, [...original.take(original.length - 1), original.last ^ 1]);
      result = loadInspectionTemplates(runtime.root);
      expect(result, isA<InspectionTemplatesUnavailable>(), reason: 'hash mismatch $path');
      final altered = (result as InspectionTemplatesUnavailable).failure;
      expect(altered, isA<VisionHashMismatch>());
      expect((altered as VisionHashMismatch).path, endsWith(path));
      runtime.write(path, original);
      runtime.bind(included: paths.where((item) => item != path).toList());
      result = loadInspectionTemplates(runtime.root);
      expect(result, isA<InspectionTemplatesUnavailable>(), reason: 'unbound $path');
      final unbound = (result as InspectionTemplatesUnavailable).failure;
      expect(unbound, isA<VisionMissingFile>());
      expect((unbound as VisionMissingFile).path, endsWith(path));
      runtime.bind();
    }
    final validMetadata = runtime.file(firJson).readAsBytesSync();
    runtime.write(firJson, utf8.encode(jsonEncode({'format': 1, 'width': 29, 'height': 28, 'stride': 29})));
    runtime.bind();
    var result = loadInspectionTemplates(runtime.root);
    expect(result, isA<InspectionTemplatesInvalid>(), reason: 'metadata disagrees with pixels');
    runtime.write(firJson, validMetadata);
    runtime.write(firGray, List.filled(784, 7));
    runtime.bind();
    result = loadInspectionTemplates(runtime.root);
    expect(result, isA<InspectionTemplatesInvalid>(), reason: 'flat check template');
    runtime.write(firGray, [for (var i = 0; i < 784; i++) (783 - i) % 251]);
    for (final (key, value) in [
      ('recipe', 'other'),
      ('sourceSha256', 'bad'),
      ('client', {'width': 1920, 'height': 1080}),
      ('crop', {'x': 3430, 'y': 732, 'width': 28, 'height': 28}),
      ('grayscale', 'unknown'),
    ]) {
      final meta = jsonDecode(utf8.decode(validMetadata)) as Map<String, dynamic>;
      meta[key] = value;
      runtime.write(firJson, utf8.encode(jsonEncode(meta)));
      runtime.bind();
      final invalid = loadInspectionTemplates(runtime.root);
      expect(invalid, isA<InspectionTemplatesInvalid>(), reason: key);
      expect((invalid as InspectionTemplatesInvalid).path, endsWith(firJson));
    }
  });
}
