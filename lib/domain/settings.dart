import 'catalog.dart';

const supportedMaps = <String>[
  'factory',
  'customs',
  'woods',
  'shoreline',
  'interchange',
  'thelab',
  'reserve',
  'lighthouse',
  'streetsoftarkov',
  'groundzero',
  'terminal',
  'icebreaker',
  'labyrinth',
];
const markerCategories = <String>[
  'Labels',
  'QuestItems',
  'QuestObjectives',
  'PmcExtracts',
  'ScavExtracts',
  'SharedExtracts',
  'Transits',
  'Hazards',
  'HazardZones',
  'Switches',
  'PmcSpawns',
  'ScavSpawns',
  'BossSpawns',
  'CultistSpawns',
  'BtrStops',
  'lootContainers',
  'lootLoose',
  'locks',
  'stationaryWeapons',
  'CustomPins',
];

/// The key that triggers a scan, or [off] for no hotkey.
///
/// Persisted as `"off"` or `"F1"` to `"F24"`.
enum ScanHotkey {
  /// No scan hotkey.
  off,
  f1,
  f2,
  f3,
  f4,
  f5,
  f6,
  f7,
  f8,
  f9,
  f10,
  f11,
  f12,
  f13,
  f14,
  f15,
  f16,
  f17,
  f18,
  f19,
  f20,
  f21,
  f22,
  f23,
  f24;

  /// The Windows virtual-key code, `0x70` (VK_F1) to `0x87` (VK_F24).
  ///
  /// Zero for [off].
  int get vk => this == off ? 0 : 0x6F + index;

  /// The display and persisted name: `Off` or `F1` to `F24`.
  String get label => this == off ? 'Off' : 'F$index';

  /// Reads a persisted [value], returning [f9] when it is missing, not a
  /// string or not a known key. Never throws.
  static ScanHotkey fromStored(Object? value) {
    for (final key in values) {
      if (value == key.stored) return key;
    }
    return f9;
  }

  /// The persisted JSON value: `off` or `F1` to `F24`.
  String get stored => this == off ? 'off' : label;
}

/// The raid timer preferences and the durable scav cooldown starts.
class RaidTimerSettings {
  /// Creates raid timer settings.
  RaidTimerSettings({
    this.enabled = true,
    this.showTimeInRaid = true,
    this.showRunThrough = true,
    this.showScavCooldown = true,
    this.runThroughSeconds = defaultRunThroughSeconds,
    Map<GameMode, double> fenceReputation = const {},
    Map<GameMode, DateTime> scavCooldownStarts = const {},
  }) : fenceReputation = Map.unmodifiable(fenceReputation),
       scavCooldownStarts = Map.unmodifiable(scavCooldownStarts);

  /// The shortest run-through length, in seconds.
  static const minRunThroughSeconds = 60;

  /// The longest run-through length, in seconds.
  static const maxRunThroughSeconds = 1800;

  /// The default run-through length, in seconds.
  static const defaultRunThroughSeconds = 430;

  /// The lowest Fence reputation.
  static const minFenceReputation = -7.0;

  /// The highest Fence reputation.
  static const maxFenceReputation = 6.0;

  /// The default settings: everything shown, 7:10 run-through, reputation 0.
  static final defaults = RaidTimerSettings();

  final bool enabled;
  final bool showTimeInRaid;
  final bool showRunThrough;
  final bool showScavCooldown;
  final int runThroughSeconds;
  final Map<GameMode, double> fenceReputation;
  final Map<GameMode, DateTime> scavCooldownStarts;

  double fenceReputationFor(GameMode mode) => fenceReputation[mode] ?? 0;

  RaidTimerSettings copyWith({
    bool? enabled,
    bool? showTimeInRaid,
    bool? showRunThrough,
    bool? showScavCooldown,
    int? runThroughSeconds,
    Map<GameMode, double>? fenceReputation,
    Map<GameMode, DateTime>? scavCooldownStarts,
  }) => RaidTimerSettings(
    enabled: enabled ?? this.enabled,
    showTimeInRaid: showTimeInRaid ?? this.showTimeInRaid,
    showRunThrough: showRunThrough ?? this.showRunThrough,
    showScavCooldown: showScavCooldown ?? this.showScavCooldown,
    runThroughSeconds: runThroughSeconds ?? this.runThroughSeconds,
    fenceReputation: fenceReputation ?? this.fenceReputation,
    scavCooldownStarts: scavCooldownStarts ?? this.scavCooldownStarts,
  );

