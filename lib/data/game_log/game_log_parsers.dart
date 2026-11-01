import 'dart:convert';

import '../../domain/raid_lifecycle.dart';
import 'game_locations.dart';
import 'log_file_tail.dart';

/// Why a record that looked like a lifecycle message was rejected.
enum GameLogRejection {
  /// The push notification body is not valid JSON.
  invalidJson,

  /// A flea sale message lacks the sold item or its count.
  malformedSale,

  /// A task message carries no task ID in its `templateId`.
  missingTaskId,
}

/// The outcome of parsing one [TailRecord].
sealed class ParseResult {
  const ParseResult();
}

/// The record produced [event].
final class ParsedEvent extends ParseResult {
  /// Creates a result carrying [event].
  const ParsedEvent(this.event);

  /// The event the record describes.
  final RecordedGameLogEvent event;
}

/// The record is valid but unrelated to the raid lifecycle.
final class ParsedNothing extends ParseResult {
  /// Creates the result.
  const ParsedNothing();
}

/// The record was a lifecycle message that could not be used.
final class ParseRejected extends ParseResult {
  /// Creates a result for [reason].
  const ParseRejected(this.reason);

  /// Why the record was rejected.
  final GameLogRejection reason;
}

/// Template ID of the rouble currency item.
const roublesTemplateId = '5449016a4bdc2d6f028b456f';

/// Parses one framed [record] of [file] in session [folder].
///
/// Returns [ParsedEvent] for a recognised message, [ParsedNothing] for an
/// unrelated one and [ParseRejected] for a recognised message whose data is
/// unusable. The event's [LogRecordId] is built from [folder], [file] and the
/// record offset, and its time from the header's timestamp. A record whose
/// header has no valid timestamp produces nothing.
ParseResult parseGameLogRecord(String folder, LogFile file, TailRecord record) {
  final newline = record.text.indexOf('\n');
  final header = newline < 0 ? record.text : record.text.substring(0, newline);
  final time = parseLogTime(header);
  final message = _headerMessage.firstMatch(header)?[1];
  if (time == null || message == null) return const ParsedNothing();
  final id = LogRecordId(folder, file, record.offset);
  final ParseResult result = switch (file) {
    LogFile.application => _application(id, time, message),
    LogFile.backend => _backend(id, time, message),
    LogFile.pushNotifications => _push(
      id,
      time,
      message,
      newline < 0 ? '' : record.text.substring(newline + 1),
    ),
  };
  return result;
}

final _headerMessage = RegExp(
  r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\|[^|]*\|[^|]*\|[^|]*\|(.*)$',
);
final _sessionMode = RegExp(r'^Session mode\s*:\s*(\S+)', caseSensitive: false);
final _scenePath = RegExp(
  r'^scene preset path:\s*maps/([a-zA-Z0-9_]+)\.bundle',
  caseSensitive: false,
);
final _transit = RegExp(
  r'^Transit reconnect status:(\S+)\s.*?\blocation:(\S+)',
  caseSensitive: false,
);

ParseResult _event(RecordedGameLogEvent event) => ParsedEvent(event);

ParseResult _application(LogRecordId id, DateTime time, String message) {
  if (_sessionMode.firstMatch(message) case final match?) {
    return _event(SessionModeChanged(id, time, gameModeFromLog(match[1]!)));
  }
  if (_scenePath.firstMatch(message) case final match?) {
    return _event(SceneLoaded(id, time, sceneMapId(match[1]!)));
  }
  if (_transit.firstMatch(message) case final match?) {
    final location = match[2]!;
    return _event(
      RaidRejoined(
        id,
        time,
        match[1]!,
        location,
        rejoinLocationMapId(location),
      ),
    );
  }
  return switch (message) {
    _ when message.startsWith('PrepareSelectedProfileLocally') => _event(
      ProfileSelected(id, time),
    ),
    _ when message.startsWith('Matching with group id:') => _event(
      QueueEntered(id, time),
    ),
    _ when message.startsWith('MatchingCompleted:') => _event(
      MatchFound(id, time),
    ),
    _ when message.startsWith('GameStarting:') => _event(
      RaidStarting(id, time),
    ),
    _ when message.startsWith('GameStarted:') => _event(RaidStarted(id, time)),
    _ when message.startsWith('Network game matching cancelled.') => _event(
      MatchingAborted(id, time),
    ),
    _ => const ParsedNothing(),
  };
}

ParseResult _backend(LogRecordId id, DateTime time, String message) =>
    message.contains('binary message received:') &&
        message.contains('payloadType=userMatchOver')
    ? _event(RaidExit(id, time))
    : const ParsedNothing();

ParseResult _push(LogRecordId id, DateTime time, String message, String body) {
  if (!message.contains('Got notification | ChatMessageReceived')) {
    return const ParsedNothing();
  }
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return const ParseRejected(GameLogRejection.invalidJson);
  }
  if (json case {'message': {'type': final int type} && final Map message}) {
    return switch (type) {
      4 => _sale(id, time, message),
      10 => _task(message, (taskId) => TaskStarted(id, time, taskId)),
      11 => _task(message, (taskId) => TaskFailed(id, time, taskId)),
      12 => _task(message, (taskId) => TaskFinished(id, time, taskId)),
      _ => const ParsedNothing(),
    };
  }
  return const ParsedNothing();
}

ParseResult _task(
  Map<Object?, Object?> message,
  RecordedGameLogEvent Function(String taskId) build,
) {
  if (message case {'templateId': final String template}) {
    final taskId = template.trim().split(RegExp(r'\s+')).first;
    if (taskId.isNotEmpty) return _event(build(taskId));
  }
  return const ParseRejected(GameLogRejection.missingTaskId);
}

ParseResult _sale(
  LogRecordId id,
  DateTime time,
  Map<Object?, Object?> message,
) {
  if (message
      case {
        'systemData': {
          'soldItem': final String itemId,
          'itemCount': final num count,
        },
      }
      when itemId.isNotEmpty) {
    return _event(FleaSale(id, time, itemId, count.toInt(), _roubles(message)));
  }
  return const ParseRejected(GameLogRejection.malformedSale);
}

int? _roubles(Map<Object?, Object?> message) {
  if (message case {'items': {'data': final List<Object?> data}}) {
    int? total;
    for (final item in data) {
      if (item case {
        '_tpl': roublesTemplateId,
        'upd': {'StackObjectsCount': final num stack},
      }) {
        total = (total ?? 0) + stack.toInt();
      }
    }
    return total;
  }
  return null;
}
