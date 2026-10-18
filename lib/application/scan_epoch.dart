/// The point in the app's lifetime at which a scan began.
///
/// A scan result is only valid for the epoch it started in. A mode change or a
/// new map session produces a different epoch, so a late result can be told
/// apart from a current one.
class ScanEpoch {
  /// Creates an epoch from the [modeTransition] and [session] counters.
  const ScanEpoch(this.modeTransition, this.session);

  /// Counts completed game-mode transitions.
  final int modeTransition;

  /// Counts map sessions.
  final int session;

  @override
  bool operator ==(Object other) =>
      other is ScanEpoch &&
      other.modeTransition == modeTransition &&
      other.session == session;

  @override
  int get hashCode => Object.hash(modeTransition, session);

  @override
  String toString() => 'ScanEpoch($modeTransition, $session)';
}
