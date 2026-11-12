import 'catalog.dart';
import 'local_progress.dart';

/// The active local progress cycle and its log-reading position for one mode.
final class ProgressWipe {
  /// Creates an active wipe record.
  const ProgressWipe({
    required this.mode,
    required this.cycleId,
    required this.startDate,
    required this.lastFolder,
    required this.updatedAtMs,
  });

  /// The game mode owning the wipe.
  final GameMode mode;

  /// The identity of the active progress cycle.
  final String cycleId;

  /// The first calendar date included in the wipe.
  final DateTime startDate;

  /// The latest fully read non-live folder, if any.
  final String? lastFolder;

  /// The time at which the wipe record was last changed.
  final int updatedAtMs;

  /// The mode-scoped identity of the active cycle.
  ProgressScope get scope => ProgressScope(mode: mode, cycleId: cycleId);
}

/// Durable active wipe selection and log-reading positions.
abstract interface class ProgressWipeStore {
  /// Reads the active wipes for all modes.
  Future<List<ProgressWipe>> readProgressWipes();

  /// Replaces one mode's active wipe without changing its cycle history.
  Future<void> replaceProgressWipe(ProgressWipe wipe);

  /// Advances a mode's last folder only when [folder] is later.
  Future<void> advanceProgressWipeFolder(
    GameMode mode,
    String folder,
    int updatedAtMs,
  );

  /// Moves a mode's start date only when [startDate] is earlier.
  Future<void> moveProgressWipeStartEarlier(
    GameMode mode,
    DateTime startDate,
    int updatedAtMs,
  );
}
