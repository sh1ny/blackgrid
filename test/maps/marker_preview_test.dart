import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:blackgrid/domain/map_coordinates.dart';
import 'package:blackgrid/maps/marker_preview.dart';
import 'package:blackgrid/maps/prepared_map.dart';

void main() {
  test('bounded preview shortens large and deeply nested source', () {
    final largeString = _preview({'description': '界' * 100000});
    final largeCollectionSource = _CountingList(100000);
    final afterLimit = _CountingList(1);
    final largeCollection = _preview({
      'entries': largeCollectionSource,
      'afterLimit': afterLimit,
    });
    final deepSource = <String, Object?>{};
    Map<String, Object?> current = deepSource;
    for (var i = 0; i < 40; i++) {
      final child = <String, Object?>{};
      current['level'] = child;
      current = child;
    }
    current['end'] = 'not reached';
    final deeplyNested = _preview(deepSource);
    final nodeReads = _ReadCounter();
    final nodeHeavy = _preview({'branches': _BranchingList(nodeReads, 5)});

    expect(utf8.encode(largeString.text).length, lessThanOrEqualTo(16 * 1024));
    expect(largeString.shortened, isTrue);
    expect(largeCollection.shortened, isTrue);
    expect(largeCollectionSource.readCount, lessThanOrEqualTo(128));
    expect(afterLimit.readCount, 0);
    expect(deeplyNested.shortened, isTrue);
    expect(deeplyNested.text, isNot(contains('not reached')));
    expect(nodeHeavy.shortened, isTrue);
    expect(nodeReads.readCount, greaterThan(0));
    expect(nodeReads.readCount, lessThanOrEqualTo(1024));
    expect(utf8.encode(nodeHeavy.text).length, lessThan(16 * 1024));

    final small = _preview({'name': 'Small source', 'count': 2});
    expect(small.shortened, isFalse);
    expect(small.text, contains('Small source'));
    expect(small.text, contains('2'));

    final utf8Boundary = _preview({'value': 'é' * 9000});
    final encoded = utf8.encode(utf8Boundary.text);
    expect(encoded.length, lessThanOrEqualTo(16 * 1024));
    expect(utf8.decode(encoded), utf8Boundary.text);
    expect(utf8Boundary.shortened, isTrue);
  });
}

BoundedMarkerPreview _preview(Map<String, Object?> details) =>
    previewMarkerDetails(_marker(details));

PreparedMarker _marker(Map<String, Object?> details) => PreparedMarker(
  id: 'preview-fixture',
  category: 'questObjectives',
  filterKey: 'QuestObjectives',
  name: 'Preview fixture',
  position: GamePoint(1, 2),
  details: Map<String, dynamic>.from(details),
  source: const {'mapId': 'map-a'},
  outline: const [],
);

class _ReadCounter {
  var readCount = 0;
}

class _BranchingList extends ListBase<Object?> {
  _BranchingList(this.counter, this.depth);

  final _ReadCounter counter;
  final int depth;

  @override
  int get length => 10;

  @override
  Object? operator [](int index) {
    counter.readCount++;
    return depth == 0 ? 'leaf' : _BranchingList(counter, depth - 1);
  }

  @override
  set length(int value) => throw UnsupportedError('fixed test fixture');

  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('fixed test fixture');
}

class _CountingList extends ListBase<Object?> {
  _CountingList(this._length);

  final int _length;

  @override
  int get length => _length;

  var readCount = 0;

  @override
  Object? operator [](int index) {
    readCount++;
    return index;
  }

  @override
  set length(int value) => throw UnsupportedError('fixed test fixture');

  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('fixed test fixture');
}
