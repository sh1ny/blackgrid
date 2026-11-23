import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/application/raid_lifecycle_controller.dart';
import 'package:blackgrid/data/game_log/game_log_parsers.dart';
import 'package:blackgrid/data/session_log_reader.dart';
import 'package:blackgrid/domain/alert_rules.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/local_progress.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

const _folder = 'log_2026.10.31_22-00-00_1.3.0.0.48484';
const _version = '1.3.0.0.48484';

String _line(String log, String message, String time) =>
    '2026-10-31 $time|$_version|Info|$log|$message\n';

String _start(String time) => _line('application', 'GameStarted: 7', time);

String _profile(String time) => _line(
  'application',
  'PrepareSelectedProfileLocally ProfileId:aaaa AccountId:1',
  time,
);

String _rejoin(String time) => _line(
  'application',
  'Transit reconnect status:MatchWait raidMode:Online location:laboratory',
  time,
);

String _queue(String time) =>
    _line('application', 'Matching with group id: 1', time);

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
    _line(
      'application',
      'TRACE-NetworkGameCreate profileStatus: Location: bigmap',
      '22:02:31.000',
    ),
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
  FleaSoldTransition() => ('flea', t.id, t.time, null),
  TaskTransition() => ('task', t.id, t.time, null),
  QueueEnteredTransition() => ('queue', t.id, t.time, null),
  MapKnownTransition() => ('map', t.id, t.time, null),
  MatchFoundTransition() => ('found', t.id, t.time, null),
  RaidStartingTransition() => ('starting', t.id, t.time, null),
};

/// A flea sale of 2 of one item paying 45 000 roubles, as the game logs it.
final String _saleRecord =
    '2026-10-31 22:05:00.000|$_version|Info|push-notifications|'
    'Got notification | ChatMessageReceived\n'
    '${const JsonEncoder.withIndent('  ').convert({
      'type': 'new_message',
      'message': {
        'type': 4,
        'systemData': {'soldItem': 'item-a', 'itemCount': 2},
        'items': {
          'data': [
            {
              '_tpl': roublesTemplateId,
              'upd': {'StackObjectsCount': 45000},
            },
          ],
        },
      },
    })}\n';

