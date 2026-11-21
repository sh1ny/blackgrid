import 'package:blackgrid/domain/objective_progress.dart';
import 'package:blackgrid_progress/blackgrid_progress.dart';
import 'package:flutter_test/flutter_test.dart';

TaskObjective _objective(num? count) => TaskObjective(id: 'o', count: count);

void main() {
  group('objectiveCounterTarget', () {
    for (final (count, target) in <(num?, int?)>[
      (null, null),
      (0, null),
      (1, null),
      (1.0, null),
      (2.5, null),
      (2, 2),
      (3.0, 3),
      (40, 40),
    ]) {
      test('a catalog count of $count gives $target', () {
        expect(objectiveCounterTarget(_objective(count)), target);
      });
    }
  });

  group('objectiveDone', () {
    for (final (name, count, complete, recorded, done)
        in <(String, num?, bool, int, bool)>[
          ('a recorded completion', null, true, 0, true),
          ('a recorded completion of a counter', 5, true, 0, true),
          ('nothing recorded', null, false, 0, false),
          ('a count on an objective that is not a counter', 1, false, 3, false),
          ('a counter below its target', 5, false, 4, false),
          ('a counter at its target', 5, false, 5, true),
          ('a counter past its target', 5, false, 7, true),
          ('a fractional count that is not a counter', 2.5, false, 3, false),
        ]) {
      test('$name is ${done ? '' : 'not '}done', () {
        expect(
          objectiveDone(_objective(count), complete: complete, count: recorded),
          done,
        );
      });
    }
  });
}