  /// The persisted block. Keys are [GameMode.name]; starts are UTC ISO-8601.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'showTimeInRaid': showTimeInRaid,
    'showRunThrough': showRunThrough,
    'showScavCooldown': showScavCooldown,
    'runThroughSeconds': runThroughSeconds,
    'fenceReputation': {
      for (final e in fenceReputation.entries) e.key.name: e.value,
    },
    'scavCooldownStarts': {
      for (final e in scavCooldownStarts.entries)
        e.key.name: e.value.toUtc().toIso8601String(),
    },
  };

  /// Decodes a persisted block, throwing on a malformed block.
  ///
  /// Inside a well-formed block an unknown mode key or an out-of-range value
  /// drops only that entry; an out-of-range run-through length gives 430.
  factory RaidTimerSettings.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Malformed raid timers.');
    final reputation = json['fenceReputation'] ?? const <String, Object?>{};
    final starts = json['scavCooldownStarts'] ?? const <String, Object?>{};
    if (reputation is! Map || starts is! Map) {
      throw const FormatException('Malformed raid timers.');
    }
    final seconds = json['runThroughSeconds'];
    return RaidTimerSettings(
      enabled: json['enabled'] as bool? ?? true,
      showTimeInRaid: json['showTimeInRaid'] as bool? ?? true,
      showRunThrough: json['showRunThrough'] as bool? ?? true,
      showScavCooldown: json['showScavCooldown'] as bool? ?? true,
      runThroughSeconds:
          seconds is int &&
              seconds >= minRunThroughSeconds &&
              seconds <= maxRunThroughSeconds
          ? seconds
          : defaultRunThroughSeconds,
      fenceReputation: {
        for (final MapEntry(:key, :value) in reputation.entries)
          ?_timerMode(key): ?_roundReputation(value),
      },
      scavCooldownStarts: {
        for (final MapEntry(:key, :value) in starts.entries)
          ?_timerMode(key): ?_parseStart(value),
      },
    );
  }

  static GameMode? _timerMode(Object? key) {
    for (final mode in GameMode.values) {
      if (mode != GameMode.unknown && mode.name == key) return mode;
    }
    return null;
  }

  static DateTime? _parseStart(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  static double? _roundReputation(Object? value) {
    if (value is! num || !value.isFinite) return null;
    // A finite value can still overflow once scaled; round() would throw.
    final scaled = value * 100;
    if (!scaled.isFinite) return null;
    final rounded = scaled.round() / 100;
    return rounded < minFenceReputation || rounded > maxFenceReputation
        ? null
        : rounded;
  }
}

class AppSettings {
  AppSettings({
    this.mode = GameMode.unknown,
    this.selectedMap = 'shoreline',
    this.saveMarkerFilters = false,
    Map<String, bool> markerFilters = const {},
    this.trackerEnabled = false,
    this.gameLogDirectory = '',
    this.screenshotDirectory = '',
    this.followGameLogs = true,
    this.liveScan = false,
    this.scanHotkey = ScanHotkey.f9,
    RaidTimerSettings? raidTimers,
  }) : raidTimers = raidTimers ?? RaidTimerSettings.defaults,
       markerFilters = Map.unmodifiable(markerFilters);
  final GameMode mode;
  final String selectedMap;
  final bool saveMarkerFilters;
  final Map<String, bool> markerFilters;
  final bool trackerEnabled;
  final String gameLogDirectory;
  final String screenshotDirectory;
  final bool followGameLogs;

  /// Whether the live scanner starts with the application. Off by default.
  final bool liveScan;

  /// The key that triggers a scan. F9 by default.
  final ScanHotkey scanHotkey;

  /// The raid timer preferences and cooldown starts.
  final RaidTimerSettings raidTimers;

