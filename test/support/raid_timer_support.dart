import 'dart:io';

import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'm1_harness.dart';

/// The clock the raid timer widget tests run on, in the log's local time.
final timerNow = DateTime(2026, 10, 31, 22, 15, 34);

/// Gives the catalog wire a 25:00 scav cooldown and a Fence trader whose
/// reputation 0 level has modifier 1, so the scav entry can be computed.
void addScavCooldown(Map<String, dynamic> wire) {
  (wire['items']['data'] as Map)['settings'] = {'scavCooldownSeconds': 1500};
  (wire['traders']['data'] as Map)['trader-fence'] = {
    'id': 'trader-fence',
    'name': 'trader-fence Nickname',
    'normalizedName': 'fence',
    'reputationLevels': [
      {'minimumReputation': 0, 'scavCooldownModifier': 1},
    ],
  };
}

/// Pumps the whole app on [timerNow] with scav cooldown data in the catalog.
///
/// [mode] is the saved mode the app starts in; pass `GameMode.unknown` to let
/// the logs decide the active mode.
Future<M1Harness> pumpTimerApp(
  WidgetTester tester, {
  GameMode mode = GameMode.pvp,
}) async {
  tester.view.physicalSize = const Size(1672, 941);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = (await tester.runAsync(() async {
    final result = M1Harness(clock: () => timerNow, shapeWire: addScavCooldown);
    await result.initialize(mode: mode);
    return result;
  }))!;
  addTearDown(h.dispose);
  await tester.pumpWidget(BlackgridApp(services: h.services));
  await tester.pumpAndSettle();
  return h;
}

/// Writes a session folder whose application log holds [lines] (each a
/// `HH:mm:ss.SSS` time and a message) and points the log input at it.
Future<void> useLogLines(
  WidgetTester tester,
  M1Harness h,
  List<(String, String)> lines,
) async {
  final root = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('blackgrid-timer-ui-'),
  ))!;
  addTearDown(() => root.delete(recursive: true));
  await tester.runAsync(() async {
    final folder = await Directory(
      '${root.path}${Platform.pathSeparator}log_2026.10.31_22-00-00_1.3.0.0.48484',
    ).create();
    final text = StringBuffer();
    for (final (time, message) in lines) {
      text.writeln('2026-10-31 $time|1.3.0.0.48484|Info|application|$message');
    }
    await File('${folder.path}${Platform.pathSeparator}application_000.log')
        .writeAsString(text.toString(), flush: true);
    await File('${folder.path}${Platform.pathSeparator}backend_000.log')
        .writeAsString('', flush: true);
    await h.services.settings.setMapInputs(gameLogDirectory: root.path);
  });
}

/// A raid that started at 22:03:00, so at [timerNow] it is 12:34 old.
const runningRaidLines = [
  ('22:00:30.000', 'PrepareSelectedProfileLocally ProfileId:aaaa AccountId:1'),
  ('22:02:00.000', 'Matching with group id: 1'),
  ('22:03:00.000', 'GameStarted: 7'),
];

/// Pumps until [done], letting real file I/O progress between frames.
///
/// Log reading crosses an isolate, so a bounded poll is the only signal.
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  final elapsed = Stopwatch()..start();
  while (!done()) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError('The app did not reach the expected state.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
