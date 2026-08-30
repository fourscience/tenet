import 'async_value.dart';

/// Accumulates the dependencies one tracked run (a [ComputedNode] recompute,
/// or one [FutureNode]/[EffectNode] run) taps, wiring each one into the
/// graph (`dep.dependents.add(owner)`) *immediately* as it's tapped —
/// not batched until the run finishes. That matters specifically for a
/// [FutureNode]/[EffectNode]: its run can span real `await`s, so a change
/// to something it already tapped *during* that run has to be visible to
/// the dirty wave right away (that's what lets a change mid-run coalesce
/// into a rerun instead of being silently missed because the edge didn't
/// exist yet). Also answers "did this run already tap that node" — the
/// query [Scope] needs to let an already-tracked dependency be read again
/// after a body has suspended, while still rejecting a *new* one
/// (`TrackingAfterSuspendError`).
final class DependencyTracker {
  DependencyTracker(this.owner);

  final ReactiveNode owner;
  final Set<ReactiveNode> seen = {};

  void record(ReactiveNode node) {
    if (seen.add(node)) node.dependents.add(owner);
  }

  bool contains(ReactiveNode node) => seen.contains(node);
}

/// Something that can be marked dirty and, when pulled or flushed, produce
/// a fresh value — the common shape [CellNode], [ComputedNode], and
/// [FutureNode] all share so the dependency graph can treat them
/// uniformly regardless of kind.
abstract class ReactiveNode {
  /// Other reactive nodes that tapped this one while it last ran —
  /// notified (marked dirty) when this node's value changes.
  final Set<ReactiveNode> dependents = {};

  /// External `watch()`/`effect()`/Flutter-element subscribers. Distinct
  /// from [dependents]: those are graph edges to other reactive nodes;
  /// these are leaf listeners with no further propagation of their own.
  final List<void Function()> _watchers = [];

  /// True once something has changed upstream and this node needs to
  /// recompute (or, for a cell, notify) before its watchers are current.
  bool dirty = false;

  /// Set once by the owning scope right after this node is created —
  /// the hook that enqueues a dirtied node onto the scheduler's flush
  /// queue. A plain field rather than a constructor param so every node
  /// subtype can share one assignment point in the scope.
  void Function(ReactiveNode node)? onDirty;

  /// Whether anything relies on this node — an external watcher, or a
  /// dependent reactive node. Drives `.autoDispose`.
  bool get isObserved => _watchers.isNotEmpty || dependents.isNotEmpty;

  /// Whether `.autoDispose` was applied to this vine — false for
  /// anything but a [ComputedNode]/[FutureNode] built from one (a plain
  /// [CellNode]/[EffectNode] never drops itself this way).
  bool get autoDispose => false;

  int get watcherCount => _watchers.length;

  void Function() addWatcher(void Function() callback) {
    _watchers.add(callback);
    return () => _watchers.remove(callback);
  }

  void notifyWatchers() {
    for (final watcher in List.of(_watchers)) {
      watcher();
    }
  }

  /// Call after this node's own value has actually changed: cascades
  /// dirty + enqueue to every dependent, transitively, exactly once each
  /// — the "dirty wave" push. Does not mark `this` dirty again (the
  /// caller just finished recomputing it).
  void propagateChange() {
    final visited = <ReactiveNode>{this};
    for (final dependent in List.of(dependents)) {
      dependent._markDirtyAndEnqueue(visited);
    }
  }

  void _markDirtyAndEnqueue(Set<ReactiveNode> visited) {
    if (!visited.add(this)) return;
    dirty = true;
    onDirty?.call(this);
    for (final dependent in List.of(dependents)) {
      dependent._markDirtyAndEnqueue(visited);
    }
  }

  /// Removes this node's edges into whatever it tapped last run, so a
  /// fresh run can rebuild dependencies from scratch (dynamic
  /// re-tracking: branches that stopped being read are dropped).
  void clearOwnDependencies();

  void dispose() {
    clearOwnDependencies();
    _watchers.clear();
    dependents.clear();
  }
}

