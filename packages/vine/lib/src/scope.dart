import 'dart:async';

import 'errors.dart';
import 'node.dart';
import 'scheduler.dart';
import 'tap.dart';
import 'vine.dart';

/// The actual resolution/caching engine behind one [Garden] (the root
/// scope) or one `growScope()` (a child). Caching is always local to
/// *this* scope — resolving a non-overridden vine here always creates
/// (or reuses) this scope's own instance, never an ancestor's, which is
/// what gives `growScope` its "scoped singleton" isolation (section 6.1).
/// Only override lookup walks the parent chain (nearest wins).
final class Scope {
  Scope(
      {this.parent,
      List<VineOverride> overrides = const [],
      void Function(Object vine, Object error, StackTrace stackTrace)? onError})
      : scheduler = parent?.scheduler ?? Scheduler(),
        onError = onError ?? parent?.onError,
        _creatingStack = parent?._creatingStack ?? [] {
    for (final override in overrides) {
      _overrides[override.vine] = override.create;
    }
    parent?._children.add(this);
  }

  final Scope? parent;
  final Scheduler scheduler;

  /// `Garden`'s observability hook — set once at the root and inherited
  /// by every `growScope()` child.
  final void Function(Object vine, Object error, StackTrace stackTrace)?
      onError;

  /// Shared across the whole scope tree (root + every descendant) so a
  /// cycle spanning scope boundaries is still caught.
  final List<Object> _creatingStack;

  final Map<Object, Function> _overrides = {};
  final Map<Object, Object?> _frozen = {};
  final Map<Object, ReactiveNode> _nodes = {};
  final List<void Function()> _disposers = [];
  final List<Scope> _children = [];
  bool disposed = false;

  /// Keys of `.autoDispose` nodes whose watcher count reached 0 and are
  /// awaiting the grace-period check — see [checkAutoDispose].
  final Set<Object> _pendingAutoDispose = {};
  bool _autoDisposeFlushScheduled = false;

  Scope get root => parent?.root ?? this;

  /// Resolves [vine] in this scope for a synchronous tap: creates (and
  /// caches) it on first resolution. [tracker] non-null makes this a
  /// *tracked* read — subject to [trackingAllowed] (false once a
  /// `Vine.future`/effect body has suspended past its first await; see
  /// [DependencyTracker]). [isComputedContext] enables the
  /// `Vine.computed`-only "no tapping a pending future" rule.
  Object? resolve(
    Vine vine, {
    DependencyTracker? tracker,
    bool trackingAllowed = true,
    bool isComputedContext = false,
  }) {
    _checkNotDisposed();

    if (vine is VineRef) {
      final bound = vine.bound;
      if (bound == null) throw UntiedRefError(vine);
      return resolve(
        bound,
        tracker: tracker,
        trackingAllowed: trackingAllowed,
        isComputedContext: isComputedContext,
      );
    }
    if (vine is ValueVine) return vine.value;
    if (vine is FrozenVine) return _resolveFrozen(vine);
    if (vine is CellVine) {
      final node = _ensureCellNode(vine);
      _track(node, tracker, trackingAllowed, vine);
      return node.value;
    }
    if (vine is ComputedVine) {
      final node = _ensureComputedNode(
        key: vine,
        overrideKey: vine,
        body: (tap) => vine.create(tap),
        autoDispose: vine.internalAutoDispose,
      );
      _track(node, tracker, trackingAllowed, vine);
      return node.value;
    }
    if (vine is VineInstance) {
      final node = _ensureComputedNode(
        key: vine,
        overrideKey: vine.family,
        body: vine.createBody(),
        invokeOverride: vine.invokeOverride,
        autoDispose: vine.family.internalAutoDispose,
      );
      _track(node, tracker, trackingAllowed, vine);
      return node.value;
    }
    if (vine is FutureVine) {
      final node = vine.ensureNode(this);
      if (isComputedContext && node.state.isLoading) {
        throw AsyncInSyncContextError(vine);
      }
      if (!node.hasStarted) node.start();
      _track(node, tracker, trackingAllowed, vine);
      return node.state;
    }
    if (vine is FutureVineInstance) {
      final node = vine.ensureNode(this);
      if (isComputedContext && node.state.isLoading) {
        throw AsyncInSyncContextError(vine);
      }
      if (!node.hasStarted) node.start();
      _track(node, tracker, trackingAllowed, vine);
      return node.state;
    }
    throw StateError('Unrecognized vine kind: $vine');
  }

