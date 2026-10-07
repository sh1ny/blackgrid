import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/credential_store.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/settings.dart';
import 'package:blackgrid/ui/app.dart';

// Run explicitly with Flutter --profile or --release. This exercises the real
// packaged map capability in the real shell, with isolated state and no HTTP.
// It is not production startup, a game listener, or a fixture-art renderer.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Native map qualification prohibits HTTP');
}

class _NoRequests extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(StateError('Native map qualification prohibits HTTP'));
}

class _NoCredentials implements CredentialStore {
  @override
  Future<String?> readCredential(GameMode mode) async => null;
  @override
  Future<void> writeCredential(GameMode mode, String token) async =>
      throw StateError('Qualification has no credentials');
  @override
  Future<void> removeCredential(GameMode mode) async {}
}

Future<void> _requireGameClosed() async {
  // Process names only; no game handles, windows, memory or other internals.
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    r'Get-Process | Where-Object { $_.ProcessName -match "^(EscapeFromTarkov(?:_BE)?|EFT)$" } | Select-Object -ExpandProperty ProcessName',
  ]);
  if (result.exitCode != 0 || (result.stdout as String).trim().isNotEmpty) {
    throw StateError(
      'EFT closure cannot be confirmed; native verification prohibited',
    );
  }
}

Future<void> _ready(AppServices services) async {
  final clock = Stopwatch()..start();
  while (services.maps.loading || services.maps.scene == null) {
    if (services.maps.error != null) throw StateError(services.maps.error!);
    if (clock.elapsed > const Duration(seconds: 10)) {
      throw StateError('Map scene availability exceeded 10 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  await SchedulerBinding.instance.endOfFrame;
}

double _p95(List<double> values) {
  if (values.isEmpty) throw StateError('No actual frames observed');
  final sorted = values.toList()..sort();
  return sorted[((sorted.length * .95).ceil() - 1).clamp(0, sorted.length - 1)];
}

Future<void> main() async {
  await _requireGameClosed();
  HttpOverrides.global = _NoNetwork();
  WidgetsFlutterBinding.ensureInitialized();
  final services = AppServices(
    database: BlackgridDatabase(NativeDatabase.memory()),
    credentials: _NoCredentials(),
    client: _NoRequests(),
  );
  final expectedMapIds = supportedMaps.toSet();
  await services.initialize();
  final actualMapIds = services.maps.maps.map((map) => map.id).toSet();
  if (actualMapIds.length != expectedMapIds.length ||
      !actualMapIds.containsAll(expectedMapIds)) {
    await services.dispose();
    throw StateError(
      'All-map qualification requires exactly the supported inventory; '
      'missing: ${expectedMapIds.difference(actualMapIds)}, '
      'unexpected: ${actualMapIds.difference(expectedMapIds)}',
    );
  }
  final initialMapClock = Stopwatch()..start();
  await services.settings.setMap('interchange');
  runApp(BlackgridApp(services: services));
  await _ready(services);
  final cold = <String, int>{
    'interchange': initialMapClock.elapsedMilliseconds,
  };
  await Future<void>.delayed(const Duration(seconds: 1));
  final floors = <String, List<int>>{};
  final warmFloors = <double>[];
  final cycles = <Map<String, Object?>>[];
  final timings = <ui.FrameTiming>[];
  final timingsByMap = <String, List<ui.FrameTiming>>{};
  String? recordingMap;
  void record(List<ui.FrameTiming> frames) {
    final mapId = recordingMap;
    if (mapId == null) return;
    timings.addAll(frames);
    timingsByMap.putIfAbsent(mapId, () => []).addAll(frames);
  }

  SchedulerBinding.instance.addTimingsCallback(record);
  try {
    for (var cycle = 0; cycle < 5; cycle++) {
      await _requireGameClosed();
      for (final mapId in supportedMaps) {
        final clock = Stopwatch()..start();
        await services.settings.setMap(mapId);
        services.maps.fit();
        await _ready(services);
        if (cycle == 0 && mapId != 'interchange') {
          cold[mapId] = clock.elapsedMilliseconds;
        }
        final floorTimes = <int>[];
        for (final floor in services.maps.preparedMap!.floorPolicy.floors) {
          clock.reset();
          services.maps.toggleFloor(floor.id);
          await _ready(services);
          floorTimes.add(clock.elapsedMilliseconds);
          if (cycle > 0) warmFloors.add(clock.elapsedMicroseconds / 1000);
          // A second toggle returns base+overlay maps to their prior composition;
          // exclusive Icebreaker instead restores its real Infirmary base.
          services.maps.toggleFloor(floor.id);
          await _ready(services);
        }
        if (cycle == 0) floors[mapId] = floorTimes;
        services.maps.fit();
        await _ready(services);
        // Let the native timings batch flush before and after the measured path.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        recordingMap = mapId;
        for (var frame = 0; frame < 120; frame++) {
          final viewport = services.maps.viewportSize;
          final cursor = ViewportPoint(viewport.width / 2, viewport.height / 2);
          services.maps.panBy(frame.isEven ? 2 : -2, frame.isEven ? 1 : -1);
          services.maps.zoomAt(cursor, frame.isEven ? 1.005 : 1 / 1.005);
          await _ready(services);
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        recordingMap = null;
        if (services.scans.hasAcceptedScan) {
          throw StateError('Map qualification emitted a scanner acceptance');
        }
        cycles.add({
          'cycle': cycle,
          'map': mapId,
          'accountedBytes': services.maps.resources.accountedBytes,
          'pictureApproximateBytes':
              services.maps.resources.pictureApproximateBytes,
          'decodedRasterBytes': services.maps.resources.imageDecodedBytes,
          'resources': services.maps.resources.retainedResourceCount,
          'processResidentBytes': ProcessInfo.currentRss,
          'processPeakResidentBytes': ProcessInfo.maxRss,
        });
      }
    }
    final build = [
      for (final frame in timings) frame.buildDuration.inMicroseconds / 1000,
    ];
    final raster = [
      for (final frame in timings) frame.rasterDuration.inMicroseconds / 1000,
    ];
    final buildP95 = _p95(build),
        rasterP95 = _p95(raster),
        floorP95 = _p95(warmFloors);
    stdout.writeln(
      'BLACKGRID_M5_NATIVE_METRICS ${jsonEncode({
        'network': 'HttpClient creation forbidden',
        'packVersion': (await services.maps.loader.load()).version,
        'viewport': {'width': services.maps.viewportSize.width, 'height': services.maps.viewportSize.height},
        'devicePixelRatio': ui.PlatformDispatcher.instance.views.first.devicePixelRatio,
        'coldSceneMs': cold,
        'firstFloorSwitchMs': floors,
        'warmFloorSwitchP95Ms': floorP95,
        'actualFrames': timings.length,
        'buildP95Ms': buildP95,
        'rasterP95Ms': rasterP95,
        'framesByMap': {
          for (final entry in timingsByMap.entries) entry.key: {
              'frames': entry.value.length,
              'buildP95Ms': _p95([for (final frame in entry.value) frame.buildDuration.inMicroseconds / 1000]),
              'rasterP95Ms': _p95([for (final frame in entry.value) frame.rasterDuration.inMicroseconds / 1000]),
            },
        },
        'cycles': cycles,
        'processMemoryMeasurement': 'dart:io ProcessInfo resident set; GPU memory is not measured',
        'acceptedScan': services.scans.hasAcceptedScan,
        'fixedBudgetResult': {'build': buildP95 <= 16.7, 'raster': rasterP95 <= 16.7, 'warmFloorSwitch': floorP95 <= 200, 'coldScene': cold.values.every((ms) => ms <= 2000), 'resources': cycles.every((row) => (row['accountedBytes'] as int) <= 192 * 1024 * 1024)},
      })}',
    );
    await services.settings.setMap('interchange');
    services.maps.fit();
    await _ready(services);
    stdout.writeln(
      'BLACKGRID_M5_NATIVE_READY — actual Map shell remains open for UI inspection',
    );
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(record);
  }
}
