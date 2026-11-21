/// A speech voice installed in Windows.
final class AudioVoice {
  /// Creates a voice.
  const AudioVoice({
    required this.id,
    required this.name,
    required this.language,
  });

  /// The id the audio channel accepts for `speak`.
  final String id;

  /// The name shown to the player.
  final String name;

  /// The language tag of the voice, for example `en-US`.
  final String language;

  @override
  bool operator ==(Object other) =>
      other is AudioVoice &&
      other.id == id &&
      other.name == name &&
      other.language == language;

  @override
  int get hashCode => Object.hash(id, name, language);
}

/// Why a speak or play call did not finish normally.
enum AudioFailureCode {
  /// The chosen voice is not installed.
  voiceMissing('voice_missing'),

  /// The sound file does not exist.
  fileMissing('file_missing'),

  /// The sound file exists but cannot be played.
  fileUnplayable('file_unplayable'),

  /// Windows speech failed.
  speechFailed('speech_failed'),

  /// Playback was stopped before it ended.
  stopped('stopped'),

  /// A sound file played longer than the runner allows.
  timeout('timeout'),

  /// A call arrived while another result was pending.
  busy('busy');

  const AudioFailureCode(this.wire);

  /// The code string the audio channel uses.
  final String wire;

  /// The code named [wire], or `null` for an unknown string.
  static AudioFailureCode? fromWire(Object? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }
}

/// How a speak or play call ended.
sealed class AudioResult {
  const AudioResult();
}

/// Playback finished.
final class AudioOk extends AudioResult {
  /// Creates the result.
  const AudioOk();
}

/// Playback failed or was cut short.
final class AudioFailure extends AudioResult {
  /// Creates a failure with [code] and an optional [message] from the runner.
  const AudioFailure(this.code, [this.message]);

  /// Why it failed.
  final AudioFailureCode code;

  /// The runner's detail, or `null`.
  final String? message;
}

/// Blackgrid's own audio output: speech, sound files and the Windows file
/// dialog.
///
/// `ChannelAudioPort` is the real implementation. Calls to [speak] and
/// [playFile] complete when playback ends; the caller never overlaps them.
abstract interface class AudioPort {
  /// Lists the installed voices.
  ///
  /// Throws when the list cannot be read.
  Future<List<AudioVoice>> voices();

  /// Speaks [text] with the voice [voice] (`null` for the Windows default),
  /// at speed step [speed] and volume [volume] percent.
  Future<AudioResult> speak({
    required String text,
    String? voice,
    required int speed,
    required int volume,
  });

  /// Plays the file at [path] at volume [volume] percent.
  Future<AudioResult> playFile({required String path, required int volume});

  /// Stops what is playing.
  Future<void> stop();

  /// Opens the Windows speech settings.
  Future<void> openVoiceSettings();

  /// Opens the Windows file dialog.
  ///
  /// Returns the chosen absolute path, or `null` when the player cancels.
  Future<String?> pickSoundFile();
}
