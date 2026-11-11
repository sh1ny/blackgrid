import 'catalog.dart';
import 'local_progress.dart';

/// The outcome of a local progress operation.
sealed class ProgressResult<T> {
  /// Creates a progress operation outcome.
  const ProgressResult();
}

/// A successfully committed or read progress value.
final class ProgressSuccess<T> extends ProgressResult<T> {
  /// Creates a successful outcome containing [value].
  const ProgressSuccess(this.value);

  /// The result of the operation.
  final T value;
}

/// An operation that did not produce a successful result.
final class ProgressFailure<T> extends ProgressResult<T> {
  /// Creates a failed outcome containing [failure].
  const ProgressFailure(this.failure);

  /// The reason the operation could not succeed.
  final ProgressStoreFailure failure;
}

/// A caller-visible reason a progress operation failed.
sealed class ProgressStoreFailure {
  /// Creates a progress store failure.
  const ProgressStoreFailure();
}

/// An argument, event, scope or operation limit was invalid.
final class ProgressInvalidInput extends ProgressStoreFailure {
  /// Creates an invalid-input failure with a descriptive [reason].
  const ProgressInvalidInput(this.reason);

  /// A description of the invalid input.
  final String reason;
}

/// An event or undo request ID was reused with contradictory content.
final class ProgressIdentityConflict extends ProgressStoreFailure {
  /// Creates an identity-conflict failure with a descriptive [reason].
  const ProgressIdentityConflict(this.reason);

  /// A description of the conflicting identity.
  final String reason;
}

/// Another progress operation is already admitted by this store instance.
final class ProgressBusy extends ProgressStoreFailure {
  /// Creates a busy failure.
  const ProgressBusy();
}

/// Storage could not complete an operation or commit its transaction.
final class ProgressStorageFailure extends ProgressStoreFailure {
  /// Creates a storage failure with a descriptive [reason].
  const ProgressStorageFailure(this.reason);

  /// A description of the storage failure.
  final String reason;
}

/// A cycle cannot be safely exposed because its history is unreadable.
final class ProgressUnavailable extends ProgressStoreFailure {
  /// Creates an unavailable-cycle failure for [scope] and [reason].
  const ProgressUnavailable({required this.scope, required this.reason});

  /// The affected mode and cycle.
  final ProgressScope scope;

  /// A description of the unsupported or damaged history.
  final String reason;
}

/// A current-value continuation no longer matches the cycle revision.
final class ProgressStaleCursor extends ProgressStoreFailure {
  /// Creates a stale-cursor failure.
  const ProgressStaleCursor();
}

/// An undo target is not the current winner of its register.
final class ProgressUndoConflict extends ProgressStoreFailure {
  /// Creates an undo-conflict failure with a descriptive [reason].
  const ProgressUndoConflict(this.reason);

  /// A description of the conflicting undo request.
  final String reason;
}

/// A position in a scope's bounded, insertion-ordered history snapshot.
final class ProgressHistoryCursor {
  /// Creates a history continuation bound to [scope] and its high-water mark.
  const ProgressHistoryCursor({
    required this.scope,
    required this.highWaterSequence,
    required this.lastSequence,
  });

  /// The mode and cycle whose history is being traversed.
  final ProgressScope scope;

  /// The highest insertion sequence included in this traversal.
  final int highWaterSequence;

  /// The insertion sequence of the last event already returned.
  final int lastSequence;
}

/// A position in the current winners at one cycle revision.
final class ProgressCurrentCursor {
  /// Creates a current-value continuation for [scope] at [revision].
  const ProgressCurrentCursor({
    required this.scope,
    required this.revision,
    required this.lastTarget,
  });

  /// The mode and cycle whose current values are being traversed.
  final ProgressScope scope;

  /// The revision shared by the pages in this traversal.
  final int revision;

  /// The last register key already returned.
  final ProgressTarget lastTarget;
}

