import 'inventory.dart';

export 'inventory.dart' show supportedMapSources, additionalVectorSources;

const vectorSourceRevision = '5a8b6115d1c0cf56f2ebaac1a96fa5ae3074d178';
const vectorSourceUrl = 'https://assets.tarkov.dev/maps/svg/Interchange.svg';
const vectorSourcePath = 'interchange/Interchange.svg';
const vectorSourceBlob = '90dedd0d22ffaa59d3b929cc1ee32e34766a6eea';
const metadataUrl =
    'https://raw.githubusercontent.com/the-hideout/tarkov-dev/main/src/data/maps.json';
const metadataRepositoryRevision = 'ef62766bbd7ffb294c7184f9b8bfe8ed0f18320e';
const metadataBlob = '4d7f7bbe8c233027b735ccb37b9b3ee48737163f';
const markerUrl = 'https://json.tarkov.dev/regular/maps';
// Independently retrieved content identities. A changed mutable metadata URL
// requires an explicit new reviewed source generation, never silent reuse.
final primarySourceHashes = Map<String, String>.unmodifiable({
  'metadata/maps.json':
      'c53a327dcdcff67a49b9fe2d150731edb4c1611dfc2f75db2ce97444dee2ef77',
  vectorSourcePath:
      '31a44112cd5fe33484ce6be7b7dc80d13db6077cba2583a4425ed94c665f47c4',
  for (final entry in additionalVectorSources.entries)
    '${entry.key}/${entry.value['file']}': entry.value['sha256']!,
  'terms/svg-maps-README.md':
      'ee4022e968c052d2920251ba2181b5ebd9ffb45c5c69bdea916bd9f3a6e7031a',
  'terms/svg-maps-LICENSE.md':
      '1349a4b6148492b44f629e64eed676612e234fe9a839e4f3b277c1482c8849f1',
});
const vectorSourceRoot =
    'https://raw.githubusercontent.com/the-hideout/tarkov-dev-svg-maps/$vectorSourceRevision';
const labsTiles = [
  'https://assets.tarkov.dev/maps/labs_v4/1st/{z}/{x}/{y}.png',
  'https://assets.tarkov.dev/maps/labs_v4/2nd/{z}/{x}/{y}.png',
  'https://assets.tarkov.dev/maps/labs_v4/technical/{z}/{x}/{y}.png',
];
const icebreakerSources = {
  'Control_Room': '00_control_room',
  'Engine_Room': '01_engine_room',
  'Engine_Room_Upper': '02_engine_room_upper',
  'Fuel_Pumps_Lower': '03_fuel_pumps_lower',
  'Fuel_Pumps': '04_fuel_pumps',
  'Storage_Security': '05_storage_ecurity',
  'Infirmary': '06_infirmary',
  'Helipad': '07_helipad',
  'Gym_Canteen': '08_gym-canteen',
  'Accommodation_Lower': '09_accommodation_lower',
  'Accommodation_Mid': '10_accommodation_mid',
  'Accommodation_Upper': '11_accommodation_upper',
  'Officers_Deck': '12_officers_deck',
  'Stairs_Blocked': '13_stairs_blocked',
  'Bridge': '14_bridge',
  'Bridge_Roof': '15_bridge_roof',
};
const icebreakerBands = {
  'Control_Room': [-10000, 3.6],
  'Engine_Room': [3.6, 5.7],
  'Engine_Room_Upper': [5.7, 8.8],
  'Fuel_Pumps_Lower': [8.8, 11.9],
  'Fuel_Pumps': [11.9, 15],
  'Storage_Security': [15, 18.92],
  'Helipad': [19.57, 22.2],
  'Gym_Canteen': [22.2, 25.3],
  'Accommodation_Lower': [25.3, 28.3],
  'Accommodation_Mid': [28.3, 31.4],
  'Accommodation_Upper': [31.4, 34.5],
  'Officers_Deck': [34.5, 37.6],
  'Stairs_Blocked': [37.6, 40.7],
  'Bridge': [40.7, 43.8],
  'Bridge_Roof': [43.8, 10000],
};

