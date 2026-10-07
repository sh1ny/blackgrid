// Canonical selector identity and upstream source identity are separate.
// Runtime inventory comes only from the prepared manifest, not this tool table.
const supportedMapSources = <String, String>{
  'factory': 'factory',
  'customs': 'customs',
  'woods': 'woods',
  'shoreline': 'shoreline',
  'interchange': 'interchange',
  'thelab': 'the-lab',
  'reserve': 'reserve',
  'lighthouse': 'lighthouse',
  'streetsoftarkov': 'streets-of-tarkov',
  'groundzero': 'ground-zero',
  'terminal': 'terminal',
  'icebreaker': 'icebreaker',
  'labyrinth': 'the-labyrinth',
};

// Actual served artwork, also byte-identical to the matching pinned repository
// revision. Unresolved references are deliberately retained: source integrity
// is checked during normalization and can block a complete candidate.
const additionalVectorSources = <String, Map<String, String>>{
  'factory': {
    'file': 'Factory.svg',
    'sha256':
        'c8e576ca7974e086b78151f9bff532b5a99b2fc4a130b080e5be030236bc07bd',
  },
  'customs': {
    'file': 'Customs.svg',
    'sha256':
        '7c4713ff1d97fdcc92a8440b8c77ec68672e0f23577c1c4de4d7913fd402f7f0',
  },
  'woods': {
    'file': 'Woods.svg',
    'sha256':
        'b356ded5e763e81edc1710d58c2fc7943f6ad6f48cd261c83dd0a192f45f0b9a',
  },
  'shoreline': {
    'file': 'Shoreline.svg',
    'sha256':
        'dabe88b2908659524e5a0abf598429c52e158624c2ec12def42d2374c5d439ee',
  },
  'reserve': {
    'file': 'Reserve.svg',
    'sha256':
        'fdb20697675ed153cb5f80f62c6feb3ae4642efbb779931bb349ae7b8310184e',
  },
  'lighthouse': {
    'file': 'Lighthouse.svg',
    'sha256':
        'c1b2603ac306e66900c0db8b68807554e7c6230c031142a3541fc7c065f8d013',
  },
  'streetsoftarkov': {
    'file': 'StreetsOfTarkov.svg',
    'sha256':
        '700965797067ec8f044d297806f9306ea4a5f06983665626afe18890b1480f0a',
  },
  'groundzero': {
    'file': 'GroundZero.svg',
    'sha256':
        '2a7bc873fa9270ec0bef99476145066ca76d17a05c36753fa93f781f3b970c4a',
  },
  'terminal': {
    'file': 'Terminal.svg',
    'sha256':
        'f0d0cc7b615e933e5846c4b4f35e7577ae151396a729b1f02e6c1267212acd71',
  },
};

