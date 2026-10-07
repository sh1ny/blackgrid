import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/vision_self_check.dart';
import 'package:blackgrid/data/vision/vision_runtime.dart'
    show visionManifestPath;
import 'package:flutter_test/flutter_test.dart';

import '../data/vision/vision_runtime_test.dart' show Fixture;

// Stub workers are top-level so they can be spawned in a helper isolate.

void passingWorker(SelfCheckRequest request) {
  for (final name in ['verify', 'load', 'match', 'ocr', 'dispose']) {
    request.sendProgress(name);
    request.sendStep(
      SelfCheckStepResult(name: name, ok: true, ms: 1, detail: 'ok $name'),
    );
    if (name == 'load') {
      request.sendIdentity({
        'files': [
          {'path': 'blackgrid_vision.dll', 'sha256': 'abc'},
        ],
        'tesseractVersion': '5.0.0',
        'visionAbi': 1,
        'loadedModulePaths': ['C:/bundle/blackgrid_vision.dll'],
      });
    }
  }
  request.sendDone();
}

void failingWorker(SelfCheckRequest request) {
  request.sendProgress('verify');
  request.sendStep(
    const SelfCheckStepResult(
      name: 'verify',
      ok: false,
      ms: 2,
      failure: {'kind': 'missingFile', 'message': 'missing eng.traineddata'},
      detail: 'verify failed',
    ),
  );
  request.sendDone();
}

void blockingWorker(SelfCheckRequest request) {
  request.sendProgress('verify');
  request.sendStep(
    const SelfCheckStepResult(name: 'verify', ok: true, ms: 1, detail: ''),
  );
  request.sendProgress('ocr');
  // Models a native call that does not return within the watchdog.
  sleep(const Duration(seconds: 3));
}

// Sends bulky messages, then done, then returns at once: done must still win
// over the exit notification.
void chattyPassingWorker(SelfCheckRequest request) {
  for (var i = 0; i < 50; i++) {
    request.sendProgress('verify $i ${'x' * 20000}');
  }
  request.sendStep(
    const SelfCheckStepResult(name: 'verify', ok: true, ms: 1, detail: ''),
  );
  request.sendDone();
}

void silentWorker(SelfCheckRequest request) {
  request.sendProgress('verify');
}

void neverCalledWorker(SelfCheckRequest request) {
  File('${request.runtimeDirectory}/worker-ran').writeAsStringSync('x');
}

