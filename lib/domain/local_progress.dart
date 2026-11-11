import 'dart:convert';

import 'catalog.dart';

/// The maximum number of records in a progress page or batch.
const progressPageLimit = 256;

/// The maximum number of UTF-8 bytes in an encoded event.
const progressEventByteLimit = 4096;

/// The maximum canonical JSON token size of an identity, including quotes.
const progressIdentityTokenLimit = 256;

/// The maximum canonical JSON token size of edition text, including quotes.
const progressTextTokenLimit = 1024;

/// The maximum absolute UTC occurrence time in milliseconds.
const progressMaxTimestampMs = 8640000000000000;

/// The greatest exactly portable nonnegative progress integer.
const progressMaxInteger = 9007199254740991;

/// The entity family owning a progress register.
enum ProgressEntityKind { task, objective, station, player, trader }

/// A field independently resolved within an entity.
enum ProgressField { state, count, complete, level, faction, edition, loyalty }

/// The origin of a fact, with log winning equal-time ties over manual.
enum ProgressSource { manual, log }

/// A task's explicitly observed state.
enum ProgressTaskStatus { started, failed, finished }

/// A locally created cycle in one known game mode.
///
/// Cycle IDs are local identities, not claims about official wipes.
final class ProgressScope {
  /// Creates a mode-scoped cycle identity.
  const ProgressScope({required this.mode, required this.cycleId});

  /// The game mode of the cycle.
  final GameMode mode;

  /// The stable local cycle identity.
  final String cycleId;

  @override
  bool operator ==(Object other) =>
      other is ProgressScope && mode == other.mode && cycleId == other.cycleId;

  @override
  int get hashCode => Object.hash(mode, cycleId);
}

/// An independently resolved field of a progress entity.
final class ProgressTarget {
  /// Creates a register key.
  const ProgressTarget({
    required this.kind,
    required this.id,
    required this.field,
  });

  /// The entity family.
  final ProgressEntityKind kind;

  /// The entity identity, or `self` for the player.
  final String id;

  /// The independently resolved field.
  final ProgressField field;

  @override
  bool operator ==(Object other) =>
      other is ProgressTarget &&
      kind == other.kind &&
      id == other.id &&
      field == other.field;

  @override
  int get hashCode => Object.hash(kind, id, field);
}

/// A typed value recorded for one progress register.
sealed class ProgressValue {
  const ProgressValue();
}

/// An absolute, nonnegative integer value.
final class ProgressInteger extends ProgressValue {
  /// Creates an integer value, validated when encoded.
  const ProgressInteger(this.value);

  /// The absolute numeric value.
  final int value;

  @override
  bool operator ==(Object other) =>
      other is ProgressInteger && value == other.value;
  @override
  int get hashCode => Object.hash(ProgressInteger, value);
}

/// A boolean progress value.
final class ProgressBoolean extends ProgressValue {
  /// Creates a boolean value.
  const ProgressBoolean(this.value);

  /// Whether the fact is true.
  final bool value;

  @override
  bool operator ==(Object other) =>
      other is ProgressBoolean && value == other.value;
  @override
  int get hashCode => Object.hash(ProgressBoolean, value);
}

/// A faction or opaque edition identifier.
final class ProgressText extends ProgressValue {
  /// Creates a text value, validated against its target when encoded.
  const ProgressText(this.value);

  /// The stored text.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is ProgressText && value == other.value;
  @override
  int get hashCode => Object.hash(ProgressText, value);
}

/// A task state value.
final class ProgressTaskState extends ProgressValue {
  /// Creates a task state value.
  const ProgressTaskState(this.value);

  /// The observed task state.
  final ProgressTaskStatus value;

  @override
  bool operator ==(Object other) =>
      other is ProgressTaskState && value == other.value;
  @override
  int get hashCode => Object.hash(ProgressTaskState, value);
}

/// An explicit unknown value that can win without resurrecting older facts.
final class ProgressUnset extends ProgressValue {
  /// Creates an explicit unset value.
  const ProgressUnset();

  @override
  bool operator ==(Object other) => other is ProgressUnset;
  @override
  int get hashCode => 0;
}

/// An immutable portable progress fact.
///
/// Event and device identities and occurrence time remain stable on replay;
/// callers retry an already identified event with the same content and ID.
final class ProgressEvent {
  /// Creates an event; the codec validates its complete envelope.
  const ProgressEvent({
    this.formatVersion = 1,
    required this.eventId,
    required this.deviceId,
    required this.occurredAtMs,
    required this.scope,
    required this.source,
    required this.target,
    required this.value,
    this.undoOf,
  });

  /// The portable event format version.
  final int formatVersion;

  /// The globally unique event identity.
  final String eventId;

  /// The identity of the originating device.
  final String deviceId;

  /// The UTC occurrence time in milliseconds since the epoch.
  final int occurredAtMs;