  AppSettings copyWith({
    GameMode? mode,
    String? selectedMap,
    bool? saveMarkerFilters,
    Map<String, bool>? markerFilters,
    bool? trackerEnabled,
    String? gameLogDirectory,
    String? screenshotDirectory,
    bool? followGameLogs,
    bool? liveScan,
    ScanHotkey? scanHotkey,
    RaidTimerSettings? raidTimers,
  }) => AppSettings(
    mode: mode ?? this.mode,
    selectedMap: selectedMap ?? this.selectedMap,
    saveMarkerFilters: saveMarkerFilters ?? this.saveMarkerFilters,
    markerFilters: markerFilters ?? this.markerFilters,
    trackerEnabled: trackerEnabled ?? this.trackerEnabled,
    gameLogDirectory: gameLogDirectory ?? this.gameLogDirectory,
    screenshotDirectory: screenshotDirectory ?? this.screenshotDirectory,
    followGameLogs: followGameLogs ?? this.followGameLogs,
    liveScan: liveScan ?? this.liveScan,
    scanHotkey: scanHotkey ?? this.scanHotkey,
    raidTimers: raidTimers ?? this.raidTimers,
  );
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'selectedMap': selectedMap,
    'saveMarkerFilters': saveMarkerFilters,
    'markerFilters': markerFilters,
    'trackerEnabled': trackerEnabled,
    'gameLogDirectory': gameLogDirectory,
    'screenshotDirectory': screenshotDirectory,
    'followGameLogs': followGameLogs,
    'liveScan': liveScan,
    'scanHotkey': scanHotkey.stored,
    'raidTimers': raidTimers.toJson(),
  };
  factory AppSettings.fromJson(Map<String, Object?> json) {
    final mode = GameMode.values.firstWhere((m) => m.name == json['mode']);
    final map = json['selectedMap'] as String;
    if (!supportedMaps.contains(map)) {
      throw const FormatException('Unsupported map preference.');
    }
    final filters = Map<String, bool>.from(json['markerFilters'] as Map);
    if (filters.keys.any((key) => !markerCategories.contains(key))) {
      throw const FormatException('Unsupported marker preference.');
    }
    // Decoded on its own so a bad timer block cannot reset the other settings.
    RaidTimerSettings timers;
    try {
      timers = json.containsKey('raidTimers')
          ? RaidTimerSettings.fromJson(json['raidTimers'])
          : RaidTimerSettings.defaults;
    } on Object {
      timers = RaidTimerSettings.defaults;
    }
    return AppSettings(
      mode: mode,
      selectedMap: map,
      saveMarkerFilters: json['saveMarkerFilters'] as bool,
      markerFilters: filters,
      trackerEnabled: json['trackerEnabled'] as bool,
      gameLogDirectory: json['gameLogDirectory'] as String? ?? '',
      screenshotDirectory: json['screenshotDirectory'] as String? ?? '',
      followGameLogs: json['followGameLogs'] as bool? ?? true,
      liveScan: json['liveScan'] as bool? ?? false,
      scanHotkey: ScanHotkey.fromStored(json['scanHotkey']),
      raidTimers: timers,
    );
  }
}

class CustomPin {
  const CustomPin({
    required this.id,
    required this.mapId,
    required this.x,
    required this.y,
    required this.frame,
    required this.frameRevision,
    required this.label,
    required this.updatedAt,
  });
  final String id;
  final String mapId;
  final double x;
  final double y;
  final String frame;
  final int frameRevision;
  final String label;
  final DateTime updatedAt;
  void validate() {
    if (id.trim().isEmpty ||
        !supportedMaps.contains(mapId) ||
        !x.isFinite ||
        !y.isFinite ||
        frameRevision < 0 ||
        !((frame == 'legacy-normalized' &&
                frameRevision == 0 &&
                mapId != 'thelab') ||
            (frame == 'labs-native-normalized' &&
                frameRevision == 1 &&
                mapId == 'thelab'))) {
      throw const FormatException(
        'Unsupported pin identity, coordinates or frame.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'mapId': mapId,
    'x': x,
    'y': y,
    'frame': frame,
    'frameRevision': frameRevision,
    'label': label,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory CustomPin.fromJson(Map<String, Object?> json) => CustomPin(
    id: json['id'] as String,
    mapId: json['mapId'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    frame: json['frame'] as String,
    frameRevision: json['frameRevision'] as int,
    label: json['label'] as String,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

/// Where an [ItemActivity] observation came from.
enum ActivitySource {
  /// A manual inspection recorded by the user.
  manual,

  /// An accepted live scan recorded by the app.
  scan,

  /// A scan observation brought in from a legacy import.
  importedScan,

  /// A manual observation brought in from a legacy import.
  importedManual,
}

class ItemActivity {
  const ItemActivity({
    required this.itemId,
    required this.mode,
    required this.source,
    required this.observedAt,
    required this.revision,
  });
  final String itemId;
  final GameMode mode;
  final ActivitySource source;
  final DateTime observedAt;
  final int revision;
  String get key => '${mode.name}:$itemId';
  Map<String, Object?> toJson() => {
    'itemId': itemId,
    'mode': mode.name,
    'source': source.name,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'revision': revision,
  };
  factory ItemActivity.fromJson(Map<String, Object?> json) => ItemActivity(
    itemId: json['itemId'] as String,
    mode: GameMode.values.byName(json['mode'] as String),
    source: ActivitySource.values.byName(json['source'] as String),
    observedAt: DateTime.parse(json['observedAt'] as String),
    revision: json['revision'] as int,
  );
}
