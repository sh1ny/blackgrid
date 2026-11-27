import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/domain/map_floors.dart';
import 'package:blackgrid/maps/prepared_map.dart';
import 'package:test/test.dart';

import '../../tool/maps/calibration.dart' show supportedMapSources;
import '../support/map_preparation_fixtures.dart'
    show preparedMapMetadataFixture;

void main() {
  // Expected floor identities are source-observation data, not obtained from
  // policy.floors or projection output. These are policy/parity tests, not
  // independent game-to-artwork placement qualification.
  final conventionalFloors = <String, List<String>>{
    'factory': ['Ground_Floor', 'Second_Floor', 'Third_Floor', 'Basement'],
    'customs': [
      'Ground_Level',
      'Second_Floor',
      'Third_Floor',
      'Fourth_Floor',
      'Underground_Level',
    ],
    'woods': ['Ground_Level'],
    'shoreline': [
      'Ground_Level',
      'Second_Floor',
      'Third_Floor',
      'Underground_Level',
    ],
    'interchange': ['Ground_Level', 'First_Floor', 'Second_Floor'],
    'reserve': [
      'Ground_Level',
      'Second_Floor',
      'Third_Floor',
      'Fourth_Floor',
      'Fifth_Floor',
      'Bunkers',
    ],
    'lighthouse': ['Ground_Level'],
    'streetsoftarkov': [
      'Ground_Level',
      'Second_Floor',
      'Third_Floor',
      'Fourth_Floor',
      'Fifth_Floor',
      'Underground_Level',
    ],
    'groundzero': [
      'Ground_Level',
      'Second_Floor',
      'Third_Floor',
      'Underground_Level',
    ],
    'terminal': ['Ground_Level'],
    'labyrinth': ['Main_Level'],
  };
  const attachedBaseMaps = {
    'customs',
    'shoreline',
    'streetsoftarkov',
    'groundzero',
    'terminal',
  };
  for (final entry in conventionalFloors.entries) {
    test(
      '${entry.key} every authored floor composes manually with explicit ownership',
      () {
        final map = PreparedMap.fromJson(
          preparedMapMetadataFixture(supportedMapSources[entry.key]!),
          assetRoot: 'fixture/',
        );
        final policy = map.floorPolicy;
        final expectedBase = [
          entry.value.first,
          if (attachedBaseMaps.contains(entry.key)) 'First_Floor',
        ];
        expect(policy.selectableFloors.map((floor) => floor.id), entry.value);
        expect(policy.reset().visibleLayerIds, expectedBase);
        expect(policy.exclusive, isFalse);
        expect(policy.supportsAutomaticHeight, isFalse);
        var selection = policy.reset();
        for (final id in entry.value.skip(1)) {
          expect(
            selection.isVisible(
              floorId: id,
              unknownHeight: UnknownHeightVisibility.visible,
            ),
            isFalse,
          );
          selection = selection.toggle(id);
          expect(selection.visibleLayerIds, containsAll([...expectedBase, id]));
          expect(
            selection.isVisible(
              floorId: id,
              unknownHeight: UnknownHeightVisibility.hidden,
            ),
            isTrue,
          );
        }
        expect(selection.selectedOverlayIds, entry.value.skip(1).toSet());
        for (final id in entry.value.skip(1).toList().reversed) {
          selection = selection.toggle(id);
          expect(selection.isLayerVisible(id), isFalse);
          expect(selection.visibleLayerIds, containsAll(expectedBase));
        }
        expect(selection.visibleLayerIds, expectedBase);
        final sample = GamePoint(0, 0, height: 1);
        expect(policy.floorForPosition(sample), isNull);
        expect(selection.followPosition(sample), same(selection));
        expect(
          selection.isVisible(unknownHeight: UnknownHeightVisibility.hidden),
          isFalse,
        );
        if (attachedBaseMaps.contains(entry.key)) {
          expect(() => selection.select('First_Floor'), throwsArgumentError);
          expect(selection.isLayerVisible('First_Floor'), isTrue);
        }
        expect(() => selection.toggle('Unowned_Floor'), throwsArgumentError);
        expect(
          () => selection.selectedOverlayIds.clear(),
          throwsUnsupportedError,
        );
      },
    );
  }

  test('narrowest extent and stable floor id win in either order', () {
    final box = GameBounds(minX: 0, minZ: -4, maxX: 4, maxZ: 0);
    final shared = FloorExtent(HeightBand(0, 10), bounds: [box]);
    final narrow = FloorExtent(HeightBand(4, 7), bounds: [box]);
    final medium = FloorExtent(HeightBand(5, 9), bounds: [box]);
    final wide = MapFloor(
      id: 'Wide',
      label: 'Wide',
      extents: [FloorExtent(HeightBand(0, 20))],
    );
    for (final reverse in [false, true]) {
      final extents = [shared, narrow];
      final floors = [
        wide,
        MapFloor(
          id: 'Narrow_A',
          label: 'A',
          extents: reverse ? extents.reversed : extents,
        ),
        MapFloor(id: 'Narrow_B', label: 'B', extents: [medium, shared]),
      ];
      final policy = MapFloorPolicy(
        mapId: 'synthetic',
        baseId: 'Base',
        floors: [
          MapFloor(id: 'Base', label: 'Base'),
          ...(reverse ? floors.reversed : floors),
        ],
      );
      expect(policy.supportsAutomaticHeight, isTrue);
      // A beats B's higher minimum, even when A's wider span is visited first.
      expect(
        policy.floorForPosition(GamePoint(4, -4, height: 6))?.id,
        'Narrow_A',
      );
      // Below both narrow bands, the shared spans tie ahead of Wide.
      expect(
        policy.floorForPosition(GamePoint(4, -4, height: 0))?.id,
        'Narrow_A',
      );
      expect(policy.floorForPosition(GamePoint(4, -4, height: 10))?.id, 'Wide');
      expect(policy.floorForPosition(GamePoint(-1, -4, height: 6))?.id, 'Wide');
      expect(
        policy.floorForPosition(GamePoint(-1, -4, height: 20))?.id,
        'Base',
      );
      expect(policy.floorForPosition(GamePoint(0, 0)), isNull);
    }
  });

  test('exclusive selection resolves a known gap to base', () {
    final policy = MapFloorPolicy(
      mapId: 'synthetic',
      baseId: 'Base',
      exclusive: true,
      floors: [
        MapFloor(id: 'Base', label: 'Base'),
        MapFloor(
          id: 'Lower',
          label: 'Lower',
          extents: [
            FloorExtent(
              HeightBand(-10, -5),
              bounds: [GameBounds(minX: -8, minZ: -8, maxX: 8, maxZ: 8)],
            ),
          ],
        ),
      ],
    );
    final base = policy.reset();
    final lower = base.followPosition(GamePoint(2, 0, height: -9));
    expect(lower.visibleLayerIds, ['Lower']);
    expect(lower.followPosition(GamePoint(2, 0)), same(lower));
    expect(lower.followPosition(GamePoint(9, 0, height: -9)).visibleLayerIds, [
      'Base',
    ]);
    expect(lower.followPosition(GamePoint(2, 0, height: -5)).visibleLayerIds, [
      'Base',
    ]);
  });

  test('selecting the additive base resets overlays', () {
    final map = PreparedMap.fromJson(
      preparedMapMetadataFixture('customs'),
      assetRoot: 'fixture/',
    );
    final policy = map.floorPolicy;
    final shown = policy.reset().toggle('Second_Floor').toggle('Third_Floor');
    expect(shown.selectOnly('Third_Floor').visibleLayerIds, [
      'Ground_Level',
      'First_Floor',
      'Third_Floor',
    ]);
    expect(shown.selectOnly(policy.base.id).visibleLayerIds, [
      'Ground_Level',
      'First_Floor',
    ]);
    expect(shown.toggle(policy.base.id).selectedOverlayIds, isEmpty);
  });

  test('invalid finite bands and structural floor identities reject', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(() => HeightBand(value, 1), throwsArgumentError);
      expect(() => HeightBand(0, value), throwsArgumentError);
    }
    expect(() => HeightBand(1, 1), throwsArgumentError);
    expect(() => HeightBand(2, 1), throwsArgumentError);
    expect(() => FloorExtent(HeightBand(-1e308, 1e308)), throwsArgumentError);
    expect(
      () => MapFloorPolicy(
        mapId: 'thelab',
        baseId: 'base',
        floors: [
          MapFloor(id: 'base', label: 'Base', attachedLayerIds: ['attached']),
          MapFloor(id: 'attached', label: 'Invalid'),
        ],
      ),
      throwsArgumentError,
    );
  });
}
