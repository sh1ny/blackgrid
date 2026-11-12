import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:blackgrid/data/game_log/session_folder_read.dart';
import 'package:blackgrid/data/session_log_reader.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:test/test.dart';

const _folder = 'log_2026.10.31_21-21-11_1.3.0.0.48484';
const _taskA = '5936d90786f7742b1420ba5b';
const _taskB = '5936d90786f7742b1420ba5c';

String _line(String log, String message, String time) =>
    '2026-10-31 $time|1.3.0.0.48484|Info|$log|$message\n';

String _mode(String mode, String time) =>
    _line('application', 'Session mode: $mode', time);

String _push(Object body, String time) =>
    '${_line('push-notifications', 'Got notification | ChatMessageReceived', time)}'
    '${body is String ? body : const JsonEncoder.withIndent('  ').convert(body)}\n';

Map<String, Object?> _task(String id) => {
  'type': 'new_message',
  'message': {'type': 10, 'templateId': '$id description'},
};

void main() {
  late Directory root;
  late Directory folder;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('blackgrid-folder-read-');
    folder = await Directory('${root.path}/$_folder').create();
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<void> writeLog(String name, String contents) async {
    await File('${folder.path}/$name').writeAsString(contents, flush: true);
  }

  test('one-shot read matches live read identities and times', () async {
    await writeLog(
      'application_000.log',
      _mode('Pve', '21:30:01.000') + _mode('Pvp', '21:30:03.000'),
    );
    await writeLog(
      'push-notifications_000.log',
      _push(_task(_taskA), '21:30:00.000') +
          _push(_task(_taskA), '21:30:01.000') +
          _push(_task(_taskB), '21:30:02.000') +
          _push(_task(_taskA), '21:30:03.000'),
    );

    final live = SessionLogReader(pollInterval: const Duration(days: 1));
    addTearDown(live.close);
    final events = <GameLogEvent>[];
    live.events.listen(events.addAll);
    await live.bind(root.path);
    final before = live.state;
    final eventCount = events.length;
    var state = RaidLifecycleState.initial;
    final transitions = <TaskTransition>[];
    for (final event in events) {
      final (next, published) = reduce(state, event);
      state = next;
      transitions.addAll(published.whereType<TaskTransition>());
    }
    expect(transitions, hasLength(4));
    expect(transitions.map((task) => task.mode), [
      null,
      GameMode.pve,
      GameMode.pve,
      GameMode.pvp,
    ]);

    final folderPath = folder.path;
    final result = await Isolate.run(() => readSessionFolderTasks(folderPath));
    final liveKnown = transitions.where((task) => task.mode != null);
    expect(result.folder, _folder);
    expect(result.unreadable, isFalse);
    expect(result.skippedNoMode, 1);
    expect(result.rejected, 0);
    expect(result.tasks, hasLength(3));
    expect(
      result.tasks.map(
        (task) => (task.id, task.time, task.taskId, task.status, task.mode),
      ),
      liveKnown.map(
        (task) => (task.id, task.time, task.taskId, task.status, task.mode),
      ),
    );
    expect(live.state, same(before));
    expect(events, hasLength(eventCount));
  });

  test('push log without application log gives tasks with no mode', () async {
    await writeLog(
      'push-notifications_000.log',
      _push(_task(_taskA), '21:30:01.000') +
          _push(_task(_taskB), '21:30:02.000'),
    );

    final result = await readSessionFolderTasks(folder.path);
    expect(result.folder, _folder);
    expect(result.unreadable, isFalse);
    expect(result.tasks, isEmpty);
    expect(result.skippedNoMode, 2);
    expect(result.rejected, 0);
  });

  test('unreadable folder is reported and yields no events', () async {
    await writeLog('application_000.log', _mode('Pve', '21:30:00.000'));
    await writeLog(
      'push-notifications_000.log',
      _push(_task(_taskA), '21:30:01.000'),
    );
    final live = SessionLogReader(pollInterval: const Duration(days: 1));
    addTearDown(live.close);
    final events = <GameLogEvent>[];
    live.events.listen(events.addAll);
    await live.bind(root.path);
    final before = live.state;
    final eventCount = events.length;

    final result = await readSessionFolderTasks('${root.path}/missing');
    expect(result.folder, 'missing');
    expect(result.unreadable, isTrue);
    expect(result.tasks, isEmpty);
    expect(result.skippedNoMode, 0);
    expect(result.rejected, 0);
    expect(live.state, same(before));

    final application = File('${folder.path}/application_000.log');
    final push = File('${folder.path}/push-notifications_000.log');
    final failingPush = _FailingOpenFile(push);
    final locked = await IOOverrides.runZoned(
      () => readSessionFolderTasks(folder.path),
      createDirectory: (_) => _FailingOpenDirectory(folder, failingPush),
      createFile: (path) => path.endsWith('push-notifications_000.log')
          ? failingPush
          : application,
    );
    expect(locked.folder, _folder);
    expect(locked.unreadable, isTrue);
    expect(locked.tasks, isEmpty);
    expect(live.state, same(before));
    expect(events, hasLength(eventCount));
  });

  test('unrecognised mode is skipped before a later known mode', () async {
    await writeLog(
      'application_000.log',
      _mode('unknownMode', '21:30:00.000') + _mode('Pve', '21:30:02.000'),
    );
    await writeLog(
      'push-notifications_000.log',
      _push(_task(_taskA), '21:30:01.000') +
          _push(_task(_taskB), '21:30:03.000'),
    );

    final result = await readSessionFolderTasks(folder.path);
    expect(result.unreadable, isFalse);
    expect(result.skippedNoMode, 1);
    expect(result.rejected, 0);
    expect(result.tasks.map((task) => task.taskId), [_taskB]);
    expect(result.tasks.single.mode, GameMode.pve);
  });

  test('malformed push record is counted and others are read', () async {
    await writeLog('application_000.log', _mode('Pve', '21:30:00.000'));
    await writeLog(
      'push-notifications_000.log',
      _push(_task(_taskA), '21:30:01.000') +
          _push('{ "type": \n}', '21:30:02.000') +
          _push(_task(_taskB), '21:30:03.000'),
    );

    final result = await readSessionFolderTasks(folder.path);
    expect(result.folder, _folder);
    expect(result.unreadable, isFalse);
    expect(result.rejected, 1);
    expect(result.skippedNoMode, 0);
    expect(result.tasks.map((task) => task.taskId), [_taskA, _taskB]);
    expect(result.tasks.map((task) => task.mode), [GameMode.pve, GameMode.pve]);
  });

  test('incomplete application snapshot yields no task output', () async {
    await writeLog(
      'application_000.log',
      _mode('Pvp', '21:30:00.000') + _mode('Pve', '21:30:01.000').trimRight(),
    );
    await writeLog(
      'push-notifications_000.log',
      _push(_task(_taskA), '21:30:02.000'),
    );
    final result = await readSessionFolderTasks(folder.path);
    expect(result.unreadable, isTrue);
    expect(result.tasks, isEmpty);

    await writeLog('application_000.log', _mode('Pve', '21:30:01.000'));
    final short = await readSessionFolderTasks(
      folder.path,
      snapshotStat: (file) async {
        final stat = await file.stat();
        return file.path.endsWith('application_000.log')
            ? _OversizedStat(stat)
            : stat;
      },
    );
    expect(short.unreadable, isTrue);
    expect(short.tasks, isEmpty);

    final failingApplication = _FailingOpenFile(
      File('${folder.path}/application_000.log'),
    );
    final failed = await IOOverrides.runZoned(
      () => readSessionFolderTasks(folder.path),
      createDirectory: (_) => _FailingOpenDirectory(folder, failingApplication),
    );
    expect(failed.unreadable, isTrue);
    expect(failed.tasks, isEmpty);
  });

  test('active folder snapshot includes all preceding mode evidence', () async {
    await writeLog('application_000.log', _mode('Pvp', '21:30:00.000'));
    await writeLog('push-notifications_000.log', '');
    var appendAtSnapshot = true;
    final application = File('${folder.path}/application_000.log');
    final push = File('${folder.path}/push-notifications_000.log');
    final result = await readSessionFolderTasks(
      folder.path,
      snapshotStat: (file) async {
        final snapshot = await file.stat();
        if (appendAtSnapshot) {
          appendAtSnapshot = false;
          await application.writeAsString(
            _mode('Pve', '21:30:01.000'),
            mode: FileMode.append,
            flush: true,
          );
          await push.writeAsString(
            _push(_task(_taskA), '21:30:02.000'),
            mode: FileMode.append,
            flush: true,
          );
        }
        return snapshot;
      },
    );
    expect(result.unreadable, isFalse);
    expect(result.tasks.map((task) => task.mode), everyElement(GameMode.pve));
    final replay = await readSessionFolderTasks(folder.path);
    expect(replay.tasks.single.mode, GameMode.pve);
    expect(replay.tasks.single.taskId, _taskA);
  });
}

class _FailingOpenDirectory implements Directory {
  _FailingOpenDirectory(this.directory, this.failingFile);

  final Directory directory;
  final File failingFile;

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
      if (entry.path.replaceAll('\\', '/') ==
          failingFile.path.replaceAll('\\', '/')) {
        yield failingFile;
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

class _FailingOpenFile implements File {
  _FailingOpenFile(this.file);

  final File file;

  @override
  String get path => file.path;

  @override
  Future<bool> exists() => file.exists();

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

class _OversizedStat implements FileStat {
  _OversizedStat(this._stat);
  final FileStat _stat;

  @override
  int get size => _stat.size + 1;

  @override
  FileSystemEntityType get type => _stat.type;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected snapshot stat: ${invocation.memberName}',
  );
}
