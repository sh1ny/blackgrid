import 'package:blackgrid/application/alerts_controller.dart';
import 'package:blackgrid/application/audio_port.dart';
import 'package:blackgrid/domain/alerts.dart';
import 'package:blackgrid/domain/catalog.dart';
import 'package:blackgrid/ui/ember/ember_theme.dart';
import 'package:blackgrid/ui/settings/commit_field.dart';
import 'package:blackgrid/ui/settings/settings_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/alerts_support.dart';
import '../support/fake_audio_port.dart';
import '../support/m1_harness.dart';
import '../support/pump_async.dart';
import '../support/raid_timer_support.dart';

const _voices = [
  AudioVoice(id: 'zira', name: 'Zira', language: 'en-US'),
  AudioVoice(id: 'david', name: 'David', language: 'en-US'),
  AudioVoice(id: 'mark', name: 'Mark', language: 'en-US'),
];

/// Everything an Alerts test touches.
class _Rig {
  _Rig(this.h, this.audio, this.controller, this.lifecycle);

  final M1Harness h;
  final FakeAudioPort audio;
  final AlertsController controller;
  final FakeAlertLifecycle lifecycle;
}

Finder _key(String key) => find.byKey(Key(key));

/// Pumps the Settings page over a real settings store and an
/// [AlertsController] on a fake audio port.
Future<_Rig> _pumpAlerts(
  WidgetTester tester, {
  void Function(FakeAudioPort audio)? shape,
}) async {
  tester.view.physicalSize = const Size(1672, 941);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = (await tester.runAsync(() async {
    final result = M1Harness();
    await result.initialize(mode: GameMode.pvp);
    return result;
  }))!;
  addPumpedTearDown(tester, h.dispose);
  final audio = FakeAudioPort()
    ..autoComplete = const AudioOk()
    ..voiceList = _voices;
  shape?.call(audio);
  final lifecycle = FakeAlertLifecycle();
  final controller = AlertsController(
    lifecycle: lifecycle,
    settings: h.services.settings,
    catalog: FakeAlertCatalog(),
    progress: FakeAlertProgress(),
    audio: audio,
    clock: () => alertsAt(12, 0, 2),
    questObjectives: (_) => null,
  );
  addTearDown(() {
    controller.dispose();
    lifecycle.dispose();
  });
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        theme: blackgridTheme(Brightness.dark),
        home: Scaffold(
          body: SettingsPage(
            services: h.services,
            backLabel: 'Back to Map',
            onBack: () {},
            flush: SettingsFlushController(),
            alerts: controller,
          ),
        ),
      ),
    );
    await h.services.localProgress.settled;
  });
  await tester.pumpAndSettle();
  return _Rig(h, audio, controller, lifecycle);
}

Future<void> _show(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, Finder target) async {
  await _show(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// The Alerts section's text widgets, to read the labels the player sees.
Iterable<String> _texts(WidgetTester tester, Finder within) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(of: within, matching: find.byType(Text)),
  ))
    ?text.data,
];

