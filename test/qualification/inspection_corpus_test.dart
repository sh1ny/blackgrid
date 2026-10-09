@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/output_path_guard.dart';
import 'package:blackgrid/application/recognition_matcher.dart';
import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/vision/inspection_recognition.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:blackgrid/data/vision/vision_service.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inspection_corpus.dart';

/// How long one job may take before the run reports where it stuck.
const _jobLimit = Duration(seconds: 60);

/// The bundle's capture DLL. The factories are top-level so they are always
/// sendable: a closure in the test body would share a context with the
/// service itself.
String _bundleCaptureDll() =>
    '${Directory(Platform.environment['BLACKGRID_RELEASE_BUNDLE']!).resolveSymbolicLinksSync()}'
    '${Platform.pathSeparator}$captureLibraryName';

CapturePlatform _bundleCapture() =>
    NativeCapturePlatform.open(_bundleCaptureDll());

FrameRegistry _bundleFrames() => _bundleCapture().frames;

/// The inspection corpus runner (design D8), over user-supplied screenshots.
///
/// Needs `BLACKGRID_RELEASE_BUNDLE` (a built Release bundle) and
/// `BLACKGRID_CORPUS_DIR` (see `docs/qualification/m2/CORPUS.md`). With either
/// absent the test skips before anything is loaded. Nothing here touches the
/// game: the corpus is a set of saved PNG files.
void main() {
  final bundleEnv = Platform.environment['BLACKGRID_RELEASE_BUNDLE'];
  final corpusEnv = Platform.environment['BLACKGRID_CORPUS_DIR'];
  final skip = switch ((bundleEnv, corpusEnv)) {
    (null, _) => 'Requires BLACKGRID_RELEASE_BUNDLE (a built Release bundle).',
    (_, null) =>
      'Requires BLACKGRID_CORPUS_DIR (a corpus directory, see '
          'docs/qualification/m2/CORPUS.md).',
    _ => false,
  };

  test(
    'corpus coverage and false positives do not regress against the baseline',
    () async {
      final bundle = Directory(bundleEnv!).resolveSymbolicLinksSync();
      final corpusDir = Directory(corpusEnv!).absolute.path;
      File at(String relative) =>
          File('$corpusDir${Platform.pathSeparator}$relative');

      final cases = parseCorpus(at('corpus.json').readAsStringSync());
      expect(cases, isNotEmpty);
      // The catalog is the app's cache format: CatalogSnapshot.toJson.
      final snapshot = CatalogSnapshot.fromJson(
        jsonDecode(at('catalog.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final index = await buildTitleMatchIndexOffUi(snapshot);
      final baselineFile = at('baseline.json');
      final baseline = baselineFile.existsSync()
          ? parseBaseline(baselineFile.readAsStringSync())
          : null;

      // The run writes only under out/; refuse before any write when an
      // input lives there, a write would overwrite an input, or a path
      // passes through a link.
      final inputs = [
        'corpus.json',
        'catalog.json',
        if (baseline != null) 'baseline.json',
        for (final c in cases) c.image,
      ];
      final collision = inputInsideOutput(corpusDir, inputs);
      if (collision != null) {
        fail('corpus input $collision lies inside $corpusOutputDir/');
      }
      final protectedInputs = [for (final input in inputs) at(input).path];
      void guardWrite(String path) {
        final unsafe = unsafeOutputReason(
          path,
          protectedFiles: protectedInputs,
        );
        if (unsafe != null) fail('refusing to write: $unsafe');
      }

      final outPath = at(corpusOutputDir).path;
      final reportPath = '$outPath${Platform.pathSeparator}report.json';
      guardWrite(reportPath);
      final outDir = Directory(outPath)..createSync(recursive: true);
      final cropDir = Directory('${outDir.path}${Platform.pathSeparator}crops')
        ..createSync(recursive: true);

      final loaded = loadMarkerTemplate(bundle);
      if (loaded is! MarkerTemplateLoaded) fail('marker template: $loaded');
      final service = VisionService<InspectionRequest, InspectionRecognition>(
        runtimeDirectory: bundle,
        jobFactory: inspectionRecognitionJobFactory,
        templates: [loaded.template],
        platformFactory: _bundleCapture,
        registryFactory: _bundleFrames,
      );
      final reports = <CaseReport>[];
      try {
        final failure = await service.start().timeout(
          _jobLimit,
          onTimeout: () => fail('start did not answer; state ${service.state}'),
        );
        expect(failure, isNull, reason: failure?.message);

        String? decodedPath;
        BgrxImage? decoded;
        BgrxImage load(CorpusCase c) {
          if (decodedPath != c.image) {
            decoded = decodePngBgrx(at(c.image).readAsBytesSync());
            decodedPath = c.image;
          }
          // Checked per case: cases sharing an image may declare other sizes.
          final mismatch = clientSizeMismatch(c, decoded!);
          if (mismatch != null) fail(mismatch);
          return decoded!;
        }

        Future<TimedRecognition> recognise(
          CorpusCase c,
          InspectionFrameKind kind,
        ) async {
          var image = load(c);
          if (kind == InspectionFrameKind.targeted) {
            final region = targetedRegion(
              clientWidth: c.clientWidth,
              clientHeight: c.clientHeight,
              cursorX: c.cursorX!,
              cursorY: c.cursorY!,
            );
            if (region == null) fail('${c.id}: cursor region is off-client');
            image = image.crop(region);
          }
          final frame = VisionImage(
            image.bytes,
            width: image.width,
            height: image.height,
            stride: image.stride,
            channels: 4,
          );
          final watch = Stopwatch()..start();
          final answer = await service
              .submit(
                frame,
                InspectionRequest(
                  kind: kind,
                  clientWidth: c.clientWidth,
                  clientHeight: c.clientHeight,
                ),
              )
              .timeout(
                _jobLimit,
                onTimeout: () => fail('${c.id}: job did not answer'),
              );
          watch.stop();
          if (answer is! VisionDelivered<InspectionRecognition>) {
            fail('${c.id}: job answered $answer');
          }
          return (result: answer.result, elapsed: watch.elapsed);
        }

        Future<String?> writeCrop(String id, InspectionEvidence e) async {
          if (e.crop.isEmpty) return null;
          // A separator in the id would place the crop outside crops/.
          if (id.contains(RegExp(r'[\\/]'))) {
            fail('case id $id cannot name a crop file');
          }
          final path = '${cropDir.path}${Platform.pathSeparator}$id.png';
          guardWrite(path);
          // Replaced through a temp file, so a hard link at the crop path is
          // replaced rather than written through to the input it shares.
          writeBytesViaTemp(path, cropToPng(e.crop, e.cropWidth, e.cropHeight));
          return path;
        }

        for (final c in cases) {
          reports.add(
            await evaluateCase(
              c,
              recognise: recognise,
              match: ({required targeted, fullClient}) => matchRecognitionOffUi(
                index,
                targeted: targeted,
                fullClient: fullClient,
                mode: snapshot.mode,
              ),
              writeCrop: writeCrop,
            ),
          );
        }
      } finally {
        await service.close();
      }

      final report = buildReport(reports, baseline: baseline);
      guardWrite(reportPath);
      writeViaTemp(
        reportPath,
        const JsonEncoder.withIndent('  ').convert(report),
      );
      // ignore: avoid_print
      print('corpus summary: ${jsonEncode(report['summary'])}');

      if (baseline != null) {
        final comparison = compareWithBaseline(reports, baseline);
        expect(
          comparison.passed,
          isTrue,
          reason:
              'regressions ${comparison.regressions}, new false positives '
              '${comparison.newFalsePositives}; coverage '
              '${comparison.current.coverage} vs '
              '${comparison.baseline.coverage}, false positives '
              '${comparison.current.falsePositives} vs '
              '${comparison.baseline.falsePositives}',
        );
      }
    },
    skip: skip,
    timeout: Timeout.none,
  );
}
