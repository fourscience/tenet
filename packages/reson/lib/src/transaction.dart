/// The temporal ledger: an immutable record of every committed state
/// transition, which powers time-travel debugging for free.
library;

/// An immutable record of a single committed state transition.
final class Transaction<S> {
  /// Human-readable name of the Flow/Ripple/Echo that produced this commit.
  final String source;

  /// State before the commit.
  final S before;

  /// State after the commit.
  final S after;

  /// Whether this commit was an optimistic one (subject to rollback).
  final bool optimistic;

  /// Monotonic sequence number, assigned by the `Store`.
  final int sequence;

  /// Wall-clock timestamp of the commit.
  final DateTime timestamp;

  /// Creates an immutable transaction record.
  const Transaction({
    required this.source,
    required this.before,
    required this.after,
    required this.optimistic,
    required this.sequence,
    required this.timestamp,
  });

  @override
  String toString() =>
      'Txn#$sequence[$source]${optimistic ? '(optimistic)' : ''}: '
      '$before -> $after';
}