/// A bounded page of explicitly created cycles for one mode.
final class ProgressCyclePage {
  /// Creates a cycle page and its optional continuation.
  const ProgressCyclePage({required this.cycles, required this.nextCursor});

  /// The cycles in ascending binary text cycle-ID order.
  final List<ProgressCycle> cycles;

  /// The cycle ID to pass as the next page's `afterCycleId`, or `null`.
  final String? nextCursor;
}

/// A bounded page of events from one history traversal.
final class ProgressHistoryPage {
  /// Creates a history page and its optional continuation.
  const ProgressHistoryPage({required this.events, required this.nextCursor});

  /// The events in ascending insertion-sequence order.
  final List<ProgressEvent> events;

  /// The continuation for the same high-water snapshot, or `null`.
  final ProgressHistoryCursor? nextCursor;
}

/// A bounded page of current winning events at one cycle revision.
final class ProgressCurrentPage {
  /// Creates a current-value page at [revision] and its optional continuation.
  const ProgressCurrentPage({
    required this.events,
    required this.revision,
    required this.nextCursor,
  });

  /// The winners in binary text kind/ID/field order, including unset winners.
  final List<ProgressEvent> events;

  /// The cycle revision represented by every event in this page.
  final int revision;

  /// The continuation for this revision, or `null`.
  final ProgressCurrentCursor? nextCursor;
}

/// The effects of one atomic event batch.
final class ProgressAppendResult {
  /// Creates an append result with the inserted count and resulting revision.
  const ProgressAppendResult({
    required this.insertedCount,
    required this.revision,
  });

  /// The number of new events inserted, excluding exact duplicates.
  final int insertedCount;

  /// The cycle revision after the batch commits.
  final int revision;
}

/// The durable, explicitly scoped local progress ledger.
///
/// A scope identifies both a known game mode and an explicitly created local
/// cycle; a cycle is not an official wipe. Operations never create missing
/// scopes implicitly, select an active cycle, reset progress or trim history.
/// Events are authoritative and register winners are ordered by occurrence
/// time, source rank (manual before log), ordinal device ID, then ordinal event
/// ID. An unset winner represents an unknown value, not zero or an older value.
///
/// All operations return typed failures rather than partial success. At most one
/// operation is admitted per store instance; a concurrent call returns
/// [ProgressBusy] rather than entering a queue. There is no automatic retry.
/// Callers may explicitly retry identified writes using the same IDs and
/// content. Other instances coordinate through their storage transactions.
abstract interface class LocalProgressStore {
  /// Returns the persistent locally generated device identity.
  ///
  /// The identity is created once and survives reopening the store; it is not
  /// an account identity or a claim of cross-device synchronization.
  Future<ProgressResult<String>> progressDeviceId();

  /// Creates and persists a distinct local cycle for [mode].
  ///
  /// Existing cycles and their events are preserved. Each successful call
  /// creates a new cycle, so retrying an ambiguous creation can create another.
  Future<ProgressResult<ProgressCycle>> createProgressCycle(GameMode mode);

  /// Lists explicitly created cycles for [mode] in binary text cycle-ID order.
  ///
  /// [limit] must be between 1 and [progressPageLimit], inclusive. A non-null
  /// [afterCycleId] resumes strictly after that ID; use the returned cursor to
  /// continue. Listing does not select, create or remove a cycle.
  Future<ProgressResult<ProgressCyclePage>> listProgressCycles(
    GameMode mode, {
    int limit = progressPageLimit,
    String? afterCycleId,
  });

  /// Validates and opens the existing cycle identified by [scope].
  ///
  /// History is validated and its current winners rebuilt atomically before
  /// success. Unsupported, malformed or inconsistent stored events yield
  /// [ProgressUnavailable], never partial progress or a reset. Original event
  /// data is retained even when validation or rebuilding fails.
  Future<ProgressResult<ProgressCycle>> openProgressCycle(ProgressScope scope);