Map<String, Object?> additionalCalibrationFor(String sourceKey) {
  Map<String, Object?> floor(
    String id, {
    bool base = false,
    List<String> attached = const [],
    String? tilePath,
  }) => {
    'id': id,
    'base': base,
    'manual': true,
    'exclusive': false,
    'attachedIds': attached,
    'sourceTileUrl': ?tilePath,
  };
  Map<String, Object?> vector({
    required String id,
    required String name,
    required List<num> affine,
    required List<List<num>> bounds,
    required List<num> frame,
    required List<Map<String, Object?>> floors,
    num rotation = 180,
  }) => {
    'id': id,
    'sourceKey': sourceKey,
    'name': name,
    'kind': 'vector',
    'sourceSvgPath': '$id/${additionalVectorSources[id]!['file']}',
    'geometry': {
      'rotation': rotation,
      'affine': affine,
      'bounds': bounds,
      'nativeZoom': null,
      'coordinateRevision': 0,
      'pinFrame': 'legacy-normalized',
      'projection': 'bounds-normalized',
    },
    'calibrationEvidence': {
      'basis': 'frozen-interactive-metadata-and-original-svg-frame',
      'independentPlacement': 'unverified',
      'metadataBounds': 'svgBounds-when-declared-otherwise-bounds',
    },
    'artworkFrame': {
      'width': frame[0],
      'height': frame[1],
      'viewBox': [0.0, 0.0, ...frame],
    },
    'floors': floors,
  };
  // Published tile grids keep their own z4 frame and the map's metadata
  // affine; the runtime places them over the SVG through game coordinates.
  const rasterOverlayFrame = {
    'nativeZoom': 4,
    'width': 4096,
    'height': 4096,
    'tileStride': 256,
    'tileImageExtent': 256,
    'nativeTilePixels': 256,
  };
  List<Map<String, Object?>> buildingFloors() => [
    floor('Ground_Level', base: true, attached: ['First_Floor']),
    floor('Second_Floor'),
    floor('Third_Floor'),
    floor('Underground_Level'),
  ];
  switch (sourceKey) {
    case 'factory':
      return vector(
        id: 'factory',
        name: 'Factory',
        affine: [1.629, 119.9, 1.629, 139.3],
        bounds: [
          [77, -64.5],
          [-65.5, 67.4],
        ],
        frame: [130.81831, 141.23242],
        rotation: 90,
        floors: [
          floor('Ground_Floor', base: true),
          floor('Second_Floor'),
          floor('Third_Floor'),
          floor('Basement'),
        ],
      );
    case 'customs':
      // tarkov.dev's default Abstract rendition: the publisher SVG, with its
      // tile-only fourth floor drawn over it as a raster overlay.
      return {
        ...vector(
          id: 'customs',
          name: 'Customs',
          affine: [0.239, 168.65, 0.239, 136.35],
          bounds: [
            [698, -307],
            [-372, 237],
          ],
          frame: [1062.4827, 535.17401],
          floors: [
            floor('Ground_Level', base: true, attached: ['First_Floor']),
            floor('Second_Floor'),
            floor('Third_Floor'),
            floor(
              'Fourth_Floor',
              tilePath: 'https://assets.tarkov.dev/maps/customs_0.16/4th/{z}/{x}/{y}.png',
            ),
            floor('Underground_Level'),
          ],
        ),
        'rasterOverlayFrame': rasterOverlayFrame,
      };
    case 'woods':
      return vector(
        id: 'woods',
        name: 'Woods',
        affine: [0.1855, 112.95, 0.1855, 167.85],
        bounds: [
          [646, -914],
          [-761, 442],
        ],
        frame: [1472.7926, 1420.5995],
        floors: [floor('Ground_Level', base: true)],
      );
    case 'shoreline':
      return vector(
        id: 'shoreline',
        name: 'Shoreline',
        affine: [0.16, 83.2, 0.16, 111.1],
        bounds: [
          [504, -415],
          [-1056, 618],
        ],
        frame: [1559.5717, 1032.4935],
        floors: buildingFloors(),
      );
    case 'reserve':
      // tarkov.dev's default Abstract rendition: the publisher SVG declares
      // Ground/Bunkers; the 2nd-5th floors exist only as tiles drawn over it.
      return {
        ...vector(
          id: 'reserve',
          name: 'Reserve',
          affine: [0.395, 122, 0.395, 137.65],
          bounds: [
            [289, -274],
            [-303, 272],
          ],
          frame: [827.28742, 761.16437],
          floors: [
            floor('Ground_Level', base: true),
            for (final (id, path) in const [
              ('Second_Floor', '2nd'),
              ('Third_Floor', '3rd'),
              ('Fourth_Floor', '4th'),
              ('Fifth_Floor', '5th'),
            ])
              floor(
                id,
                tilePath:
                    'https://assets.tarkov.dev/maps/reserve/$path/{z}/{x}/{y}.png',
              ),
            floor('Bunkers'),
          ],
        ),
        'rasterOverlayFrame': rasterOverlayFrame,
      };
    case 'lighthouse':
      return vector(
        id: 'lighthouse',
        name: 'Lighthouse',
        affine: [0.2, 0, 0.2, 0],
        bounds: [
          [515, -998],
          [-545, 725],
        ],
        frame: [1059.3752, 1722.9499],
        floors: [floor('Ground_Level', base: true)],
      );
    case 'streets-of-tarkov':
      return vector(
        id: 'streetsoftarkov',
        name: 'Streets of Tarkov',
        affine: [0.38, 0, 0.38, 0],
        bounds: [
          [323, -295],
          [-280, 532],
        ],
        frame: [605.32395, 831.57753],
        floors: [
          floor('Ground_Level', base: true, attached: ['First_Floor']),
          floor('Second_Floor'),
          floor('Third_Floor'),
          floor('Fourth_Floor'),
          floor('Fifth_Floor'),
          floor('Underground_Level'),
        ],
      );
    case 'ground-zero':
      return {
        ...vector(
          id: 'groundzero',
          name: 'Ground Zero',
          affine: [0.524, 167.3, 0.524, 65.1],
          bounds: [
            [249, -124],
            [-99, 364],
          ],
          frame: [348.92543, 488.44792],
          floors: buildingFloors(),
        ),
        // Metadata declares alternative raster renditions, not embedded SVG
        // images. Freeze/package every grid without painting duplicate art.
        'rasterDependencies': [
          for (final entry in const {
            'Ground_Level': 'main_summer',
            'Second_Floor': '2nd',
            'Third_Floor': '3rd',
            'Underground_Level': 'garage',
          }.entries)
            {
              'id': entry.key,
              'sourceTileUrl':
                  'https://assets.tarkov.dev/maps/groundzero/${entry.value}/{z}/{x}/{y}.png',
              'displayFrame': {
                'width': 4096,
                'height': 4096,
                'tileStride': 256,
                'tileImageExtent': 256,
                'nativeTilePixels': 256,
              },
            },
        ],
      };
    case 'terminal':
      return vector(
        id: 'terminal',
        name: 'Terminal',
        affine: [0.2, 0, 0.2, 0],
        bounds: [
          [463, -580],
          [-433, 475],
        ],
        frame: [887.70096, 1043.9554],
        floors: [
          floor('Ground_Level', base: true, attached: ['First_Floor']),
        ],
      );
    case 'the-labyrinth':
      return {
        'id': 'labyrinth',
        'sourceKey': sourceKey,
        'name': 'Labyrinth',
        'kind': 'raster',
        'geometry': {
          'rotation': 270,
          'affine': [2.115, 85.5, 2.115, 128],
          'bounds': [
            [-52, -37],
            [53, 76],
          ],
          'nativeZoom': 4,
          'coordinateRevision': 0,
          'pinFrame': 'legacy-normalized',
          'projection': 'native-pixels',
        },
        'calibrationEvidence': {
          'basis': 'frozen-interactive-metadata-and-original-z4-tile-grid',
          'independentPlacement': 'unverified',
          'representation':
              'published-interactive-tiles-no-svg-wrapper-declared',
        },
        'artworkFrame': {
          'width': 4096,
          'height': 4096,
          'tileStride': 256,
          'tileImageExtent': 256,
          'nativeTilePixels': 256,
        },
        'floors': [
          floor(
            'Main_Level',
            base: true,
            tilePath:
                'https://assets.tarkov.dev/maps/labyrinth/main/{z}/{x}/{y}.png',
          ),
        ],
      };
    default:
      throw FormatException('Unknown source map: $sourceKey');
  }
}
