import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/data/scan_frame_recorder.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:blackgrid/ui/panels.dart';
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
  ScanFrameRecorder? scanFrameRecorder,
  BlackgridDatabase? database,
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
    final result = M1Harness(
      scanPorts: scanPorts,
      scanFrameRecorder: scanFrameRecorder,
      database: database,
    );
    await result.initialize(mode: mode);
    return result;
  }))!;
  addTearDown(h.dispose);
  await tester.pumpWidget(BlackgridApp(services: h.services));
  await tester.pumpAndSettle();
  return h;
}

/// Opens the shared inspector and brings its named panel into view.
Future<void> showInspectorPanel(WidgetTester tester, String title) async {
  if (find.byKey(const Key('shell-inspector')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
  }
  final inspector = find.byKey(const Key('shell-inspector'));
  final scrollable = find
      .descendant(of: inspector, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final targetOffset = switch (title) {
    'Data sources' => 850.0,
    'Recent item activity' => position.maxScrollExtent,
    _ => 0.0,
  };
  position.jumpTo(targetOffset.clamp(0, position.maxScrollExtent));
  await tester.pumpAndSettle();
  final panel = find.byWidgetPredicate(
    (w) => w is GridPanel && w.title == title,
  );
  expect(panel, findsOneWidget);
  await tester.ensureVisible(panel);
  await tester.pumpAndSettle();
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
