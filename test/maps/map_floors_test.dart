import 'package:blackgrid/domain/map_floors.dart';
import 'package:test/test.dart';

void main() {
  test('Streets base and attached first floor remain together with manual overlays only', () {
    final policy = MapFloorPolicy.streets();
    final base = policy.reset();
    expect(base.visibleLayerIds, containsAll(['Ground_Level', 'First_Floor']));
    expect(
      policy.selectableFloors.map((floor) => floor.id),
      isNot(contains('First_Floor')),
    );
    expect(policy.floors.every((floor) => floor.heightBand == null), isTrue);
    final selected = base.toggle('Second_Floor').toggle('Underground_Level');
    expect(
      selected.visibleLayerIds,
      containsAll([
        'Ground_Level',
        'First_Floor',
        'Second_Floor',
        'Underground_Level',
      ]),
    );
    expect(
      selected.isVisible(
        floorId: 'Second_Floor',
        unknownHeight: UnknownHeightVisibility.hidden,
      ),
      isTrue,
    );
    expect(
      selected.isVisible(
        floorId: 'Third_Floor',
        unknownHeight: UnknownHeightVisibility.visible,
      ),
      isFalse,
    );
    expect(
      selected.isVisible(
        floorId: 'First_Floor',
        unknownHeight: UnknownHeightVisibility.hidden,
      ),
      isTrue,
    );
    expect(() => base.toggle('First_Floor'), throwsArgumentError);
    expect(selected.select('Ground_Level').visibleLayerIds, [
      'Ground_Level',
      'First_Floor',
    ]);
    for (final height in [null, 0.0, 12.0, -100.0, 30.0]) {
      expect(policy.selectionForHeight(height).visibleLayerIds, [
        'Ground_Level',
        'First_Floor',
      ]);
    }
    expect(
      selected.isVisible(
        height: 12,
        unknownHeight: UnknownHeightVisibility.hidden,
      ),
      isFalse,
    );
  });

  test(
    'conventional maps cannot infer a floor even if upstream supplies a band',
    () {
      final policy = MapFloorPolicy(
        mapId: 'streetsoftarkov',
        base: MapFloor(id: 'Ground_Level', label: 'Ground'),
        overlays: [
          MapFloor(
            id: 'Second_Floor',
            label: 'Second',
            heightBand: HeightBand(10, 15),
          ),
        ],
      );
      expect(policy.floorForHeight(12), isNull);
      expect(policy.selectionForHeight(12).visibleLayerIds, ['Ground_Level']);
      expect(
        policy.reset().isVisible(
          height: 12,
          unknownHeight: UnknownHeightVisibility.visible,
        ),
        isTrue,
      );
      expect(
        policy.reset().isVisible(
          height: 12,
          unknownHeight: UnknownHeightVisibility.hidden,
        ),
        isFalse,
      );
    },
  );

  test('Labs manual selection retains base plus overlays and reset removes overlays', () {
    final policy = MapFloorPolicy.labs();
    final selected = policy
        .reset()
        .toggle('Second_Level')
        .toggle('Technical_Level');
    expect(selected.visibleLayerIds, [
      'First_Level',
      'Second_Level',
      'Technical_Level',
    ]);
    expect(selected.toggle('Second_Level').visibleLayerIds, [
      'First_Level',
      'Technical_Level',
    ]);
    expect(policy.reset().visibleLayerIds, ['First_Level']);
    final expected = [
      (-1000.0, 'Technical_Level'),
      (-.900001, 'Technical_Level'),
      (-.9, 'First_Level'),
      (0.0, 'First_Level'),
      (2.999999, 'First_Level'),
      (3.0, 'Second_Level'),
      (999.999, 'Second_Level'),
      (1000.0, 'First_Level'),
      (-1000.001, 'First_Level'),
    ];
    for (final (height, floorId) in expected) {
      expect(policy.floorForHeight(height)!.id, floorId);
      final visible = policy.selectionForHeight(height).visibleLayerIds;
      expect(
        visible,
        floorId == 'First_Level' ? ['First_Level'] : ['First_Level', floorId],
      );
    }
  });

  test('Icebreaker every exact half-open boundary including gap restores base', () {
    final policy = MapFloorPolicy.icebreaker();
    // Expected data is independent of policy.floors and never derived from it.
    final bands = [
      ('Bridge_Roof', 43.8, 10000.0),
      ('Bridge', 40.7, 43.8),
      ('Stairs_Blocked', 37.6, 40.7),
      ('Officers_Deck', 34.5, 37.6),
      ('Accommodation_Upper', 31.4, 34.5),
      ('Accommodation_Mid', 28.3, 31.4),
      ('Accommodation_Lower', 25.3, 28.3),
      ('Gym_Canteen', 22.2, 25.3),
      ('Helipad', 19.57, 22.2),
      ('Storage_Security', 15.0, 18.92),
      ('Fuel_Pumps', 11.9, 15.0),
      ('Fuel_Pumps_Lower', 8.8, 11.9),
      ('Engine_Room_Upper', 5.7, 8.8),
      ('Engine_Room', 3.6, 5.7),
      ('Control_Room', -10000.0, 3.6),
    ];
    for (var index = 0; index < bands.length; index++) {
      final (id, min, max) = bands[index];
      expect(policy.selectionForHeight(min).visibleLayerIds, [id]);
      expect(policy.selectionForHeight((min + max) / 2).visibleLayerIds, [id]);
      final atMaximum = id == 'Storage_Security' || id == 'Bridge_Roof'
          ? 'Infirmary'
          : bands[index - 1].$1;
      expect(policy.selectionForHeight(max).visibleLayerIds, [atMaximum]);
      expect(policy.floorForHeight(max)!.id, isNot(id));
    }
    for (final height in [18.92, 19.0, 19.569999, -10000.001, 10000.0]) {
      expect(policy.selectionForHeight(height).visibleLayerIds, ['Infirmary']);
    }
    expect(policy.selectionForHeight(null).visibleLayerIds, ['Infirmary']);
    expect(policy.selectionForHeight(0).visibleLayerIds, ['Control_Room']);
    final bridge = policy.reset().select('Bridge');
    expect(bridge.visibleLayerIds, ['Bridge']);
    expect(bridge.select('Helipad').visibleLayerIds, ['Helipad']);
    expect(bridge.toggle('Bridge').visibleLayerIds, ['Infirmary']);
    expect(bridge.select('Infirmary').visibleLayerIds, ['Infirmary']);
    expect(
      bridge.isVisible(
        floorId: 'Infirmary',
        unknownHeight: UnknownHeightVisibility.visible,
      ),
      isFalse,
    );
    expect(
      bridge.isVisible(
        floorId: 'Bridge',
        unknownHeight: UnknownHeightVisibility.hidden,
      ),
      isTrue,
    );
  });

  test('automatic overlaps prefer highest minimum, then narrower maximum, then source order', () {
    final policy = MapFloorPolicy(
      mapId: 'thelab',
      base: MapFloor(id: 'base', label: 'Base'),
      overlays: [
        MapFloor(id: 'low', label: 'Low', heightBand: HeightBand(0, 100)),
        MapFloor(id: 'wide', label: 'Wide', heightBand: HeightBand(10, 50)),
        MapFloor(
          id: 'narrow-first',
          label: 'First',
          heightBand: HeightBand(10, 20),
        ),
        MapFloor(
          id: 'narrow-second',
          label: 'Second',
          heightBand: HeightBand(10, 20),
        ),
      ],
    );
    expect(policy.floorForHeight(9)!.id, 'low');
    expect(policy.floorForHeight(10)!.id, 'narrow-first');
    expect(policy.floorForHeight(19.999)!.id, 'narrow-first');
    expect(policy.floorForHeight(20)!.id, 'wide');
    expect(policy.floorForHeight(50)!.id, 'low');
    expect(policy.floorForHeight(100)!.id, 'base');
    expect(policy.floorForHeight(null), isNull);
  });

  test('one predicate keeps null distinct from zero and unknown height visibility explicit', () {
    final selected = MapFloorPolicy.icebreaker().reset();
    expect(
      selected.isVisible(
        height: null,
        unknownHeight: UnknownHeightVisibility.visible,
      ),
      isTrue,
    );
    expect(
      selected.isVisible(
        height: null,
        unknownHeight: UnknownHeightVisibility.hidden,
      ),
      isFalse,
    );
    expect(
      selected.isVisible(
        height: 0,
        unknownHeight: UnknownHeightVisibility.visible,
      ),
      isFalse,
    );
    expect(
      selected.isVisible(
        height: 19,
        unknownHeight: UnknownHeightVisibility.hidden,
      ),
      isTrue,
    );
    expect(
      selected.isVisible(
        floorId: 'Control_Room',
        unknownHeight: UnknownHeightVisibility.visible,
      ),
      isFalse,
    );
    final control = selected.select('Control_Room');
    expect(
      control.isVisible(
        height: 0,
        unknownHeight: UnknownHeightVisibility.hidden,
      ),
      isTrue,
    );
    expect(
      control.isVisible(
        floorId: 'Control_Room',
        unknownHeight: UnknownHeightVisibility.hidden,
      ),
      isTrue,
    );
    expect(
      control.isVisible(
        height: null,
        unknownHeight: UnknownHeightVisibility.hidden,
      ),
      isFalse,
    );
    expect(
      () => control.isVisible(
        floorId: 'missing',
        unknownHeight: UnknownHeightVisibility.visible,
      ),
      throwsArgumentError,
    );
  });

  test('invalid finite bands and structural floor identities reject', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(() => HeightBand(value, 1), throwsArgumentError);
      expect(() => HeightBand(0, value), throwsArgumentError);
      expect(
        () => MapFloorPolicy.labs().selectionForHeight(value),
        throwsArgumentError,
      );
    }
    expect(() => HeightBand(1, 1), throwsArgumentError);
    expect(() => HeightBand(2, 1), throwsArgumentError);
    expect(
      () => MapFloorPolicy(
        mapId: 'thelab',
        base: MapFloor(
          id: 'base',
          label: 'Base',
          attachedLayerIds: ['attached'],
        ),
        overlays: [MapFloor(id: 'attached', label: 'Invalid')],
      ),
      throwsArgumentError,
    );
  });
}
