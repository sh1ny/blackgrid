import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../domain/catalog.dart';
import '../domain/import_preview.dart';
import '../domain/map_coordinates.dart';
import '../domain/settings.dart';
import 'database.dart';
import 'wire_json.dart';

class LegacyImport {
  const LegacyImport(this.database);
  final BlackgridDatabase database;

  /// Parses the selected legacy files into a preview against the stored data.
  ///
  /// Stored pins and history rows that cannot be read are left out of the
  /// comparison, so the preview may report a record as added while a commit
  /// that keeps existing data keeps the unreadable row instead. An unreadable
  /// settings record compares as the default settings.
  Future<ImportPreview> previewFiles({
    String? settingsPath,
    String? historyPath,
  }) async {
    final sources = <String, List<int>>{};
    if (settingsPath != null && settingsPath.trim().isNotEmpty) {
      sources['settings'] = await File(settingsPath).readAsBytes();
    }
    if (historyPath != null && historyPath.trim().isNotEmpty) {
      sources['history'] = await File(historyPath).readAsBytes();
    }
    if (sources.isEmpty) {
      throw const FormatException('Select explicit settings or history files.');
    }
    final settings = (await database.readSettings()).settings;
    final hasSettings = await database
        .customSelect('SELECT id FROM preferences WHERE id = 1')
        .get();
    final pins = (await database.readPins()).pins;
    final history = (await database.readActivity()).rows;
    final paths = [
      if (sources.containsKey('settings')) settingsPath!,
      if (sources.containsKey('history')) historyPath!,
    ];
    final destinationSettings = hasSettings.isEmpty ? null : settings;
    final result = await _parseLegacyOffRender(
      sources,
      destinationSettings,
      pins,
      history,
      paths,
    );
    return ImportPreview(
      digest: result.digest,
      settings: result.settings,
      pins: result.pins,
      winningActivity: result.winningActivity,
      accounting: result.accounting,
      exclusions: result.exclusions,
      sourcePaths: result.sourcePaths,
      alreadyImported: await database.wasImported(result.digest),
    );
  }

  Future<void> commit(ImportPreview preview, {required bool replaceExisting}) =>
      database.commitImport(preview, replaceExisting: replaceExisting);
}

// Keep SQLite QueryRow objects and the owning importer/database outside the
// isolate closure's context; only materialized immutable records cross it.
Future<ImportPreview> _parseLegacyOffRender(
  Map<String, List<int>> sources,
  AppSettings? settings,
  List<CustomPin> pins,
  List<ItemActivity> history,
  List<String> paths,
) => Isolate.run(
  () => parseLegacySources(
    sources,
    destinationSettings: settings,
    destinationPins: pins,
    destinationActivity: history,
    sourcePaths: paths,
  ),
);