  /// Resolves a future-shaped vine ([FutureVine] or [FutureVineInstance])
  /// for `tap.async`/`Garden.tapAsync`: returns the *raw* awaited data,
  /// rethrowing on failure, deduping onto an already-in-flight run.
  Future<Object?> resolveAsync(
    Vine vine, {
    DependencyTracker? tracker,
    bool trackingAllowed = true,
  }) {
    _checkNotDisposed();
    if (vine is VineRef) {
      final bound = vine.bound;
      if (bound == null) throw UntiedRefError(vine);
      return resolveAsync(bound,
          tracker: tracker, trackingAllowed: trackingAllowed);
    }
    final FutureNode node;
    if (vine is FutureVine) {
      node = vine.ensureNode(this);
    } else if (vine is FutureVineInstance) {
      node = vine.ensureNode(this);
    } else {
      throw ArgumentError(
          'tap.async/tapAsync only accept a future vine, got: $vine');
    }
    _track(node, tracker, trackingAllowed, vine);
    return node.start();
  }

  // ---- frozen (value handled by caller; single/transient/eager here) ----

  Object? _resolveFrozen(FrozenVine vine) {
    if (!vine.isTransient && _frozen.containsKey(vine)) return _frozen[vine];
    _pushCreating(vine);
    final Object? value;
    try {
      final override = _findOverride(vine);
      final tap = TapImpl(this);
      value = override != null ? override(tap) : vine.create(tap);
    } finally {
      _popCreating(vine);
    }
    if (!vine.isTransient) {
      _frozen[vine] = value;
      if (vine.hasDispose) _disposers.add(() => vine.invokeDispose(value));
    }
    return value;
  }

  // ---- cell ----

  CellNode _ensureCellNode(CellVine vine) {
    var node = _nodes[vine] as CellNode?;
    if (node != null) return node;
    _pushCreating(vine);
    final Object? initial;
    try {
      final override = _findOverride(vine);
      initial = override != null ? override(TapImpl(this)) : vine.initial;
    } finally {
      _popCreating(vine);
    }
    node = CellNode(initial)..onDirty = scheduler.schedule;
    _nodes[vine] = node;
    return node;
  }

  // ---- computed / each (sync) ----

  ComputedNode _ensureComputedNode({
    required Object key,
    required Object overrideKey,
    required Object? Function(Tap tap) body,
    required bool autoDispose,
    Object? Function(Function override, Tap tap)? invokeOverride,
  }) {
    final existing = _nodes[key] as ComputedNode?;
    if (existing != null) return existing;
    late final ComputedNode node;
    node = ComputedNode<Object?>(() {
      _pushCreating(key);
      try {
        final override = _findOverride(overrideKey);
        final tap = TapImpl(this,
            tracker: node.currentTracker, isComputedContext: true);
        if (override == null) return body(tap);
        return invokeOverride != null
            ? invokeOverride(override, tap)
            : override(tap);
      } finally {
        _popCreating(key);
      }
    }, autoDispose: autoDispose)
      ..onDirty = scheduler.schedule;
    _nodes[key] = node;
    return node;
  }

  // ---- future / eachAsync ----

  /// Gets-or-creates the [FutureNode] backing a future-shaped vine, with
  /// `T` correctly reified. Public (unlike the other `_ensure*Node`
  /// helpers) because it has to be called from *within* `FutureVine<T>`/
  /// `FutureVineInstance<K, T>`'s own generic scope — see
  /// [FutureVine.ensureNode]'s doc comment for why `Scope` can't safely
  /// do this itself from an erased `Vine`/`FutureNode` reference.
  FutureNode<T> ensureFutureNode<T>({
    required Object key,
    required Object overrideKey,
    required Future<T> Function(Tap tap) body,
    required bool autoDispose,
    required bool eager,
    Future<T> Function(Function override, Tap tap)? invokeOverride,
  }) {
    final existing = _nodes[key];
    if (existing != null) return existing as FutureNode<T>;
    final node = FutureNode<T>((tracker) {
      _pushCreating(key);
      try {
        final override = _findOverride(overrideKey);
        final tap = TapImpl(this, tracker: tracker);
        if (override == null) return body(tap);
        return invokeOverride != null
            ? invokeOverride(override, tap)
            : override(tap) as Future<T>;
      } finally {
        _popCreating(key);
      }
    },
        autoDispose: autoDispose,
        eager: eager,
        onError: onError == null ? null : (e, st) => onError!(key, e, st))
      ..onDirty = scheduler.schedule;
    _nodes[key] = node;
    return node;
  }

  /// Writes [vine]'s cell — `Garden.set`. Returns true if the value
  /// actually changed.
  bool setCell(CellVine vine, Object? value) =>
      _ensureCellNode(vine).set(value);

