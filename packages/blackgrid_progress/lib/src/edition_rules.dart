/// A versioned vocabulary and task-to-edition restriction table.
///
/// Collections supplied to this const-compatible type are owned by the caller;
/// use immutable collections when sharing a table across evaluations.
final class EditionTable {
  /// Creates a table with its vocabulary, task entries and version.
  const EditionTable({
    required this.version,
    required this.editions,
    required this.entries,
  });

  /// The version of the reviewed table data.
  final int version;

  /// Edition identifiers recognized by the table.
  final Set<String> editions;

  /// Edition restrictions keyed by task ID.
  final Map<String, EditionRule> entries;
}

/// A sourced set of allowed or excluded editions for a task.
///
/// The supplied set is caller-owned; use an immutable set when sharing a rule.
final class EditionRule {
  /// Creates a rule permitting only editions in [editions].
  const EditionRule.allowed(this.editions, {required this.source})
    : excludes = false;

  /// Creates a rule permitting editions outside [editions].
  const EditionRule.excluded(this.editions, {required this.source})
    : excludes = true;

  /// The edition identifiers included in the rule.
  final Set<String> editions;

  /// The evidence supporting the restriction.
  final String source;

  /// Whether listed editions are excluded rather than allowed.
  final bool excludes;

  /// Returns whether this rule permits [edition].
  bool permits(String edition) => editions.contains(edition) != excludes;
}
