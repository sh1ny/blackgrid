import 'package:blackgrid/domain/raid_lifecycle.dart';
import 'package:blackgrid/domain/screenshot_cleanup.dart';
import 'package:test/test.dart';

const _base =
    '2026-11-22[14-05]_-120.5, 2.1, 33.4_0, 0.70711, 0, 0.70711_12.34';
final _start = DateTime(2026, 11, 22, 14);
final _end = DateTime(2026, 11, 22, 14, 30);

Raid _raid({DateTime? endTime}) => Raid(
  mapId: null,
  mode: null,
  queueTime: null,
  startTime: _start,
  startId: const LogRecordId('session', LogFile.application, 1),
  entry: RaidEntry.noQueue,
  endTime: endTime,
);

ScreenshotEntry _entry(
  String name,
  DateTime modified, {
  bool isFile = true,
  bool isLink = false,
}) => ScreenshotEntry(
  name: name,
  isFile: isFile,
  isLink: isLink,
  modified: modified,
);

void main() {
  test('screenshot-cleanup: A screenshot from the raid', () {
    final names = pickRaidScreenshots([
      _entry('$_base.png', DateTime(2026, 11, 22, 14, 5, 10)),
      _entry('$_base.JPG', _start),
      _entry('$_base.JpEg', _end),
    ], _raid(endTime: _end));

    expect(names, ['$_base.png', '$_base.JPG', '$_base.JpEg']);
  });

  test('screenshot-cleanup: Screenshots outside the raid window', () {
    final entries = [
      _entry('$_base.png', DateTime(2026, 11, 22, 13, 59, 59)),
      _entry('$_base.jpg', DateTime(2026, 11, 22, 14, 30, 1)),
    ];
    expect(pickRaidScreenshots(entries, _raid(endTime: _end)), isEmpty);
  });

  test('only direct regular non-link game-named images are selected', () {
    final time = DateTime(2026, 11, 22, 14, 5);
    expect(
      pickRaidScreenshots([
        _entry('notes.png', time),
        _entry('2026-11-22[14-05]_renamed.png', time),
        _entry('$_base.bmp', time),
        _entry('subfolder/$_base.png', time),
        _entry('subfolder\\$_base.png', time),
        _entry('$_base.png', time, isFile: false),
        _entry('$_base.jpg', time, isLink: true),
        _entry('$_base.jpeg', time),
      ], _raid(endTime: _end)),
      ['$_base.jpeg'],
    );
  });

  test('unfinished or reversed raid windows select nothing', () {
    final entries = [_entry('$_base.png', _start)];
    expect(pickRaidScreenshots(entries, _raid()), isEmpty);
    expect(
      pickRaidScreenshots(
        entries,
        _raid(endTime: _start.subtract(const Duration(seconds: 1))),
      ),
      isEmpty,
    );
  });
}