/// The reactive source: a plain mutable cell. [set] applies the equality
/// gate (`==` short-circuits with no notification) and pushes dirtiness
/// to dependents when the value actually changes.
final class CellNode<T> extends ReactiveNode {
  CellNode(this._value);

  T _value;
  T get value => _value;

  /// Returns true if the value actually changed (and dependents were
  /// notified) — false on a same-value write, which is a no-op.
  bool set(T next) {
    if (_value == next) return false;
    _value = next;
    dirty = true;
    onDirty?.call(this);
    propagateChange();
    return true;
  }

  @override
  void clearOwnDependencies() {} // a cell has no dependencies of its own
}

/// A memoized, synchronously-derived value. [pull] is the single place
/// recompute/equality-gate/re-dirty-propagation happens, called both from
/// a direct `tap()` (lazy pull) and from the scheduler's flush (so an
/// active watcher still gets notified without anyone explicitly tapping).
final class ComputedNode<T> extends ReactiveNode {
  ComputedNode(this._recompute, {this.autoDispose = false});

  final T Function() _recompute;
  @override
  final bool autoDispose;
  bool _hasValue = false;
  late T _value;
  Set<ReactiveNode> _lastDeps = {};

  /// The tracker `_recompute`'s body records taps into — replaced with a
  /// fresh one before every recompute; kept as a field (not a local) so
  /// the closure `_recompute` wraps can reach the *current* run's
  /// tracker via [currentTracker] while it's live.
  late DependencyTracker currentTracker = DependencyTracker(this);

  bool get hasValue => _hasValue;

  T get value {
    pull();
    return _value;
  }

  /// Recomputes if dirty (or never run), applying the equality gate.
  /// Returns true if the value actually changed (false both for a no-op
  /// re-run and for this node's very first computation — there's no
  /// "previous" value yet for that one to be a change *from*, so it
  /// doesn't notify watchers either; call [value] right after `watch`ing
  /// for the initial one instead).
  bool pull() {
    if (!dirty && _hasValue) return false;
    dirty = false;
    final hadValue = _hasValue;
    for (final dep in _lastDeps) {
      dep.dependents.remove(this);
    }
    _lastDeps = {};
    currentTracker = DependencyTracker(this);
    final T next;
    try {
      next = _recompute();
    } finally {
      _lastDeps = currentTracker.seen;
    }
    if (hadValue && _value == next) return false;
    _value = next;
    _hasValue = true;
    if (!hadValue) return false;
    notifyWatchers();
    propagateChange();
    return true;
  }

  @override
  void clearOwnDependencies() {
    for (final dep in _lastDeps) {
      dep.dependents.remove(this);
    }
    _lastDeps = {};
  }
}

/// A [Vine.future] node: dual-mode async derivation. Holds the current
/// [AsyncValue] and a monotonic generation counter for race safety — a
/// superseded run's result is discarded rather than written back, and
/// concurrent callers awaiting the same in-flight run dedupe onto it.
final class FutureNode<T> extends ReactiveNode {
  FutureNode(this._run,
      {this.autoDispose = false, this.eager = false, this.onError});

  /// Runs the body, given a [DependencyTracker] to record taps before
  /// the first await into.
  final Future<T> Function(DependencyTracker tracker) _run;
  @override
  final bool autoDispose;
  final bool eager;

  /// `Garden`'s observability hook, called whenever a run fails —
  /// regardless of whether anyone is awaiting `start()`'s result. Also
  /// what keeps a scheduler-triggered (fire-and-forget) failing run from
  /// surfacing as an unhandled async error: see the `catchError` in
  /// [start].
  final void Function(Object error, StackTrace stackTrace)? onError;

  AsyncValue<T> state = const AsyncLoading();
  int _generation = 0;
  Future<T>? _inFlight;
  Set<ReactiveNode> _lastDeps = {};

  bool get hasStarted => _generation > 0;

