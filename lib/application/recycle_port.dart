/// The outcome of moving one requested screenshot to the Recycle Bin.
sealed class RecycleStatus {
  const RecycleStatus();
}

/// The file was moved to the Recycle Bin.
final class RecycleMoved extends RecycleStatus {
  /// Creates a confirmed move.
  const RecycleMoved();
}

/// The file no longer exists and counts as neither moved nor failed.
final class RecycleMissing extends RecycleStatus {
  /// Creates a missing-file outcome.
  const RecycleMissing();
}

/// The Recycle Bin cannot take the file, which was left untouched.
final class RecycleNotRecyclable extends RecycleStatus {
  /// Creates a vetoed permanent deletion.
  const RecycleNotRecyclable();
}

/// The runner rejected the name or a non-regular file.
final class RecycleRejected extends RecycleStatus {
  /// Creates a rejected-file outcome.
  const RecycleRejected();
}

/// The file could not be moved.
final class RecycleFailed extends RecycleStatus {
  /// Creates a failed-file outcome.
  const RecycleFailed();
}

/// The move stopped before processing the file.
final class RecycleCancelled extends RecycleStatus {
  /// Creates a cancelled-file outcome.
  const RecycleCancelled();
}

/// The result of one bounded call to the runner.
sealed class RecycleReply {
  const RecycleReply();
}

/// One status for every requested name, in request order.
final class RecycleStatuses extends RecycleReply {
  /// Creates a reply from the per-name [statuses].
  RecycleStatuses(Map<String, RecycleStatus> statuses)
    : statuses = Map.unmodifiable(statuses);

  /// The status of each requested basename.
  final Map<String, RecycleStatus> statuses;
}

/// The channel failed to return a valid per-name reply.
final class RecycleCallFailure extends RecycleReply {
  /// Creates a call failure.
  const RecycleCallFailure();
}

/// The sole application boundary for moving screenshots to the Recycle Bin.
abstract interface class RecyclePort {
  /// Recycles at most 64 basenames directly inside [folder].
  ///
  /// Calls must not overlap. No operation permanently deletes a file.
  Future<RecycleReply> recycle(String folder, List<String> names);

  /// Requests that the active call stop before its next file.
  ///
  /// The active reply still completes separately; cancellation is not a drain.
  Future<void> cancel();
}
