import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/support/scan_ui_support.dart';
import 'm1_harness.dart';

Future<M1Harness> pumpM1(
  WidgetTester tester, {
  Size size = const Size(1672, 941),
  double scale = 1,
  GameMode mode = GameMode.pvp,
  ScanFakePorts? scanPorts,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  // Create native/external async resources in the real zone too; constructing
  // them under FakeAsync can strand initialization before runAsync returns.
  final h = (await tester.runAsync(() async {
    final result = M1Harness(scanPorts: scanPorts);
    await result.initialize(mode: mode);
    return result;
  }))!;
  addTearDown(h.dispose);
  await tester.pumpWidget(BlackgridApp(services: h.services));
  await tester.pumpAndSettle();
  return h;
}

Future<void> tapM1Async(
  WidgetTester tester,
  Finder target,
  bool Function() completed,
) async {
  // Start external I/O in the real zone, but still drive the actual UI tap.
  await tester.runAsync(() => tester.tap(target));
  final elapsed = Stopwatch()..start();
  while (!completed()) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError('M1 UI action did not complete within 10 seconds.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
