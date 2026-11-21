import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/alerts_controller.dart';
import '../../application/settings_controller.dart';
import '../../domain/alerts.dart';
import '../ember/ember_tokens.dart';
import '../ember/theme_access.dart';
import 'raid_timer_input.dart';
import 'settings_row.dart';

/// The rows of the Settings page's Alerts section: one voice, speed and volume
/// for every spoken alert, then a switch, a sound and a test button for each of
/// the eight alerts.
///
/// It listens to [settings] and [alerts] and keeps only view state: the volume
/// being dragged and the messages of the last save or file choice. Without an
/// [alerts] controller the switches and sliders still save, but the buttons
/// that make a sound or open a dialog are disabled.
class AlertsSettings extends StatefulWidget {
  /// Creates the rows over [settings] and [alerts].
  const AlertsSettings({super.key, required this.settings, this.alerts});

  /// Where the alert preferences are read and saved.
  final SettingsController settings;

  /// The controller behind the test, preview, voice and file buttons, or
  /// `null` while none is wired.
  final AlertsController? alerts;

  @override
  State<AlertsSettings> createState() => _AlertsSettingsState();
}

class _AlertsSettingsState extends State<AlertsSettings> {
  /// The save failure shown under a row, by row: an [AlertKind], or one of
  /// `voice`, `speed` and `volume`.
  final Map<Object, String> _saveFailures = {};

  /// The refusal of the last file choice or sound change, by alert.
  final Map<AlertKind, String> _soundMessages = {};

  /// The speed or volume under the thumb while it moves, `null` when still.
  double? _speedDraft;
  double? _volumeDraft;

  @override
  void initState() {
    super.initState();
    unawaited(widget.alerts?.refreshVoices());
  }

  @override
  void didUpdateWidget(AlertsSettings old) {
    super.didUpdateWidget(old);
    if (old.alerts != widget.alerts) unawaited(widget.alerts?.refreshVoices());
  }

  /// Records the outcome of a save under [row]: a message on failure, nothing
  /// on success.
  Future<void> _save(Object row, Future<bool> save) async {
    final saved = await save;
    if (!mounted) return;
    setState(() {
      if (saved) {
        _saveFailures.remove(row);
      } else {
        _saveFailures[row] = notSavedMessage;
      }
    });
  }

  Future<void> _chooseFile(AlertKind kind) async {
    final alerts = widget.alerts;
    if (alerts == null) return;
    final message = await alerts.pickSoundFile(kind);
    if (!mounted) return;
    setState(() {
      if (message == null) {
        _soundMessages.remove(kind);
      } else {
        _soundMessages[kind] = message;
      }
    });
  }

  Future<void> _useSpeech(AlertKind kind) async {
    final message = await widget.settings.setAlertSound(
      kind,
      const SpeechSound(),
    );
    if (!mounted) return;
    setState(() {
      if (message == null) {
        _soundMessages.remove(kind);
      } else {
        _soundMessages[kind] = message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.settings, ?widget.alerts]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._voiceRows(context),
          ..._speakingRows(context),
          if (widget.alerts?.lastFailure case final failure?)
            _line(
              context,
              failure,
              const Key('alerts-last-failure'),
              error: true,
            ),
          for (final kind in AlertKind.values) ..._alertRows(context, kind),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String text,
    Key key, {
    bool error = false,
  }) {
    final ember = context.ember;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: EmberSpace.sm),
      child: Text(
        text,
        style: EmberType.label.copyWith(
          color: error ? ember.errInk : ember.inkTertiary,
        ),
      ),
    );
  }

