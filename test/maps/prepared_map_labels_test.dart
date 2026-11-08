import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/maps/prepared_map.dart';
import 'package:blackgrid/maps/prepared_map_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/maps/pack.dart' show validateCandidate;
import '../support/prepared_pack_manifest.dart';

Map<String, Object?> _label({
  Object? text = 'Gate',
  Object? position = const {'x': 10, 'z': -4.5},
  Object? rotation = 0,
  Object? size = 80,
  Object? floorIds = const ['Ground'],
}) => {
  'text': text,
  'position': position,
  'rotation': rotation,
  'size': size,
  'floorIds': floorIds,
};

Map<String, dynamic> _map(Map<String, dynamic> manifest, String id) =>
    (manifest['maps'] as List).cast<Map<String, dynamic>>().singleWhere(
      (map) => map['id'] == id,
    );

Future<PreparedMapPack> _load(Map<String, dynamic> manifest) =>
    PreparedMapPackLoader(loadBytes: preparedPackBytes(manifest)).load();

Matcher _formatError(Pattern first, [Pattern? second]) => throwsA(
  isA<FormatException>().having(
    (e) => e.message,
    'message',
    allOf(contains(first), contains(second ?? '')),
  ),
);

void main() {
  late Directory candidate;

  setUp(() async {
    candidate = await Directory.systemTemp.createTemp('blackgrid-labels-');
    addTearDown(() => candidate.delete(recursive: true));
  });

  Future<void> writeManifest(Map<String, Object?> manifest) =>
      File('${candidate.path}/manifest.json')
          .writeAsString(jsonEncode(manifest));

  group('the loader parses labels', () {
    test('valid labels become immutable place labels in pack order', () async {
      final manifest = preparedPackManifest();
      _map(manifest, 'woods')['labels'] = [
        _label(text: 'Gate', rotation: -9, size: 100),
        _label(text: 'Дом', position: {'x': 1.5, 'z': 2}),
      ];
      final pack = await _load(manifest);
      final labels = pack.byId['woods']!.placeLabels;
      expect(labels.map((l) => l.text), ['Gate', 'Дом']);
      expect(labels[0].position.x, 10);
      expect(labels[0].position.z, -4.5);
      expect(labels[0].rotation, -9);
      expect(labels[0].size, 100);
      expect(labels[0].floorIds, ['Ground']);
      expect(() => labels.add(labels.first), throwsUnsupportedError);
      expect(() => labels[0].floorIds.add('x'), throwsUnsupportedError);
      expect(pack.byId['customs']!.placeLabels, isEmpty);
    });

    test('an invalid label fails naming the map and label index', () async {
      final invalid = <String, Object?>{
        'blank text': _label(text: '  '),
        'missing text': _label(text: null),
        'one-number position': _label(position: {'x': 1}),
        'string position': _label(position: {'x': '1', 'z': 0}),
        'string rotation': _label(rotation: '-9'),
        'zero size': _label(size: 0),
        'negative size': _label(size: -1),
        'no floors': _label(floorIds: <String>[]),
      };
      for (final MapEntry(:key, :value) in invalid.entries) {
        final manifest = preparedPackManifest();
        _map(manifest, 'woods')['labels'] = [_label(), value];
        await expectLater(
          _load(manifest),
          _formatError('woods', 'label 1'),
          reason: key,
        );
      }
    });
  });

  group('the loader and validator gate labels', () {
    test('map without labels key fails in loader and validator', () async {
      final manifest = preparedPackManifest();
      _map(manifest, 'woods').remove('labels');
      await expectLater(_load(manifest), _formatError('woods', 'labels'));

      // The validator reads the key before any evidence, so a bare manifest
      // is enough. An empty list is a present key.
      await writeManifest({
        'schemaVersion': 1,
        'preparationVersion': 4,
        'maps': [
          {'id': 'customs', 'labels': <Object>[]},
          {'id': 'woods'},
        ],
        'outputs': <Object>[],
      });
      await expectLater(
        validateCandidate(candidate),
        _formatError('woods', 'labels'),
      );
    });

    test('label with an unknown floor fails naming map and floor', () async {
      final manifest = preparedPackManifest();
      _map(manifest, 'woods')['labels'] = [
        _label(floorIds: ['Ground', 'Attic']),
      ];
      await expectLater(_load(manifest), _formatError('woods', 'Attic'));
    });

    test('preparation version 3 is refused by loader and validator', () async {
      final manifest = preparedPackManifest()..['preparationVersion'] = 3;
      await expectLater(_load(manifest), _formatError('version 3'));

      await writeManifest({
        'schemaVersion': 1,
        'preparationVersion': 3,
        'maps': [
          {'id': 'woods', 'labels': <Object>[]},
        ],
        'outputs': <Object>[],
      });
      await expectLater(
        validateCandidate(candidate),
        _formatError('preparation version 3'),
      );
    });
  });
}
