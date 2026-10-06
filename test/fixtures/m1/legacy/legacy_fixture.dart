import 'dart:convert';

Map<String, Object?> syntheticSettings({int version = 3, int scanner = 1}) => {
  'SchemaVersion': version,
  'Mode': 'PvE',
  'LastSelectedMap': 'customs',
  'SaveMarkerFilters': true,
  'MarkerFilters': {'Labels': true, 'CustomPins': true},
  'Scanner': {
    'Version': scanner,
    'TrackerProgressEnabled': true,
    'ScanHotkey': 'SYNTHETIC',
  },
  'CustomPinsByMap': {
    'customs': [
      {'id': 'synthetic-pin', 'normalizedX': 1.2, 'normalizedY': -.2},
    ],
  },
  'CustomPinCoordinateRevisions': {'customs': 0},
  'ProtectedToken': 'NOT_A_TOKEN_SYNTHETIC_EXCLUDED',
  'OverlayCenterOnPlayer': true,
};
Map<String, Object?> activity({
  String id = 'synthetic-unmatched',
  Object mode = 'PvE',
  Object source = 'ManualSearch',
  int? revision = 1,
  String time = '2026-10-06T00:00:00Z',
}) => {
  'ItemId': id,
  'Mode': mode,
  'Source': source,
  'ActivityAtUtc': time,
  'ActivityRevision': ?revision,
  'FIR': true,
  'Price': 123,
  'Progress': 'SYNTHETIC_EXCLUDED',
};
Map<String, Object?> syntheticHistory({
  int version = 1,
  List<Map<String, Object?>>? rows,
}) => {
  'SchemaVersion': version,
  'FileRevision': 7,
  'Rows': rows ?? [activity()],
};
Map<String, List<int>> legacyBytes({
  Map<String, Object?>? settings,
  Map<String, Object?>? history,
}) => {
  if (settings != null) 'settings': utf8.encode(jsonEncode(settings)),
  if (history != null) 'history': utf8.encode(jsonEncode(history)),
};
