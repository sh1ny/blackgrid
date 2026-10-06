import 'catalog.dart';

class EntityProgress {
  const EntityProgress({
    required this.complete,
    this.count,
    this.failed,
    this.invalid,
  });
  final bool complete;
  final num? count;
  final bool? failed, invalid;
}

class ProgressSnapshot {
  ProgressSnapshot({
    required this.mode,
    required this.credentialSession,
    required this.owner,
    required this.observedAt,
    required Map<String, EntityProgress> tasks,
    required Map<String, EntityProgress> objectives,
    required Map<String, EntityProgress> modules,
    required Map<String, EntityProgress> parts,
    this.playerLevel,
    this.gameEdition,
    this.faction,
    this.etag,
  }) : tasks = Map.unmodifiable(tasks),
       objectives = Map.unmodifiable(objectives),
       modules = Map.unmodifiable(modules),
       parts = Map.unmodifiable(parts);
  final GameMode mode;
  final int credentialSession;
  final String owner;
  final DateTime observedAt;
  final int? playerLevel, gameEdition;
  final String? faction, etag;
  final Map<String, EntityProgress> tasks, objectives, modules, parts;
  bool authoritativeAt(DateTime now) =>
      !now.isBefore(observedAt) &&
      now.difference(observedAt) < const Duration(minutes: 15);
  ProgressSnapshot renewed(DateTime at, String? etag) => ProgressSnapshot(
    mode: mode,
    credentialSession: credentialSession,
    owner: owner,
    observedAt: at,
    tasks: tasks,
    objectives: objectives,
    modules: modules,
    parts: parts,
    playerLevel: playerLevel,
    gameEdition: gameEdition,
    faction: faction,
    etag: etag ?? this.etag,
  );
}
