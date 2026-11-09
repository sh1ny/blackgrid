import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:blackgrid/application/app_services.dart';
import 'package:blackgrid/application/map_controller.dart';
import 'package:blackgrid/data/database.dart';
import 'package:blackgrid/data/raid_panel_ocr.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/maps/map_marker_icons.dart';
import 'package:blackgrid/maps/native_map_scene.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:blackgrid/ui/app.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fixtures/m1/catalog/fixture.dart';
import '../ui/support/scan_ui_support.dart';
import 'm1_harness.dart';
import 'prepared_pack_manifest.dart';

/// A small prepared pack decoded by the production loader and resource owner.
/// Marker positions are independent game coordinates, not mocked projections.
class MapWidgetHarness {
  MapWidgetHarness._(this.services, this._scanLogs);
  final AppServices services;
  final Directory? _scanLogs;

  static Future<MapWidgetHarness> create({
    String? sourceCategory,
    List<Map<String, int>>? hazardOutline,
    ScanFakePorts? scanPorts,
    RaidPanelOcr? panelOcr,
    MapMarkerIcons? markerIcons,
    List<Map<String, Object?>> extraMarkers = const [],
    List<Map<String, Object?>> extraLabels = const [],
    bool artwork = true,
    bool packFails = false,
    http.Client? client,
    MemoryCredentials? credentials,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 256, 256),
      Paint()..color = const Color(0xff253541),
    );
    canvas.drawLine(
      const Offset(0, 128),
      const Offset(256, 128),
      Paint()..color = Colors.white,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(256, 256);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    picture.dispose();
    final manifest = preparedPackManifest(
      maps: [
        for (final id in const ['shoreline', 'thelab'])
          _map(
            id,
            sourceCategory: sourceCategory,
            hazardOutline: hazardOutline,
            extraMarkers: extraMarkers,
            extraLabels: extraLabels,
          ),
      ],
    );
    final loader = PreparedMapPackLoader(
      loadBytes: packFails
          ? (path) async => throw StateError('Fixture pack is unreadable.')
          : preparedPackBytes(
              manifest,
              other: (path) async {
                if (artwork &&
                    (path == 'assets/maps/versions/fixture/base.png' ||
                        path == 'assets/maps/versions/fixture/upper.png')) {
                  return png;
                }
                throw StateError('Unknown fixture asset: $path');
              },
            ),
    );
    final wire = wireFixture();
    final scanLogs = scanPorts == null
        ? null
        : Directory.systemTemp.createTempSync('blackgrid-map-scan-');
    final services = AppServices(
      database: BlackgridDatabase(NativeDatabase.memory()),
      credentials: credentials ?? MemoryCredentials(),
      clock: () => fixtureNow,
      mapController: MapController(
        loader: loader,
        resources: NativeMapResourceOwner(loader),
      ),
      client:
          client ??
          MockClient((request) async {
            final value = wire[request.url.pathSegments.last];
            return http.Response(
              jsonEncode(value ?? {}),
              value == null ? 404 : 200,
            );
          }),
      panelOcr: panelOcr,
      markerIcons: markerIcons,
      scanLogDirectory: scanLogs,
      scanRuntimeDirectory: scanPorts == null ? null : r'C:\fake\bundle',
      scanMarkerLoader: scanPorts?.loader,
      scanCaptureFactory: scanPorts?.captureFactory,
      scanVisionFactory: scanPorts?.visionFactory,
      scanPlatformFactory: scanPorts?.platformFactory,
      scanWaiter: scanPorts?.waiter,
    );
    await services.initialize();
    await services.setMode(GameMode.pvp);
    await services.catalog.refresh();
    return MapWidgetHarness._(services, scanLogs);
  }

  Future<void> dispose() async {
    await services.dispose();
    final logs = _scanLogs;
    if (logs != null && logs.existsSync()) logs.deleteSync(recursive: true);
  }
}

