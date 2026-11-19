import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Runs [work] in the test zone, pumping frames while real time passes, until
/// it completes.
///
/// A mounted Map reads local progress, and that read only finishes while
/// frames are pumped and real file and database I/O progresses, which crosses
/// an isolate. Waiting on such work without pumping, as a plain
/// `addTearDown(services.dispose)` does, never returns. The poll is bounded:
/// it throws after 10 seconds.
Future<void> pumpUntilComplete(
  WidgetTester tester,
  Future<void> Function() work,
) async {
  var done = false;
  Object? failure;
  StackTrace? failureStack;
  unawaited(
    work().then<void>(
      (_) => done = true,
      onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        done = true;
      },
    ),
  );
  final elapsed = Stopwatch()..start();
  while (!done) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError('The work did not complete within 10 seconds.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  if (failure case final error?) {
    Error.throwWithStackTrace(error, failureStack ?? StackTrace.empty);
  }
}

/// Registers [dispose] as a tear-down that pumps until it completes.
///
/// Use it for app services whose widgets were mounted by the test, so a
/// progress read the mounted Map left queued can finish before the services
/// close.
void addPumpedTearDown(WidgetTester tester, Future<void> Function() dispose) =>
    addTearDown(() => pumpUntilComplete(tester, dispose));