Map<String, Object?> calibrationFor(String sourceKey) {
  Map<String, Object?> floor(
    String id, {
    bool base = false,
    String? tilePath,
    List<num>? band,
    List<String> attached = const [],
    bool exclusive = false,
    String? label,
    List<String>? componentIds,
  }) => {
    'id': id,
    'base': base,
    'manual': true,
    'exclusive': exclusive,
    'attachedIds': attached,
    'sourceTileUrl': ?tilePath,
    'heightBand': ?band,
    'label': ?label,
    'componentIds': ?componentIds,
  };
  switch (sourceKey) {
    case 'interchange':
      return {
        'id': 'interchange',
        'sourceKey': sourceKey,
        'name': 'Interchange',
        'kind': 'vector',
        'geometry': {
          'rotation': 180,
          'affine': [0.265, 150.6, 0.265, 134.6],
          'bounds': [
            [598, -442],
            [-433, 426],
          ],
          'nativeZoom': null,
          'coordinateRevision': 0,
          'pinFrame': 'legacy-normalized',
          'projection': 'bounds-normalized',
        },
        // Exact reviewed console only: its full frozen volume and outline lie
        // inside metadata's Second_Floor height band AND mall rectangle.
        // This annotation is not automatic vector height classification.
        'markerFloorAssignments': {
          'switches:6b9023f26446d73433823e872e6d69688083beaf:0': {
            'floorId': 'Second_Floor',
            'basis': 'frozen-console-volume-and-outline-contained-in-Second_Floor-mall-extent',
            'evidenceSourcePaths': [
              'metadata/maps.json:interchange/interactive/layers/Second_Floor/extents/0',
              'markers/maps.json:5714dbc024597771384a510d/switches/1',
            ],
            'evidenceSourceHashes': {
              'metadata/maps.json': primarySourceHashes['metadata/maps.json'],
              'markers/maps.json': '62b06a28603ce9091fd57b3fb3e4f9bb1261140843e07cf80767679ad805d99b',
            },
            'evidenceHeightBand': [34, 1000],
            'evidenceSpatialBounds': [
              [120, 218],
              [-222, -327],
              'mall',
            ],
            'sourceVolume': {
              'position': {'x': -46.555, 'y': 37.347, 'z': -55.202},
              'heightBand': [37.187, 37.507],
              'outline': [
                {'x': -46.81, 'y': 37.347, 'z': -55.517},
                {'x': -46.3, 'y': 37.347, 'z': -55.517},
                {'x': -46.3, 'y': 37.347, 'z': -54.887},
                {'x': -46.81, 'y': 37.347, 'z': -54.887},
              ],
            },
          },
        },
        'artworkFrame': {
          'width': 1127.6852,
          'height': 947.02582,
          'viewBox': [0.0, 0.0, 1127.6852, 947.02582],
        },
        'floors': [
          floor('Ground_Level', base: true, label: 'Ground Level'),
          floor(
            'First_Floor',
            label: '2nd Floor',
            band: [25, 34],
            componentIds: ['Structure-1', 'Pavament-1', 'Floor-1', 'Ramps-1'],
          ),
          floor(
            'Second_Floor',
            label: '3rd Floor',
            band: [34, 1000],
            componentIds: ['Structure-2', 'Floor-2', 'Ramps-2'],
          ),
        ],
      };
    case 'the-lab':
      return {
        'id': 'thelab',
        'sourceKey': sourceKey,
        'name': 'Labs',
        'kind': 'raster',
        'geometry': {
          'rotation': 270,
          // The reference affine emits 175-stride display pixels, not the
          // original 256-pixel tile units required by native-pixels geometry.
          // Convert every coefficient once during preparation. Normalized
          // rev1 pins already refer to the full native frame and stay intact.
          'affine': [
            0.575 * 256 / 175,
            281.2 * 256 / 175,
            0.575 * 256 / 175,
            193.7 * 256 / 175,
          ],
          'bounds': [
            [-80, -477],
            [-287, -193],
          ],
          'nativeZoom': 4,
          'coordinateRevision': 1,
          'pinFrame': 'labs-native-normalized',
          'projection': 'native-pixels',
        },
        'calibrationEvidence': {
          'sourceAffine': [0.575, 281.2, 0.575, 193.7],
          'sourcePixelUnits': 'z4-175-pixel-display-stride',
          'outputPixelUnits': 'z4-256-pixel-native-tiles',
          'nativePixelsPerSourcePixel': 256 / 175,
          'basis': 'independently-labelled-original-tile-landmarks',
        },
        'artworkFrame': {
          'width': 2800,
          'height': 2800,
          'tileStride': 175,
          'tileImageExtent': 175.5,
          'nativeTilePixels': 256,
        },
        'floors': [
          floor('First_Level', base: true, tilePath: labsTiles[0]),
          floor('Second_Level', tilePath: labsTiles[1], band: [3, 1000]),
          floor('Technical_Level', tilePath: labsTiles[2], band: [-1000, -0.9]),
        ],
      };
    case 'icebreaker':
      return {
        'id': 'icebreaker',
        'sourceKey': sourceKey,
        'name': 'Icebreaker',
        'kind': 'raster',
        'geometry': {
          'rotation': 180,
          'affine': [2, 125, 3.5, 91],
          'bounds': [
            [77, -64.5],
            [-65.5, 67.4],
          ],
          'nativeZoom': 4,
          'coordinateRevision': 0,
          'pinFrame': 'legacy-normalized',
          'projection': 'native-pixels',
        },
        // Physical marker ownership is separate from the unchanged source
        // height policy. The public Boreas guide identifies the extraction
        // at the helipad centre and the level-seven C-1 server-room door.
        'markerFloorAssignments': {
          'extracts:9bf65c4c24d0153f1542a90ddabadb37198ab9ff:0': {
            'floorId': 'Helipad',
            'basis': 'helicopter-extraction-at-physical-helipad-centre',
            'evidenceObservedOn': '2026-10-06',
            'evidenceUrls': ['https://tarkov.help/en/quest/boreas'],
          },
          'locks:f680d37a9e9c4f7b4673a2cd1bedd4a8ed73e104:0': {
            'floorId': 'Officers_Deck',
            'basis': 'level-seven-compartment-C-1-server-room-door',
            'evidenceObservedOn': '2026-10-06',
            'keyId': '69bb3f278af9f360ee010a7a',
            'evidenceUrls': [
              'https://tarkov.help/en/quest/boreas',
              'https://markschaefer.dev/item_view?id=69bb3f278af9f360ee010a7a',
            ],
          },
        },
        'artworkFrame': {
          'width': 4096,
          'height': 4096,
          'tileStride': 256,
          'tileImageExtent': 256,
          'nativeTilePixels': 256,
        },
        'floors': [
          for (final entry in icebreakerSources.entries)
            floor(
              entry.key,
              base: entry.key == 'Infirmary',
              exclusive: true,
              tilePath:
                  'https://assets.tarkov.dev/maps/icebreaker/${entry.value}/{z}/{x}/{y}.png',
              band: icebreakerBands[entry.key],
            ),
        ],
      };
    default:
      return additionalCalibrationFor(sourceKey);
  }
}

