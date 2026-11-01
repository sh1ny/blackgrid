import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/session_log_reader.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/domain/map_session.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late SessionLogReader reader;
  late List<SessionLogState> states;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('blackgrid-session-log-');
    reader = SessionLogReader(
      pollInterval: const Duration(days: 1),
      chunkBytes: 1,
      maxLineBytes: 256,
    );
    states = [];
    reader.states.listen(states.add);
  });
  tearDown(() async {
    await reader.close();
    await root.delete(recursive: true);
  });

  Future<File> application(
    String folder,
    String text, {
    String name = 'application.log',
  }) async {
    final directory = await Directory('${root.path}/$folder').create();
    return File('${directory.path}/$name').writeAsString(text, flush: true);
  }

  test(
    'game folders with a version suffix select the newest session',
    () async {
      await application(
        'log_2026.10.06_19-24-14_1.2.0.0.47888',
        'application|scene preset path:maps/woods.bundle\n',
        name: '2026.10.06_19-24-14_1.2.0.0.47888 application_000.log',
      );
      await application(
        'log_2026.10.07_10-25-14_1.2.0.0.47888',
        'Session mode: Pve\napplication|scene preset path:maps/shoreline.bundle\n',
        name: '2026.10.07_10-25-14_1.2.0.0.47888 application_000.log',
      );
      await reader.bind(root.path);
      expect(reader.state.status, MapInputStatus.watching);
      expect(reader.state.detectedMapId, 'shoreline');
      expect(reader.state.detectedMode, GameMode.pve);
    },
  );

  test('tailing past the validation window keeps appending and catches rewrites', () async {
    final file = await application(
      'log_2026.10.07_0-52-00',
      '${'filler line\n' * 500}application|scene preset path:maps/woods.bundle\n',
    );
    await reader.bind(root.path);
    expect(reader.state.detectedMapId, 'woods');
    final incarnation = reader.state.incarnation;
    await file.writeAsString(
      'application|scene preset path:maps/bigmap.bundle\n',
      mode: FileMode.append,
      flush: true,
    );
    await reader.rescan();
    expect(reader.state.detectedMapId, 'customs');
    expect(reader.state.incarnation, incarnation);
    final text = await file.readAsString();
    await file.writeAsString(
      text.replaceFirst('bigmap', 'rezervbase'),
      flush: true,
    );
    await reader.rescan();
    expect(reader.state.detectedMapId, 'reserve');
    expect(reader.state.incarnation, greaterThan(incarnation));
  });

  test('replay reconstructs latest state and duplicate tail transitions do not republish', () async {
    final file = await application(
      'log_2026.10.07_0-52-00',
      'Session mode: Regular\r\napplication|scene preset path:maps/woods.bundle\r\nSession mode: Pve\r\napplication|scene preset path:maps/laboratory.bundle\r\n',
    );
    await reader.bind(root.path);
    expect(reader.state.detectedMapId, 'thelab');
    expect(reader.state.detectedMode, GameMode.pve);
    final count = states.length;
    await reader.rescan();
    await file.writeAsString(
      'Session mode: Pve\napplication|scene preset path:maps/laboratory.bundle\n',
      mode: FileMode.append,
      flush: true,
    );
    await reader.rescan();
    expect(states.length, count);
    await file.writeAsString(
      'application|scene preset path:maps/icebreaker.bundle\n',
      mode: FileMode.append,
      flush: true,
    );
    await reader.rescan();
    expect(reader.state.detectedMapId, 'icebreaker');
  });

  test(
    'split multibyte UTF8 CRLF and partial records wait for completed lines',
    () async {
      final file = await application('log_2026.10.07_0-52-00', '');
      await reader.bind(root.path);
      final bytes = utf8.encode(
        'é application|scene preset path:maps/woods.bundle\r\n',
      );
      await file.writeAsBytes(
        bytes.sublist(0, 1),
        mode: FileMode.append,
        flush: true,
      );
      await reader.rescan();
      expect(reader.state.detectedMapId, isNull);
      await file.writeAsBytes(
        bytes.sublist(1, bytes.length - 1),
        mode: FileMode.append,
        flush: true,
      );
      await reader.rescan();
      expect(reader.state.detectedMapId, isNull);
      await file.writeAsBytes([10], mode: FileMode.append, flush: true);
      await reader.rescan();
      expect(reader.state.detectedMapId, 'woods');
    },
  );

  test('truncation same-path edits rotation and new sessions reset incarnation and mode', () async {
    final file = await application(
      'log_2026.10.07_0-52-00',
      'Session mode: Pve\napplication|scene preset path:maps/woods.bundle\n',
    );
    await reader.bind(root.path);
    final first = reader.state.incarnation;
    await file.writeAsString(
      'application|scene preset path:maps/bigmap.bundle\n',
      flush: true,
    );
    await reader.rescan();
    expect(reader.state.incarnation, greaterThan(first));
    expect(reader.state.detectedMode, GameMode.unknown);
    expect(reader.state.detectedMapId, 'customs');
    final truncated = reader.state.incarnation;
    // Same-length rewrite with identical prefix/suffix is still a new incarnation.
    final padded =
        'header\napplication|scene preset path:maps/woods.bundle\nfooter\n';
    await file.writeAsString(padded, flush: true);
    await reader.rescan();
    final original = reader.state.incarnation;
    await file.writeAsString(
      padded.replaceFirst('woods', 'bogus'),
      flush: true,
    );
    await reader.rescan();
    expect(reader.state.incarnation, greaterThan(original));
    expect(reader.state.incarnation, greaterThan(truncated));
    final rotated = await File('${file.parent.path}/new_application_000.log')
        .writeAsString(
          'Session mode: SZN\napplication|scene preset path:maps/terminal.bundle\n',
          flush: true,
        );
    await rotated.setLastModified(DateTime(2030));
    await reader.rescan();
    expect(reader.state.detectedMapId, 'terminal');
    expect(reader.state.detectedMode, GameMode.seasonal);
    await application(
      'log_2026.10.07_1-00-00',
      'application|scene preset path:maps/labyrinth.bundle\n',
    );
    await reader.rescan();
    expect(reader.state.detectedMapId, 'labyrinth');
    expect(reader.state.detectedMode, GameMode.unknown);
  });

  test('same-path rewrite before handle replay clears the prior map and drains pending replay', () async {
    final file = await application(
      'log_2026.10.07_0-52-00',
      'Session mode: Pve\napplication|scene preset path:maps/laboratory.bundle\n',
    );
    await reader.bind(root.path);
    expect(reader.state.detectedMapId, 'thelab');
    final incarnation = reader.state.incarnation;
    final sessionUri = file.parent.uri;
    var rewrites = 0;

    await IOOverrides.runZoned(
      reader.rescan,
      createDirectory: (path) {
        expect(path, root.path);
        return _ReplayDirectory(root, file, sessionUri, () async {
          if (rewrites != 0) return;
          ++rewrites;
          // The old reader's separate path fingerprint has already completed
          // when open is called. Replace all records before returning its real
          // handle, so hashing skipped bytes must not adopt the new prefix.
          await file.writeAsString(
            'Session mode: Pve\napplication|scene preset path:maps/not_supported.bundle\n',
            flush: true,
          );
        });
      },
    );

    expect(rewrites, 1);
    expect(reader.state.status, MapInputStatus.unavailable);
    expect(reader.state.detectedMapId, isNull);
    expect(reader.state.detectedMode, GameMode.pve);
    expect(reader.state.incarnation, greaterThan(incarnation));
    expect(states.last.status, MapInputStatus.unavailable);
    expect(states.last.detectedMapId, isNull);
    final count = states.length;
    await reader.rescan();
    expect(states.length, count);
    expect(reader.state.detectedMapId, isNull);
  });

  test('configured missing input unsupported scene malformed and overlimit records report honestly', () async {
    await reader.bind(root.path);
    expect(reader.state.status, MapInputStatus.missing);
    final file = await application(
      'log_2026.10.07_0-52-00',
      'application|scene preset path:maps/not_supported.bundle\n',
    );
    await reader.rescan();
    expect(reader.state.status, MapInputStatus.unavailable);
    expect(reader.state.detectedMapId, isNull);
    await file.writeAsBytes([255, 10], mode: FileMode.append, flush: true);
    await reader.rescan();
    expect(reader.state.status, MapInputStatus.error);
    await file.writeAsString(
      '${'x' * 300}\napplication|scene preset path:maps/shoreline.bundle\n',
      mode: FileMode.append,
      flush: true,
    );
    await reader.rescan();
    expect(reader.state.detectedMapId, 'shoreline');
    await file.writeAsBytes([255, 10], mode: FileMode.append, flush: true);
    await reader.rescan();
    expect(reader.state.status, MapInputStatus.error);
    expect(reader.state.detectedMapId, 'shoreline');
    await reader.rescan();
    expect(
      reader.state.status,
      MapInputStatus.error,
      reason: 'a rejected record stays visible until newer bytes arrive',
    );
    await file.writeAsString(
      'clean line\n',
      mode: FileMode.append,
      flush: true,
    );
    await reader.rescan();
    expect(reader.state.status, MapInputStatus.watching);
    expect(reader.state.detectedMapId, 'shoreline');
    await file.delete();
    await reader.rescan();
    expect(reader.state.status, MapInputStatus.missing);
    expect(reader.state.detectedMode, GameMode.unknown);
  });

  test(
    'close or rebind during bounded replay fences obsolete callbacks',
    () async {
      await application(
        'log_2026.10.07_0-52-00',
        '${'header\n' * 500}application|scene preset path:maps/woods.bundle\n',
      );
      final replay = reader.bind(root.path);
      await reader.bind('');
      await replay;
      expect(reader.state.detectedMapId, isNull);
      await reader.close();
      final count = states.length;
      await reader.rescan();
      expect(states.length, count);
    },
  );

  test('event presets detect Factory and The Lab', () async {
    await application(
      'log_2026.10.07_10-25-14',
      'application|scene preset path:maps/factory_event_preset.bundle\n',
    );
    await reader.bind(root.path);
    expect(reader.state.detectedMapId, 'factory');
    await application(
      'log_2026.10.08_10-25-14',
      'application|scene preset path:maps/laboratory_event_preset.bundle\n',
    );
    await reader.rescan();
    expect(reader.state.detectedMapId, 'thelab');
  });
}

/// Delegates real filesystem operations, changing only the replay-open boundary.
class _ReplayDirectory implements Directory {
  _ReplayDirectory(this.directory, this.file, this.sessionUri, this.beforeOpen);

  final Directory directory;
  final File file;
  final Uri sessionUri;
  final Future<void> Function() beforeOpen;

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
      if (entry is Directory && entry.uri == sessionUri) {
        yield _ReplayDirectory(entry, file, sessionUri, beforeOpen);
      } else if (entry is File && entry.uri == file.uri) {
        // Preserve the listed path spelling so wrapping cannot fake rotation.
        yield _ReplayFile(entry, beforeOpen);
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

class _ReplayFile implements File {
  _ReplayFile(this.file, this.beforeOpen);

  final File file;
  final Future<void> Function() beforeOpen;

  @override
  String get path => file.path;

  @override
  Future<FileStat> stat() => file.stat();

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      file.openRead(start, end);

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    await beforeOpen();
    return file.open(mode: mode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected file operation: ${invocation.memberName}',
  );
}