  /// The mode and locally created cycle owning the event.
  final ProgressScope scope;

  /// The evidence source.
  final ProgressSource source;

  /// The independent field affected by the event.
  final ProgressTarget target;

  /// The recorded value, including explicit unknown.
  final ProgressValue value;

  /// The identity of the event compensated by this event, if any.
  final String? undoOf;

  @override
  bool operator ==(Object other) =>
      other is ProgressEvent &&
      formatVersion == other.formatVersion &&
      eventId == other.eventId &&
      deviceId == other.deviceId &&
      occurredAtMs == other.occurredAtMs &&
      scope == other.scope &&
      source == other.source &&
      target == other.target &&
      value == other.value &&
      undoOf == other.undoOf;

  @override
  int get hashCode => Object.hash(
    formatVersion,
    eventId,
    deviceId,
    occurredAtMs,
    scope,
    source,
    target,
    value,
    undoOf,
  );
}

/// A locally created cycle and its committed ledger revision.
final class ProgressCycle {
  /// Creates a cycle descriptor.
  const ProgressCycle({
    required this.scope,
    required this.createdAtMs,
    required this.revision,
  });

  /// The mode and local identity of the cycle.
  final ProgressScope scope;

  /// The UTC creation time in milliseconds.
  final int createdAtMs;

  /// The committed revision of the cycle's ledger.
  final int revision;
}

/// Strict, canonical version-1 encoding of portable progress events.
///
/// Identity and edition budgets include JSON quotes and escapes. Five maximum
/// identity tokens, one maximum edition token and 512 bytes of fixed envelope
/// fit below [progressEventByteLimit], including a maximum-width timestamp and
/// an undo link. Invalid data throws [FormatException] without truncation.
abstract final class ProgressEventCodec {
  /// Validates a nonempty identity's canonical JSON token size.
  ///
  /// The same budget applies to event, device, cycle, target and undo IDs.
  static void validateIdentity(String value) {
    _validateToken(value, progressIdentityTokenLimit);
  }

  /// Encodes a validated event in fixed field order.
  static String encode(ProgressEvent event) {
    _validateEvent(event);
    final value = switch (event.value) {
      ProgressInteger(:final value) => {'type': 'integer', 'value': value},
      ProgressBoolean(:final value) => {'type': 'boolean', 'value': value},
      ProgressText(:final value) => {'type': 'text', 'value': value},
      ProgressTaskState(:final value) => {
        'type': 'task-state',
        'value': value.name,
      },
      ProgressUnset() => {'type': 'unset'},
    };
    final encoded = jsonEncode({
      'formatVersion': event.formatVersion,
      'eventId': event.eventId,
      'deviceId': event.deviceId,
      'occurredAtMs': event.occurredAtMs,
      'mode': event.scope.mode.name,
      'cycleId': event.scope.cycleId,
      'source': event.source.name,
      'target': {
        'kind': event.target.kind.name,
        'id': event.target.id,
        'field': event.target.field.name,
      },
      'value': value,
      if (event.undoOf != null) 'undoOf': event.undoOf,
    });
    if (utf8.encode(encoded).length > progressEventByteLimit) {
      throw const FormatException('Event exceeds byte limit');
    }
    return encoded;
  }

  /// Decodes a supported event, rejecting unknown fields and invalid values.
  ///
  /// Incoming property order is immaterial; re-encoding yields canonical JSON.
  static ProgressEvent decode(String encoded) {
    if (encoded.length > progressEventByteLimit ||
        utf8.encode(encoded).length > progressEventByteLimit) {
      throw const FormatException('Event exceeds byte limit');
    }
    final root = _object(jsonDecode(encoded));
    _keys(
      root,
      {
        'formatVersion',
        'eventId',
        'deviceId',
        'occurredAtMs',
        'mode',
        'cycleId',
        'source',
        'target',
        'value',
      },
      optional: {'undoOf'},
    );
    final target = _object(root['target']);
    _keys(target, {'kind', 'id', 'field'});
    final rawValue = _object(root['value']);
    final type = _string(rawValue['type']);
    _keys(rawValue, type == 'unset' ? {'type'} : {'type', 'value'});
    final value = switch (type) {
      'integer' => ProgressInteger(_integer(rawValue['value'])),
      'boolean' => ProgressBoolean(_boolean(rawValue['value'])),
      'text' => ProgressText(_string(rawValue['value'])),
      'task-state' => ProgressTaskState(
        _enumValue(ProgressTaskStatus.values, rawValue['value']),
      ),
      'unset' => const ProgressUnset(),
      _ => throw const FormatException('Unknown value type'),
    };
    final event = ProgressEvent(
      formatVersion: _integer(root['formatVersion']),
      eventId: _string(root['eventId']),
      deviceId: _string(root['deviceId']),
      occurredAtMs: _integer(root['occurredAtMs']),
      scope: ProgressScope(
        mode: _enumValue(GameMode.values, root['mode']),
        cycleId: _string(root['cycleId']),
      ),
      source: _enumValue(ProgressSource.values, root['source']),
      target: ProgressTarget(
        kind: _enumValue(ProgressEntityKind.values, target['kind']),
        id: _string(target['id']),
        field: _enumValue(ProgressField.values, target['field']),
      ),
      value: value,
      undoOf: root.containsKey('undoOf') ? _string(root['undoOf']) : null,
    );
    _validateEvent(event);
    return event;
  }
}