  /// Atomically appends [events] to the existing cycle identified by [scope].
  ///
  /// The batch must contain 1 through [progressPageLimit] valid events, all in
  /// [scope], each within the encoding and identity budgets. At most one item
  /// beyond the limit is consumed before rejecting an oversized iterable.
  /// Event IDs are globally unique across modes and cycles. An exact replay,
  /// including duplicates within the batch, changes nothing; reuse with
  /// different canonical content returns [ProgressIdentityConflict] and
  /// rejects the entire batch. No event or winner is partially committed.
  ///
  /// New events and their winning-register updates commit together. Revision
  /// advances once if at least one event is new, even if none becomes a winner;
  /// a duplicate-only batch leaves it unchanged. Incoming IDs and occurrence
  /// times are preserved, including for late or losing events.
  Future<ProgressResult<ProgressAppendResult>> appendProgressEvents(
    ProgressScope scope,
    Iterable<ProgressEvent> events,
  );

  /// Reads a bounded insertion-ordered page of history for [scope].
  ///
  /// [limit] must be between 1 and [progressPageLimit], inclusive. The first
  /// page captures a high-water sequence; subsequent pages using [cursor]
  /// return each event through that mark once and exclude later appends,
  /// regardless of occurrence time. A cursor must belong to [scope]. Invalid
  /// or unsupported history returns [ProgressUnavailable], not a partial page.
  Future<ProgressResult<ProgressHistoryPage>> readProgressHistory(
    ProgressScope scope, {
    int limit = progressPageLimit,
    ProgressHistoryCursor? cursor,
  });

  /// Reads a bounded page of winning events for [scope].
  ///
  /// [limit] must be between 1 and [progressPageLimit], inclusive. Results use
  /// binary text kind/ID/field order and include explicit unset winners.
  /// This keyset order is separate from the event conflict comparator.
  /// A continuation must
  /// name [scope] and the same committed revision; a changed revision returns
  /// [ProgressStaleCursor]. Each page's revision check, validation or rebuild,
  /// and row reads share one storage transaction and snapshot, including the
  /// final page. A racing commit cannot yield newer rows under an older
  /// revision: the page either uses the checked snapshot or fails explicitly.
  /// No transaction remains open between page calls. Damaged or unsupported
  /// history returns [ProgressUnavailable], never a partial page.
  Future<ProgressResult<ProgressCurrentPage>> readProgressCurrent(
    ProgressScope scope, {
    int limit = progressPageLimit,
    ProgressCurrentCursor? cursor,
  });

  /// Atomically rebuilds the current winners from history in [scope].
  ///
  /// History remains unchanged and other scopes are unaffected. Failure leaves
  /// no partial replacement visible; unreadable history returns
  /// [ProgressUnavailable]. The returned cycle describes the rebuilt scope.
  Future<ProgressResult<ProgressCycle>> rebuildProgress(ProgressScope scope);

  /// Appends and returns a guarded compensation for [targetEventId].
  ///
  /// [requestEventId] is the stable event ID of the compensation. An existing
  /// matching request is returned before checking whether the target is still
  /// the winner, including after another event subsequently wins. Contradictory
  /// reuse of the request ID returns [ProgressIdentityConflict].
  ///
  /// For a new request, the target must still be the current winner in [scope]
  /// in the same transaction as the append, or [ProgressUndoConflict] is
  /// returned without mutation. The manual compensation links to the target
  /// and restores its greatest strict predecessor for that register, or unset
  /// if none exists. Its timestamp is the later of the current time and one
  /// millisecond after the target; an unrepresentable timestamp is invalid.
  /// The original history remains intact, and a compensation can itself be
  /// undone under the same rules.
  Future<ProgressResult<ProgressEvent>> undoProgress(
    ProgressScope scope, {
    required String targetEventId,
    required String requestEventId,
  });
}
