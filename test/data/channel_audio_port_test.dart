import 'dart:async';

import 'package:blackgrid/application/alerts_controller.dart';
import 'package:blackgrid/application/audio_port.dart';
import 'package:blackgrid/data/channel_audio_port.dart';
import 'package:blackgrid/data/local_paths.dart';
import 'package:blackgrid/domain/alerts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/alerts_support.dart';

const _channel = MethodChannel('blackgrid/audio');

const _allowedMethods = {
  'voices',
  'speak',
  'playFile',
  'stop',
  'openVoiceSettings',
  'pickSoundFile',
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) answer;

  setUp(() {
    calls = [];
    answer = (_) async => null;
    messenger.setMockMethodCallHandler(_channel, (call) {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  Future<Object?> fail(String code) =>
      Future<Object?>.error(PlatformException(code: code, message: 'detail'));

  group('method and argument mapping', () {
    test('speak sends text, voice, speed and volume', () async {
      final result = await ChannelAudioPort().speak(
        text: 'Match found',
        voice: 'voice-1',
        speed: -2,
        volume: 40,
      );

      expect(result, isA<AudioOk>());
      expect(calls.single.method, 'speak');
      expect(calls.single.arguments, {
        'text': 'Match found',
        'voice': 'voice-1',
        'speed': -2,
        'volume': 40,
      });
    });

    test('speak sends a null voice for the Windows default', () async {
      await ChannelAudioPort().speak(text: 't', speed: 0, volume: 100);

      expect((calls.single.arguments as Map)['voice'], isNull);
    });

    test('playFile sends path and volume', () async {
      final result = await ChannelAudioPort().playFile(
        path: r'C:\sounds\a.wav',
        volume: 70,
      );

      expect(result, isA<AudioOk>());
      expect(calls.single.method, 'playFile');
      expect(calls.single.arguments, {
        'path': r'C:\sounds\a.wav',
        'volume': 70,
      });
    });

    test('stop and openVoiceSettings send no arguments', () async {
      final port = ChannelAudioPort();
      await port.stop();
      await port.openVoiceSettings();

      expect(
        [for (final call in calls) call.method],
        ['stop', 'openVoiceSettings'],
      );
      expect(calls.every((call) => call.arguments == null), isTrue);
    });

    test('a custom channel is used when given', () async {
      const other = MethodChannel('blackgrid/other_audio');
      final seen = <String>[];
      messenger.setMockMethodCallHandler(other, (call) async {
        seen.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(other, null));

      await ChannelAudioPort(other).stop();

      expect(seen, ['stop']);
      expect(calls, isEmpty);
    });
  });

  group('speak failures', () {
    for (final code in [
      AudioFailureCode.voiceMissing,
      AudioFailureCode.speechFailed,
      AudioFailureCode.stopped,
      AudioFailureCode.busy,
    ]) {
      test('${code.wire} maps to its failure code', () async {
        answer = (_) => fail(code.wire);

        final result = await ChannelAudioPort().speak(
          text: 't',
          speed: 0,
          volume: 100,
        );

        expect(result, isA<AudioFailure>());
        expect((result as AudioFailure).code, code);
        expect(result.message, 'detail');
      });
    }

    for (final wire in ['bad_arguments', 'surprise']) {
      test('$wire becomes speech failed', () async {
        answer = (_) => fail(wire);

        final result = await ChannelAudioPort().speak(
          text: 't',
          speed: 0,
          volume: 100,
        );

        expect((result as AudioFailure).code, AudioFailureCode.speechFailed);
      });
    }

    test('a missing channel becomes speech failed', () async {
      messenger.setMockMethodCallHandler(_channel, null);

      final result = await ChannelAudioPort().speak(
        text: 't',
        speed: 0,
        volume: 100,
      );

      expect((result as AudioFailure).code, AudioFailureCode.speechFailed);
    });
  });

  group('playFile failures', () {
    for (final code in [
      AudioFailureCode.fileMissing,
      AudioFailureCode.fileUnplayable,
      AudioFailureCode.stopped,
      AudioFailureCode.timeout,
      AudioFailureCode.busy,
    ]) {
      test('${code.wire} maps to its failure code', () async {
        answer = (_) => fail(code.wire);

        final result = await ChannelAudioPort().playFile(
          path: 'a.wav',
          volume: 100,
        );

        expect((result as AudioFailure).code, code);
        expect(result.message, 'detail');
      });
    }

    for (final wire in ['bad_arguments', 'surprise']) {
      test('$wire becomes file unplayable', () async {
        answer = (_) => fail(wire);

        final result = await ChannelAudioPort().playFile(
          path: 'a.wav',
          volume: 100,
        );

        expect((result as AudioFailure).code, AudioFailureCode.fileUnplayable);
      });
    }

    test('a missing channel becomes file unplayable', () async {
      messenger.setMockMethodCallHandler(_channel, null);

      final result = await ChannelAudioPort().playFile(
        path: 'a.wav',
        volume: 100,
      );

      expect((result as AudioFailure).code, AudioFailureCode.fileUnplayable);
    });
  });

  group('voices', () {
    test('parses the voice list', () async {
      answer = (_) async => [
        {'id': 'v1', 'name': 'Anna', 'language': 'en-US'},
        {'id': 'v2', 'name': 'Boris', 'language': 'ru-RU'},
      ];

      final voices = await ChannelAudioPort().voices();

      expect(calls.single.method, 'voices');
      expect(voices, const [
        AudioVoice(id: 'v1', name: 'Anna', language: 'en-US'),
        AudioVoice(id: 'v2', name: 'Boris', language: 'ru-RU'),
      ]);
    });

    test('a null answer is an empty list', () async {
      expect(await ChannelAudioPort().voices(), isEmpty);
    });

    test('voices_failed throws', () async {
      answer = (_) => fail('voices_failed');

      await expectLater(
        ChannelAudioPort().voices(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('a malformed entry throws', () async {
      answer = (_) async => [
        {'id': 'v1'},
      ];

      await expectLater(ChannelAudioPort().voices(), throwsA(anything));
    });

    test(
      'the controller shows the voice list unavailable on a throw',
      () async {
        answer = (_) => fail('voices_failed');
        final rig = _PlainRig(ChannelAudioPort());
        addTearDown(rig.dispose);

        await rig.controller.refreshVoices();

        expect(rig.controller.voicesUnavailable, isTrue);
        expect(rig.controller.voices, isEmpty);
      },
    );
  });

  group('pickSoundFile and openVoiceSettings', () {
    test('returns the chosen path', () async {
      answer = (_) async => r'C:\sounds\a.mp3';

      expect(await ChannelAudioPort().pickSoundFile(), r'C:\sounds\a.mp3');
      expect(calls.single.method, 'pickSoundFile');
    });

    test('returns null when the player cancels', () async {
      expect(await ChannelAudioPort().pickSoundFile(), isNull);
    });

    test('dialog_failed throws', () async {
      answer = (_) => fail('dialog_failed');

      await expectLater(
        ChannelAudioPort().pickSoundFile(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('the controller shows the dialog message on a throw', () async {
      answer = (_) => fail('dialog_failed');
      final rig = _PlainRig(ChannelAudioPort());
      addTearDown(rig.dispose);

      expect(
        await rig.controller.pickSoundFile(AlertKind.matchFound),
        'The file dialog could not be opened.',
      );
    });

    test('launch_failed throws from openVoiceSettings', () async {
      answer = (_) => fail('launch_failed');

      await expectLater(
        ChannelAudioPort().openVoiceSettings(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  test("alerts call only the audio channel's methods", () async {
    final otherCalls = <String>[];
    for (final name in [localDataChannelName]) {
      final other = MethodChannel(name);
      messenger.setMockMethodCallHandler(other, (call) async {
        otherCalls.add('$name.${call.method}');
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(other, null));
    }
    answer = (call) async => switch (call.method) {
      'voices' => [
        {'id': 'v1', 'name': 'Anna', 'language': 'en-US'},
      ],
      'pickSoundFile' => r'C:\sounds\a.wav',
      _ => null,
    };

    var playCount = 0;
    var waiting = Completer<void>();
    var target = 0;
    final recorder = answer;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      final reply = await recorder(call);
      if (call.method == 'speak' || call.method == 'playFile') {
        playCount++;
        if (playCount >= target && !waiting.isCompleted) waiting.complete();
      }
      return reply;
    });
    Future<void> untilPlayed(int count) {
      target = count;
      waiting = Completer<void>();
      if (playCount >= count) waiting.complete();
      return waiting.future;
    }

    final rig = _PlainRig(ChannelAudioPort());
    final controller = rig.controller;
    final now = DateTime.now();

    // Every alert's test button, with a speech sound.
    for (final kind in AlertKind.values) {
      controller.test(kind);
    }
    await untilPlayed(AlertKind.values.length);

    // A file sound, a voice preview, then real lifecycle alerts.
    rig.settings.setSound(AlertKind.scavReady, const FileSound(r'C:\a.wav'));
    controller.test(AlertKind.scavReady);
    await untilPlayed(AlertKind.values.length + 1);
    controller.previewVoice();
    await untilPlayed(AlertKind.values.length + 2);
    rig.lifecycle
      ..profile(now)
      ..queue(now)
      ..matchFound(now)
      ..raidStarting(now);
    await untilPlayed(AlertKind.values.length + 4);

    await controller.refreshVoices();
    await controller.pickSoundFile(AlertKind.matchFound);
    await controller.openVoiceSettings();
    rig.dispose();
    await pumpEventQueue();

    final methods = {for (final call in calls) call.method};
    expect(methods, containsAll({'speak', 'playFile', 'voices', 'stop'}));
    expect(methods, containsAll({'pickSoundFile', 'openVoiceSettings'}));
    for (final call in calls) {
      expect(_allowedMethods, contains(call.method));
      final args = call.arguments;
      if (args is Map) {
        for (final key in args.keys) {
          expect(
            key.toString().toLowerCase(),
            isNot(
              anyOf(contains('hwnd'), contains('window'), contains('handle')),
            ),
          );
        }
      }
    }
    expect(otherCalls, isEmpty);
  });
}

/// An [AlertsController] over fakes and the real clock, wired to [audio].
class _PlainRig {
  _PlainRig(AudioPort audio) {
    controller = AlertsController(
      lifecycle: lifecycle,
      settings: settings,
      catalog: FakeAlertCatalog(),
      progress: FakeAlertProgress(),
      audio: audio,
      clock: DateTime.now,
      questObjectives: (_) => null,
    );
  }

  final lifecycle = FakeAlertLifecycle();
  final settings = FakeAlertSettings();
  late final AlertsController controller;

  void dispose() {
    controller.dispose();
    lifecycle.dispose();
  }
}
