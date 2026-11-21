/// The eight spoken alerts, in the order the Alerts section lists them.
///
/// The [id] is the stable key stored in the settings record and must never
/// change; the [line] is what the voice says.
enum AlertKind {
  /// A match was found.
  matchFound('matchFound', 'Match found', defaultOn: true),

  /// The raid countdown started.
  raidStarting('raidStarting', 'Raid starting', defaultOn: true),

  /// The run-through countdown reached zero.
  runThroughOver('runThroughOver', 'Run-through over', defaultOn: true),

  /// The scav cooldown is over.
  scavReady('scavReady', 'Scav ready', defaultOn: true),

  /// Reminder to switch the Air Filtering Unit on.
  airFilterOn('airFilterOn', 'Air filter on', defaultOn: false),

  /// Reminder to switch the Air Filtering Unit off.
  airFilterOff('airFilterOff', 'Air filter off', defaultOn: false),

  /// Reminder to bring quest items for the queued map.
  questItems('questItems', 'Check your quest items', defaultOn: false),

  /// Reminder to restart a failed task that can be restarted.
  failedTasks('failedTasks', 'Restart failed tasks', defaultOn: false);

  const AlertKind(this.id, this.line, {required this.defaultOn});

  /// The stable id stored in settings.
  final String id;

  /// The fixed line the voice says.
  final String line;

  /// Whether the alert is on when nothing is stored.
  final bool defaultOn;