void main() {
  testWidgets('voice list starts with Windows default', (tester) async {
    await _pumpAlerts(tester);
    final dropdown = _key('alert-voice');
    await _show(tester, dropdown);

    final items = tester
        .widget<DropdownButton<String?>>(dropdown)
        .items!
        .map((item) => (item.child as Text).data);
    expect(items, ['Windows default', 'Zira', 'David', 'Mark']);

    // Opened, the menu shows the same four names.
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('Zira'), findsOneWidget);
    expect(find.text('David'), findsOneWidget);
    expect(find.text('Mark'), findsOneWidget);
    expect(find.text('Windows default'), findsWidgets);
    expect(_key('alert-voice-unavailable'), findsNothing);
  });

  testWidgets('unreadable voice list offers only Windows default', (
    tester,
  ) async {
    await _pumpAlerts(tester, shape: (a) => a.voicesError = StateError('no'));
    final dropdown = _key('alert-voice');
    await _show(tester, dropdown);

    final items = tester
        .widget<DropdownButton<String?>>(dropdown)
        .items!
        .map((item) => (item.child as Text).data);
    expect(items, ['Windows default']);
    expect(_key('alert-voice-unavailable'), findsOneWidget);
    expect(find.textContaining('Voice list unavailable'), findsOneWidget);
  });

  testWidgets('choosing a voice saves it', (tester) async {
    final rig = await _pumpAlerts(tester);
    await _show(tester, _key('alert-voice'));
    await tester.tap(_key('alert-voice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('David').last);
    await pumpUntil(
      tester,
      () => rig.h.services.settings.alerts.voice == 'david',
    );
    expect(rig.h.services.settings.alerts.voice, 'david');
  });

  testWidgets('voice preview and Get more voices call the controller', (
    tester,
  ) async {
    final rig = await _pumpAlerts(tester);
    await _press(tester, _key('alert-voice-preview'));
    expect(rig.audio.playCalls.single.args['text'], voicePreviewLine);

    await _press(tester, _key('alert-more-voices'));
    expect(
      rig.audio.calls.map((call) => call.method),
      contains('openVoiceSettings'),
    );
  });

  testWidgets('test button plays an alert that is off', (tester) async {
    final rig = await _pumpAlerts(tester);
    expect(
      rig.h.services.settings.alerts.itemFor(AlertKind.questItems).on,
      isFalse,
    );

    await _press(tester, _key('alert-test-questItems'));

    expect(rig.audio.playCalls, hasLength(1));
    expect(rig.audio.playCalls.single.method, 'speak');
    expect(rig.audio.playCalls.single.args['text'], 'Check your quest items');
    expect(
      rig.h.services.settings.alerts.itemFor(AlertKind.questItems).on,
      isFalse,
    );
  });

  testWidgets('every alert has a switch, a sound and a test button', (
    tester,
  ) async {
    await _pumpAlerts(tester);
    for (final kind in AlertKind.values) {
      expect(_key('alert-row-${kind.id}'), findsOneWidget, reason: kind.id);
      expect(_key('alert-test-${kind.id}'), findsOneWidget, reason: kind.id);
      expect(_key('alert-choose-${kind.id}'), findsOneWidget, reason: kind.id);
      expect(find.text(kind.line), findsWidgets, reason: kind.id);
    }
  });

  testWidgets('a switch saves the alert on or off', (tester) async {
    final rig = await _pumpAlerts(tester);
    final row = _key('alert-row-airFilterOn');
    await _show(tester, row);
    await tester.tap(row);
    await pumpUntil(
      tester,
      () => rig.h.services.settings.alerts.itemFor(AlertKind.airFilterOn).on,
    );
    expect(
      rig.h.services.settings.alerts.itemFor(AlertKind.airFilterOn).on,
      isTrue,
    );
  });

  testWidgets('choosing a non-WAV/MP3 file is refused', (tester) async {
    final rig = await _pumpAlerts(
      tester,
      shape: (a) => a.pickResult = r'C:\Sounds\ding.ogg',
    );
    await _press(tester, _key('alert-choose-matchFound'));

    expect(
      find.text('Only WAV and MP3 files can be used as an alert sound.'),
      findsOneWidget,
    );
    expect(
      _texts(tester, _key('alert-problem-matchFound')),
      contains('Only WAV and MP3 files can be used as an alert sound.'),
    );
    expect(
      rig.h.services.settings.alerts.itemFor(AlertKind.matchFound).sound,
      const SpeechSound(),
    );
    expect(_key('alert-speech-matchFound'), findsNothing);
  });

  testWidgets('cancelling the file dialog keeps the sound', (tester) async {
    final rig = await _pumpAlerts(tester);
    await tester.runAsync(
      () => rig.h.services.settings.setAlertSound(
        AlertKind.matchFound,
        const FileSound(r'C:\Sounds\ding.wav'),
      ),
    );
    await tester.pumpAndSettle();
    rig.audio.pickResult = null;

    await _press(tester, _key('alert-choose-matchFound'));

    expect(rig.audio.calls.map((c) => c.method), contains('pickSoundFile'));
    expect(
      rig.h.services.settings.alerts.itemFor(AlertKind.matchFound).sound,
      const FileSound(r'C:\Sounds\ding.wav'),
    );
    expect(_key('alert-problem-matchFound'), findsNothing);
    expect(find.text('ding.wav'), findsOneWidget);
  });

  testWidgets('a failing file dialog shows its message under the row', (
    tester,
  ) async {
    await _pumpAlerts(tester, shape: (a) => a.pickError = StateError('no'));
    await _press(tester, _key('alert-choose-scavReady'));
    expect(
      _texts(tester, _key('alert-problem-scavReady')),
      contains('The file dialog could not be opened.'),
    );
  });

  testWidgets('a chosen file shows its name and a way back to speech', (
    tester,
  ) async {
    final rig = await _pumpAlerts(tester);
    await tester.runAsync(
      () => rig.h.services.settings.setAlertSound(
        AlertKind.raidStarting,
        const FileSound(r'C:\Sounds\go.mp3'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('go.mp3'), findsOneWidget);

    await _show(tester, _key('alert-speech-raidStarting'));
    await tester.tap(_key('alert-speech-raidStarting'));
    await pumpUntil(
      tester,
      () =>
          rig.h.services.settings.alerts.itemFor(AlertKind.raidStarting).sound
              is SpeechSound,
    );
    expect(find.text('go.mp3'), findsNothing);
    expect(_key('alert-speech-raidStarting'), findsNothing);
  });

  testWidgets('a sound file that cannot play shows its row problem', (
    tester,
  ) async {
    final rig = await _pumpAlerts(tester);
    await tester.runAsync(
      () => rig.h.services.settings.setAlertSound(
        AlertKind.matchFound,
        const FileSound(r'C:\Sounds\gone.wav'),
      ),
    );
    rig.audio.autoComplete = const AudioFailure(AudioFailureCode.fileMissing);

    await _press(tester, _key('alert-test-matchFound'));

    expect(
      _texts(tester, _key('alert-problem-matchFound')),
      contains(
        'The sound file could not be played. The alert is spoken instead.',
      ),
    );
  });

  testWidgets('the last playback failure is shown', (tester) async {
    final rig = await _pumpAlerts(tester);
    expect(_key('alerts-last-failure'), findsNothing);
    rig.audio.autoComplete = const AudioFailure(AudioFailureCode.speechFailed);

    await _press(tester, _key('alert-test-scavReady'));

    await _show(tester, _key('alerts-last-failure'));
    expect(find.text('"Scav ready" could not be spoken.'), findsOneWidget);
  });

  testWidgets('a missing saved voice is noted under the voice row', (
    tester,
  ) async {
    final rig = await _pumpAlerts(tester);
    await tester.runAsync(() => rig.h.services.settings.setAlertVoice('gone'));
    await tester.runAsync(rig.controller.refreshVoices);
    await tester.pumpAndSettle();

    await _show(tester, _key('alert-voice-note'));
    expect(
      find.textContaining('The saved voice is not installed'),
      findsOneWidget,
    );
  });

  testWidgets('the air filter note shows while local progress is missing', (
    tester,
  ) async {
    final rig = await _pumpAlerts(tester);
    expect(_key('alerts-air-filter-note'), findsNothing);

    await tester.runAsync(
      () => rig.h.services.settings.setAlertOn(AlertKind.airFilterOn, true),
    );
    await tester.pumpAndSettle();

    await _show(tester, _key('alerts-air-filter-note'));
    expect(
      find.text('The air filter reminders wait for local progress.'),
      findsOneWidget,
    );
  });

  testWidgets('the quest items note shows while map data is missing', (
    tester,
  ) async {
    final rig = await _pumpAlerts(tester);
    await tester.runAsync(
      () => rig.h.services.settings.setAlertOn(AlertKind.questItems, true),
    );
    rig.lifecycle
      ..profile(alertsAt(12))
      ..queue(alertsAt(12))
      ..scene(alertsAt(12), 'customs');
    await tester.pumpAndSettle();

    await _show(tester, _key('alerts-quest-items-note'));
    expect(
      find.text(
        'The quest items reminder waits for map, quest or progress data.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('speed and volume sliders keep to their ranges', (tester) async {
    await _pumpAlerts(tester);
    await _show(tester, _key('alert-speed'));
    final speed = tester.widget<Slider>(_key('alert-speed'));
    expect((speed.min, speed.max, speed.divisions), (-5.0, 5.0, 10));
    final volume = tester.widget<Slider>(_key('alert-volume'));
    expect((volume.min, volume.max, volume.divisions), (0.0, 100.0, 100));
  });

  testWidgets('moving a slider saves its value', (tester) async {
    final rig = await _pumpAlerts(tester);
    await _show(tester, _key('alert-volume'));
    await tester.drag(_key('alert-volume'), const Offset(-60, 0));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => rig.h.services.settings.alerts.volume < 100);
    expect(rig.h.services.settings.alerts.volume, lessThan(100));
  });

  testWidgets('a failed save shows under the volume row', (tester) async {
    final rig = await _pumpAlerts(tester);
    await tester.runAsync(
      () => rig.h.db.customStatement(
        "CREATE TRIGGER preference_failure BEFORE INSERT ON preferences "
        "BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      ),
    );
    await _show(tester, _key('alert-volume'));
    await tester.drag(_key('alert-volume'), const Offset(-60, 0));
    await tester.pump();
    await pumpUntil(
      tester,
      () => _key('alert-save-failure-volume').evaluate().isNotEmpty,
    );

    expect(find.text('Not saved. Try again.'), findsOneWidget);
    expect(rig.h.services.settings.alerts.volume, 100);
  });
}
