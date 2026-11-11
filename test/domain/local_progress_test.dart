import 'dart:convert';

import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:flutter_test/flutter_test.dart';

const _scope = ProgressScope(mode: GameMode.pvp, cycleId: 'cycle');
const _task = ProgressTarget(
  kind: ProgressEntityKind.task,
  id: 'task',
  field: ProgressField.state,
);
const _count = ProgressTarget(
  kind: ProgressEntityKind.objective,
  id: 'objective',
  field: ProgressField.count,
);
const _complete = ProgressTarget(
  kind: ProgressEntityKind.objective,
  id: 'objective',
  field: ProgressField.complete,
);

ProgressEvent _event({
  String eventId = 'event',
  String deviceId = 'device',
  int time = 123,
  ProgressScope scope = _scope,
  ProgressSource source = ProgressSource.manual,
  ProgressTarget target = _task,
  ProgressValue value = const ProgressTaskState(ProgressTaskStatus.started),
  String? undoOf,
  int version = 1,
}) => ProgressEvent(
  formatVersion: version,
  eventId: eventId,
  deviceId: deviceId,
  occurredAtMs: time,
  scope: scope,
  source: source,
  target: target,
  value: value,
  undoOf: undoOf,
);

final _families = <(ProgressTarget, List<ProgressValue>)>[
  (
    _task,
    [for (final status in ProgressTaskStatus.values) ProgressTaskState(status)],
  ),
  (
    _count,
    [const ProgressInteger(0), const ProgressInteger(progressMaxInteger)],
  ),
  (_complete, [const ProgressBoolean(false), const ProgressBoolean(true)]),
  (
    const ProgressTarget(
      kind: ProgressEntityKind.station,
      id: 'station',
      field: ProgressField.level,
    ),
    [const ProgressInteger(42)],
  ),
  (
    const ProgressTarget(
      kind: ProgressEntityKind.player,
      id: 'self',
      field: ProgressField.level,
    ),
    [const ProgressInteger(42)],
  ),
  (
    const ProgressTarget(
      kind: ProgressEntityKind.player,
      id: 'self',
      field: ProgressField.faction,
    ),
    [const ProgressText('bear'), const ProgressText('usec')],
  ),
  (
    const ProgressTarget(
      kind: ProgressEntityKind.player,
      id: 'self',
      field: ProgressField.edition,
    ),
    [const ProgressText('opaque edition')],
  ),
  (
    const ProgressTarget(
      kind: ProgressEntityKind.trader,
      id: 'trader',
      field: ProgressField.loyalty,
    ),
    [const ProgressInteger(42)],
  ),
];

Iterable<List<T>> _permutations<T>(List<T> values) sync* {
  if (values.isEmpty) {
    yield <T>[];
    return;
  }
  for (var i = 0; i < values.length; i++) {
    final rest = [...values]..removeAt(i);
    for (final suffix in _permutations(rest)) {
      yield [values[i], ...suffix];
    }
  }
}