  /// Starts a run if one isn't already in flight and the current state
  /// isn't already a settled, up-to-date result — in flight, dedupes
  /// onto it; settled-and-not-[dirty], returns/rethrows the cached
  /// outcome without re-running. Otherwise transitions to
  /// `AsyncLoading(previous: ...)` and starts a fresh run right away.
  /// Returns the future of raw data — awaiting it rethrows on failure.
  Future<T> start() {
    final existing = _inFlight;
    if (existing != null) return existing;
    if (hasStarted && !dirty) {
      final settled = state;
      if (settled is AsyncData<T>) return Future.value(settled.value);
      if (settled is AsyncError<T>) {
        return Future<T>.error(settled.error, settled.stackTrace);
      }
    }
    final myGeneration = ++_generation;
    final previous = state.value;
    state = AsyncLoading<T>(previous);
    dirty = false;
    notifyWatchers();
    // Wired live, as the run taps each dependency — not batched until it
    // finishes — so a change to something already tapped *during* this
    // (possibly long-running) run is visible to the dirty wave right
    // away. See [DependencyTracker]'s doc comment.
    for (final dep in _lastDeps) {
      dep.dependents.remove(this);
    }
    _lastDeps = {};
    final tracker = DependencyTracker(this);
    final future = _run(tracker).then<T>(
      (data) {
        _lastDeps = tracker.seen;
        if (myGeneration != _generation) return data; // superseded
        state = AsyncData<T>(data);
        _inFlight = null;
        notifyWatchers();
        propagateChange();
        return data;
      },
      onError: (Object error, StackTrace stackTrace) {
        _lastDeps = tracker.seen;
        if (myGeneration == _generation) {
          state = AsyncError<T>(error, stackTrace, previous);
          _inFlight = null;
          notifyWatchers();
          propagateChange();
          onError?.call(error, stackTrace);
        }
        throw error;
      },
    );
    // A second listener on the same future purely so a fire-and-forget
    // caller (the scheduler, an eager grow(), an auto-started watch())
    // doesn't turn a failing run into an unhandled async error — the
    // failure is already recorded into `state` and reported to `onError`
    // above regardless of who (if anyone) awaits this specific future.
    future.then((_) {}, onError: (Object _, StackTrace __) {});
    _inFlight = future;
    return future;
  }

  /// Forces a fresh run (`Garden.refresh`), discarding any in-flight one.
  void invalidate() {
    _generation++;
    _inFlight = null;
    dirty = true;
  }

  @override
  void clearOwnDependencies() {
    for (final dep in _lastDeps) {
      dep.dependents.remove(this);
    }
    _lastDeps = {};
    _generation++; // orphan any in-flight run so it can't write back
  }
}

/// An `effect()`: push-only, no cached value of its own. Runs are
/// serialized — a change arriving mid-run schedules (coalesces) exactly
/// one rerun rather than overlapping.
final class EffectNode extends ReactiveNode {
  EffectNode(this._run);

  final Future<void> Function(DependencyTracker tracker) _run;
  bool _running = false;
  bool _rerunRequested = false;
  int _generation = 0;
  Set<ReactiveNode> _lastDeps = {};
  bool disposed = false;

  Future<void> runIfNeeded() async {
    if (disposed) return;
    if (_running) {
      _rerunRequested = true;
      return;
    }
    _running = true;
    final myGeneration = ++_generation;
    try {
      do {
        _rerunRequested = false;
        dirty = false;
        // Wired live, as the run taps each dependency — see
        // [FutureNode.start]'s matching comment for why: a change to
        // something already tapped *during* this run (which can span
        // real `await`s) has to be visible to the dirty wave right away
        // for "a change mid-run coalesces into a rerun" to actually work.
        for (final dep in _lastDeps) {
          dep.dependents.remove(this);
        }
        _lastDeps = {};
        final tracker = DependencyTracker(this);
        try {
          await _run(tracker);
        } finally {
          _lastDeps = tracker.seen;
        }
        if (disposed || myGeneration != _generation) return;
      } while (_rerunRequested && !disposed);
    } finally {
      _running = false;
    }
  }

  @override
  void clearOwnDependencies() {
    for (final dep in _lastDeps) {
      dep.dependents.remove(this);
    }
    _lastDeps = {};
  }

  @override
  void dispose() {
    disposed = true;
    _generation++;
    super.dispose();
  }
}
