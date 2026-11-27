import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Runs [work] in the test zone, pumping frames while real time passes, until
/// it completes.
///
/// A mounted Map reads local progress, and that read only finishes while
/// frames are pumped and real file and database I/O progresses, which crosses
/// an isolate. The widget test's outer timeout is the hang guard.
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
  while (!done) {
    await tester.runAsync(() => Future<void>(() {}));
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