ImportPreview parseLegacySources(
  Map<String, List<int>> sources, {
  AppSettings? destinationSettings,
  List<CustomPin> destinationPins = const [],
  List<ItemActivity> destinationActivity = const [],
  List<String> sourcePaths = const [],
}) {
  try {
    final digestInput = BytesBuilder()
      ..add(utf8.encode('blackgrid-legacy-import:1\n'));
    for (final key in ['settings', 'history']) {
      final bytes = sources[key];
      if (bytes != null) {
        digestInput
          ..add(utf8.encode('$key:${bytes.length}\n'))
          ..add(bytes);
      }
    }
    final digest = sha256.convert(digestInput.takeBytes()).toString();
    ImportedPreferences? settings;
    final pins = <CustomPin>[];
    final activity = <ItemActivity>[];
    final accounting = <ImportAccounting>[];
    final exclusions = <String>{};
    if (sources['settings'] case final bytes?) {
      final root = decodeWireObject(utf8.decode(bytes));
      _version(root, 'SchemaVersion', 3);
      final scanner = root.containsKey('Scanner')
          ? _object(root['Scanner'])
          : <String, dynamic>{};
      _version(scanner, 'Version', 1);
      final mode = root.containsKey('Mode')
          ? _mode(root['Mode'], allowUnknown: true)
          : GameMode.unknown;
      final map =
          !root.containsKey('LastSelectedMap') || root['LastSelectedMap'] == ''
          ? 'shoreline'
          : _map(root['LastSelectedMap']);
      final filters = <String, bool>{};
      if (root.containsKey('MarkerFilters')) {
        final raw = _object(root['MarkerFilters']);
        for (final key in raw.keys) {
          if (!markerCategories.contains(key)) {
            throw const FormatException('Unsupported marker category.');
          }
          filters[key] = _boolean(raw[key]);
        }
      }
      // Local inputs are never part of the preview; the commit takes them
      // from the stored settings.
      settings = ImportedPreferences(
        mode: mode,
        selectedMap: map,
        saveMarkerFilters: root.containsKey('SaveMarkerFilters')
            ? _boolean(root['SaveMarkerFilters'])
            : false,
        markerFilters: filters,
        trackerEnabled: scanner.containsKey('TrackerProgressEnabled')
            ? _boolean(scanner['TrackerProgressEnabled'])
            : false,
      );
      accounting.add(
        ImportAccounting(
          kind: 'settings',
          key: 'supported preferences',
          inputOrder: 0,
          disposition: destinationSettings == null
              ? 'add'
              : 'destination conflict',
          reason: destinationSettings == null ? 'Settings will be added.' : 'Your current settings are kept unless you choose to replace them.',
        ),
      );
      final revisions = root.containsKey('CustomPinCoordinateRevisions')
          ? _object(root['CustomPinCoordinateRevisions'])
          : <String, dynamic>{};
      final normalizedRevisions = <String, int>{};
      for (final entry in revisions.entries) {
        final key = _map(entry.key);
        final revision = _integer(entry.value);
        if (normalizedRevisions.containsKey(key)) {
          throw const FormatException(
            'The same map appears twice in the pin positions.',
          );
        }
        if ((key == 'thelab' && revision != 0 && revision != 1) ||
            (key != 'thelab' && revision != 0)) {
          throw const FormatException('Unsupported coordinate revision.');
        }
        normalizedRevisions[key] = revision;
      }
      final groups = root.containsKey('CustomPinsByMap')
          ? _object(root['CustomPinsByMap'])
          : <String, dynamic>{};
      final destinationPinKeys = {
        if (groups.isNotEmpty)
          for (final pin in destinationPins) (pin.mapId, pin.id),
      };
      final seen = <String>{};
      for (final entry in groups.entries) {
        final mapId = _map(entry.key);
        final revision = normalizedRevisions[mapId] ?? 0;
        for (final value in _array(entry.value)) {
          final raw = _object(value);
          final id = _string(raw['id']);
          final key = '$mapId:$id';
          if (!seen.add(key)) {
            throw const FormatException('The same pin appears twice.');
          }
          var x = _number(raw['normalizedX']).toDouble();
          var y = _number(raw['normalizedY']).toDouble();
          if (mapId == 'thelab' && revision == 0) {
            final converted = convertLabsLegacy(x, y);
            x = converted.$1;
            y = converted.$2;
          }
          final pin = CustomPin(
            id: id,
            mapId: mapId,
            x: x,
            y: y,
            frame: mapId == 'thelab'
                ? MapCoordinateFrame.labsNativeNormalized.wireName
                : MapCoordinateFrame.legacyNormalized.wireName,
            frameRevision: mapId == 'thelab' ? 1 : 0,
            label: id,
            updatedAt: DateTime.utc(1970),
          );
          pin.validate();
          pins.add(pin);
          final existing = destinationPinKeys.contains((mapId, id));
          accounting.add(
            ImportAccounting(
              kind: 'pin',
              key: key,
              inputOrder: pins.length,
              disposition: existing ? 'destination conflict' : 'add',
              reason: existing
                  ? 'The existing pin is kept unless you choose to replace it.'
                  : 'Position kept as saved.',
            ),
          );
        }
      }
      for (final key in root.keys) {
        if (![
          'SchemaVersion',
          'Revision',
          'Mode',
          'LastSelectedMap',
          'SaveMarkerFilters',
          'MarkerFilters',
          'Scanner',
          'CustomPinsByMap',
          'CustomPinCoordinateRevisions',
        ].contains(key)) {
          exclusions.add(key);
        }
      }
      for (final key in scanner.keys) {
        if (!['Version', 'TrackerProgressEnabled'].contains(key)) {
          exclusions.add('Scanner.$key');
        }
      }
    }
    if (sources['history'] case final bytes?) {
      final root = decodeWireObject(utf8.decode(bytes));
      _version(root, 'SchemaVersion', 1);
      if (root.containsKey('FileRevision')) _integer(root['FileRevision']);
      if (root.containsKey('Revision')) _integer(root['Revision']);
      if (root.containsKey('Rows') && root.containsKey('Entries')) {
        throw const FormatException('Ambiguous history collection aliases.');
      }
      final rows = _array(root['Rows'] ?? root['Entries']);
      for (var index = 0; index < rows.length; index++) {
        final row = _object(rows[index]);
        final item = _string(_alias(row, 'ItemId', 'CanonicalItemId'))
            .trim()
            .toLowerCase();
        final mode = _mode(row['Mode']);
        final source = switch (row['Source']) {
          'Automatic' || 'Scan' || 1 => ActivitySource.importedScan,
          'Manual' || 'ManualSearch' || 2 => ActivitySource.importedManual,
          _ => throw const FormatException('Unsupported activity source.'),
        };
        final stamp = _string(row['ActivityAtUtc']);
        if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(stamp)) {
          throw const FormatException(
            'History timestamp requires a UTC offset.',
          );
        }
        final time = DateTime.parse(stamp).toUtc();
        final revision = row.containsKey('ActivityRevision')
            ? _integer(row['ActivityRevision'])
            : index + 1;
        if (revision <= 0) {
          throw const FormatException('Activity revision must be positive.');
        }
        activity.add(
          ItemActivity(
            itemId: item,
            mode: mode,
            source: source,
            observedAt: time,
            revision: revision,
          ),
        );
        for (final key in row.keys) {
          if (![
            'ItemId',
            'CanonicalItemId',
            'Mode',
            'Source',
            'ActivityAtUtc',
            'ActivityRevision',
          ].contains(key)) {
            exclusions.add('History.$key');
          }
        }
      }
    }
    final winners = <String, int>{};
    for (var i = 0; i < activity.length; i++) {
      final row = activity[i];
      final prior = winners[row.key];
      if (prior == null ||
          row.revision > activity[prior].revision ||
          (row.revision == activity[prior].revision &&
              row.observedAt.isAfter(activity[prior].observedAt))) {
        winners[row.key] = i;
      }
    }
    final destinationByKey = <String, ItemActivity>{};
    if (activity.isNotEmpty) {
      for (final row in destinationActivity) {
        destinationByKey.putIfAbsent(row.key, () => row);
      }
    }
    for (var i = 0; i < activity.length; i++) {
      final row = activity[i];
      final winner = winners[row.key]!;
      final selected = activity[winner];
      final destination = destinationByKey[row.key];
      final sourceReason = row.revision != selected.revision
          ? 'Entry $winner wins: its revision ${selected.revision} is newer than ${row.revision}.'
          : row.observedAt != selected.observedAt
          ? 'Entry $winner wins: same revision ${row.revision}, but it was saved later.'
          : 'Entry $winner wins: same revision and time, so the earlier entry is used.';
      accounting.add(
        ImportAccounting(
          kind: 'activity',
          key: row.key,
          inputOrder: i,
          disposition: winner != i
              ? 'source collision loser'
              : destination != null
              ? 'destination conflict'
              : 'add',
          reason: winner != i
              ? sourceReason
              : destination != null
              ? 'File revision ${row.revision}, current revision ${destination.revision}. Your current entry is kept unless you choose to replace it.'
              : 'File revision ${row.revision}; kept even if the item is missing from the current item data.',
        ),
      );
    }
    final winning = winners.values.map((i) => activity[i]).toList();
    return ImportPreview(
      digest: digest,
      settings: settings,
      pins: pins,
      winningActivity: winning,
      accounting: accounting,
      exclusions: exclusions.toList()..sort(),
      sourcePaths: sourcePaths,
    );
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'Malformed supported legacy data; nothing was imported.',
    );
  }
}

