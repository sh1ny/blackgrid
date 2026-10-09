import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An import or export of the vision service or worker library, or of the
/// inspection recognition job library, in package, relative or absolute form.
/// Other `data/vision/` imports (the runtime used by `vision_self_check.dart`,
/// the geometry or the marker loader) are allowed.
final _serviceImport = RegExp(
  r'''(?:import|export)\s+['"][^'"]*'''
  r'''(?:vision_(?:service|worker)|inspection_recognition)\.dart['"]''',
);

/// Any mention of the service type or the recognition job type.
final _serviceReference = RegExp('VisionService|InspectionRecognitionJob');

/// Whether [source] imports the vision service, worker or recognition job, or
/// names the service or the job.
bool startsVisionService(String source) =>
    _serviceImport.hasMatch(source) || _serviceReference.hasMatch(source);

void main() {
  group('vision worker audit', () {
    test(
      'no startup path imports or starts the vision service or recognition job',
      () {
        final roots = <FileSystemEntity>[
          Directory('lib/application'),
          Directory('lib/ui'),
          File('lib/main.dart'),
        ];
        final files = <File>[];
        for (final root in roots) {
          if (root is File && root.existsSync()) files.add(root);
          if (root is Directory && root.existsSync()) {
            files.addAll(
              root
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.dart')),
            );
          }
        }
        expect(files, isNotEmpty, reason: 'audit would be vacuous');
        final offenders = [
          for (final file in files)
            if (startsVisionService(file.readAsStringSync())) file.path,
        ];
        expect(offenders, isEmpty);
      },
    );

    test('the matcher catches service and recognition job imports and '
        'references only', () {
      const flagged = <String>[
        "import 'package:blackgrid/data/vision/vision_service.dart';",
        "import '../data/vision/vision_service.dart' show X;",
        'import "vision_worker.dart";',
        "export 'package:blackgrid/data/vision/vision_worker.dart';",
        'final s = VisionService(factory);',
        'late VisionService service;',
        "import 'package:blackgrid/data/vision/inspection_recognition.dart';",
        "import '../data/vision/inspection_recognition.dart' show X;",
        'import "inspection_recognition.dart";',
        "export 'package:blackgrid/data/vision/inspection_recognition.dart';",
        'final job = InspectionRecognitionJob();',
        'final factory = () => InspectionRecognitionJob(cropByteLimit: 1);',
      ];
      for (final source in flagged) {
        expect(startsVisionService(source), isTrue, reason: source);
      }
      const allowed = <String>[
        "import '../data/vision/vision_native.dart' show openVisionNative;",
        "import '../data/vision/vision_runtime.dart';",
        "const d = 'data/vision/self_check';",
        "import '../data/vision/inspection_geometry.dart';",
        "import '../data/vision/marker_template.dart';",
        "import 'package:blackgrid/domain/title_matching.dart';",
        '// inspection recognition is not started at launch',
      ];
      for (final source in allowed) {
        expect(startsVisionService(source), isFalse, reason: source);
      }
      final selfCheck = File('lib/application/vision_self_check.dart');
      expect(selfCheck.existsSync(), isTrue);
      final text = selfCheck.readAsStringSync();
      expect(text, contains('data/vision/vision_runtime.dart'));
      expect(startsVisionService(text), isFalse);
    });
  });
}
