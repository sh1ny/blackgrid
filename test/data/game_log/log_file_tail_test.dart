import 'dart:convert';
import 'dart:io';

import 'package:blackgrid/data/game_log/log_file_tail.dart';
import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late File file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('blackgrid-log-tail-');
    file = File('${dir.path}/a.log');
    await file.writeAsBytes(const []);
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> append(List<int> bytes) =>
      file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
  Future<void> appendText(String text) => append(utf8.encode(text));

  Future<TailBatch> poll(LogFileTail tail) async =>
      tail.read(file, await tail.stat(file));

  LogFileTail tailOf(
    LogFile kind, {
    int chunk = 3,
    int line = 65536,
    int recordBytes = 1 << 20,
    int recordLines = 8192,
  }) => LogFileTail(
    kind: kind,
    chunkBytes: chunk,
    maxLineBytes: line,
    maxRecordBytes: recordBytes,
    maxRecordLines: recordLines,
  );

  const header = '2026-10-28 19:41:06.991|1.2.5.0.48146|Info|application|';
  const push = '2026-10-28 19:41:07.100|1.2.5.0.48146|Info|push-notifications|';
  const open = '${push}Got notification | ChatMessageReceived';
  const next = '${push}NotificationMessageProcessor.ProcessMessage';

  test('line split across two reads decodes once', () async {
    final tail = tailOf(LogFile.application);
    await appendText('${header}GameSt');
    expect((await poll(tail)).records, isEmpty);
    await appendText('arted:161.35(10.98) real:176.48(12) diff:15.12\n');
    final records = (await poll(tail)).records;
    expect(records, hasLength(1));
    expect(
      records.single.text,
      '${header}GameStarted:161.35(10.98) real:176.48(12) diff:15.12',
    );
    expect(records.single.offset, 0);
  });

  test('unfinished last line waits for its newline', () async {
    final tail = tailOf(LogFile.backend);
    await appendText('${header}one\n${header}two');
    final first = (await poll(tail)).records;
    expect(first.map((r) => r.text), ['${header}one']);
    await appendText('\r\n');
    final second = (await poll(tail)).records;
    expect(second.map((r) => r.text), ['${header}two']);
    expect(second.single.offset, utf8.encode('${header}one\n').length);
  });

  test('application and backend drop continuation lines', () async {
    final tail = tailOf(LogFile.application);
    await appendText('${header}one\n{\n  "a": 1\n}\n${header}two\n');
    expect((await poll(tail)).records.map((r) => r.text), [
      '${header}one',
      '${header}two',
    ]);
  });

  test('multi-byte character split across reads stays intact', () async {
    final tail = tailOf(LogFile.pushNotifications, chunk: 64);
    final bytes = utf8.encode('$open\n{\n"n":"Сёма"\n}\n');
    // Split between the two bytes of 'ё' (D1 91).
    final split = bytes.indexOf(0xD1, bytes.indexOf(0xD0) + 2) + 1;
    expect(bytes[split], 0x91);
    await append(bytes.sublist(0, split));
    expect((await poll(tail)).items, isEmpty);
    await append(bytes.sublist(split));
    final batch = await poll(tail);
    expect(batch.rejections, isEmpty);
    expect(batch.records.single.text, contains('Сёма'));
  });

  group('push framing', () {
    test('push record completes at its closing brace', () async {
      final tail = tailOf(LogFile.pushNotifications);
      await appendText('$open\n{\n  "type": "x"\n}\n');
      final records = (await poll(tail)).records;
      expect(records.single.text, '$open\n{\n  "type": "x"\n}');
      expect(records.single.offset, 0);
    });

    test('half-written push body produces nothing yet', () async {
      final tail = tailOf(LogFile.pushNotifications);
      await appendText('$open\n{\n  "type": "x"\n');
      expect((await poll(tail)).items, isEmpty);
      await appendText('}\n');
      expect(
        (await poll(tail)).records.single.text,
        '$open\n{\n  "type": "x"\n}',
      );
    });

    test('next header ends an unclosed push body', () async {
      final tail = tailOf(LogFile.pushNotifications);
      await appendText('$open\n{\n  "a": 1\n$open\n{\n}\n$next\n');
      final records = (await poll(tail)).records;
      expect(records.map((r) => r.text), ['$open\n{\n  "a": 1', '$open\n{\n}']);
      expect(records[1].offset, utf8.encode('$open\n{\n  "a": 1\n').length);
    });

    test('headers other than Got notification open no push record', () async {
      final tail = tailOf(LogFile.pushNotifications);
      await appendText('$next\n{\n}\n');
      expect((await poll(tail)).items, isEmpty);
    });
  });

  test('malformed UTF-8 line is rejected and reading continues', () async {
    final tail = tailOf(LogFile.application);
    await append([...utf8.encode('${header}bad '), 0xFF, 0x0A]);
    await appendText('${header}good\n');
    final batch = await poll(tail);
    expect(batch.rejections.single.reason, TailRejectionReason.malformedUtf8);
    expect(batch.rejections.single.offset, 0);
    expect(batch.records.map((r) => r.text), ['${header}good']);
  });

  test('over-long line and over-limit push record are rejected', () async {
    final app = tailOf(LogFile.application, line: 80);
    await appendText('$header${'x' * 60}\n${header}ok\n');
    final batch = await poll(app);
    expect(batch.rejections.single.reason, TailRejectionReason.lineTooLong);
    expect(batch.records.map((r) => r.text), ['${header}ok']);

    await file.writeAsBytes(const []);
    final lines = tailOf(LogFile.pushNotifications, recordLines: 3);
    await appendText('$open\n{\na\nb\nc\n}\n$open\n{\n}\n');
    final byLines = await poll(lines);
    expect(
      byLines.rejections.single.reason,
      TailRejectionReason.recordTooLarge,
    );
    expect(byLines.rejections.single.offset, 0);
    expect(byLines.records.map((r) => r.text), ['$open\n{\n}']);

    await file.writeAsBytes(const []);
    final bytes = tailOf(LogFile.pushNotifications, recordBytes: 300);
    await appendText('$open\n{\n${'y' * 400}\n}\n$open\n{\n}\n');
    final bySize = await poll(bytes);
    expect(bySize.rejections.single.reason, TailRejectionReason.recordTooLarge);
    expect(bySize.records.map((r) => r.text), ['$open\n{\n}']);
  });

  test('truncated file is read again from the start', () async {
    final tail = tailOf(LogFile.application);
    await appendText('${header}one\n${header}two\n');
    expect((await poll(tail)).records, hasLength(2));
    await file.writeAsString('${header}3\n', flush: true);
    final batch = await poll(tail);
    expect(batch.restarted, isTrue);
    expect(batch.records.map((r) => r.text), ['${header}3']);
    expect(batch.records.single.offset, 0);
  });

  test('same-length rewrite is read again from the start', () async {
    final tail = tailOf(LogFile.application);
    await appendText('${header}one\n');
    expect((await poll(tail)).records, hasLength(1));
    await file.writeAsString('${header}two\n', flush: true);
    final batch = await poll(tail);
    expect(batch.restarted, isTrue);
    expect(batch.records, isEmpty);
    final again = await poll(tail);
    expect(again.restarted, isFalse);
    expect(again.records.map((r) => r.text), ['${header}two']);
  });

  test('reads stop at the size seen at stat', () async {
    final tail = tailOf(LogFile.application);
    await appendText('${header}one\n');
    final size = await tail.stat(file);
    await appendText('${header}two\n');
    expect((await tail.read(file, size)).records.map((r) => r.text), [
      '${header}one',
    ]);
    expect((await poll(tail)).records.map((r) => r.text), ['${header}two']);
  });
}