void main() {
  late Directory root;
  late Directory folder;
  final readers = <SessionLogReader>[];

  SessionLogReader newReader({
    Future<FileStat> Function(File file)? snapshotStat,
  }) {
    final reader = SessionLogReader(
      pollInterval: const Duration(days: 1),
      snapshotStat: snapshotStat,
    );
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
  (RaidLifecycleController, SessionLogReader, List<RaidTransition>) open({
    Future<FileStat> Function(File file)? snapshotStat,
  }) {
    final reader = newReader(snapshotStat: snapshotStat);
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

    expect(first.map((t) => _key(t).$1), [
      'queue',
      'aborted',
      'queue',
      'map',
      'found',
      'starting',
      'started',
      'ended',
    ]);
    expect(second.map(_key).toList(), first.map(_key).toList());
  });

  test(
    're-reading a folder republishes queue progress with the same identities',
    () async {
      await writeWhole();
      final first = await replay();
      final second = await replay();

      bool isProgress(RaidTransition t) =>
          t is QueueEnteredTransition ||
          t is MapKnownTransition ||
          t is MatchFoundTransition ||
          t is RaidStartingTransition;
      final firstProgress = first.where(isProgress).toList();
      expect(firstProgress, hasLength(5));
      expect(
        second.where(isProgress).map(_key).toList(),
        firstProgress.map(_key).toList(),
      );
      final map = firstProgress.whereType<MapKnownTransition>().single;
      expect(map.mapId, 'customs');
      expect(map.time, DateTime(2026, 10, 31, 22, 2, 20));
    },
  );

  test('replayed folder republishes the sale with the same identity', () async {
    await write(LogFile.backend, '');
    await write(
      LogFile.application,
      _line('application', 'Session mode: Regular', '22:00:00.000'),
    );
    await write(LogFile.pushNotifications, _saleRecord);
    final first = await replay();
    final second = await replay();

    for (final run in [first, second]) {
      final sale = run.whereType<FleaSoldTransition>().single;
      expect(sale.id, const LogRecordId(_folder, LogFile.pushNotifications, 0));
      expect(sale.time, DateTime(2026, 10, 31, 22, 5));
      expect(sale.itemId, 'item-a');
      expect(sale.count, 2);
      expect(sale.roubles, 45000);
    }
    expect(second.map(_key).toList(), first.map(_key).toList());
  });

  test('re-reading a folder republishes task transitions with the same identity', () async {
    const taskId = '5936d90786f7742b1420ba5b';
    String taskRecord(int type, String time) =>
        '${_line('push-notifications', 'Got notification | ChatMessageReceived', time)}'
        '${const JsonEncoder.withIndent('  ').convert({
          'type': 'new_message',
          'message': {'type': type, 'templateId': '$taskId description'},
        })}\n';

    final records = [
      taskRecord(10, '22:01:00.000'),
      taskRecord(11, '22:02:00.000'),
      taskRecord(12, '22:03:00.000'),
    ];
    await write(LogFile.backend, '');
    await write(
      LogFile.application,
      _line('application', 'Session mode: Regular', '22:00:00.000'),
    );
    await write(LogFile.pushNotifications, records.join());

    final (firstController, firstReader, first) = open();
    await firstReader.bind(root.path);
    firstController.dispose();
    await firstReader.close();
    readers.remove(firstReader);
    final second = await replay();

    final expected = [
      (
        const LogRecordId(_folder, LogFile.pushNotifications, 0),
        DateTime(2026, 10, 31, 22, 1),
        taskId,
        ProgressTaskStatus.started,
        GameMode.pvp,
      ),
      (
        LogRecordId(
          _folder,
          LogFile.pushNotifications,
          utf8.encode(records[0]).length,
        ),
        DateTime(2026, 10, 31, 22, 2),
        taskId,
        ProgressTaskStatus.failed,
        GameMode.pvp,
      ),
      (
        LogRecordId(
          _folder,
          LogFile.pushNotifications,
          utf8.encode(records[0] + records[1]).length,
        ),
        DateTime(2026, 10, 31, 22, 3),
        taskId,
        ProgressTaskStatus.finished,
        GameMode.pvp,
      ),
    ];
    for (final run in [first, second]) {
      expect(run, hasLength(3));
      expect(
        run.map((transition) {
          final task = transition as TaskTransition;
          return (task.id, task.time, task.taskId, task.status, task.mode);
        }).toList(),
        expected,
      );
    }
  });

  test('a new folder without its application log yet keeps the raid', () async {
    const next = 'log_2026.10.31_23-00-00_1.3.0.0.48484';
    final (controller, reader, seen) = open();
    await write(LogFile.application, '');
    await reader.bind(root.path);
    for (final (file, line) in _session.take(9)) {
      if (file == LogFile.application) {
        await write(LogFile.application, line, append: true);
      }
    }
    await reader.rescan();
    final raid = controller.state.raid!;
    expect(controller.state.phase, RaidPhase.inRaid);
    expect(
      seen
          .map((t) => _key(t).$1)
          .where((kind) => kind == 'aborted' || kind == 'started'),
      ['aborted', 'started'],
    );

    // The restarted client creates its folder before its application log.
    await Directory('${root.path}/$next').create();
    await reader.rescan();
    expect(controller.state.raid, raid);

    await File('${root.path}/$next/application_000.log').writeAsString(
      _line(
            'application',
            'PrepareSelectedProfileLocally ProfileId:aaaa AccountId:1',
            '23:00:30.000',
          ) +
          _line(
            'application',
            'Transit reconnect status:MatchWait raidMode:Online '
                'location:laboratory',
            '23:00:40.000',
          ) +
          _line('application', 'GameStarted: 8', '23:01:00.000'),
      flush: true,
    );
    await reader.rescan();

    expect(
      seen
          .map((t) => _key(t).$1)
          .where((kind) => kind == 'aborted' || kind == 'started'),
      ['aborted', 'started'],
    );
    expect(controller.state.phase, RaidPhase.inRaid);
    expect(controller.state.raid!.interrupted, isFalse);
  });

  test('cleanup skips startup and reconnect-only raids', () async {
    await write(LogFile.application, _start('22:00:00.000'));
    final (controller, reader, seen) = open();
    final cleanup = <RaidTransition>[];
    controller.cleanupTransitions.listen(cleanup.add);
    await reader.bind(root.path);

    await write(
      LogFile.application,
      _profile('22:00:05.000') +
          _queue('22:00:06.000') +
          _rejoin('22:00:07.000') +
          _start('22:00:08.000') +
          _profile('22:00:10.000'),
      append: true,
    );
    await reader.rescan();
    expect(
      seen.whereType<RaidStartedTransition>().map((start) => start.raid.entry),
      [RaidEntry.noQueue, RaidEntry.reconnect],
    );
    expect(seen.whereType<RaidEndedTransition>(), hasLength(2));
    expect(cleanup, isEmpty);

    await write(LogFile.application, _start('22:00:11.000'), append: true);
    await reader.rescan();
    // The backend role was confirmed absent when the session was bound.
    await write(LogFile.backend, _session[9].$2);
    await reader.rescan();
    expect(cleanup, [seen.whereType<RaidEndedTransition>().last]);
    expect(
      (cleanup.single as RaidEndedTransition).cause,
      RaidEndCause.raidExit,
    );
  });

  test(
    'cleanup ignores deferred baseline bytes after clock rollback',
    () async {
      final partialStart = _start('22:00:00.000');
      // The start's header is already on disk, but not its final newline.
      await write(
        LogFile.application,
        partialStart.substring(0, partialStart.length - 1),
      );
      final (controller, reader, seen) = open();
      final cleanup = <RaidTransition>[];
      controller.cleanupTransitions.listen(cleanup.add);
      await reader.bind(root.path);
      expect(seen, isEmpty);

      await write(
        LogFile.application,
        '\n${_profile('22:00:05.000')}',
        append: true,
      );
      await reader.rescan();
      final replayed = seen.whereType<RaidEndedTransition>().single;
      final initialClock = DateTime(2026, 10, 31, 23);
      final rolledBackClock = DateTime(2026, 10, 31, 22, 0, 10);
      expect(isFreshLogTime(replayed.time, initialClock), isFalse);
      expect(isFreshLogTime(replayed.time, rolledBackClock), isTrue);
      expect(cleanup, isEmpty);

      await write(
        LogFile.application,
        _start('22:00:11.000') + _profile('22:00:12.000'),
        append: true,
      );
      await reader.rescan();
      expect(cleanup, [seen.whereType<RaidEndedTransition>().last]);
    },
  );

  test(
    'the first successful snapshot baselines an unknown file size',
    () async {
      await write(LogFile.application, _start('22:00:00.000'));
      var failStat = true;
      final (controller, reader, seen) = open(
        snapshotStat: (file) async {
          if (failStat) {
            throw FileSystemException('no snapshot size', file.path);
          }
          return file.stat();
        },
      );
      final cleanup = <RaidTransition>[];
      controller.cleanupTransitions.listen(cleanup.add);
      await reader.bind(root.path);
      expect(seen, isEmpty);

      await write(LogFile.application, _profile('22:00:05.000'), append: true);
      failStat = false;
      await reader.rescan();
      expect(seen.whereType<RaidEndedTransition>(), hasLength(1));
      expect(cleanup, isEmpty);

      await write(
        LogFile.application,
        _start('22:00:11.000') + _profile('22:00:12.000'),
        append: true,
      );
      await reader.rescan();
      expect(cleanup, [seen.whereType<RaidEndedTransition>().last]);
    },
  );

  for (final reconnect in [false, true]) {
    test(
      reconnect
          ? 'cleanup keeps the original live raid identity across reconnect'
          : 'cleanup publishes a live crash ending immediately before its queue',
      () async {
        await write(LogFile.application, '');
        final (controller, reader, seen) = open();
        final cleanup = <RaidTransition>[];
        controller.cleanupTransitions.listen(cleanup.add);
        await reader.bind(root.path);
        await write(LogFile.application, _start('22:00:00.000'), append: true);
        await reader.rescan();
        final original = seen.whereType<RaidStartedTransition>().single;

        const next = 'log_2026.10.31_23-00-00_1.3.0.0.48484';
        folder = await Directory('${root.path}/$next').create();
        await write(
          LogFile.application,
          _profile('23:00:01.000') +
              (reconnect
                  ? _rejoin('23:00:05.000') +
                        _start('23:00:10.000') +
                        _profile('23:00:15.000')
                  : _queue('23:05:00.000')),
        );
        await reader.rescan();

        expect(seen.whereType<RaidStartedTransition>(), [original]);
        final ended = seen.whereType<RaidEndedTransition>().single;
        expect(ended.raid.startId, original.id);
        if (reconnect) {
          expect(ended.cause, RaidEndCause.menus);
          expect(cleanup, [ended]);
        } else {
          expect(ended.cause, RaidEndCause.clientRestart);
          expect(ended.time, DateTime(2026, 10, 31, 23, 0, 1));
          final queue = seen.whereType<QueueEnteredTransition>().single;
          expect(queue.time, DateTime(2026, 10, 31, 23, 5));
          expect(cleanup, [ended, queue]);
        }
      },
    );
  }

  test(
    'a deferred backend replay cannot end an enrolled raid for cleanup',
    () async {
      final partialExit = _session[9].$2;
      await write(LogFile.application, '');
      await write(
        LogFile.backend,
        partialExit.substring(0, partialExit.length - 1),
      );
      final (controller, reader, seen) = open();
      final cleanup = <RaidTransition>[];
      controller.cleanupTransitions.listen(cleanup.add);
      await reader.bind(root.path);

      await write(LogFile.application, _start('22:09:00.000'), append: true);
      await reader.rescan();
      await write(LogFile.backend, '\n', append: true);
      await reader.rescan();
      expect(
        seen.whereType<RaidEndedTransition>().single.cause,
        RaidEndCause.raidExit,
      );
      expect(cleanup, isEmpty);

      await write(
        LogFile.application,
        _start('22:09:05.000') + _profile('22:09:10.000'),
        append: true,
      );
      await reader.rescan();
      expect(cleanup, [seen.whereType<RaidEndedTransition>().last]);
    },
  );

  test('a transit needs both its rejoin record and GameStarted live', () async {
    await write(
      LogFile.application,
      _start('22:00:00.000') +
          _profile('22:00:05.000') +
          _rejoin('22:00:06.000'),
    );
    final (controller, reader, seen) = open();
    final cleanup = <RaidTransition>[];
    controller.cleanupTransitions.listen(cleanup.add);
    await reader.bind(root.path);

    await write(
      LogFile.application,
      _start('22:00:07.000') + _profile('22:00:08.000'),
      append: true,
    );
    await reader.rescan();
    expect(
      seen.whereType<RaidStartedTransition>().last.raid.entry,
      RaidEntry.transit,
    );
    expect(seen.whereType<RaidEndedTransition>(), hasLength(2));
    expect(cleanup, isEmpty);

    await write(LogFile.application, _rejoin('22:00:09.000'), append: true);
    await reader.rescan();
    await write(
      LogFile.application,
      _start('22:00:10.000') + _profile('22:00:11.000'),
      append: true,
    );
    await reader.rescan();
    final started = seen.whereType<RaidStartedTransition>().last;
    final ended = seen.whereType<RaidEndedTransition>().last;
    expect(started.raid.entry, RaidEntry.transit);
    expect(started.time, DateTime(2026, 10, 31, 22, 0, 9));
    expect(ended.raid.startId, started.id);
    expect(cleanup, [ended]);
  });

  test('dispose stops the subscription and closes transitions', () async {
    await writeWhole();
    final reader = newReader();
    final controller = RaidLifecycleController(reader);
    var done = false;
    var cleanupDone = false;
    controller.transitions.listen((_) {}, onDone: () => done = true);
    controller.cleanupTransitions.listen(
      (_) {},
      onDone: () => cleanupDone = true,
    );
    controller.dispose();
    expect(done, isTrue);
    expect(cleanupDone, isTrue);
    await reader.bind(root.path);
    expect(controller.state.phase, RaidPhase.unknown);
  });
}