void _validateToken(String value, int limit) {
  // Bound the temporary JSON and UTF-8 buffers before encoding arbitrary input.
  if (value.isEmpty ||
      value.length > limit ||
      utf8.encode(jsonEncode(value)).length > limit) {
    throw const FormatException('Invalid or oversized string token');
  }
}

void _validateEvent(ProgressEvent event) {
  if (event.formatVersion != 1 ||
      event.scope.mode == GameMode.unknown ||
      event.occurredAtMs < -progressMaxTimestampMs ||
      event.occurredAtMs > progressMaxTimestampMs) {
    throw const FormatException('Unsupported event envelope');
  }
  ProgressEventCodec.validateIdentity(event.eventId);
  ProgressEventCodec.validateIdentity(event.deviceId);
  ProgressEventCodec.validateIdentity(event.scope.cycleId);
  ProgressEventCodec.validateIdentity(event.target.id);
  if (event.undoOf case final undoOf?)
    ProgressEventCodec.validateIdentity(undoOf);
  final target = event.target;
  if (target.kind == ProgressEntityKind.player && target.id != 'self') {
    throw const FormatException('Invalid player identity');
  }
  final validTarget = switch ((target.kind, target.field)) {
    (ProgressEntityKind.task, ProgressField.state) ||
    (ProgressEntityKind.objective, ProgressField.count) ||
    (ProgressEntityKind.objective, ProgressField.complete) ||
    (ProgressEntityKind.station, ProgressField.level) ||
    (ProgressEntityKind.player, ProgressField.level) ||
    (ProgressEntityKind.player, ProgressField.faction) ||
    (ProgressEntityKind.player, ProgressField.edition) ||
    (ProgressEntityKind.trader, ProgressField.loyalty) => true,
    _ => false,
  };
  if (!validTarget) throw const FormatException('Invalid progress target');
  final validValue = switch (event.value) {
    ProgressUnset() => true,
    ProgressInteger(:final value) =>
      (target.field == ProgressField.count ||
              target.field == ProgressField.level ||
              target.field == ProgressField.loyalty) &&
          value >= 0 &&
          value <= progressMaxInteger,
    ProgressBoolean() => target.field == ProgressField.complete,
    ProgressTaskState() => target.field == ProgressField.state,
    ProgressText(:final value) => switch (target.field) {
      ProgressField.faction => value == 'bear' || value == 'usec',
      ProgressField.edition => true,
      _ => false,
    },
  };
  if (!validValue) throw const FormatException('Invalid progress value');
  if (event.value case ProgressText(:final value)
      when target.field == ProgressField.edition) {
    _validateToken(value, progressTextTokenLimit);
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>)
    throw const FormatException('Expected object');
  return value;
}

void _keys(
  Map<String, dynamic> value,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  if (!value.keys.toSet().containsAll(required) ||
      value.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    throw const FormatException('Invalid object fields');
  }
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected string');
  return value;
}

int _integer(Object? value) {
  if (value is! int) throw const FormatException('Expected integer');
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException('Expected boolean');
  return value;
}

T _enumValue<T extends Enum>(List<T> values, Object? value) {
  final name = _string(value);
  for (final candidate in values) {
    if (candidate.name == name) return candidate;
  }
  throw const FormatException('Unknown enum tag');
}

/// Compares events by time, source rank, ordinal device ID and ordinal event ID.
///
/// Log wins a source tie; a later occurrence always wins regardless of source.
int compareProgressEvents(ProgressEvent a, ProgressEvent b) {
  final time = a.occurredAtMs.compareTo(b.occurredAtMs);
  if (time != 0) return time;
  final source = a.source.index.compareTo(b.source.index);
  if (source != 0) return source;
  final device = a.deviceId.compareTo(b.deviceId);
  if (device != 0) return device;
  return a.eventId.compareTo(b.eventId);
}

/// Folds a finite set of events into its latest event per independent target.
///
/// The caller supplies events from a single scope. Unset is retained as a
/// winning event rather than removed or replaced by an older value.
Map<ProgressTarget, ProgressEvent> foldProgressEvents(
  Iterable<ProgressEvent> events,
) {
  final winners = <ProgressTarget, ProgressEvent>{};
  for (final event in events) {
    final previous = winners[event.target];
    if (previous == null || compareProgressEvents(event, previous) > 0) {
      winners[event.target] = event;
    }
  }
  return winners;
}