(double, double) convertLabsLegacy(double x, double y) {
  if (!x.isFinite || !y.isFinite) {
    throw const FormatException('Nonfinite Labs coordinates.');
  }
  const rotation = 270 * math.pi / 180;
  const ax = 0.575, bx = 281.2, ay = 0.575, by = 193.7;
  const bounds = [(-80.0, -477.0), (-287.0, -193.0)];
  (double, double) project(double wx, double wz) {
    final rx = wx * math.cos(rotation) - wz * math.sin(rotation);
    final ry = wx * math.sin(rotation) + wz * math.cos(rotation);
    return (rx * ax + bx, -ry * ay + by);
  }

  final corners = [
    for (final wx in [bounds[0].$1, bounds[1].$1])
      for (final wz in [bounds[0].$2, bounds[1].$2]) project(wx, wz),
  ];
  final minX = corners.map((p) => p.$1).reduce(math.min);
  final maxX = corners.map((p) => p.$1).reduce(math.max);
  final minY = corners.map((p) => p.$2).reduce(math.min);
  final maxY = corners.map((p) => p.$2).reduce(math.max);
  final px = minX + x * (maxX - minX), py = minY + y * (maxY - minY);
  final rx = (px - bx) / ax, ry = (by - py) / ay;
  final wx = rx * math.cos(rotation) + ry * math.sin(rotation);
  final wz = -rx * math.sin(rotation) + ry * math.cos(rotation);
  final projected = project(wx, wz);
  final result = (projected.$1 * 16 / 2800, projected.$2 * 16 / 2800);
  if (!result.$1.isFinite ||
      !result.$2.isFinite ||
      maxX == minX ||
      maxY == minY) {
    throw const FormatException('Noninvertible Labs frame.');
  }
  return result;
}