Map<String, dynamic> interactiveMetadata(
  List<dynamic> metadata,
  String sourceKey,
) {
  final map = metadata.cast<Map<String, dynamic>>().singleWhere(
    (m) => m['normalizedName'] == sourceKey,
  );
  return (map['maps'] as List).cast<Map<String, dynamic>>().singleWhere(
    (m) => m['key'] == sourceKey && m['projection'] == 'interactive',
  );
}

List<Map<String, Object?>> reconcileFloors(
  Map<String, Object?> local,
  Map<String, dynamic> upstream,
) {
  final floors = (local['floors'] as List).cast<Map<String, Object?>>();
  final sourceLayers = <String>{
    if (local['kind'] == 'vector' && upstream['svgLayer'] is String)
      upstream['svgLayer'] as String
    else if (upstream['tilePath'] is String)
      upstream['tilePath'] as String,
    for (final layer in (upstream['layers'] as List? ?? []))
      if (local['kind'] == 'vector' && layer['svgLayer'] is String)
        layer['svgLayer'] as String
      else if (layer['tilePath'] is String)
        layer['tilePath'] as String,
  };
  for (final floor in floors) {
    final identity = floor['sourceTileUrl'] ?? floor['id'];
    if (!sourceLayers.contains(identity)) {
      throw FormatException('Upstream silently lost required floor $identity');
    }
  }
  final rasterDependencies = (local['rasterDependencies'] as List? ?? [])
      .cast<Map>();
  if (rasterDependencies.isNotEmpty) {
    final declared = <String>{
      if (upstream['tilePath'] is String) upstream['tilePath'] as String,
      for (final layer in (upstream['layers'] as List? ?? []))
        if (layer['tilePath'] is String) layer['tilePath'] as String,
    };
    final required = rasterDependencies
        .map((resource) => resource['sourceTileUrl'] as String)
        .toSet();
    if (required.length != rasterDependencies.length ||
        declared.length != required.length ||
        !declared.containsAll(required)) {
      throw const FormatException(
        'Metadata raster dependency closure differs from calibration',
      );
    }
    for (final resource in rasterDependencies) {
      if (!floors.any((floor) => floor['id'] == resource['id'])) {
        throw const FormatException('Raster dependency has unknown floor');
      }
    }
  }
  final expected = floors.map((f) => f['sourceTileUrl'] ?? f['id']).toSet();
  if (!expected.containsAll(sourceLayers)) {
    throw FormatException(
      'Upstream added uncalibrated floors: ${sourceLayers.difference(expected)}',
    );
  }
  return floors.map((f) => Map<String, Object?>.from(f)).toList();
}

