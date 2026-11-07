import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/maps/calibration.dart' show interactiveMetadata;
import '../../tool/maps/place_labels.dart';

/// The active pack's frozen interactive metadata and its prepared maps.
({List<dynamic> metadata, List<Map<String, Object?>> maps}) _activePack() {
  final pointer = jsonDecode(
    File('assets/maps/active.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final manifestFile = File('assets/maps/${pointer['manifest']}');
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final metadata = jsonDecode(
    File('${manifestFile.parent.path}/evidence/metadata/maps.json')
        .readAsStringSync(),
  ) as List;
  return (
    metadata: metadata,
    maps: (manifest['maps'] as List).cast<Map<String, Object?>>(),
  );
}

Map<String, dynamic> _interactive(Map<String, Object?> source) =>
    interactiveMetadata(_pack.metadata, source['sourceKey'] as String);

final _pack = _activePack();

Map<String, dynamic> _frozen(String mapId) =>
    _interactive(_pack.maps.singleWhere((map) => map['id'] == mapId));

String _baseFloor(String mapId) =>
    ((_pack.maps.singleWhere((map) => map['id'] == mapId)['floors'] as List)
            .cast<Map<String, Object?>>()
            .singleWhere((floor) => floor['base'] == true))['id']
        as String;

PlaceLabel _label(String text, {num? bottom, num? top}) =>
    PlaceLabel(text: text, x: 0, z: 0, bottom: bottom, top: top);

Map<String, dynamic> _entry(List<Object?> labels) => {'labels': labels};

const _table = <String, List<LabelFloorBand>>{
  'm': [
    LabelFloorBand('Base', -10, 5, MapHeightRange()),
    LabelFloorBand('Upper', 5, 9, LayerExtent('Up', 0)),
  ],
};

List<String> _floors(
  PlaceLabel label, {
  Map<String, List<LabelFloorBand>> table = _table,
}) => assignLabelFloors(
  [label],
  mapId: 'm',
  baseFloorId: 'Base',
  table: table,
).single.floorIds;

void main() {
  group('extraction', () {
    test('frozen metadata yields 303 labels on 10 maps in source order', () {
      var total = 0;
      var withLabels = 0;
      for (final map in _pack.maps) {
        final upstream = _interactive(map);
        final labels = extractPlaceLabels(upstream, mapId: map['id'] as String);
        final source = (upstream['labels'] as List? ?? const [])
            .cast<Map<String, dynamic>>();
        expect(labels.map((l) => l.text), source.map((l) => l['text']));
        expect(labels.map((l) => [l.x, l.z]), [
          for (final l in source) l['position'],
        ]);
        total += labels.length;
        if (labels.isNotEmpty) withLabels++;
        // Every frozen label also gets a floor.
        final assigned = assignLabelFloors(
          labels,
          mapId: map['id'] as String,
          baseFloorId: _baseFloor(map['id'] as String),
        );
        expect(assigned.every((l) => l.floorIds.isNotEmpty), isTrue);
      }
      expect(total, 303);
      expect(withLabels, 10);
      expect(
        extractPlaceLabels(_frozen('interchange'), mapId: 'i'),
        hasLength(77),
      );
      expect(extractPlaceLabels(_frozen('customs'), mapId: 'c'), hasLength(24));
      expect(extractPlaceLabels(_frozen('thelab'), mapId: 'l'), hasLength(31));
    });

    test('maps without source labels get an empty list', () {
      for (final id in ['terminal', 'icebreaker', 'labyrinth']) {
        expect(extractPlaceLabels(_frozen(id), mapId: id), isEmpty);
      }
      expect(extractPlaceLabels(_entry(const []), mapId: 'x'), isEmpty);
    });

    test('missing rotation and size default to 0 and 80', () {
      final label = extractPlaceLabels(
        _entry([
          {
            'text': 'Gate',
            'position': [1, -2.5],
          },
        ]),
        mapId: 'x',
      ).single;
      expect(label.rotation, 0);
      expect(label.size, 80);
      expect(label.toJson(), {
        'text': 'Gate',
        'position': {'x': 1, 'z': -2.5},
        'rotation': 0,
        'size': 80,
        'floorIds': isEmpty,
      });
    });

    test('numeric string rotation is converted', () {
      final labels = extractPlaceLabels(_frozen('customs'), mapId: 'customs');
      expect(labels.firstWhere((l) => l.text == 'Skeleton').rotation, -9);
      expect(labels.firstWhere((l) => l.text == 'Main Bridge').rotation, 6);
    });

    test('malformed position fails naming map and index', () {
      for (final position in <Object?>[
        [1],
        [1, 'x'],
        [1, 2, 3],
        'nope',
        null,
        [1, double.nan],
      ]) {
        expect(
          () => extractPlaceLabels(
            _entry([
              {
                'text': 'ok',
                'position': [0, 0],
              },
              {'text': 'Bad', 'position': position},
            ]),
            mapId: 'woods',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('woods'), contains('label 1')),
            ),
          ),
          reason: '$position',
        );
      }
    });

    test('blank text fails naming map and index', () {
      for (final text in <Object?>['', '  \t', null]) {
        expect(
          () => extractPlaceLabels(
            _entry([
              {
                'text': text,
                'position': [0, 0],
              },
            ]),
            mapId: 'woods',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('woods'), contains('label 0')),
            ),
          ),
          reason: '$text',
        );
      }
    });
  });

  group('floor assignment', () {
    test('Interchange IDEA belongs to First_Floor only', () {
      final idea = extractPlaceLabels(
        _frozen('interchange'),
        mapId: 'interchange',
      ).singleWhere((l) => l.text == 'IDEA');
      expect(
        assignLabelFloors(
          [idea],
          mapId: 'interchange',
          baseFloorId: 'Ground_Level',
        ).single.floorIds,
        ['First_Floor'],
      );
    });

    test('Factory Office Building belongs to base and both upper floors', () {
      final office = extractPlaceLabels(
        _frozen('factory'),
        mapId: 'factory',
      ).singleWhere((l) => l.text == 'Office Building');
      expect(
        assignLabelFloors(
          [office],
          mapId: 'factory',
          baseFloorId: 'Ground_Floor',
        ).single.floorIds,
        ['Ground_Floor', 'Second_Floor', 'Third_Floor'],
      );
    });

    test('unbanded Customs label belongs to the base floor', () {
      final skeleton = extractPlaceLabels(
        _frozen('customs'),
        mapId: 'customs',
      ).singleWhere((l) => l.text == 'Skeleton');
      expect(skeleton.isBanded, isFalse);
      expect(
        assignLabelFloors(
          [skeleton],
          mapId: 'customs',
          baseFloorId: 'Ground_Level',
        ).single.floorIds,
        ['Ground_Level'],
      );
    });

    test('label overlapping no floor band fails naming map and text', () {
      expect(
        () => _floors(_label('Nowhere', bottom: 100, top: 200)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('m:'), contains('Nowhere')),
          ),
        ),
      );
    });

    test('floor band includes its bottom and excludes its top', () {
      // Base is [-10, 5), Upper is [5, 9).
      expect(_floors(_label('edge', bottom: 5, top: 8)), ['Upper']);
      expect(_floors(_label('under', bottom: 0, top: 4.9)), ['Base']);
      expect(_floors(_label('touch', bottom: 0, top: 5)), ['Base', 'Upper']);
      expect(_floors(_label('open top', bottom: 8)), ['Upper']);
      expect(_floors(_label('open bottom', top: 0)), ['Base']);
      expect(
        () => _floors(_label('above', bottom: 9, top: 20)),
        throwsFormatException,
      );
    });

    test('banded label on a map without table bands fails', () {
      expect(
        () => assignLabelFloors(
          [_label('Free', bottom: 0, top: 3)],
          mapId: 'woods',
          baseFloorId: 'Ground_Level',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('woods'), contains('Free')),
          ),
        ),
      );
    });
  });

  group('band table', () {
    test('band table matches frozen metadata heights and floor pairing', () {
      expect(() => checkBandTable(_pack.metadata, _pack.maps), returnsNormally);
      // Every labelled, banded map is covered by the table.
      for (final map in _pack.maps) {
        final id = map['id'] as String;
        final labels = extractPlaceLabels(_interactive(map), mapId: id);
        if (labels.any((l) => l.isBanded)) {
          expect(placeLabelBandTable, contains(id), reason: id);
        }
      }

      // A drifted band names the map, floor and both bands.
      final drifted = {
        ...placeLabelBandTable,
        'interchange': [
          const LabelFloorBand(
            'Ground_Level',
            -1000,
            26,
            InterchangeHeightRange(),
          ),
          ...placeLabelBandTable['interchange']!.skip(1),
        ],
      };
      expect(
        () => checkBandTable(_pack.metadata, _pack.maps, table: drifted),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('interchange Ground_Level'),
              contains('[-1000, 26)'),
              contains('[-1000, 25]'),
            ),
          ),
        ),
      );

      // A floor paired with another floor's layer fails.
      final mispaired = {
        ...placeLabelBandTable,
        'factory': [
          const LabelFloorBand(
            'Second_Floor',
            6,
            10000,
            LayerExtent('3rd Floor', 0),
          ),
        ],
      };
      expect(
        () => checkBandTable(_pack.metadata, _pack.maps, table: mispaired),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('factory Second_Floor'), contains('Third_Floor')),
          ),
        ),
      );
    });
  });
}
