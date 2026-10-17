@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/output_path_guard.dart';
import 'package:blackgrid/application/recognition_matcher.dart';
import 'package:blackgrid/data/capture/capture_frame.dart';
import 'package:blackgrid/data/capture/capture_native.dart';
import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:blackgrid/data/vision/inspection_recognition.dart';
import 'package:blackgrid/data/vision/marker_template.dart';
import 'package:blackgrid/data/vision/vision_job.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart';
import 'package:blackgrid/data/vision/vision_service.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inspection_corpus.dart' show BgrxImage, decodePngBgrx;
import 'support/targeted_region_replay.dart';

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

/// The targeted-region replay (design D5), over recorded scan frames.
///
/// Needs `BLACKGRID_RELEASE_BUNDLE`, `BLACKGRID_RECORDING_DIRS` (`;`-separated
/// session folders), `BLACKGRID_REPLAY_CATALOG` (a `catalog.json`) and
/// `BLACKGRID_REPLAY_OUT` (the run folder `out/replay.json` is written under);
/// see `docs/qualification/m2/REPLAY.md`. With any absent the test skips
/// before anything is loaded. Nothing here touches the game: the recordings
/// are saved PNG files.
void main() {
  final env = Platform.environment;
  final bundleEnv = env['BLACKGRID_RELEASE_BUNDLE'];
  final dirsEnv = env['BLACKGRID_RECORDING_DIRS'];
  final catalogEnv = env['BLACKGRID_REPLAY_CATALOG'];
  final outEnv = env['BLACKGRID_REPLAY_OUT'];
  const doc = 'see docs/qualification/m2/REPLAY.md';
  final sessionDirs = [
    for (final part in (dirsEnv ?? '').split(';'))
      if (part.trim().isNotEmpty) Directory(part.trim()).absolute.path,
  ];
  final sep = Platform.pathSeparator;
  final skip = switch ((bundleEnv, dirsEnv, catalogEnv, outEnv)) {
    (null, _, _, _) =>
      'Requires BLACKGRID_RELEASE_BUNDLE (a built Release bundle).',
    (_, null, _, _) =>
      'Requires BLACKGRID_RECORDING_DIRS (;-separated recording session '
          'folders, $doc).',
    (_, _, null, _) =>
      'Requires BLACKGRID_REPLAY_CATALOG (a catalog.json, $doc).',
    (_, _, _, null) =>
      'Requires BLACKGRID_REPLAY_OUT (a run folder outside the inputs, $doc).',
    (final bundle?, _, final catalog?, _) =>
      _missingInput(bundle, sessionDirs, catalog) ?? false,
  };

  test(
    'the targeted band never accepts what the full-client pass does not',
    () async {
      final bundle = Directory(bundleEnv!).resolveSymbolicLinksSync();
      final catalogPath = File(catalogEnv!).absolute.path;

      // Refuse before anything runs: the report may not land inside a
      // recording folder or the bundle, overwrite the catalog, or pass
      // through a link.
      final reportPath = replayReportPath(outEnv!);
      String? refusal() => replayOutputRefusal(
        reportPath,
        inputDirectories: [...sessionDirs, bundle],
        inputFiles: [catalogPath],
      );
      if (refusal() case final reason?) fail('refusing to write: $reason');

      final sessions = [
        for (final dir in sessionDirs)
          (
            directory: dir,
            session: parseFramesJsonl(
              File('$dir$sep$scanFramesFileName').readAsStringSync(),
            ),
          ),
      ];

      // The catalog is the app's cache format: CatalogSnapshot.toJson.
      final snapshot = CatalogSnapshot.fromJson(
        jsonDecode(File(catalogPath).readAsStringSync())
            as Map<String, dynamic>,
      );
      final index = await buildTitleMatchIndexOffUi(snapshot);

      final loaded = loadMarkerTemplate(bundle);
      if (loaded is! MarkerTemplateLoaded) fail('marker template: $loaded');
      final service = VisionService<InspectionRequest, InspectionRecognition>(
        runtimeDirectory: bundle,
        jobFactory: inspectionRecognitionJobFactory,
        templates: [loaded.template],
        platformFactory: _bundleCapture,
        registryFactory: _bundleFrames,
      );
      final results = <ReplayFrameResult>[];
      try {
        final failure = await service.start().timeout(
          _jobLimit,
          onTimeout: () => fail('start did not answer; state ${service.state}'),
        );
        expect(failure, isNull, reason: failure?.message);

        Future<(InspectionRecognition, int)> recognise(
          ReplayFrame f,
          BgrxImage image,
          InspectionFrameKind kind,
        ) async {
          final watch = Stopwatch()..start();
          final answer = await service
              .submit(
                VisionImage(
                  image.bytes,
                  width: image.width,
                  height: image.height,
                  stride: image.stride,
                  channels: 4,
                ),
                InspectionRequest(
                  kind: kind,
                  clientWidth: f.clientWidth,
                  clientHeight: f.clientHeight,
                ),
              )
              .timeout(
                _jobLimit,
                onTimeout: () =>
                    fail('${f.id}: ${kind.name} job did not answer'),
              );
          watch.stop();
          if (answer is! VisionDelivered<InspectionRecognition>) {
            fail('${f.id}: ${kind.name} job answered $answer');
          }
          return (answer.result, watch.elapsedMilliseconds);
        }

        for (final (:directory, :session) in sessions) {
          for (final f in session.frames) {
            final full = decodePngBgrx(
              File('$directory$sep${f.image}').readAsBytesSync(),
            );
            if (full.width != f.clientWidth || full.height != f.clientHeight) {
              fail(
                '${f.id}: image ${full.width}x${full.height} does not match '
                'the client ${f.clientWidth}x${f.clientHeight}',
              );
            }
            final band = replayBand(
              clientWidth: f.clientWidth,
              clientHeight: f.clientHeight,
              cursorX: f.cursorX,
              cursorY: f.cursorY,
            );
            if (band == null) fail('${f.id}: band lies outside the client');

            // Each pass is matched alone, so the targeted outcome is not
            // rescued by full-client evidence.
            final (targeted, targetedMs) = await recognise(
              f,
              full.crop(band),
              InspectionFrameKind.targeted,
            );
            final targetedOutcome = await matchRecognitionOffUi(
              index,
              targeted: targeted,
              mode: snapshot.mode,
            );
            final (wholeClient, fullMs) = await recognise(
              f,
              full,
              InspectionFrameKind.fullClient,
            );
            final fullOutcome = await matchRecognitionOffUi(
              index,
              targeted: null,
              fullClient: wholeClient,
              mode: snapshot.mode,
            );

            results.add(
              ReplayFrameResult(
                frameId: f.id,
                session: directory,
                band: band,
                targetedAccepted: _accepted(targetedOutcome),
                fullClientAccepted: _accepted(fullOutcome),
                targetedRejectReason: _rejectReason(targetedOutcome),
                fullClientRejectReason: _rejectReason(fullOutcome),
                targetedMs: targetedMs,
                fullClientMs: fullMs,
                // The full image is the whole client, so its frame pixels
                // are client pixels.
                fullWinnerInBand: switch (fullOutcome) {
                  OutcomeAccepted(:final evidence) => markerInsideBand(
                    band,
                    evidence.markerX,
                    evidence.markerY,
                  ),
                  OutcomeRejected() => null,
                },
              ),
            );
          }
        }
      } finally {
        await service.close();
      }

      final report = buildReplayReport(sessions: sessions, results: results);
      if (refusal() case final reason?) fail('refusing to write: $reason');
      File(reportPath).parent.createSync(recursive: true);
      writeViaTemp(
        reportPath,
        const JsonEncoder.withIndent('  ').convert(report),
      );
      // ignore: avoid_print
      print('replay summary: ${jsonEncode(report['summary'])}');
      // ignore: avoid_print
      print('replay report: $reportPath');

      final conflicts = summariseReplay(results).conflicts;
      expect(
        conflicts,
        isEmpty,
        reason: 'targeted accepts the full-client pass does not: $conflicts',
      );
    },
    skip: skip,
    timeout: Timeout.none,
  );
}

/// Why an input named by the variables is missing, or null when all exist.
///
/// Checked before the test is declared, so a missing bundle, recording folder
/// or catalog skips with its path instead of loading anything.
String? _missingInput(String bundle, List<String> sessionDirs, String catalog) {
  final sep = Platform.pathSeparator;
  if (!Directory(bundle).existsSync()) return 'No Release bundle at $bundle.';
  if (sessionDirs.isEmpty) return 'BLACKGRID_RECORDING_DIRS names no folder.';
  for (final dir in sessionDirs) {
    if (!File('$dir$sep$scanFramesFileName').existsSync()) {
      return 'No recording session at $dir (no $scanFramesFileName).';
    }
  }
  if (!File(catalog).existsSync()) return 'No catalog at $catalog.';
  return null;
}

String? _accepted(RecognitionOutcome<Object?> outcome) => switch (outcome) {
  OutcomeAccepted(:final match) => match.bestId,
  OutcomeRejected() => null,
};

String? _rejectReason(RecognitionOutcome<Object?> outcome) => switch (outcome) {
  OutcomeAccepted() => null,
  OutcomeRejected(:final reason) => reason.name,
};
