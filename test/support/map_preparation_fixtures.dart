import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

import '../../tool/maps/calibration.dart';
import '../../tool/maps/pack.dart';

// Owned by one qualification suite, never by a process-global cache. Only
// private copies are returned to mutation tests; the two complete builds and
// reduced template remain read-only after construction.
class MapPreparationFixtures {
  MapPreparationFixtures._(this.root);
  final Directory root;
  Directory get raw => Directory('${root.path}/raw');
  Directory get first => Directory('${root.path}/first');
  Directory get second => Directory('${root.path}/second');
  Directory get _small => Directory('${root.path}/small');

  static Future<MapPreparationFixtures> create(Directory root) async {
    final fixtures = MapPreparationFixtures._(root);
    await materializeFullRaw(fixtures.raw);
    await rebuildCandidate(fixtures.raw, fixtures.first);
    await rebuildCandidate(fixtures.raw, fixtures.second);
    await fixtures._makeSmallTemplate();
    return fixtures;
  }

  Future<Directory> copyCandidate(Directory destination) async {
    await copyPack(_small, destination);
    return destination;
  }

  Future<void> _makeSmallTemplate() async {
    final manifest = await readManifest(first);
    final calibration = jsonDecode(
      await packFile(first, 'evidence/calibration.json').readAsString(),
    ) as Map<String, dynamic>;
    final metadata = jsonDecode(
      await packFile(first, 'evidence/metadata/maps.json').readAsString(),
    ) as List;
    final index = jsonDecode(
      await packFile(first, 'evidence/sources.json').readAsString(),
    ) as Map<String, dynamic>;
    final selected = <String, Set<String>>{
      'interchange': {'Ground_Level', 'First_Floor', 'Second_Floor'},
      'thelab': {'First_Level'},
      'icebreaker': {'Helipad'},
    };
    for (final local in calibration['maps'] as List) {
      final ids = selected[local['id']]!;
      (local['floors'] as List).removeWhere(
        (floor) => !ids.contains(floor['id']),
      );
      final assignments = local['markerFloorAssignments'] as Map?;
      assignments?.removeWhere(
        (_, assignment) => !ids.contains(assignment['floorId']),
      );
      final upstream = interactiveMetadata(
        metadata,
        local['sourceKey'] as String,
      );
      if (local['kind'] == 'raster') {
        upstream['tilePath'] =
            (local['floors'] as List).single['sourceTileUrl'];
        upstream['layers'] = <Object>[];
      }
    }
    final snapshot = jsonDecode(
      await packFile(first, 'evidence/markers/maps.json').readAsString(),
    ) as Map<String, dynamic>;
    final translations =
        (jsonDecode(
              await packFile(
                first,
                'evidence/markers/maps_en.json',
              ).readAsString(),
            ) as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final keptTilePaths = <String>{};
    final keptOutputPaths = <String>{};
    for (final map in manifest['maps'] as List) {
      final ids = selected[map['id']]!;
      (map['floors'] as List).removeWhere(
        (floor) => !ids.contains(floor['id']),
      );
      final local = (calibration['maps'] as List).singleWhere(
        (local) => local['id'] == map['id'],
      ) as Map<String, dynamic>;
      map['markers'] = prepareMarkers(snapshot, translations, local);
      if (local.containsKey('markerFloorAssignments')) {
        map['markerFloorAssignments'] = local['markerFloorAssignments'];
      }
      if (map['kind'] == 'vector') {
        for (final floor in map['floors'] as List) {
          for (final component in floor['artwork']['components'] as List) {
            keptOutputPaths.addAll([
              component['sourceSvg'] as String,
              component['compilerSvg'] as String,
              component['path'] as String,
            ]);
          }
        }
      } else {
        for (final floor in map['floors'] as List) {
          for (final tile in floor['artwork']['tiles'] as List) {
            keptTilePaths.add(tile['sourcePath'] as String);
            keptOutputPaths.add(
              tile['empty'] == true
                  ? 'evidence/tile-alpha/${tile['sourceSha256']}.png'
                  : tile['path'] as String,
            );
          }
        }
      }
    }
    (index['sources'] as List).removeWhere(
      (entry) =>
          (entry['path'] as String).startsWith('tiles/') &&
          !keptTilePaths.contains(entry['path']),
    );
    keptOutputPaths.addAll([
      for (final output in manifest['outputs'] as List)
        if (!(output['path'] as String).startsWith('artwork/') &&
            !(output['path'] as String).startsWith('evidence/tile-alpha/'))
          output['path'] as String,
    ]);
    await _small.create();
    (manifest['outputs'] as List).removeWhere(
      (output) => !keptOutputPaths.contains(output['path']),
    );
    const rewrittenEvidence = {
      'evidence/calibration.json',
      'evidence/metadata/maps.json',
      'evidence/sources.json',
    };
    for (final path in keptOutputPaths.difference(rewrittenEvidence)) {
      final target = packFile(_small, path);
      await target.parent.create(recursive: true);
      await packFile(first, path).copy(target.path);
    }

    // A second visible Labs tile ensures forged-empty rejection is about its
    // decoded witness, not the unrelated last-visible-floor requirement.
    final labs = (manifest['maps'] as List).singleWhere(
      (map) => map['id'] == 'thelab',
    );
    final tiles = labs['floors'][0]['artwork']['tiles'] as List;
    final solid = tiles.singleWhere((tile) => tile['x'] == 0 && tile['y'] == 0);
    final extra = tiles.singleWhere((tile) => tile['x'] == 1 && tile['y'] == 0);
    extra['empty'] = false;
    extra['sourceSha256'] = solid['sourceSha256'];
    extra['alphaBounds'] = List<dynamic>.from(solid['alphaBounds'] as List);
    extra['path'] = 'artwork/thelab/First_Level/1/0.png';
    final extraFile = packFile(_small, extra['path'] as String);
    await extraFile.parent.create(recursive: true);
    await packFile(_small, solid['path'] as String).copy(extraFile.path);
    (manifest['outputs'] as List).add({
      'path': extra['path'],
      'sha256': solid['sourceSha256'],
    });
    final extraSource = (index['sources'] as List).singleWhere(
      (source) => source['path'] == extra['sourcePath'],
    );
    extraSource['sha256'] = solid['sourceSha256'];
    labs['displayCrop']['right'] = 176;

    await Directory('${_small.path}/evidence/metadata').create(recursive: true);
    await packFile(
      _small,
      'evidence/calibration.json',
    ).writeAsString(canonicalJson(calibration));
    await packFile(
      _small,
      'evidence/metadata/maps.json',
    ).writeAsString(canonicalJson(metadata));
    for (final path in ['calibration.json', 'metadata/maps.json']) {
      final entry = (index['sources'] as List).singleWhere(
        (source) => source['path'] == path,
      );
      entry['sha256'] = sha256
          .convert(await packFile(_small, 'evidence/$path').readAsBytes())
          .toString();
    }
    final indexBytes = utf8.encode(canonicalJson(index));
    await packFile(_small, 'evidence/sources.json').writeAsBytes(indexBytes);
    manifest['sourceGeneration'] = sha256.convert(indexBytes).toString();
    await saveManifest(_small, manifest, refreshOutputs: true);
    // Published validation binds the pack to its own frozen historical floors;
    // no current-calibration rebuild bypass is introduced.
    await validateCandidate(_small);
  }
}

Future<Map<String, dynamic>> readManifest(Directory candidate) async =>
    jsonDecode(await packFile(candidate, 'manifest.json').readAsString())
        as Map<String, dynamic>;

Uint8List png(int width, int height, {bool empty = false}) {
  final picture = image.Image(width: width, height: height, numChannels: 4);
  if (!empty) picture.setPixelRgba(0, 0, 20, 40, 60, 255);
  return image.encodePng(picture);
}

Future<Directory> materializeFullRaw(Directory raw) async {
  await raw.create();
  final sources = <Map<String, Object?>>[];
  final createdParents = <String>{};
  Future<void> put(String path, List<int> bytes) async {
    final file = File('${raw.path}/$path');
    final parent = file.parent;
    if (!createdParents.contains(parent.path)) {
      await parent.create(recursive: true);
      createdParents.add(parent.path);
    }
    await file.writeAsBytes(bytes);
    sources.add({
      'path': path,
      'url': 'https://example.invalid/$path',
      'sha256': sha256.convert(bytes).toString(),
    });
  }

  final locals = [
    for (final key in ['interchange', 'the-lab', 'icebreaker'])
      calibrationFor(key),
  ];
  await put(
    'calibration.json',
    utf8.encode(canonicalJson({'schemaVersion': 1, 'maps': locals})),
  );
  final metadata = [];
  final mapData = <String, Object?>{};
  final solid = png(256, 256), empty = png(256, 256, empty: true);
  for (final local in locals) {
    final floors = (local['floors'] as List).cast<Map<String, Object?>>();
    metadata.add({
      'normalizedName': local['sourceKey'],
      'maps': [
        {
          'key': local['sourceKey'],
          'projection': 'interactive',
          'author': 'Synthetic fixture author',
          'authorLink': 'https://example.invalid/',
          if (local['kind'] == 'vector')
            'svgLayer': floors.first['id']
          else
            'tilePath': floors.first['sourceTileUrl'],
          'layers': [
            for (final floor in floors.skip(1))
              {
                if (local['kind'] == 'vector')
                  'svgLayer': floor['id']
                else
                  'tilePath': floor['sourceTileUrl'],
              },
          ],
        },
      ],
    });
    mapData[local['id'] as String] = {
      'id': local['id'],
      'normalizedName': local['sourceKey'],
      if (local['id'] == 'icebreaker')
        'extracts': [
          {
            'id': '9bf65c4c24d0153f1542a90ddabadb37198ab9ff',
            'name': 'Heli',
            'position': {'x': .28, 'y': 22.56, 'z': -66.03},
          },
        ],
      'spawns': [
        {
          'position': {'x': 2, 'y': null, 'z': 3},
          'zoneName': 'Independently authored offline fixture',
        },
      ],
      'bosses': [],
    };
    if (local['kind'] == 'raster') {
      for (final floor in floors) {
        for (var x = 0; x < 16; x++) {
          for (var y = 0; y < 16; y++) {
            await put(
              rawTilePath(local['id'] as String, floor['id'] as String, x, y),
              y == 0 && x == 0 ? solid : empty,
            );
          }
        }
      }
    }
  }
  await put('metadata/maps.json', utf8.encode(jsonEncode(metadata)));
  await put(
    'markers/maps.json',
    utf8.encode(
      jsonEncode({
        'data': {'maps': mapData},
      }),
    ),
  );
  await put('markers/maps_en.json', utf8.encode('{"data":{}}'));
  const svg = '''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1127.6852 947.02582">
<style>.shadow {filter:drop-shadow(0 0 2px #000)} .paint {stroke:url(#ramp)}</style>
<defs><linearGradient id="base"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></linearGradient><linearGradient id="ramp" xlink:href="#base" x1="0" x2="1"/></defs>
<g id="Ground_Level"><path d="M0 0L1 0L1 1Z"/></g>
<g id="First_Floor" fill="#123456"><g id="Structure-1" class="shadow"><path d="M1 1L2 1L2 2Z"/></g><g id="Pavament-1"><path d="M2 2L3 2L3 3Z"/></g><g id="Floor-1"><path d="M3 3L4 3L4 4Z"/></g><g id="Ramps-1" class="paint"><path d="M4 4L5 5"/></g></g>
<g id="Second_Floor"><g id="Structure-2" class="shadow"><path d="M5 5L6 5L6 6Z"/></g><g id="Floor-2"><path d="M6 6L7 6L7 7Z"/></g><g id="Ramps-2" class="paint"><path d="M7 7L8 8"/></g></g>
</svg>''';
  await put('interchange/Interchange.svg', utf8.encode(svg));
  await put(
    'terms/svg-maps-README.md',
    utf8.encode('Independently authored test terms, not production artwork'),
  );
  await put(
    'terms/svg-maps-LICENSE.md',
    utf8.encode('Independently authored test terms'),
  );
  sources.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
  await File('${raw.path}/sources.json')
      .writeAsString(canonicalJson({'schemaVersion': 1, 'sources': sources}));
  return raw;
}

Future<void> saveManifest(
  Directory candidate,
  Map<String, dynamic> manifest, {
  bool refreshOutputs = false,
}) async {
  if (refreshOutputs) {
    for (final output in manifest['outputs'] as List) {
      output['sha256'] = sha256
          .convert(
            await packFile(candidate, output['path'] as String).readAsBytes(),
          )
          .toString();
    }
    (manifest['outputs'] as List).sort(
      (a, b) => (a['path'] as String).compareTo(b['path'] as String),
    );
  }
  await packFile(
    candidate,
    'manifest.json',
  ).writeAsString(canonicalJson(manifest));
}

Future<void> copyPack(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(source.path.length + 1)
        .replaceAll('\\', '/');
    final target = packFile(destination, relative);
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}
