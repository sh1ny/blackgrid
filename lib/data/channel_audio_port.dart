import 'package:flutter/services.dart';

import '../application/audio_port.dart';

/// Name of the native channel that plays speech and sound files.
///
/// It must equal the name registered in `windows/runner/audio_channel.cpp`.
const String audioChannelName = 'blackgrid/audio';

/// The [AudioPort] backed by the runner's `blackgrid/audio` method channel.
///
/// Blackgrid plays its own sound only: this class sends no window handle and
/// uses no other channel. [speak] and [playFile] complete when playback ends.
class ChannelAudioPort implements AudioPort {
  /// Creates the port over [channel], or the `blackgrid/audio` channel.
  ChannelAudioPort([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(audioChannelName);

  final MethodChannel _channel;

  /// Lists the installed voices.
  ///
  /// Throws a [PlatformException] (`voices_failed`) when the runner cannot read
  /// the list, and a [FormatException] when an entry is malformed.
  @override
  Future<List<AudioVoice>> voices() async {
    final raw = await _channel.invokeListMethod<Object?>('voices') ?? const [];
    return [
      for (final entry in raw)
        switch (entry) {
          {
            'id': final String id,
            'name': final String name,
            'language': final String language,
          } =>
            AudioVoice(id: id, name: name, language: language),
          _ => throw const FormatException('Malformed voice entry.'),
        },
    ];
  }

  /// Speaks [text]; a runner error becomes an [AudioFailure].
  ///
  /// An error code the app does not know, `bad_arguments` and a missing
  /// channel all become [AudioFailureCode.speechFailed].
  @override
  Future<AudioResult> speak({
    required String text,
    String? voice,
    required int speed,
    required int volume,
  }) => _play('speak', {
    'text': text,
    'voice': voice,
    'speed': speed,
    'volume': volume,
  }, fallback: AudioFailureCode.speechFailed);

  /// Plays the file at [path]; a runner error becomes an [AudioFailure].
  ///
  /// An error code the app does not know, `bad_arguments` and a missing
  /// channel all become [AudioFailureCode.fileUnplayable].
  @override
  Future<AudioResult> playFile({required String path, required int volume}) =>
      _play('playFile', {
        'path': path,
        'volume': volume,
      }, fallback: AudioFailureCode.fileUnplayable);

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// Opens the Windows speech settings.
  ///
  /// Throws a [PlatformException] (`launch_failed`) when it cannot open.
  @override
  Future<void> openVoiceSettings() =>
      _channel.invokeMethod<void>('openVoiceSettings');

  /// Opens the Windows file dialog.
  ///
  /// Returns `null` when the player cancels. Throws a [PlatformException]
  /// (`dialog_failed`) when the dialog cannot open.
  @override
  Future<String?> pickSoundFile() =>
      _channel.invokeMethod<String>('pickSoundFile');

  Future<AudioResult> _play(
    String method,
    Map<String, Object?> arguments, {
    required AudioFailureCode fallback,
  }) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
      return const AudioOk();
    } on PlatformException catch (error) {
      final code = AudioFailureCode.fromWire(error.code) ?? fallback;
      return AudioFailure(code, error.message);
    } on MissingPluginException {
      return AudioFailure(fallback);
    }
  }
}