void main() {
  test('named event codec round trips every envelope field', () {
    for (final (target, values) in _families) {
      for (final value in [...values, const ProgressUnset()]) {
        final event = _event(
          eventId: 'event"\\',
          deviceId: 'device',
          time: -42,
          scope: const ProgressScope(mode: GameMode.pve, cycleId: 'cycle'),
          source: ProgressSource.log,
          target: target,
          value: value,
          undoOf: 'previous',
        );
        final encoded = ProgressEventCodec.encode(event);
        final decoded = ProgressEventCodec.decode(encoded);
        expect(decoded, event);
        expect(decoded.hashCode, event.hashCode);
        expect(ProgressEventCodec.encode(decoded), encoded);
      }
    }
    expect(
      ProgressEventCodec.encode(_event()),
      '{"formatVersion":1,"eventId":"event","deviceId":"device","occurredAtMs":123,"mode":"pvp","cycleId":"cycle","source":"manual","target":{"kind":"task","id":"task","field":"state"},"value":{"type":"task-state","value":"started"}}',
    );
    final reordered =
        '{"value":{"value":"started","type":"task-state"},"target":{"field":"state","id":"task","kind":"task"},"source":"manual","cycleId":"cycle","mode":"pvp","occurredAtMs":123,"deviceId":"device","eventId":"event","formatVersion":1}';
    expect(ProgressEventCodec.decode(reordered), _event());
    expect(
      ProgressEventCodec.encode(ProgressEventCodec.decode(reordered)),
      ProgressEventCodec.encode(_event()),
    );
  });

  test('invalid versions sources targets and values are rejected', () {
    final baseline =
        jsonDecode(ProgressEventCodec.encode(_event())) as Map<String, dynamic>;
    void invalid(void Function(Map<String, dynamic>) mutate) {
      final map = jsonDecode(jsonEncode(baseline)) as Map<String, dynamic>;
      mutate(map);
      expect(
        () => ProgressEventCodec.decode(jsonEncode(map)),
        throwsFormatException,
        reason: '$map',
      );
    }

    invalid((m) => m['formatVersion'] = 2);
    invalid((m) => m['formatVersion'] = 1.0);
    invalid((m) => m['source'] = 'unknown');
    invalid((m) => m['mode'] = 'unknown');
    invalid((m) => m['mode'] = 'future');
    invalid((m) => m.remove('eventId'));
    invalid((m) => m['eventId'] = '');
    invalid((m) => m['eventId'] = 9);
    invalid((m) => m['occurredAtMs'] = 1.5);
    invalid((m) => m['extra'] = true);
    invalid((m) => (m['target'] as Map<String, dynamic>)['extra'] = true);
    invalid((m) => (m['value'] as Map<String, dynamic>)['extra'] = true);
    invalid((m) => (m['target'] as Map<String, dynamic>)['kind'] = 'future');
    invalid((m) => (m['target'] as Map<String, dynamic>)['field'] = 'future');
    invalid((m) => (m['target'] as Map<String, dynamic>)['field'] = 'count');
    invalid((m) => (m['value'] as Map<String, dynamic>)['type'] = 'future');
    invalid((m) => (m['value'] as Map<String, dynamic>)['value'] = 'future');
    invalid((m) => m['value'] = {'type': 'unset', 'value': null});
    invalid((m) => m['value'] = {'type': 'boolean', 'value': true});
    invalid((m) => m['target'] = null);
    invalid((m) => m['value'] = []);
    invalid((m) => m['value'] = {'type': 'task-state'});
    invalid((m) => m['value'] = {'type': 'task-state', 'value': 1});
    invalid((m) => m['value'] = {'type': 'integer', 'value': 1.0});
    invalid((m) => m['value'] = {'type': 'boolean', 'value': 'true'});
    invalid((m) => m['value'] = {'type': 'text', 'value': false});
    invalid((m) => m['deviceId'] = '');
    invalid((m) => m['cycleId'] = '');
    invalid((m) => (m['target'] as Map<String, dynamic>)['id'] = '');
    invalid((m) => m['occurredAtMs'] = progressMaxTimestampMs + 1);
    invalid((m) => m['occurredAtMs'] = -progressMaxTimestampMs - 1);
    invalid((m) => m['eventId'] = 'x' * progressEventByteLimit);
    invalid((m) => m['undoOf'] = null);
    expect(() => ProgressEventCodec.decode('[]'), throwsFormatException);
    expect(() => ProgressEventCodec.decode('{'), throwsFormatException);
    for (final event in [
      _event(version: 2),
      _event(
        scope: const ProgressScope(mode: GameMode.unknown, cycleId: 'c'),
      ),
      _event(target: _count, value: const ProgressInteger(-1)),
      _event(
        target: _count,
        value: const ProgressInteger(progressMaxInteger + 1),
      ),
      _event(target: _complete, value: const ProgressInteger(1)),
      _event(
        target: const ProgressTarget(
          kind: ProgressEntityKind.player,
          id: 'other',
          field: ProgressField.level,
        ),
        value: const ProgressInteger(1),
      ),
      _event(
        target: const ProgressTarget(
          kind: ProgressEntityKind.player,
          id: 'self',
          field: ProgressField.faction,
        ),
        value: const ProgressText('other'),
      ),
      _event(
        target: const ProgressTarget(
          kind: ProgressEntityKind.player,
          id: 'self',
          field: ProgressField.edition,
        ),
        value: const ProgressText(''),
      ),
      _event(time: progressMaxTimestampMs + 1),
      _event(time: -progressMaxTimestampMs - 1),
      _event(undoOf: ''),
    ]) {
      expect(() => ProgressEventCodec.encode(event), throwsFormatException);
    }
    for (final kind in ProgressEntityKind.values) {
      for (final field in ProgressField.values) {
        final target = ProgressTarget(
          kind: kind,
          id: kind == ProgressEntityKind.player ? 'self' : 'id',
          field: field,
        );
        if (_families.any(
          (family) => family.$1.kind == kind && family.$1.field == field,
        )) {
          continue;
        }
        expect(
          () => ProgressEventCodec.encode(
            _event(target: target, value: const ProgressUnset()),
          ),
          throwsFormatException,
          reason: '${kind.name}/${field.name}',
        );
      }
    }
  });

  test('absolute objective counts do not replace completion', () {
    final a = _event(
      eventId: 'a',
      target: _count,
      value: const ProgressInteger(4),
      time: 1,
    );
    final b = _event(
      eventId: 'b',
      target: _complete,
      value: const ProgressBoolean(true),
      time: 2,
    );
    final c = _event(
      eventId: 'c',
      target: _count,
      value: const ProgressInteger(2),
      time: 3,
    );
    for (final order in _permutations([a, b, c])) {
      expect(foldProgressEvents(order), {
        (_scope, _count): c,
        (_scope, _complete): b,
      });
    }
  });

  test('unset wins without resurrection and negative counts reject', () {
    final old = _event(
      eventId: 'old',
      target: _count,
      value: const ProgressInteger(5),
      time: 1,
    );
    final unset = _event(
      eventId: 'unset',
      target: _count,
      value: const ProgressUnset(),
      time: 2,
    );
    for (final order in _permutations([old, unset])) {
      expect(foldProgressEvents(order)[(_scope, _count)], unset);
    }
    expect(
      () => ProgressEventCodec.encode(
        _event(target: _count, value: const ProgressInteger(-1)),
      ),
      throwsFormatException,
    );
  });

  test(
    'event permutations preserve time-first and equal-time log precedence',
    () {
      final older = _event(eventId: 'older', time: 1);
      final log = _event(eventId: 'log', time: 2, source: ProgressSource.log);
      final equalManual = _event(eventId: 'manual', time: 2);
      final correction = _event(eventId: 'correction', time: 3);
      expect(compareProgressEvents(log, equalManual), greaterThan(0));
      expect(compareProgressEvents(log, older), greaterThan(0));
      expect(compareProgressEvents(correction, log), greaterThan(0));
      for (final order in _permutations([
        older,
        log,
        equalManual,
        correction,
      ])) {
        expect(foldProgressEvents(order)[(_scope, _task)], correction);
      }
    },
  );

  test('device and event identity ties converge in either arrival order', () {
    final a = _event(eventId: 'z', deviceId: 'a');
    final b = _event(eventId: 'a', deviceId: 'b');
    final c = _event(eventId: 'b', deviceId: 'b');
    expect(compareProgressEvents(b, a), greaterThan(0));
    expect(compareProgressEvents(c, b), greaterThan(0));
    expect(compareProgressEvents(c, c), 0);
    for (final order in _permutations([a, b, c])) {
      expect(foldProgressEvents(order)[(_scope, _task)], c);
    }
    expect(const ProgressScope(mode: GameMode.pvp, cycleId: 'cycle'), _scope);
    expect(
      const ProgressScope(mode: GameMode.pvp, cycleId: 'cycle').hashCode,
      _scope.hashCode,
    );
    expect(
      const ProgressTarget(
        kind: ProgressEntityKind.task,
        id: 'task',
        field: ProgressField.state,
      ),
      _task,
    );
  });

  test('encoded token boundaries and compensation envelope headroom', () {
    final identity = '${'\\' * 126}ab';
    final edition = '${'\\' * 510}ab';
    expect(
      utf8.encode(jsonEncode(identity)).length,
      progressIdentityTokenLimit,
    );
    expect(utf8.encode(jsonEncode(edition)).length, progressTextTokenLimit);
    ProgressEventCodec.validateIdentity(identity);
    expect(
      () => ProgressEventCodec.validateIdentity(
        '$identity'
        'c',
      ),
      throwsFormatException,
    );
    expect(
      () => ProgressEventCodec.validateIdentity(''),
      throwsFormatException,
    );
    final editionTarget = const ProgressTarget(
      kind: ProgressEntityKind.player,
      id: 'self',
      field: ProgressField.edition,
    );
    final overEdition = _event(
      target: editionTarget,
      value: ProgressText(
        '$edition'
        'c',
      ),
    );
    expect(() => ProgressEventCodec.encode(overEdition), throwsFormatException);
    final overIdentityEvents = [
      _event(
        eventId:
            '$identity'
            'c',
      ),
      _event(
        deviceId:
            '$identity'
            'c',
      ),
      _event(
        scope: ProgressScope(
          mode: GameMode.pvp,
          cycleId:
              '$identity'
              'c',
        ),
      ),
      _event(
        target: ProgressTarget(
          kind: ProgressEntityKind.task,
          id:
              '$identity'
              'c',
          field: ProgressField.state,
        ),
      ),
      _event(
        undoOf:
            '$identity'
            'c',
      ),
    ];
    for (final event in overIdentityEvents) {
      expect(() => ProgressEventCodec.encode(event), throwsFormatException);
    }
    for (final (target, values) in _families) {
      final id = target.kind == ProgressEntityKind.player ? 'self' : identity;
      final sizedTarget = ProgressTarget(
        kind: target.kind,
        id: id,
        field: target.field,
      );
      for (final value in [
        ...values,
        const ProgressUnset(),
        if (target == editionTarget) ProgressText(edition),
      ]) {
        for (final time in [progressMaxTimestampMs, -progressMaxTimestampMs]) {
          final event = _event(
            eventId: identity,
            deviceId: identity,
            time: time,
            scope: ProgressScope(mode: GameMode.pve, cycleId: identity),
            target: sizedTarget,
            value: value,
            undoOf: identity,
          );
          final encoded = ProgressEventCodec.encode(event);
          final length = utf8.encode(encoded).length;
          final textLength = value is ProgressText
              ? utf8.encode(jsonEncode(value.value)).length
              : 0;
          final idsLength =
              utf8.encode(jsonEncode(identity)).length * 4 +
              utf8.encode(jsonEncode(id)).length;
          expect(length - idsLength - textLength, lessThanOrEqualTo(512));
          expect(length, lessThanOrEqualTo(progressEventByteLimit));
          expect(ProgressEventCodec.decode(encoded), event);
        }
      }
    }
    final unicode = _event(
      target: editionTarget,
      value: const ProgressText('雪\u0000\n"\\'),
    );
    expect(
      ProgressEventCodec.decode(ProgressEventCodec.encode(unicode)),
      unicode,
    );
  });

  test(
    'all identity fields reject unpaired surrogates without normalization',
    () {
      for (final invalid in [
        String.fromCharCode(0xD800),
        String.fromCharCode(0xDC00),
        String.fromCharCodes([0xD800, 0x61]),
      ]) {
        for (final event in [
          _event(eventId: invalid),
          _event(deviceId: invalid),
          _event(
            scope: ProgressScope(mode: GameMode.pvp, cycleId: invalid),
          ),
          _event(
            target: ProgressTarget(
              kind: ProgressEntityKind.task,
              id: invalid,
              field: ProgressField.state,
            ),
          ),
          _event(undoOf: invalid),
        ]) {
          expect(() => ProgressEventCodec.encode(event), throwsFormatException);
        }
        final raw = jsonDecode(
          ProgressEventCodec.encode(_event()),
        ) as Map<String, dynamic>;
        raw['deviceId'] = invalid;
        expect(
          () => ProgressEventCodec.decode(jsonEncode(raw)),
          throwsFormatException,
        );
      }
      final valid = _event(
        eventId: 'event-\u{1F600}',
        deviceId: 'device-\u{1F600}',
        scope: const ProgressScope(
          mode: GameMode.pvp,
          cycleId: 'cycle-\u{1F600}',
        ),
        target: const ProgressTarget(
          kind: ProgressEntityKind.task,
          id: 'task-\u{1F600}',
          field: ProgressField.state,
        ),
        undoOf: 'undo-\u{1F600}',
      );
      expect(
        ProgressEventCodec.decode(ProgressEventCodec.encode(valid)),
        valid,
      );
    },
  );

  test('mixed modes and cycles retain independent field winners', () {
    const anotherCycle = ProgressScope(mode: GameMode.pvp, cycleId: 'cycle-2');
    const anotherMode = ProgressScope(mode: GameMode.pve, cycleId: 'pve-cycle');
    final old = _event(
      eventId: 'old',
      target: _count,
      time: 1,
      value: const ProgressInteger(1),
    );
    final current = _event(
      eventId: 'current',
      target: _count,
      time: 4,
      value: const ProgressInteger(4),
    );
    final cycleEvent = _event(
      eventId: 'other-cycle',
      scope: anotherCycle,
      target: _count,
      time: 3,
      value: const ProgressInteger(2),
    );
    final modeEvent = _event(
      eventId: 'other-mode',
      scope: anotherMode,
      target: _count,
      time: 5,
      value: const ProgressInteger(3),
    );
    for (final order in _permutations([old, current, cycleEvent, modeEvent])) {
      expect(foldProgressEvents(order), {
        (_scope, _count): current,
        (anotherCycle, _count): cycleEvent,
        (anotherMode, _count): modeEvent,
      });
    }
  });
}