String tileUrl(String template, int x, int y) => template
    .replaceAll('{z}', '4')
    .replaceAll('{x}', '$x')
    .replaceAll('{y}', '$y');
String rawTilePath(String mapId, String floorId, int x, int y) =>
    'tiles/$mapId/$floorId/$x/$y.png';

const artworkNotices = '''Blackgrid map artwork notices
Factory, Customs, Woods, Shoreline, Reserve, Lighthouse, Streets of Tarkov,
Ground Zero and Terminal: Shebuka / Escape from Tarkov SVG Maps Project.
Original SVG sources and per-map URL/SHA-256 identities are frozen in
evidence/sources.json; matching repository revision is
5a8b6115d1c0cf56f2ebaac1a96fa5ae3074d178. Published LICENSE.md/README.md
conditions below apply to these source SVGs and their prepared derivatives.
Changes: ordered dependency-closed floor/component normalization, inherited
styles/transforms/references retained and exact source drop shadows transferred
to native effects. <use> references to publisher-deleted symbols (Customs
path493; Streets stairs-85/86/87/90/92) are dropped, matching browser
rendering; no symbol is synthesized and any other missing symbol fails
preparation.
Ground Zero's four metadata-declared raster grids are frozen/package-validated
alternative renditions, not embedded SVG overlays and not duplicate painting.
Labyrinth uses the metadata-declared interactive original z4 raster grid:
https://assets.tarkov.dev/maps/labyrinth/main/. The selected upstream metadata
declares no SVG wrapper. No wrapper or substitute artwork has been invented.
Ground Zero rasters and Labyrinth interactive tiles are credited according to
their frozen interactive metadata. SVG licensing is not assigned to these
raster resources; source/creator/terms evidence does not assert public
redistribution clearance. Inclusion is user-directed private implementation.
Independent numeric placement for new families is unverified.


Interchange: Shebuka / Escape from Tarkov SVG Maps Project.
Artwork: https://assets.tarkov.dev/maps/svg/Interchange.svg
SHA-256: 31a44112cd5fe33484ce6be7b7dc80d13db6077cba2583a4425ed94c665f47c4
Matching source: https://github.com/the-hideout/tarkov-dev-svg-maps/
Revision: 5a8b6115d1c0cf56f2ebaac1a96fa5ae3074d178
CC BY-NC-SA 4.0: https://creativecommons.org/licenses/by-nc-sa/4.0/
Verbatim LICENSE.md and README.md, including its additional anti-cheating,
unfair-advantage, radar/ESP and automation prohibitions and revocation wording,
are included in evidence/. Retain those published conditions separately from
Blackgrid code. Prepared derivatives retain noncommercial/share-alike terms.
Changes: dependency-closed ordered floor components, CSS normalization with
chained gradient references retained, native vector compilation and
exact Structure-1/Structure-2 drop-shadow transfer to native component effects;
no authorship or ownership of the original artwork is claimed.

Labs interactive: Tarkov.dev, https://tarkov.dev/map/the-lab
Artwork: https://assets.tarkov.dev/maps/labs_v4/
Icebreaker interactive: TarkovBOT.eu, https://tarkovbot.eu/
Artwork: https://assets.tarkov.dev/maps/icebreaker/
Credits follow interactive maps.json, not the separate re3mr 2D Icebreaker map.
Changes: validated z4 tile selection and common display crop calibration;
Labs source affine coefficients converted from 175-stride display pixels to
256-pixel native tile units, checked against independently labelled landmarks.
Evidence-owned Helicopter/Compartment C-1 marker floor ownership is retained
separately from unchanged source heights and configured automatic height bands.
The exact Interchange Non-Kiba alarm console has prepared Second_Floor ownership:
its complete frozen volume/outline lies within the source metadata layer's
height band and mall rectangle. Vector automatic height selection remains off;
unreviewed, unknown and cross-floor records receive no inferred ownership.
The SVG repository licence is not assigned to these raster families. Frozen
metadata, creator pages and Tarkov.dev terms evidence are supplied; no separate
owner-cleared permission or blanket raster licence is asserted. Inclusion is
for this user-directed private implementation, not authorization to publish.

Marker data and metadata: Tarkov.dev, https://tarkov.dev and
https://json.tarkov.dev/regular/maps. Source bytes/URLs/hashes are retained.
Blackgrid claims no ownership of community artwork or Escape from Tarkov assets.
''';