Map<String, Object?> _map(
  String id, {
  String? sourceCategory,
  List<Map<String, int>>? hazardOutline,
  List<Map<String, Object?>> extraMarkers = const [],
  List<Map<String, Object?>> extraLabels = const [],
}) => {
  'id': id,
  'name': id == 'thelab' ? 'Fixture Labs' : 'Fixture Shoreline',
  'kind': 'raster',
  'geometry': {
    'bounds': [
      [0, 0],
      [256, 256],
    ],
    'rotation': 0,
    'affine': [1, 0, 1, 256],
    'projection': 'native-pixels',
    'nativeZoom': 0,
    'pinFrame': id == 'thelab' ? 'labs-native-normalized' : 'legacy-normalized',
    'coordinateRevision': id == 'thelab' ? 1 : 0,
  },
  'artworkFrame': {
    'width': 256,
    'height': 256,
    'nativeTilePixels': 256,
    'tileStride': 256,
    'tileImageExtent': 256,
  },
  'displayCrop': {'left': 0, 'top': 0, 'right': 256, 'bottom': 256},
  'floors': [
    _floor('ground', 'Ground', base: true),
    _floor('upper', 'Upper', base: false),
  ],
  'markers': [
    _marker(
      'ground-exit',
      'Ground exit',
      'ground',
      'extracts',
      'PmcExtracts',
      128,
      128,
    ),
    _marker(
      'upper-exit',
      'Upper exit',
      'upper',
      'extracts',
      'PmcExtracts',
      192,
      192,
    ),
    {
      ..._marker(
        'ground-hazard',
        'Ground hazard',
        'ground',
        sourceCategory ?? 'hazards',
        sourceCategory ?? 'Hazards',
        64,
        192,
      ),
      'outline': ?hazardOutline,
    },
    ...extraMarkers,
  ],
  'labels': extraLabels,
  'attribution': {'author': 'Deterministic test fixture'},
};

Map<String, Object?> _floor(String id, String label, {required bool base}) => {
  'id': id,
  'label': label,
  'base': base,
  'manual': true,
  'exclusive': false,
  'attachedIds': <String>[],
  'artwork': {
    'tiles': [
      {'x': 0, 'y': 0, 'empty': false, 'path': base ? 'base.png' : 'upper.png'},
    ],
  },
};

Map<String, Object?> _marker(
  String id,
  String name,
  String floor,
  String category,
  String filter,
  int x,
  int z,
) => {
  'id': id,
  'name': name,
  'floorId': floor,
  'category': category,
  'filterKey': filter,
  'position': {'x': x, 'z': z},
  'details': {'description': '$name offline fixture details'},
  'source': {'fixture': true},
};

/// Pumps the map application with a prepared fixture and real application
/// services. Set [autoDispose] to false when a test must dispose the harness
/// before constructing a second database.
Future<MapWidgetHarness> pumpMapFixture(
  WidgetTester tester, {
  Size size = const Size(1912, 823),
  double scale = 1,
  String? sourceCategory,
  List<Map<String, int>>? hazardOutline,
  ScanFakePorts? scanPorts,
  RaidPanelOcr? panelOcr,
  List<Map<String, Object?>> extraMarkers = const [],
  bool artwork = true,
  bool packFails = false,
  http.Client? client,
  MemoryCredentials? credentials,
  bool autoDispose = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final harness = (await tester.runAsync(
    () => MapWidgetHarness.create(
      sourceCategory: sourceCategory,
      hazardOutline: hazardOutline,
      scanPorts: scanPorts,
      panelOcr: panelOcr,
      extraMarkers: extraMarkers,
      artwork: artwork,
      packFails: packFails,
      client: client,
      credentials: credentials,
    ),
  ))!;
  if (autoDispose) addTearDown(harness.dispose);
  await tester.pumpWidget(BlackgridApp(services: harness.services));
  await settleMapFixture(tester, harness);
  return harness;
}

/// Native image codecs run outside FakeAsync; ordinary pumps still drive UI.
Future<void> settleMapFixture(
  WidgetTester tester,
  MapWidgetHarness harness,
) async {
  await tester.pump();
  final elapsed = Stopwatch()..start();
  while (harness.services.maps.loading) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError('Fixture artwork did not finish loading.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