  /// Gets-or-creates the reactive node backing [vine] — `Garden.watch`.
  /// Starts a not-yet-started future vine, since otherwise nothing would
  /// ever drive it forward for a watcher that never taps it directly.
  /// Throws [ArgumentError] for a non-reactive (frozen) vine — nothing
  /// to watch, since it never changes after its first tap.
  ReactiveNode ensureReactiveNode(Vine vine) {
    if (vine is VineRef) {
      final bound = vine.bound;
      if (bound == null) throw UntiedRefError(vine);
      return ensureReactiveNode(bound);
    }
    if (vine is CellVine) return _ensureCellNode(vine);
    if (vine is ComputedVine) {
      final node = _ensureComputedNode(
        key: vine,
        overrideKey: vine,
        body: (tap) => vine.create(tap),
        autoDispose: vine.internalAutoDispose,
      );
      node.pull(); // establishes its dependency edges even if never tapped
      return node;
    }
    if (vine is VineInstance) {
      final node = _ensureComputedNode(
        key: vine,
        overrideKey: vine.family,
        body: vine.createBody(),
        invokeOverride: vine.invokeOverride,
        autoDispose: vine.family.internalAutoDispose,
      );
      node.pull();
      return node;
    }
    if (vine is FutureVine) {
      final node = vine.ensureNode(this);
      if (!node.hasStarted) node.start();
      return node;
    }
    if (vine is FutureVineInstance) {
      final node = vine.ensureNode(this);
      if (!node.hasStarted) node.start();
      return node;
    }
    throw ArgumentError(
      '$vine is not reactive — only cell/computed/future/each vines can '
      'be watched (a frozen vine never changes after its first tap).',
    );
  }

  /// Starts (or restarts) the async run backing [vine] — `Garden.refresh`.
  /// [replacement], if given, temporarily replaces the body for every
  /// future run (spec's `garden.refresh(v, altBody)`).
  Future<void> refreshFuture(Vine vine, Function? replacement) {
    final node = _nodes[vine] as FutureNode?;
    if (node == null) return Future.value();
    if (replacement != null) {
      _overrides[_overrideKeyFor(vine)] = replacement;
    }
    node.invalidate();
    return node.start().then((_) {}, onError: (_) {});
  }

  Object _overrideKeyFor(Vine vine) => switch (vine) {
        VineInstance instance => instance.family,
        FutureVineInstance instance => instance.family,
        _ => vine,
      };

  // ---- tracking / cycle helpers ----

  void _track(
    ReactiveNode node,
    DependencyTracker? tracker,
    bool trackingAllowed,
    Object vine,
  ) {
    if (tracker == null) return; // untracked context
    if (!trackingAllowed && !tracker.contains(node)) {
      throw TrackingAfterSuspendError(vine);
    }
    tracker.record(node);
  }

  Function? _findOverride(Object vine) {
    var scope = this;
    while (true) {
      final override = scope._overrides[vine];
      if (override != null) return override;
      final next = scope.parent;
      if (next == null) return null;
      scope = next;
    }
  }

  void _pushCreating(Object vine) {
    if (_creatingStack.contains(vine)) {
      final start = _creatingStack.indexOf(vine);
      throw CyclicDependencyError([..._creatingStack.sublist(start), vine]);
    }
    _creatingStack.add(vine);
  }

  void _popCreating(Object vine) => _creatingStack.removeLast();

  /// Call after removing a watcher/dependent from [node] (keyed by
  /// [key] in `_nodes`) — schedules it to be dropped once nothing has
  /// re-subscribed by the next microtask boundary, if it's `.autoDispose`
  /// and now unobserved. Re-subscribing before that check runs (a rapid
  /// unwatch + rewatch in the same turn) cancels the drop, since the
  /// check re-verifies `isObserved` right before acting on it.
  void checkAutoDispose(Object key, ReactiveNode node) {
    if (!node.autoDispose || node.isObserved) return;
    _pendingAutoDispose.add(key);
    if (!_autoDisposeFlushScheduled) {
      _autoDisposeFlushScheduled = true;
      scheduleMicrotask(_flushAutoDispose);
    }
  }

  void _flushAutoDispose() {
    _autoDisposeFlushScheduled = false;
    final keys = _pendingAutoDispose.toList();
    _pendingAutoDispose.clear();
    for (final key in keys) {
      final node = _nodes[key];
      if (node == null || node.isObserved) continue;
      node.dispose();
      _nodes.remove(key);
    }
  }

  void _checkNotDisposed() {
    if (disposed) throw GardenDisposedError();
  }

  /// Constructs (and runs, for eager ones) every declared vine —
  /// `Garden.grow()`.
  void grow(List<Vine> vines) {
    for (final vine in vines) {
      if (vine is FrozenVine && vine.isEager) resolve(vine);
      if (vine is FutureVine && vine.internalEager) resolve(vine);
    }
  }

  Future<void> dispose() async {
    if (disposed) return;
    for (final child in List.of(_children.reversed)) {
      await child.dispose();
    }
    for (final node in _nodes.values) {
      node.dispose();
    }
    for (final dispose in _disposers.reversed) {
      dispose();
    }
    _nodes.clear();
    _frozen.clear();
    _disposers.clear();
    disposed = true;
    parent?._children.remove(this);
  }
}