void main() {
  late Directory dir;
  late String reportPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bgselfcheck');
    reportPath = '${dir.path}${Platform.pathSeparator}vision.json';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, dynamic> readReport() =>
      jsonDecode(File(reportPath).readAsStringSync()) as Map<String, dynamic>;

  test('blocking stub step yields timeout report and code 3', () async {
    final code = await runVisionSelfCheck(
      ['--vision-self-check', reportPath],
      watchdog: const Duration(milliseconds: 400),
      runtimeDirectory: dir.path,
      worker: blockingWorker,
    );
    expect(code, 3);
    final report = readReport();
    expect(report['result'], 'fail');
    final steps = (report['steps'] as List).cast<Map<String, dynamic>>();
    expect(steps.first['name'], 'verify');
    expect(steps.first['ok'], isTrue);
    final last = steps.last;
    expect(last['name'], 'ocr');
    expect(last['ok'], isFalse);
    expect((last['failure'] as Map)['kind'], 'timeout');
    expect(File('$reportPath.tmp').existsSync(), isFalse);
  });

  test('missing path or directory returns code 2 before loading', () async {
    final usage = <String>[];
    Future<int> run(List<String> args) => runVisionSelfCheck(
      args,
      runtimeDirectory: dir.path,
      worker: neverCalledWorker,
      writeUsage: usage.add,
    );

    expect(await run(['--vision-self-check']), 2);
    final missingDir =
        '${dir.path}${Platform.pathSeparator}nope${Platform.pathSeparator}r.json';
    expect(await run(['--vision-self-check', missingDir]), 2);
    expect(await run(['--vision-self-check', reportPath, 'extra']), 2);

    expect(File('${dir.path}/worker-ran').existsSync(), isFalse);
    expect(File(reportPath).existsSync(), isFalse);
    expect(usage, hasLength(3));
    expect(usage.first, contains('Start-Process -Wait -PassThru'));
    expect(usage.first, contains('start /wait'));
  });

  test('report path that would overwrite a runtime input is refused', () async {
    final usage = <String>[];
    final manifest = File('${dir.path}/$visionManifestPath')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"keep":true}');
    final code = await runVisionSelfCheck(
      ['--vision-self-check', manifest.path],
      runtimeDirectory: dir.path,
      worker: neverCalledWorker,
      writeUsage: usage.add,
    );
    expect(code, 2);
    expect(usage.single, contains('Refusing report path'));
    expect(manifest.readAsStringSync(), '{"keep":true}');
    expect(File('${dir.path}/worker-ran').existsSync(), isFalse);
  });

  test('done sent just before the worker exits is never lost', () async {
    for (var run = 0; run < 20; run++) {
      final code = await runVisionSelfCheck(
        ['--vision-self-check', reportPath],
        runtimeDirectory: dir.path,
        worker: chattyPassingWorker,
      );
      expect(
        code,
        0,
        reason: 'run $run: ${File(reportPath).readAsStringSync()}',
      );
    }
  });

  test('worker that exits without done fails with code 1', () async {
    final code = await runVisionSelfCheck(
      ['--vision-self-check', reportPath],
      runtimeDirectory: dir.path,
      worker: silentWorker,
    );
    expect(code, 1);
    expect(
      File(reportPath).readAsStringSync(),
      contains('helper isolate exited without a result'),
    );
  });

  test('report has format identity steps and result mirroring code', () async {
    final pass = await runVisionSelfCheck(
      ['--vision-self-check', reportPath],
      runtimeDirectory: dir.path,
      worker: passingWorker,
    );
    expect(pass, 0);
    var report = readReport();
    expect(report['format'], 1);
    expect(DateTime.parse(report['startedAt'] as String), isA<DateTime>());
    expect(report['result'], 'pass');
    final identity = report['runtimeIdentity'] as Map<String, dynamic>;
    expect(identity['tesseractVersion'], '5.0.0');
    expect(identity['visionAbi'], 1);
    expect((identity['files'] as List).single, {
      'path': 'blackgrid_vision.dll',
      'sha256': 'abc',
    });
    expect(identity['loadedModulePaths'], ['C:/bundle/blackgrid_vision.dll']);
    final steps = (report['steps'] as List).cast<Map<String, dynamic>>();
    expect(steps.map((s) => s['name']), [
      'verify',
      'load',
      'match',
      'ocr',
      'dispose',
    ]);
    expect(steps.every((s) => s['ok'] == true), isTrue);
    expect(steps.first.keys, containsAll(['name', 'ok', 'ms', 'detail']));

    final fail = await runVisionSelfCheck(
      ['--vision-self-check', reportPath],
      runtimeDirectory: dir.path,
      worker: failingWorker,
    );
    expect(fail, 1);
    report = readReport();
    expect(report['result'], 'fail');
    final failed = (report['steps'] as List).single as Map<String, dynamic>;
    expect((failed['failure'] as Map)['message'], contains('eng.traineddata'));
  });

  test('report is written to tmp then renamed; previous report survives a '
      'failed write', () async {
    expect(
      await runVisionSelfCheck(
        ['--vision-self-check', reportPath],
        runtimeDirectory: dir.path,
        worker: passingWorker,
      ),
      0,
    );
    // Only the final path remains: the tmp file was renamed away.
    expect(File('$reportPath.tmp').existsSync(), isFalse);
    final previous = File(reportPath).readAsStringSync();
    expect(previous, isNotEmpty);

    // A directory squatting on the tmp path makes the write fail.
    Directory('$reportPath.tmp').createSync();
    final code = await runVisionSelfCheck(
      ['--vision-self-check', reportPath],
      runtimeDirectory: dir.path,
      worker: failingWorker,
    );
    expect(code, 1);
    expect(File(reportPath).readAsStringSync(), previous);
  });

  test(
    'step runner names the datapath on engineInitFailed and still disposes',
    () {
      final fixture = Fixture();
      addTearDown(fixture.dispose);
      fixture.writeManifest();
      fixture.native.engine.initResult = 1;
      final steps = <SelfCheckStepResult>[];
      final progress = <String>[];
      executeSelfCheckSteps(
        _RecordingSink(steps, progress),
        runtimeDirectory: fixture.root,
        opener: (a, b, c) => fixture.native,
        loadedModulePaths: () => const [],
      );
      expect(steps.map((s) => s.name), ['verify', 'load', 'dispose']);
      final load = steps[1];
      expect(load.ok, isFalse);
      expect(load.failure!['kind'], 'engineInitFailed');
      expect(load.failure!['message'], contains('data/vision/tessdata'));
      expect(progress, ['verify', 'load', 'dispose']);
    },
  );
}

class _RecordingSink implements SelfCheckSink {
  _RecordingSink(this.steps, this.progress);

  final List<SelfCheckStepResult> steps;
  final List<String> progress;

  @override
  void sendProgress(String step) => progress.add(step);

  @override
  void sendStep(SelfCheckStepResult step) => steps.add(step);

  @override
  void sendIdentity(Map<String, Object?> identity) {}

  @override
  void sendDone() {}
}
