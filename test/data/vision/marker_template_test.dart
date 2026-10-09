import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_failure.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _grayPath = 'data/vision/marker/inspection_marker.gray';
const _jsonPath = 'data/vision/marker/inspection_marker.json';

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

/// A runtime directory holding only the marker files and a manifest binding
/// them with their current hashes.
class _Runtime {
  _Runtime() : dir = Directory.systemTemp.createTempSync('bg_marker_load') {
    write(
      _grayPath,
      Uint8List.fromList([for (var i = 0; i < 784; i++) i % 251]),
    );
    write(
      _jsonPath,
      utf8.encode(
        jsonEncode({'format': 1, 'width': 28, 'height': 28, 'stride': 28}),
      ),
    );
    writeManifest();
  }

  final Directory dir;

  String get root => dir.path.replaceAll(r'\', '/');

  void write(String relative, List<int> bytes) {
    File('$root/$relative')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  /// Binds the files as they are now, listing only [only] when given.
  void writeManifest({List<String> only = const [_grayPath, _jsonPath]}) {
    write(
      'data/vision/runtime.manifest.json',
      utf8.encode(
        jsonEncode({
          'format': 1,
          'abi': 2,
          'engineVersion': '5.0.0',
          'files': [
            for (final path in only)
              if (File('$root/$path').existsSync())
                {
                  'path': path,
                  'sha256': _sha(File('$root/$path').readAsBytesSync()),
                },
          ],
        }),
      ),
    );
  }

  void dispose() => dir.deleteSync(recursive: true);
}

void main() {
  late _Runtime runtime;
  setUp(() => runtime = _Runtime());
  tearDown(() => runtime.dispose());

  test('intact bundle yields a 28x28 template bound by the manifest', () {
    final result = loadMarkerTemplate(runtime.root);
    expect(result, isA<MarkerTemplateLoaded>());
    final template = (result as MarkerTemplateLoaded).template;
    expect(template, isA<VisionTemplate>());
    expect(template.name, 'inspectionMarker');
    final image = template.image;
    expect(
      (image.width, image.height, image.stride, image.channels),
      (28, 28, 28, 1),
    );
    expect(image.bytes, hasLength(784));
    expect(image.validate(), isNull);
    expect(image.bytes.toSet().length, greaterThan(1));
  });

  test('metadata size disagreeing with pixel bytes is invalidTemplate', () {
    runtime.write(
      _jsonPath,
      utf8.encode(
        jsonEncode({'format': 1, 'width': 30, 'height': 28, 'stride': 30}),
      ),
    );
    runtime.writeManifest();
    final result = loadMarkerTemplate(runtime.root);
    expect(result, isA<MarkerTemplateInvalid>());
    expect((result as MarkerTemplateInvalid).path, endsWith(_grayPath));
  });

  test('pixel byte count other than 784 is invalidTemplate', () {
    runtime.write(_grayPath, List.filled(783, 7)..[0] = 1);
    runtime.writeManifest();
    final result = loadMarkerTemplate(runtime.root);
    expect(result, isA<MarkerTemplateInvalid>());
  });

  test('flat template is invalidTemplate', () {
    runtime.write(_grayPath, List.filled(784, 9));
    runtime.writeManifest();
    final result = loadMarkerTemplate(runtime.root);
    expect(result, isA<MarkerTemplateInvalid>());
    expect((result as MarkerTemplateInvalid).reason, contains('variance'));
  });

  test('altered byte is hashMismatch naming the template', () {
    final bytes = File('${runtime.root}/$_grayPath').readAsBytesSync();
    runtime.write(_grayPath, [...bytes.take(783), bytes.last ^ 1]);
    final result = loadMarkerTemplate(runtime.root);
    final failure = (result as MarkerTemplateUnavailable).failure;
    expect(failure, isA<VisionHashMismatch>());
    expect((failure as VisionHashMismatch).path, endsWith(_grayPath));
  });

  test('metadata absent from the manifest is missingFile', () {
    runtime.writeManifest(only: const [_grayPath]);
    final result = loadMarkerTemplate(runtime.root);
    final failure = (result as MarkerTemplateUnavailable).failure;
    expect(failure, isA<VisionMissingFile>());
    expect((failure as VisionMissingFile).path, endsWith(_jsonPath));
  });

  test('deleted template file is missingFile', () {
    File('${runtime.root}/$_grayPath').deleteSync();
    final result = loadMarkerTemplate(runtime.root);
    final failure = (result as MarkerTemplateUnavailable).failure;
    expect(failure, isA<VisionMissingFile>());
    expect((failure as VisionMissingFile).path, endsWith(_grayPath));
  });
}