Map<String, dynamic> _object(Object? v) => v is Map
    ? Map<String, dynamic>.from(v)
    : throw const FormatException('Expected supported object.');
List<dynamic> _array(Object? v) => v is List
    ? v
    : throw const FormatException('Expected supported collection.');
String _string(Object? v) => v is String && v.trim().isNotEmpty
    ? v
    : throw const FormatException('A required name or id is missing.');
bool _boolean(Object? v) =>
    v is bool ? v : throw const FormatException('Malformed supported boolean.');
num _number(Object? v) => v is num && v.isFinite
    ? v
    : throw const FormatException('Malformed supported number.');
int _integer(Object? v) =>
    v is int ? v : throw const FormatException('Malformed supported integer.');
void _version(Map<String, dynamic> root, String key, int max) {
  final version = root.containsKey(key) ? _integer(root[key]) : 0;
  if (version < 0 || version > max) {
    throw const FormatException('Unsupported legacy schema version.');
  }
}

Object? _alias(Map<String, dynamic> row, String a, String b) {
  if (row.containsKey(a) && row.containsKey(b) && row[a] != row[b]) {
    throw const FormatException('Conflicting supported aliases.');
  }
  return row[a] ?? row[b];
}

GameMode _mode(Object? v, {bool allowUnknown = false}) => switch (v) {
  'PvP' || 1 => GameMode.pvp,
  'PvE' || 2 => GameMode.pve,
  'Seasonal' || 3 => GameMode.seasonal,
  'Unknown' || 0 when allowUnknown => GameMode.unknown,
  _ => throw const FormatException('Unsupported legacy mode.'),
};
String _map(Object? v) {
  final key = _string(v).toLowerCase();
  final canonical = switch (key) {
    'lab' || 'labs' => 'thelab',
    _ => key,
  };
  if (!supportedMaps.contains(canonical)) {
    throw const FormatException('Unsupported legacy map.');
  }
  return canonical;
}
