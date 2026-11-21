import 'dart:async';

import 'package:blackgrid/application/audio_port.dart';

/// One call the fake port received.
final class AudioCall {
  /// Records a call of [method] with [args].
  const AudioCall(this.method, [this.args = const {}]);

  /// The port method name.
  final String method;

  /// The named arguments.
  final Map<String, Object?> args;

  @override
  String toString() => '$method($args)';
}

/// A recording [AudioPort] whose playback results the test completes.
class FakeAudioPort implements AudioPort {
  /// Every call, in order.
  final calls = <AudioCall>[];

  /// Playback calls (speak or playFile) waiting for [completeNext].
  final _pending = <Completer<AudioResult>>[];

  /// When set, playback calls complete at once with this result.
  AudioResult? autoComplete;

  /// When set, playback calls fail with this error.
  Object? playError;

  /// The voices [voices] returns.
  List<AudioVoice> voiceList = const [];

  /// When set, [voices] throws it.
  Object? voicesError;

  /// What [pickSoundFile] returns.
  String? pickResult;

  /// When set, [pickSoundFile] throws it.
  Object? pickError;

  /// The playback calls only, in order.
  List<AudioCall> get playCalls => [
    for (final call in calls)
      if (call.method == 'speak' || call.method == 'playFile') call,
  ];

  /// How many playback calls wait for a result.
  int get pendingCount => _pending.length;

  /// Completes the oldest waiting playback call with [result].
  void completeNext([AudioResult result = const AudioOk()]) {
    _pending.removeAt(0).complete(result);
  }

  Future<AudioResult> _play(AudioCall call) {
    calls.add(call);
    final error = playError;
    if (error != null) return Future.error(error);
    final auto = autoComplete;
    if (auto != null) return Future.value(auto);
    final completer = Completer<AudioResult>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  Future<List<AudioVoice>> voices() async {
    calls.add(const AudioCall('voices'));
    final error = voicesError;
    if (error != null) throw error;
    return voiceList;
  }

  @override
  Future<AudioResult> speak({
    required String text,
    String? voice,
    required int speed,
    required int volume,
  }) => _play(
    AudioCall('speak', {
      'text': text,
      'voice': voice,
      'speed': speed,
      'volume': volume,
    }),
  );

  @override
  Future<AudioResult> playFile({required String path, required int volume}) =>
      _play(AudioCall('playFile', {'path': path, 'volume': volume}));

  @override
  Future<void> stop() async => calls.add(const AudioCall('stop'));

  @override
  Future<void> openVoiceSettings() async =>
      calls.add(const AudioCall('openVoiceSettings'));

  @override
  Future<String?> pickSoundFile() async {
    calls.add(const AudioCall('pickSoundFile'));
    final error = pickError;
    if (error != null) throw error;
    return pickResult;
  }
}
