import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/session_log_reader.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/map_session.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:test/test.dart';

const _older = 'log_2026.10.30_20-27-43_1.3.0.0.48484';
const _newer = 'log_2026.10.31_21-21-11_1.3.0.0.48484';
const _version = '1.3.0.0.48484';

String _line(String log, String message, [String time = '21:30:00.000']) =>
    '2026-10-31 $time|$_version|Info|$log|$message\n';

String _app(String message, [String time = '21:30:00.000']) =>
    _line('application', message, time);

String _backendExit([String tracking = 't1', String time = '21:30:00.000']) =>
    _line(
      'backend',
      'WebSocketSharp - binary message received: type=Notification, '
          'trackingId=$tracking, payloadType=userMatchOver, payloadLength=393',
      time,
    );

String _push(Object body, [String time = '21:30:00.000']) =>
    '${_line('push-notifications', 'Got notification | ChatMessageReceived', time)}'
    '${body is String ? body : const JsonEncoder.withIndent('  ').convert(body)}\n';

Map<String, Object?> _taskStarted(String task) => {
  'type': 'new_message',
  'message': {'type': 10, 'templateId': '$task description'},
};

const _badPush = '{ "type": \n}';

void main() {
  late Directory root;
  late SessionLogReader reader;
  late List<List<GameLogEvent>> batches;

  SessionLogReader newReader() => SessionLogReader(
    pollInterval: const Duration(days: 1),
    chunkBytes: 64,
    maxLineBytes: 4096,
  );

  Future<File> write(
    String folder,
    String name,
    String text, {
    bool append = false,
  }) async {
    final directory = await Directory('${root.path}/$folder').create();
    return File('${directory.path}/$name').writeAsString(
      text,
      mode: append ? FileMode.append : FileMode.write,
      flush: true,
    );
  }

  List<RecordedGameLogEvent> records() => [
    for (final batch in batches) ...batch.whereType<RecordedGameLogEvent>(),
  ];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('blackgrid-events-');
    reader = newReader();
    batches = [];
    reader.events.listen(batches.add);
  });
  tearDown(() async {
    await reader.close();
    await root.delete(recursive: true);
  });

  test('reads the three files of the newest folder only', () async {
    for (final folder in [_older, _newer]) {
      await write(folder, 'application_000.log', _app('GameStarted: x'));
      await write(folder, 'backend_000.log', _backendExit());
      await write(
        folder,
        'push-notifications_000.log',
        _push(_taskStarted('aaaa')),
      );
    }
    await reader.bind(root.path);
    expect(batches, hasLength(1));
    expect(batches.single.take(2), [
      isA<LogInputReset>(),
      isA<SessionFolderChanged>().having((e) => e.folder, 'folder', _newer),
    ]);
    final found = records();
    expect({for (final e in found) e.id.folder}, {_newer});
    expect(
      {for (final e in found) e.id.file},
      {LogFile.application, LogFile.backend, LogFile.pushNotifications},
    );
  });

  test('a newer folder replaces the current one', () async {
    await write(_older, 'application_000.log', _app('GameStarted: x'));
    await reader.bind(root.path);
    batches.clear();
    await write(_newer, 'application_000.log', _app('GameStarting: y'));
    await reader.rescan();
    expect(batches, hasLength(1));
    expect(batches.single.first, isA<SessionFolderChanged>());
    expect((batches.single.first as SessionFolderChanged).folder, _newer);
    expect(batches.single.skip(1), [isA<RaidStarting>()]);
    expect(records().single.id.folder, _newer);
    // Later appends to the old folder are not read.
    await write(
      _older,
      'application_000.log',
      _app('GameStarted: z'),
      append: true,
    );
    await reader.rescan();
    expect(records(), hasLength(1));
  });

  test('a new folder without its application log yet does not reset the '
      'raid input', () async {
    await write(_older, 'application_000.log', _app('GameStarted: x'));
    await reader.bind(root.path);
    batches.clear();
    await Directory('${root.path}/$_newer').create();
    await reader.rescan();
    expect(batches.expand((b) => b), isEmpty);
    expect(reader.state.status, MapInputStatus.missing);
    expect(
      reader.state.message,
      'No current application log found in the configured root.',
    );
    await reader.rescan();
    expect(batches.expand((b) => b), isEmpty);
    await write(_newer, 'application_000.log', _app('GameStarting: y'));
    await reader.rescan();
    final events = batches.expand((b) => b).toList();
    expect(events.whereType<LogInputReset>(), isEmpty);
    expect(events.first, isA<SessionFolderChanged>());
    expect((events.first as SessionFolderChanged).folder, _newer);
    expect(events.skip(1), [isA<RaidStarting>()]);
  });

  test('a vanished root still resets the raid input', () async {
    await write(_older, 'application_000.log', _app('GameStarted: x'));
    await reader.bind(root.path);
    batches.clear();
    await Directory('${root.path}/$_older').delete(recursive: true);
    await reader.rescan();
    expect(batches.expand((b) => b), [isA<LogInputReset>()]);
  });

  test('missing push log keeps application and backend events', () async {
    await write(_newer, 'application_000.log', _app('GameStarted: x'));
    await write(_newer, 'backend_000.log', _backendExit());
    await reader.bind(root.path);
    expect(records().map((e) => e.id.file).toSet(), {
      LogFile.application,
      LogFile.backend,
    });
    expect(reader.state.raidLogsMessage, 'notifications log not written yet');
    expect(reader.state.status, MapInputStatus.watching);
    await write(
      _newer,
      'push-notifications_000.log',
      _push(_taskStarted('aaaa')),
    );
    await reader.rescan();
    expect(reader.state.raidLogsMessage, isNull);
    expect(records().last, isA<TaskStarted>());
  });

  test('no session folder produces no events', () async {
    await reader.bind(root.path);
    expect(records(), isEmpty);
    expect(batches.expand((b) => b), everyElement(isA<LogInputReset>()));
    expect(reader.state.status, MapInputStatus.missing);
    expect(reader.state.raidLogsMessage, isNull);
    await reader.rescan();
    expect(records(), isEmpty);
  });

  test('rejected push record reports on raid logs only', () async {
    await write(
      _newer,
      'application_000.log',
      _app('Session mode: Pve') +
          _app('scene preset path:maps/woods.bundle', '21:30:01.000'),
    );
    await write(_newer, 'backend_000.log', '');
    await write(_newer, 'push-notifications_000.log', _push(_badPush));
    await reader.bind(root.path);
    final state = reader.state;
    expect(state.detectedMapId, 'woods');
    expect(state.detectedMode, GameMode.pve);
    expect(state.status, MapInputStatus.watching);
    expect(state.message, isNull);
    expect(
      state.raidLogsMessage,
      allOf(contains('notifications'), contains('rejected')),
    );
    // The rejection stays until newer bytes read cleanly.
    await reader.rescan();
    expect(reader.state.raidLogsMessage, contains('rejected'));
    await write(
      _newer,
      'push-notifications_000.log',
      _push(_taskStarted('aaaa'), '21:31:00.000'),
      append: true,
    );
    await reader.rescan();
    expect(reader.state.raidLogsMessage, isNull);
    expect(reader.state.detectedMapId, 'woods');
    expect(reader.state.incarnation, state.incarnation);
  });

  Future<void> rescanWithPushOpenFailing() => IOOverrides.runZoned(
    reader.rescan,
    createDirectory: (path) {
      expect(path, root.path);
      return _FailingOpenDirectory(
        root,
        (file) => file.path.endsWith('push-notifications_000.log'),
      );
    },
  );

  test('a read failure clears on the next clean read', () async {
    await write(_newer, 'application_000.log', _app('GameStarted: x'));
    await write(_newer, 'backend_000.log', '');
    await write(
      _newer,
      'push-notifications_000.log',
      _push(_taskStarted('aaaa')),
    );
    await reader.bind(root.path);
    expect(reader.state.raidLogsMessage, isNull);
    await rescanWithPushOpenFailing();
    expect(reader.state.raidLogsMessage, 'notifications log could not be read');
    // No new bytes: the retry alone must clear the transient failure.
    await reader.rescan();
    expect(reader.state.raidLogsMessage, isNull);
  });

  test('a read failure does not hide an earlier rejection', () async {
    await write(_newer, 'application_000.log', _app('GameStarted: x'));
    await write(_newer, 'backend_000.log', '');
    await write(_newer, 'push-notifications_000.log', _push(_badPush));
    await reader.bind(root.path);
    expect(reader.state.raidLogsMessage, contains('rejected'));
    await rescanWithPushOpenFailing();
    expect(reader.state.raidLogsMessage, contains('could not be read'));
    await reader.rescan();
    expect(reader.state.raidLogsMessage, contains('rejected'));
    await write(
      _newer,
      'push-notifications_000.log',
      _push(_taskStarted('aaaa'), '21:31:00.000'),
      append: true,
    );
    await reader.rescan();
    expect(reader.state.raidLogsMessage, isNull);
  });

  test('backend rewrite keeps map, mode and incarnation', () async {
    await write(
      _newer,
      'application_000.log',
      _app('Session mode: Pve') +
          _app('scene preset path:maps/woods.bundle', '21:30:01.000'),
    );
    final backend = await write(_newer, 'backend_000.log', _backendExit('t1'));
    await write(_newer, 'push-notifications_000.log', '');
    await reader.bind(root.path);
    final before = reader.state;
    expect(before.raidLogsMessage, isNull);
    batches.clear();
    // Same length, different bytes: the tail must notice the rewrite.
    await backend.writeAsString(_backendExit('t2'), flush: true);
    await reader.rescan();
    final after = reader.state;
    expect(after.detectedMapId, 'woods');
    expect(after.detectedMode, GameMode.pve);
    expect(after.incarnation, before.incarnation);
    expect(after.status, before.status);
    expect(after.message, before.message);
    expect(after.raidLogsMessage, contains('backend'));
    expect(batches.expand((b) => b).whereType<LogInputReset>(), isEmpty);
    expect(records().single, isA<RaidExit>());
    await write(
      _newer,
      'backend_000.log',
      _backendExit('t3', '21:32:00.000'),
      append: true,
    );
    await reader.rescan();
    expect(reader.state.raidLogsMessage, isNull);
  });

  test('a second reader gives the same identities and times', () async {
    await write(
      _newer,
      'application_000.log',
      _app('PrepareSelectedProfileLocally ProfileId:aaaa AccountId:1') +
          _app('Matching with group id: 3515690', '21:30:01.000'),
    );
    await write(_newer, 'backend_000.log', _backendExit());
    await write(
      _newer,
      'push-notifications_000.log',
      _push(_taskStarted('aaaa')),
    );
    await reader.bind(root.path);
    final second = newReader();
    addTearDown(second.close);
    final secondBatches = <List<GameLogEvent>>[];
    second.events.listen(secondBatches.add);
    await second.bind(root.path);
    List<(LogRecordId, DateTime)> keys(List<List<GameLogEvent>> from) => [
      for (final batch in from)
        for (final e in batch.whereType<RecordedGameLogEvent>()) (e.id, e.time),
    ];
    expect(keys(batches), hasLength(4));
    expect(keys(secondBatches), keys(batches));
  });

  test('identical lines get different identities', () async {
    final line = _app('Matching with group id: 3515690');
    await write(_newer, 'application_000.log', line + line);
    await reader.bind(root.path);
    final found = records();
    expect(found, hasLength(2));
    expect(found[0], isA<QueueEntered>());
    expect(found[1], isA<QueueEntered>());
    expect(found[0].time, found[1].time);
    expect(found[0].id, isNot(found[1].id));
  });

  test('equal times sort application before backend', () async {
    await write(_newer, 'backend_000.log', _backendExit());
    await write(
      _newer,
      'application_000.log',
      _app('PrepareSelectedProfileLocally ProfileId:aaaa AccountId:1'),
    );
    await reader.bind(root.path);
    expect(records(), [isA<ProfileSelected>(), isA<RaidExit>()]);
  });
}

/// Wraps a real directory so that opening a matching listed file fails.
class _FailingOpenDirectory implements Directory {
  _FailingOpenDirectory(this.directory, this.fails);

  final Directory directory;
  final bool Function(File file) fails;

  @override
  String get path => directory.path;

  @override
  Future<bool> exists() => directory.exists();

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    await for (final entry in directory.list(
      recursive: recursive,
      followLinks: followLinks,
    )) {
      if (entry is Directory) {
        yield _FailingOpenDirectory(entry, fails);
      } else if (entry is File && fails(entry)) {
        yield _FailingOpenFile(entry);
      } else {
        yield entry;
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected directory operation: ${invocation.memberName}',
  );
}

/// A listed file whose [open] always fails, as a locked file would.
class _FailingOpenFile implements File {
  _FailingOpenFile(this.file);

  final File file;

  @override
  String get path => file.path;

  @override
  Future<FileStat> stat() => file.stat();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      throw FileSystemException('locked for the test', path);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected file operation: ${invocation.memberName}',
  );
}
