@Tags(['qualification'])
library;

import 'dart:isolate';

import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/title_matching.dart';
import 'package:flutter_test/flutter_test.dart';

const _itemCount = 10000;
const _titleCount = 200;
const _p95Limit = Duration(milliseconds: 20);

const _words = [
  'salewa',
  'grizzly',
  'medical',
  'kit',
  'ammo',
  'pack',
  'rifle',
  'magazine',
  'armor',
  'plate',
  'helmet',
  'vest',
  'bolt',
  'carrier',
  'optic',
  'scope',
  'suppressor',
  'grip',
  'stock',
  'barrel',
  'flashlight',
  'battery',
  'cable',
  'bandage',
  'tourniquet',
  'injector',
  'canister',
  'gasan',
  'analyzer',
  'ledx',
  'thermal',
  'camera',
  'wire',
  'tape',
  'matches',
  'lighter',
];

/// Deterministic linear congruential generator, so runs are comparable.
final class _Lcg {
  _Lcg(this._state);
  int _state;
  int next(int bound) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return (_state >> 8) % bound;
  }
}

String _name(_Lcg rng, int serial) {
  final count = 2 + rng.next(4);
  final words = [
    for (var i = 0; i < count; i++) _words[rng.next(_words.length)],
  ];
  final pack = rng.next(3) == 0 ? ' (${(1 + rng.next(60)) * 10} pcs)' : '';
  return '${words.join(' ')} mk$serial$pack';
}

CatalogSnapshot _snapshot(List<String> names) => CatalogSnapshot(
  mode: GameMode.pvp,
  revision: 'bench',
  observedAt: DateTime.utc(2026, 1, 1),
  items: {
    for (var i = 0; i < names.length; i++)
      'id${i.toString().padLeft(6, '0')}': CatalogItem(
        id: 'id${i.toString().padLeft(6, '0')}',
        name: names[i],
        normalizedName: names[i].replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
      ),
  },
  traders: const {},
  requirements: const [],
);

/// A title as OCR might read [name]: one character dropped or swapped.
String _noisy(_Lcg rng, String name) {
  final at = rng.next(name.length);
  return rng.next(2) == 0
      ? name.replaceRange(at, at + 1, '')
      : name.replaceRange(at, at + 1, 'x');
}

void main() {
  test('matchTitle p95 is within 20 ms over a 10k-item catalog', () async {
    final rng = _Lcg(42);
    final names = [for (var i = 0; i < _itemCount; i++) _name(rng, i)];
    final snapshot = _snapshot(names);

    final build = Stopwatch()..start();
    final index = TitleMatchIndex.build(snapshot);
    build.stop();

    final copy = Stopwatch()..start();
    final seen = await Isolate.run(() => index.length);
    copy.stop();
    expect(seen, _itemCount);

    final titles = [
      for (var i = 0; i < _titleCount; i++)
        _noisy(rng, names[rng.next(names.length)]),
    ];
    // Warm up the JIT before timing.
    for (final t in titles.take(20)) {
      matchTitle(index, t, GameMode.pvp);
    }
    final micros = <int>[];
    for (final t in titles) {
      final watch = Stopwatch()..start();
      matchTitle(index, t, GameMode.pvp);
      micros.add(watch.elapsedMicroseconds);
    }
    micros.sort();
    final p95 = Duration(
      microseconds: micros[(micros.length * 0.95).ceil() - 1],
    );
    final median = Duration(microseconds: micros[micros.length ~/ 2]);

    // ignore: avoid_print
    print(
      'title matching, $_itemCount items: '
      'index build ${build.elapsedMilliseconds} ms, '
      'index into Isolate.run ${copy.elapsedMilliseconds} ms '
      '(includes isolate spawn), '
      'matchTitle median ${median.inMicroseconds / 1000} ms, '
      'p95 ${p95.inMicroseconds / 1000} ms over $_titleCount titles',
    );
    expect(p95, lessThanOrEqualTo(_p95Limit));
  });
}
