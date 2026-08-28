import 'dart:async';

/// Structured, hierarchical cancellation scopes for Ripples.

/// Thrown when a Ripple attempts to emit into a [FlowScope] that has been
/// closed. Surfacing this loudly prevents ghost writes after cancellation.
class ScopeDeadException implements Exception {
  /// The name of the scope that was already closed.
  final String scopeName;

  /// Creates the exception.
  ScopeDeadException(this.scopeName);

  @override
  String toString() => 'ScopeDeadException: scope "$scopeName" is closed; '
      'a Ripple attempted a late emission after cancellation.';
}

/// A structured, hierarchical cancellation scope.
///
/// Every Ripple runs inside exactly one scope. Closing a scope:
///   * cancels its cancellation token (propagates through await chains),
///   * closes all child scopes (recursively),
///   * marks the scope dead so late emissions throw [ScopeDeadException].
///
/// This mirrors structured concurrency: a screen's lifetime *is* its scope.
final class FlowScope {
  final String _name;
  final FlowScope? _parent;
  final List<FlowScope> _children = [];
  final Completer<void> _canceller = Completer<void>();
  bool _closed = false;

  /// The root, immortal scope owned by a `Store`.
  FlowScope.root()
      : _name = 'root',
        _parent = null;

  FlowScope._(this._name, this._parent) {
    _parent?._children.add(this);
  }

  /// Spawns a named child scope. Closing [this] closes all children.
  FlowScope spawn(String name) {
    if (_closed) {
      throw StateError('Cannot spawn "$name" inside closed scope "$_name".');
    }
    return FlowScope._(name, this);
  }

  /// A future that completes when this scope is closed/cancelled.
  /// Ripples can race their work against this to implement cooperative
  /// cancellation:
  ///
  /// ```dart
  /// await work.timeout(...).catchError((_) => fallback);
  /// // or: race with scope.cancelled
  /// ```
  Future<void> get cancelled => _canceller.future;

  /// Whether this scope (or any ancestor) has been closed.
  bool get isDead =>
      _closed || _canceller.isCompleted || (_parent?.isDead ?? false);

  /// The scope's name — useful for logging and tests.
  String get name => _name;

  /// Closes this scope and all descendants. Idempotent.
  void close() {
    if (_closed) return;
    _closed = true;
    if (!_canceller.isCompleted) _canceller.complete();
    for (final child in List<FlowScope>.of(_children)) {
      child.close();
    }
    _children.clear();
    _parent?._children.remove(this);
  }
}