  List<Widget> _voiceRows(BuildContext context) {
    final alerts = widget.alerts;
    final saved = widget.settings.alerts.voice;
    final voices = alerts?.voices ?? const [];
    // A saved voice that is not installed shows as the default, which is the
    // voice that speaks.
    final shown = voices.any((voice) => voice.id == saved) ? saved : null;
    final busy = widget.settings.busy;
    return [
      SettingsRow(
        name: 'Voice',
        explanation: 'One voice for every spoken alert.',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButton<String?>(
                key: const Key('alert-voice'),
                isExpanded: true,
                value: shown,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Windows default'),
                  ),
                  for (final voice in voices)
                    DropdownMenuItem<String?>(
                      value: voice.id,
                      child: Text(voice.name),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (voice) => unawaited(
                        _save('voice', widget.settings.setAlertVoice(voice)),
                      ),
              ),
            ),
            const SizedBox(width: EmberSpace.sm),
            OutlinedButton(
              key: const Key('alert-voice-preview'),
              onPressed: alerts?.previewVoice,
              child: const Text('Preview'),
            ),
            const SizedBox(width: EmberSpace.sm),
            TextButton(
              key: const Key('alert-more-voices'),
              onPressed: alerts == null
                  ? null
                  : () => unawaited(alerts.openVoiceSettings()),
              child: const Text('Get more voices'),
            ),
          ],
        ),
      ),
      if (_saveFailures['voice'] case final failure?)
        _line(
          context,
          failure,
          const Key('alert-save-failure-voice'),
          error: true,
        ),
      if (alerts != null && alerts.voicesUnavailable)
        _line(
          context,
          'Voice list unavailable. Spoken alerts use the Windows default voice.',
          const Key('alert-voice-unavailable'),
        ),
      if (alerts?.voiceNote case final note?)
        _line(context, note, const Key('alert-voice-note'), error: true),
    ];
  }

  List<Widget> _speakingRows(BuildContext context) {
    final ember = context.ember;
    final alerts = widget.settings.alerts;
    final busy = widget.settings.busy;
    List<Widget> slider({
      required Key key,
      required String name,
      required String explanation,
      required String row,
      required double value,
      required double min,
      required double max,
      required String Function(double) label,
      required ValueChanged<double> onDrag,
      required ValueChanged<double> onEnd,
    }) => [
      SettingsRow(
        name: name,
        explanation: explanation,
        trailing: SizedBox(
          width: 320,
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  key: key,
                  min: min,
                  max: max,
                  divisions: (max - min).round(),
                  value: value.clamp(min, max),
                  label: label(value),
                  semanticFormatterCallback: label,
                  onChanged: busy ? null : onDrag,
                  onChangeEnd: busy ? null : onEnd,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  label(value),
                  textAlign: TextAlign.end,
                  style: EmberType.body.copyWith(color: ember.ink),
                ),
              ),
            ],
          ),
        ),
      ),
      if (_saveFailures[row] case final failure?)
        _line(context, failure, Key('alert-save-failure-$row'), error: true),
    ];
    return [
      ...slider(
        key: const Key('alert-speed'),
        name: 'Speed',
        explanation: 'How fast the voice speaks, from slowest to fastest.',
        row: 'speed',
        value: _speedDraft ?? alerts.speed.toDouble(),
        min: AlertSettings.minSpeed.toDouble(),
        max: AlertSettings.maxSpeed.toDouble(),
        label: (value) {
          final step = value.round();
          return step > 0 ? '+$step' : '$step';
        },
        onDrag: (value) => setState(() => _speedDraft = value),
        onEnd: (value) {
          setState(() => _speedDraft = null);
          unawaited(
            _save('speed', widget.settings.setAlertSpeed(value.round())),
          );
        },
      ),
      ...slider(
        key: const Key('alert-volume'),
        name: 'Volume',
        explanation: 'How loud alerts play, including sound files.',
        row: 'volume',
        value: _volumeDraft ?? alerts.volume.toDouble(),
        min: AlertSettings.minVolume.toDouble(),
        max: AlertSettings.maxVolume.toDouble(),
        label: (value) => '${value.round()}%',
        onDrag: (value) => setState(() => _volumeDraft = value),
        onEnd: (value) {
          setState(() => _volumeDraft = null);
          unawaited(
            _save('volume', widget.settings.setAlertVolume(value.round())),
          );
        },
      ),
    ];
  }

  List<Widget> _alertRows(BuildContext context, AlertKind kind) {
    final ember = context.ember;
    final alerts = widget.alerts;
    final item = widget.settings.alerts.itemFor(kind);
    final busy = widget.settings.busy;
    final problem = alerts?.rowProblem(kind) ?? _soundMessages[kind];
    final note = switch (kind) {
      // One note for both reminders, under the second.
      AlertKind.airFilterOff => (
        alerts?.airFilterNote,
        const Key('alerts-air-filter-note'),
      ),
      AlertKind.questItems => (
        alerts?.questItemsNote,
        const Key('alerts-quest-items-note'),
      ),
      _ => (null, null),
    };
    final (soundLabel, onSpeech) = switch (item.sound) {
      SpeechSound() => ('Windows speech', false),
      FileSound(:final path) => (_fileName(path), true),
    };
    return [
      SettingsRow.toggle(
        key: Key('alert-row-${kind.id}'),
        name: kind.line,
        explanation: _explanation(kind),
        value: item.on,
        enabled: !busy,
        onChanged: (on) =>
            unawaited(_save(kind, widget.settings.setAlertOn(kind, on))),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: EmberSpace.sm),
        child: Wrap(
          spacing: EmberSpace.sm,
          runSpacing: EmberSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              soundLabel,
              key: Key('alert-sound-${kind.id}'),
              style: EmberType.label.copyWith(color: ember.inkSecondary),
            ),
            OutlinedButton(
              key: Key('alert-choose-${kind.id}'),
              onPressed: alerts == null || busy
                  ? null
                  : () => unawaited(_chooseFile(kind)),
              child: Text(onSpeech ? 'Change file' : 'Choose file'),
            ),
            if (onSpeech)
              TextButton(
                key: Key('alert-speech-${kind.id}'),
                onPressed: busy ? null : () => unawaited(_useSpeech(kind)),
                child: const Text('Use speech'),
              ),
            OutlinedButton(
              key: Key('alert-test-${kind.id}'),
              onPressed: alerts == null ? null : () => alerts.test(kind),
              child: const Text('Test'),
            ),
          ],
        ),
      ),
      if (_saveFailures[kind] case final failure?)
        _line(
          context,
          failure,
          Key('alert-save-failure-${kind.id}'),
          error: true,
        ),
      if (problem != null)
        _line(context, problem, Key('alert-problem-${kind.id}'), error: true),
      if (note case (final text?, final key?)) _line(context, text, key),
    ];
  }

  String _explanation(AlertKind kind) => switch (kind) {
    AlertKind.matchFound => 'When the game finds a match.',
    AlertKind.raidStarting => 'When the raid countdown starts.',
    AlertKind.runThroughOver => 'When the run-through countdown ends.',
    AlertKind.scavReady => 'When the scav cooldown ends.',
    AlertKind.airFilterOn => 'A reminder to switch the air filter on.',
    AlertKind.airFilterOff => 'A reminder to switch the air filter off.',
    AlertKind.questItems => 'A reminder to bring quest items for the map.',
    AlertKind.failedTasks => 'A reminder to restart a failed task.',
  };
}

/// The file name of [path], for either kind of separator.
String _fileName(String path) {
  final cut = path.lastIndexOf(RegExp(r'[\\/]'));
  return cut < 0 ? path : path.substring(cut + 1);
}