  /// The alert stored under [id], or `null` for a missing or unknown id.
  static AlertKind? fromId(Object? id) {
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

/// What an alert plays: Windows speech, or a file the player chose.
sealed class AlertSound {
  const AlertSound();

  /// Reads a stored sound.
  ///
  /// An unknown `kind`, a file without a path, or anything that is not a map
  /// reads as [SpeechSound], so a later kind is additive. Never throws.
  factory AlertSound.fromJson(Object? json) => switch (json) {
    {'kind': 'file', 'path': final String path} when path.isNotEmpty =>
      FileSound(path),
    _ => const SpeechSound(),
  };

  /// The stored form: `{kind: speech}` or `{kind: file, path}`.
  Map<String, Object?> toJson();
}

/// The alert's line, spoken by the chosen voice.
final class SpeechSound extends AlertSound {
  /// Creates the speech sound.
  const SpeechSound();

  @override
  Map<String, Object?> toJson() => const {'kind': 'speech'};

  @override
  bool operator ==(Object other) => other is SpeechSound;

  @override
  int get hashCode => (SpeechSound).hashCode;
}

/// A WAV or MP3 file at [path] that the player chose.
final class FileSound extends AlertSound {
  /// Creates a file sound for [path].
  const FileSound(this.path);

  /// The absolute path of the file.
  final String path;

  /// Whether [path] ends in `.wav` or `.mp3`, in any letter case.
  bool get isSupported {
    final lower = path.toLowerCase();
    return lower.endsWith('.wav') || lower.endsWith('.mp3');
  }

  @override
  Map<String, Object?> toJson() => {'kind': 'file', 'path': path};

  @override
  bool operator ==(Object other) => other is FileSound && other.path == path;

  @override
  int get hashCode => Object.hash(FileSound, path);
}

/// One alert's switch and sound.
final class AlertItem {
  /// Creates an item.
  const AlertItem({required this.on, this.sound = const SpeechSound()});

  /// The default item of [kind].
  factory AlertItem.defaultFor(AlertKind kind) => AlertItem(on: kind.defaultOn);

  /// Reads a stored item, throwing a [FormatException] when it is malformed.
  factory AlertItem.fromJson(Object? json) {
    if (json is! Map || json['on'] is! bool) {
      throw const FormatException('Malformed alert item.');
    }
    return AlertItem(
      on: json['on'] as bool,
      sound: AlertSound.fromJson(json['sound']),
    );
  }

  /// Whether the alert plays from its event.
  final bool on;

  /// What the alert plays.
  final AlertSound sound;

  /// A copy with the given fields replaced.
  AlertItem copyWith({bool? on, AlertSound? sound}) =>
      AlertItem(on: on ?? this.on, sound: sound ?? this.sound);

  /// The stored form.
  Map<String, Object?> toJson() => {'on': on, 'sound': sound.toJson()};

  @override
  bool operator ==(Object other) =>
      other is AlertItem && other.on == on && other.sound == sound;

  @override
  int get hashCode => Object.hash(on, sound);
}

const Object _keep = Object();

/// The alert preferences: one voice, speed and volume for every spoken alert,
/// and a switch and sound for each [AlertKind].
final class AlertSettings {
  /// Creates settings.
  ///
  /// [speed] and [volume] are clamped into range. Every kind in [items] that
  /// is missing gets its default, so [items] always holds all eight.
  AlertSettings({
    this.voice,
    int speed = 0,
    int volume = 100,
    Map<AlertKind, AlertItem> items = const {},
  }) : speed = speed.clamp(minSpeed, maxSpeed),
       volume = volume.clamp(minVolume, maxVolume),
       items = Map.unmodifiable({
         for (final kind in AlertKind.values)
           kind: items[kind] ?? AlertItem.defaultFor(kind),
       });

  /// The slowest speech step.
  static const minSpeed = -5;

  /// The fastest speech step.
  static const maxSpeed = 5;

  /// The lowest volume, in percent.
  static const minVolume = 0;

  /// The highest volume, in percent.
  static const maxVolume = 100;

  /// Reads a stored `alerts` block, throwing a [FormatException] when it is
  /// not a map.
  ///
  /// Inside a map an unknown alert id is ignored, a malformed item gives that
  /// alert its default, and an out-of-range speed or volume is clamped.
  factory AlertSettings.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Malformed alerts.');
    final rawItems = json['items'];
    final items = <AlertKind, AlertItem>{};
    if (rawItems is Map) {
      for (final MapEntry(:key, :value) in rawItems.entries) {
        final kind = AlertKind.fromId(key);
        if (kind == null) continue;
        try {
          items[kind] = AlertItem.fromJson(value);
        } on FormatException {
          // This alert keeps its default.
        }
      }
    }
    final voice = json['voice'];
    return AlertSettings(
      voice: voice is String && voice.isNotEmpty ? voice : null,
      speed: _wholeNumber(json['speed']) ?? 0,
      volume: _wholeNumber(json['volume']) ?? 100,
      items: items,
    );
  }

  static int? _wholeNumber(Object? value) =>
      value is num && value.isFinite ? value.round() : null;

  /// The id of the chosen voice, or `null` for the Windows default.
  final String? voice;

  /// The speech speed step, from [minSpeed] to [maxSpeed].
  final int speed;

  /// The volume in percent, from [minVolume] to [maxVolume].
  final int volume;

  /// The switch and sound of every alert.
  final Map<AlertKind, AlertItem> items;

  /// The item of [kind].
  AlertItem itemFor(AlertKind kind) => items[kind]!;

  /// A copy with the given fields replaced.
  ///
  /// Pass `voice: null` to go back to the Windows default voice.
  AlertSettings copyWith({
    Object? voice = _keep,
    int? speed,
    int? volume,
    Map<AlertKind, AlertItem>? items,
  }) => AlertSettings(
    voice: identical(voice, _keep) ? this.voice : voice as String?,
    speed: speed ?? this.speed,
    volume: volume ?? this.volume,
    items: items ?? this.items,
  );

  /// A copy with [kind] set to [item].
  AlertSettings withItem(AlertKind kind, AlertItem item) =>
      copyWith(items: {...items, kind: item});

  /// The stored form: `{voice, speed, volume, items: {<id>: {on, sound}}}`.
  Map<String, Object?> toJson() => {
    'voice': voice,
    'speed': speed,
    'volume': volume,
    'items': {
      for (final MapEntry(:key, :value) in items.entries)
        key.id: value.toJson(),
    },
  };

  @override
  bool operator ==(Object other) =>
      other is AlertSettings &&
      other.voice == voice &&
      other.speed == speed &&
      other.volume == volume &&
      other.items.length == items.length &&
      items.entries.every((e) => other.items[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    voice,
    speed,
    volume,
    Object.hashAll(items.entries.map((e) => Object.hash(e.key, e.value))),
  );
}
