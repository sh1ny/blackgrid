import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/progress_facts.dart';
import 'package:flutter_test/flutter_test.dart';

const _scope = ProgressScope(mode: GameMode.pvp, cycleId: 'cycle');

MapEntry<ProgressTarget, ProgressEvent> _winner(
  ProgressEntityKind kind,
  String id,
  ProgressField field,
  ProgressValue value,
) {
  final target = ProgressTarget(kind: kind, id: id, field: field);
  return MapEntry(
    target,
    ProgressEvent(
      eventId: 'e-${kind.name}-$id-${field.name}',
      deviceId: 'device',
      occurredAtMs: 1,
      scope: _scope,
      source: ProgressSource.manual,
      target: target,
      value: value,
    ),
  );
}

ProgressFacts _build(
  Iterable<MapEntry<ProgressTarget, ProgressEvent>> events,
) => ProgressFacts.fromWinners(GameMode.pvp, Map.fromEntries(events));

void main() {
  group('defaults', () {
    final facts = ProgressFacts(mode: GameMode.pve);

    test('an unrecorded task is not started', () {
      expect(facts.mode, GameMode.pve);
      expect(facts.taskState('t'), isNull);
    });

    test('an unrecorded objective is 0 and not done', () {
      expect(facts.objectiveCount('o'), 0);
      expect(facts.objectiveComplete('o'), isFalse);
    });

    test('an unrecorded station is level 0', () {
      expect(facts.stationLevel('s'), 0);
    });

    test('player level, faction and edition stay unset', () {
      expect(facts.level, isNull);
      expect(facts.faction, isNull);
      expect(facts.edition, isNull);
    });
  });

  group('winner mapping', () {
    test('maps every register family', () {
      final facts = _build([
        _winner(
          ProgressEntityKind.task,
          't1',
          ProgressField.state,
          const ProgressTaskState(ProgressTaskStatus.finished),
        ),
        _winner(
          ProgressEntityKind.task,
          't2',
          ProgressField.state,
          const ProgressTaskState(ProgressTaskStatus.failed),
        ),
        _winner(
          ProgressEntityKind.objective,
          'o1',
          ProgressField.count,
          const ProgressInteger(2),
        ),
        _winner(
          ProgressEntityKind.objective,
          'o2',
          ProgressField.complete,
          const ProgressBoolean(true),
        ),
        _winner(
          ProgressEntityKind.station,
          's1',
          ProgressField.level,
          const ProgressInteger(3),
        ),
        _winner(
          ProgressEntityKind.player,
          'self',
          ProgressField.level,
          const ProgressInteger(25),
        ),
        _winner(
          ProgressEntityKind.player,
          'self',
          ProgressField.edition,
          const ProgressText('edge_of_darkness'),
        ),
      ]);
      expect(facts.mode, GameMode.pvp);
      expect(facts.taskState('t1'), ProgressTaskStatus.finished);
      expect(facts.taskState('t2'), ProgressTaskStatus.failed);
      expect(facts.objectiveCount('o1'), 2);
      expect(facts.objectiveComplete('o2'), isTrue);
      expect(facts.objectiveComplete('o1'), isFalse);
      expect(facts.stationLevel('s1'), 3);
      expect(facts.level, 25);
      expect(facts.edition, 'edge_of_darkness');
    });

    test('unset events leave the default', () {
      final facts = _build([
        _winner(
          ProgressEntityKind.task,
          't',
          ProgressField.state,
          const ProgressUnset(),
        ),
        _winner(
          ProgressEntityKind.objective,
          'o',
          ProgressField.count,
          const ProgressUnset(),
        ),
        _winner(
          ProgressEntityKind.objective,
          'o',
          ProgressField.complete,
          const ProgressUnset(),
        ),
        _winner(
          ProgressEntityKind.station,
          's',
          ProgressField.level,
          const ProgressUnset(),
        ),
        _winner(
          ProgressEntityKind.player,
          'self',
          ProgressField.level,
          const ProgressUnset(),
        ),
        _winner(
          ProgressEntityKind.player,
          'self',
          ProgressField.faction,
          const ProgressUnset(),
        ),
        _winner(
          ProgressEntityKind.player,
          'self',
          ProgressField.edition,
          const ProgressUnset(),
        ),
      ]);
      expect(facts.taskState('t'), isNull);
      expect(facts.objectiveCount('o'), 0);
      expect(facts.objectiveComplete('o'), isFalse);
      expect(facts.stationLevel('s'), 0);
      expect(facts.level, isNull);
      expect(facts.faction, isNull);
      expect(facts.edition, isNull);
    });

    test('faction is upper-cased from the bear and usec register', () {
      for (final (raw, expected) in [('bear', 'BEAR'), ('usec', 'USEC')]) {
        final facts = _build([
          _winner(
            ProgressEntityKind.player,
            'self',
            ProgressField.faction,
            ProgressText(raw),
          ),
        ]);
        expect(facts.faction, expected);
      }
    });

    test('trader loyalty does not enter the facts', () {
      final facts = _build([
        _winner(
          ProgressEntityKind.trader,
          'prapor',
          ProgressField.loyalty,
          const ProgressInteger(4),
        ),
      ]);
      expect(facts.stationLevel('prapor'), 0);
      expect(facts.level, isNull);
    });
  });
}
