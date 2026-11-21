import 'package:blackgrid/domain/alerts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each alert has its fixed spoken line', () {
    expect(
      {for (final kind in AlertKind.values) kind.id: kind.line},
      {
        'matchFound': 'Match found',
        'raidStarting': 'Raid starting',
        'runThroughOver': 'Run-through over',
        'scavReady': 'Scav ready',
        'airFilterOn': 'Air filter on',
        'airFilterOff': 'Air filter off',
        'questItems': 'Check your quest items',
        'failedTasks': 'Restart failed tasks',
      },
    );
  });

  test('fromId finds a kind by its stable id and rejects unknown ids', () {
    expect(AlertKind.fromId('scavReady'), AlertKind.scavReady);
    expect(AlertKind.fromId('nope'), isNull);
    expect(AlertKind.fromId(3), isNull);
  });

  group('AlertSound JSON', () {
    test('speech round-trips', () {
      expect(const SpeechSound().toJson(), {'kind': 'speech'});
      expect(AlertSound.fromJson({'kind': 'speech'}), const SpeechSound());
    });

    test('file round-trips with its path', () {
      const sound = FileSound(r'C:\sounds\ping.wav');
      expect(sound.toJson(), {'kind': 'file', 'path': r'C:\sounds\ping.wav'});
      expect(AlertSound.fromJson(sound.toJson()), sound);
    });

    test('an unknown kind loads as speech', () {
      expect(AlertSound.fromJson({'kind': 'pack'}), const SpeechSound());
    });

    test('a file with no usable path, or a non-map, loads as speech', () {
      expect(AlertSound.fromJson({'kind': 'file'}), const SpeechSound());
      expect(
        AlertSound.fromJson({'kind': 'file', 'path': ''}),
        const SpeechSound(),
      );
      expect(AlertSound.fromJson('x'), const SpeechSound());
      expect(AlertSound.fromJson(null), const SpeechSound());
    });
  });
}
