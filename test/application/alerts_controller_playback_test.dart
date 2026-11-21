import 'package:blackgrid/application/audio_port.dart';
import 'package:blackgrid/domain/alerts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/alerts_support.dart';

const _mp3 = r'C:\sounds\raid.mp3';

/// Settings with the raid starting alert on a custom file.
AlertSettings _fileSettings({int volume = 100}) => AlertSettings(
  volume: volume,
  items: const {
    AlertKind.raidStarting: AlertItem(on: true, sound: FileSound(_mp3)),
  },
);

void main() {
  final origin = alertsAt(12);

  test('custom file plays in place of speech', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(_fileSettings());
      rig.open().controller.test(AlertKind.raidStarting);
      rig.settle();

      expect(rig.audio.playCalls.map((c) => c.method), ['playFile']);
      expect(rig.audio.playCalls.single.args['path'], _mp3);
    });
  });

  test('volume is passed to file playback', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(_fileSettings(volume: 50));
      rig.open().controller.test(AlertKind.raidStarting);
      rig.settle();

      expect(rig.audio.playCalls.single.args['volume'], 50);
    });
  });

  test('speech is passed the voice, speed and volume', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(
        AlertSettings(voice: 'zira', speed: 3, volume: 70),
      );
      rig.open().controller.test(AlertKind.scavReady);
      rig.settle();

      expect(rig.audio.playCalls.single.args, {
        'text': 'Scav ready',
        'voice': 'zira',
        'speed': 3,
        'volume': 70,
      });
    });
  });

  test('missing file falls back to speech and flags the row', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(_fileSettings());
      final c = rig.open().controller;
      c.test(AlertKind.raidStarting);
      rig.settle();
      rig.finish(const AudioFailure(AudioFailureCode.fileMissing));

      expect(rig.audio.playCalls.map((c) => c.method), ['playFile', 'speak']);
      expect(rig.audio.playCalls.last.args['text'], 'Raid starting');
      expect(c.rowProblem(AlertKind.raidStarting), isNotNull);
      expect(c.rowProblem(AlertKind.matchFound), isNull);

      rig.finish();
      // The speech played, but the file did not: the problem stays.
      expect(c.rowProblem(AlertKind.raidStarting), isNotNull);
      expect(c.lastFailure, isNull);

      // The file next plays fine: the problem clears.
      c.test(AlertKind.raidStarting);
      rig.settle();
      rig.finish();
      expect(c.rowProblem(AlertKind.raidStarting), isNull);
    });
  });

  test('an unplayable file also falls back to speech', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(_fileSettings());
      final c = rig.open().controller;
      c.test(AlertKind.raidStarting);
      rig.settle();
      rig.finish(const AudioFailure(AudioFailureCode.fileUnplayable));

      expect(rig.audio.playCalls.last.method, 'speak');
      expect(c.rowProblem(AlertKind.raidStarting), isNotNull);
    });
  });

  test('a file problem goes away when the sound changes', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(_fileSettings());
      final c = rig.open().controller;
      c.test(AlertKind.raidStarting);
      rig.settle();
      rig.finish(const AudioFailure(AudioFailureCode.fileMissing));
      rig.finish();
      expect(c.rowProblem(AlertKind.raidStarting), isNotNull);

      rig.settings.setSound(AlertKind.raidStarting, const SpeechSound());

      expect(c.rowProblem(AlertKind.raidStarting), isNull);
    });
  });

  test('a file timeout is dropped without speech and names the alert', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(_fileSettings());
      final c = rig.open().controller;
      c.test(AlertKind.raidStarting);
      rig.settle();
      rig.finish(const AudioFailure(AudioFailureCode.timeout));

      expect(rig.audio.playCalls.map((c) => c.method), ['playFile']);
      expect(c.lastFailure, contains('Raid starting'));
    });
  });

  test('alerts play in order without overlap', () {
    runAlerts(origin, (rig) {
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      rig.async.elapse(const Duration(seconds: 1));
      c.test(AlertKind.raidStarting);
      rig.settle();

      expect(rig.played, ['Match found']);
      rig.finish();
      expect(rig.played, ['Match found', 'Raid starting']);
      expect(rig.audio.pendingCount, 1);
    });
  });

  test('an alert waiting over 15 s is dropped', () {
    runAlerts(origin, (rig) {
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      c.test(AlertKind.raidStarting);
      rig.settle();
      rig.async.elapse(const Duration(seconds: 16));
      rig.finish();

      expect(rig.played, ['Match found']);
      expect(rig.audio.pendingCount, 0);
    });
  });

  test('an alert waiting exactly 15 s still plays', () {
    runAlerts(origin, (rig) {
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      c.test(AlertKind.raidStarting);
      rig.settle();
      rig.async.elapse(const Duration(seconds: 15));
      rig.finish();

      expect(rig.played, ['Match found', 'Raid starting']);
    });
  });

  test('a ninth waiting alert is dropped at once', () {
    runAlerts(origin, (rig) {
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      rig.settle();
      for (var i = 0; i < 8; i++) {
        c.test(AlertKind.raidStarting);
      }
      c.test(AlertKind.scavReady);
      rig.settle();

      for (var i = 0; i < 9; i++) {
        rig.finish();
      }
      expect(rig.played, [
        'Match found',
        for (var i = 0; i < 8; i++) 'Raid starting',
      ]);
    });
  });

  test('speech failure is shown and the next alert plays', () {
    runAlerts(origin, (rig) {
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      c.test(AlertKind.raidStarting);
      rig.settle();
      rig.finish(const AudioFailure(AudioFailureCode.speechFailed));

      expect(c.lastFailure, contains('Match found'));
      expect(rig.played, ['Match found', 'Raid starting']);
    });
  });

  test('a later success clears the failure', () {
    runAlerts(origin, (rig) {
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      c.test(AlertKind.raidStarting);
      rig.settle();
      rig.finish(const AudioFailure(AudioFailureCode.speechFailed));
      expect(c.lastFailure, isNotNull);
      rig.finish();

      expect(c.lastFailure, isNull);
    });
  });

  test('a thrown port error counts as a speech failure', () {
    runAlerts(origin, (rig) {
      rig.audio.playError = StateError('channel gone');
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      rig.settle();

      expect(c.lastFailure, contains('Match found'));
    });
  });

  test('uninstalled voice falls back to default and is reported', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(AlertSettings(voice: 'gone'));
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      rig.settle();
      expect(c.voiceNote, isNull);
      rig.finish(const AudioFailure(AudioFailureCode.voiceMissing));

      expect(rig.audio.playCalls.map((c) => c.args['voice']), ['gone', null]);
      expect(rig.settings.alerts.voice, 'gone');
      expect(c.voiceNote, isNotNull);
      rig.finish();
      expect(c.lastFailure, isNull);
      expect(rig.audio.playCalls, hasLength(2));
    });
  });

  test('a second voice-missing result is not retried again', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(AlertSettings(voice: 'gone'));
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      rig.settle();
      rig.finish(const AudioFailure(AudioFailureCode.voiceMissing));
      rig.finish(const AudioFailure(AudioFailureCode.voiceMissing));

      expect(rig.audio.playCalls, hasLength(2));
      expect(c.lastFailure, isNotNull);
    });
  });

  test('the voice note goes away when the voice choice changes', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(AlertSettings(voice: 'gone'));
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      rig.settle();
      rig.finish(const AudioFailure(AudioFailureCode.voiceMissing));
      rig.finish();
      expect(c.voiceNote, isNotNull);

      rig.settings.setAlerts(AlertSettings());

      expect(c.voiceNote, isNull);
    });
  });

  test('the voice note goes away once the saved voice speaks again', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(AlertSettings(voice: 'gone'));
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      rig.settle();
      rig.finish(const AudioFailure(AudioFailureCode.voiceMissing));
      rig.finish();
      expect(c.voiceNote, isNotNull);

      // The player reinstalls the voice; the next speak with it succeeds.
      c.test(AlertKind.matchFound);
      rig.settle();
      rig.finish();

      expect(rig.audio.playCalls.last.args['voice'], 'gone');
      expect(c.voiceNote, isNull);
    });
  });

  test('the voice note goes away when the voice list has it again', () {
    runAlerts(origin, (rig) {
      rig.settings.setAlerts(AlertSettings(voice: 'gone'));
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      rig.settle();
      rig.finish(const AudioFailure(AudioFailureCode.voiceMissing));
      rig.finish();
      expect(c.voiceNote, isNotNull);

      rig.audio.voiceList = const [
        AudioVoice(id: 'gone', name: 'Gone', language: 'en-US'),
      ];
      c.refreshVoices();
      rig.settle();

      expect(c.voiceNote, isNull);
    });
  });

  test('a test waits behind the playing alert', () {
    runAlerts(origin, (rig) {
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      rig.settle();
      c.test(AlertKind.failedTasks);
      rig.settle();

      expect(rig.played, ['Match found']);
      rig.finish();
      expect(rig.played, ['Match found', 'Restart failed tasks']);
    });
  });

  test('a test plays an alert that is off', () {
    runAlerts(origin, (rig) {
      final c = rig.open().controller;
      expect(rig.settings.alerts.itemFor(AlertKind.questItems).on, isFalse);
      c.test(AlertKind.questItems);
      rig.settle();

      expect(rig.played, ['Check your quest items']);
    });
  });

  test('settings are read when the item starts playing', () {
    runAlerts(origin, (rig) {
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      c.test(AlertKind.raidStarting);
      rig.settle();
      rig.settings.setAlerts(AlertSettings(volume: 20, speed: -2));
      rig.finish();

      expect(rig.audio.playCalls.last.args['volume'], 20);
      expect(rig.audio.playCalls.last.args['speed'], -2);
    });
  });

  group('backstops', () {
    test('a speech call that never completes is stopped after 30 s', () {
      runAlerts(origin, (rig) {
        final c = rig.open().controller;
        c.test(AlertKind.matchFound);
        rig.settle();
        rig.async.elapse(const Duration(seconds: 20));
        c.test(AlertKind.raidStarting);
        rig.settle();
        rig.async.elapse(const Duration(seconds: 9));
        expect(rig.audio.calls.map((c) => c.method), ['speak']);
        rig.async.elapse(const Duration(seconds: 1));
        rig.settle();

        expect(rig.audio.calls.map((c) => c.method), [
          'speak',
          'stop',
          'speak',
        ]);
        expect(c.lastFailure, contains('Match found'));
      });
    });

    test('a file call that never completes is stopped after 125 s', () {
      runAlerts(origin, (rig) {
        rig.settings.setAlerts(_fileSettings());
        final c = rig.open().controller;
        c.test(AlertKind.raidStarting);
        rig.settle();
        rig.async.elapse(const Duration(seconds: 124));
        expect(rig.audio.calls.map((c) => c.method), ['playFile']);
        rig.async.elapse(const Duration(seconds: 1));
        rig.settle();

        // Stopped and treated as failed: no speech fallback.
        expect(rig.audio.calls.map((c) => c.method), ['playFile', 'stop']);
        expect(c.lastFailure, contains('Raid starting'));
      });
    });

    test('a stopped result moves on silently', () {
      runAlerts(origin, (rig) {
        final c = rig.open().controller;
        c.test(AlertKind.matchFound);
        c.test(AlertKind.raidStarting);
        rig.settle();
        rig.finish(const AudioFailure(AudioFailureCode.stopped));

        expect(c.lastFailure, isNull);
        expect(rig.played, ['Match found', 'Raid starting']);
      });
    });
  });

  group('voices and dialogs', () {
    test('refreshVoices lists the installed voices', () {
      runAlerts(origin, (rig) {
        rig.audio.voiceList = const [
          AudioVoice(id: 'z', name: 'Zira', language: 'en-US'),
          AudioVoice(id: 'd', name: 'David', language: 'en-US'),
        ];
        final c = rig.open().controller;
        c.refreshVoices();
        rig.settle();

        expect(c.voices.map((v) => v.name), ['Zira', 'David']);
        expect(c.voicesUnavailable, isFalse);
      });
    });

    test('a failed or empty voice read marks the list unavailable', () {
      runAlerts(origin, (rig) {
        final c = rig.open().controller;
        rig.audio.voicesError = StateError('no');
        c.refreshVoices();
        rig.settle();
        expect(c.voices, isEmpty);
        expect(c.voicesUnavailable, isTrue);

        rig.audio
          ..voicesError = null
          ..voiceList = const [
            AudioVoice(id: 'z', name: 'Zira', language: 'x'),
          ];
        c.refreshVoices();
        rig.settle();
        expect(c.voicesUnavailable, isFalse);

        rig.audio.voiceList = const [];
        c.refreshVoices();
        rig.settle();
        expect(c.voicesUnavailable, isTrue);
      });
    });

    test('a saved voice missing from the list is reported', () {
      runAlerts(origin, (rig) {
        rig.settings.setAlerts(AlertSettings(voice: 'gone'));
        rig.audio.voiceList = const [
          AudioVoice(id: 'z', name: 'Zira', language: 'en-US'),
        ];
        final c = rig.open().controller;
        c.refreshVoices();
        rig.settle();

        expect(c.voiceNote, isNotNull);
      });
    });

    test('previewVoice speaks a sample line in the queue', () {
      runAlerts(origin, (rig) {
        rig.open().controller.previewVoice();
        rig.settle();

        expect(rig.audio.playCalls.single.method, 'speak');
        expect(rig.audio.playCalls.single.args['text'], isNotEmpty);
      });
    });

    test('openVoiceSettings calls the port', () {
      runAlerts(origin, (rig) {
        rig.open().controller.openVoiceSettings();
        rig.settle();

        expect(rig.audio.calls.map((c) => c.method), ['openVoiceSettings']);
      });
    });

    test('pickSoundFile passes the chosen path to the settings', () {
      runAlerts(origin, (rig) {
        rig.audio.pickResult = _mp3;
        String? message = 'unset';
        rig
            .open()
            .controller
            .pickSoundFile(AlertKind.scavReady)
            .then((m) => message = m);
        rig.settle();

        expect(message, isNull);
        expect(rig.settings.soundCalls, [
          (AlertKind.scavReady, const FileSound(_mp3)),
        ]);
      });
    });

    test('pickSoundFile returns the settings message for a refused file', () {
      runAlerts(origin, (rig) {
        rig.audio.pickResult = r'C:\a.txt';
        rig.settings.soundMessage = 'Only WAV and MP3 files.';
        String? message;
        rig
            .open()
            .controller
            .pickSoundFile(AlertKind.scavReady)
            .then((m) => message = m);
        rig.settle();

        expect(message, 'Only WAV and MP3 files.');
      });
    });

    test('a cancelled dialog changes nothing and shows no message', () {
      runAlerts(origin, (rig) {
        String? message = 'unset';
        rig
            .open()
            .controller
            .pickSoundFile(AlertKind.scavReady)
            .then((m) => message = m);
        rig.settle();

        expect(message, isNull);
        expect(rig.settings.soundCalls, isEmpty);
      });
    });

    test('a dialog failure gives a message and keeps the sound', () {
      runAlerts(origin, (rig) {
        rig.audio.pickError = StateError('no dialog');
        String? message;
        rig
            .open()
            .controller
            .pickSoundFile(AlertKind.scavReady)
            .then((m) => message = m);
        rig.settle();

        expect(message, isNotNull);
        expect(rig.settings.soundCalls, isEmpty);
      });
    });
  });

  test('dispose stops playback and empties the queue', () {
    runAlerts(origin, (rig) {
      final c = rig.open().controller;
      c.test(AlertKind.matchFound);
      c.test(AlertKind.raidStarting);
      rig.settle();
      c.dispose();
      rig.settle();

      expect(rig.audio.calls.map((c) => c.method), ['speak', 'stop']);
      rig.audio.completeNext(const AudioFailure(AudioFailureCode.stopped));
      rig.settle();
      expect(rig.played, ['Match found']);
    });
  });
}
