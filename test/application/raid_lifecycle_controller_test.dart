import 'dart:io';

import 'package:blackgrid/application/raid_lifecycle_controller.dart';
import 'package:blackgrid/data/session_log_reader.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

const _folder = 'log_2026.10.31_22-00-00_1.3.0.0.48484';
const _version = '1.3.0.0.48484';

String _line(String log, String message, String time) =>
    '2026-10-31 $time|$_version|Info|$log|$message\n';

/// One log line and the file it belongs to, in log-time order.
typedef _Entry = (LogFile, String);

/// A cancelled queue, then a queued raid on Customs whose backend exit
/// (22:09:04) is nine minutes before the next profile selection (22:17:49).
final List<_Entry> _session = [
  (
    LogFile.application,
    _line(
      'application',
      'PrepareSelectedProfileLocally ProfileId:aaaa AccountId:1',
      '22:00:30.000',
    ),
  ),
  (
    LogFile.application,
    _line('application', 'Matching with group id: 1', '22:01:00.000'),
  ),
  (
    LogFile.application,
    _line('application', 'Network game matching cancelled.', '22:01:30.000'),
  ),
  (
    LogFile.application,
    _line('application', 'Matching with group id: 2', '22:02:00.000'),
  ),
  (
    LogFile.application,
    _line(
      'application',
      'scene preset path:maps/bigmap.bundle',
      '22:02:20.000',
    ),
  ),
  (
    LogFile.application,
    _line('application', 'MatchingCompleted: 7', '22:02:30.000'),
  ),
  (
    LogFile.application,
    _line('application', 'GameStarting: 7', '22:02:40.000'),
  ),
  (LogFile.application, _line('application', 'GameStarted: 7', '22:03:00.000')),
  (
    LogFile.backend,
    _line(
      'backend',
      'WebSocketSharp - binary message received: type=Notification, '
          'trackingId=t1, payloadType=userMatchOver, payloadLength=393',
      '22:09:04.000',
    ),
  ),
  (
    LogFile.application,
    _line(
      'application',
      'PrepareSelectedProfileLocally ProfileId:aaaa AccountId:1',
      '22:17:49.000',
    ),
  ),
];

String _fileName(LogFile file) => switch (file) {
  LogFile.application => 'application_000.log',
  LogFile.backend => 'backend_000.log',
  LogFile.pushNotifications => 'push-notifications_000.log',
};

/// What a consumer can compare across runs: kind, record identity, time and
/// end cause.
typedef _Key = (String, LogRecordId, DateTime, RaidEndCause?);

_Key _key(RaidTransition t) => switch (t) {
  RaidStartedTransition() => ('started', t.id, t.time, null),
  final RaidEndedTransition e => ('ended', e.id, e.time, e.cause),
  MatchingAbortedTransition() => ('aborted', t.id, t.time, null),
};

void main() {
  late Directory root;
  late Directory folder;
  final readers = <SessionLogReader>[];

  SessionLogReader newReader() {
    final reader = SessionLogReader(pollInterval: const Duration(days: 1));
    readers.add(reader);
    return reader;
  }

  Future<void> write(LogFile file, String text, {bool append = false}) =>
      File('${folder.path}/${_fileName(file)}').writeAsString(
        text,
        mode: append ? FileMode.append : FileMode.write,
        flush: true,
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('blackgrid-raid-lifecycle-');
    folder = await Directory('${root.path}/$_folder').create();
  });
  tearDown(() async {
    for (final reader in readers) {
      await reader.close();
    }
    readers.clear();
    await root.delete(recursive: true);
  });

  /// Builds a controller over a fresh reader, collecting its transitions.
  (RaidLifecycleController, SessionLogReader, List<RaidTransition>) open() {
    final reader = newReader();
    final controller = RaidLifecycleController(reader);
    addTearDown(controller.dispose);
    final seen = <RaidTransition>[];
    controller.transitions.listen(seen.add);
    return (controller, reader, seen);
  }

  Future<List<RaidTransition>> replay() async {
    final (_, reader, seen) = open();
    await reader.bind(root.path);
    return seen;
  }

  Future<void> writeWhole() async {
    for (final file in LogFile.values) {
      await write(file, '');
    }
    for (final (file, line) in _session) {
      await write(file, line, append: true);
    }
  }

  test('replay and live read end the raid identically', () async {
    await writeWhole();
    final replayed = await replay();

    // Live: start from empty files and append each line in log order.
    await root.delete(recursive: true);
    root = await Directory.systemTemp.createTemp('blackgrid-raid-lifecycle-');
    folder = await Directory('${root.path}/$_folder').create();
    for (final file in LogFile.values) {
      await write(file, '');
    }
    final (controller, reader, live) = open();
    await reader.bind(root.path);
    expect(live, isEmpty);
    for (final (file, line) in _session) {
      await write(file, line, append: true);
      await reader.rescan();
    }

    for (final run in [replayed, live]) {
      final ended = run.whereType<RaidEndedTransition>().single;
      expect(ended.time, DateTime(2026, 10, 31, 22, 9, 4));
      expect(ended.cause, RaidEndCause.raidExit);
      expect(ended.id, const LogRecordId(_folder, LogFile.backend, 0));
    }
    expect(live.map(_key).toList(), replayed.map(_key).toList());
    expect(controller.state.phase, RaidPhase.inMenus);
    expect(controller.state.raid!.endCause, RaidEndCause.raidExit);
  });

  test('re-reading a folder republishes the same transitions', () async {
    await writeWhole();
    final first = await replay();
    final second = await replay();

    expect(first.map((t) => _key(t).$1), ['aborted', 'started', 'ended']);
    expect(second.map(_key).toList(), first.map(_key).toList());
  });

  test('dispose stops the subscription and closes transitions', () async {
    await writeWhole();
    final reader = newReader();
    final controller = RaidLifecycleController(reader);
    var done = false;
    controller.transitions.listen((_) {}, onDone: () => done = true);
    controller.dispose();
    expect(done, isTrue);
    await reader.bind(root.path);
    expect(controller.state.phase, RaidPhase.unknown);
  });
}
