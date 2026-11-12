import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:test/test.dart';

void main() {
  test('edition table entries use known editions and cite their sources', () {
    expect(editionTable.version, 1);
    expect(editionTable.editions, {
      'standard',
      'left-behind',
      'prepare-for-escape',
      'edge-of-darkness',
      'unheard',
    });
    for (final entry in editionTable.entries.entries) {
      expect(
        entry.value.editions.difference(editionTable.editions),
        isEmpty,
        reason: 'Unknown edition in ${entry.key}',
      );
      expect(
        entry.value.source.trim(),
        isNotEmpty,
        reason: 'Missing source for ${entry.key}',
      );
    }
  });

  test('Good Times Part 1 permits the owner-confirmed editions', () {
    expect(editionTable.entries.keys.toSet(), {'666314b4d7f171c4c20226c3'});
    final rule = editionTable.entries['666314b4d7f171c4c20226c3']!;
    expect(rule.excludes, isFalse);
    expect(rule.editions, {'edge-of-darkness', 'unheard'});
    expect(rule.permits('edge-of-darkness'), isTrue);
    expect(rule.permits('unheard'), isTrue);
    expect(rule.permits('standard'), isFalse);
    expect(rule.source, contains('2026-11-12'));
  });

  test('excluded edition rules permit nonmembers', () {
    const rule = EditionRule.excluded({'unheard'}, source: 'Example source');
    expect(rule.excludes, isTrue);
    expect(rule.permits('unheard'), isFalse);
    expect(rule.permits('standard'), isTrue);
  });
}
