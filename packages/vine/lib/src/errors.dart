/// Thrown when resolving a vine would require resolving itself again —
/// either directly (`a` taps `a` in its own body) or transitively (`a`
/// taps `b` taps `a`). [path] is the resolution stack at the moment the
/// cycle was detected, root first, so `path.join(' -> ')` reads as the
/// walk that led back to the start.
///
/// A genuine mutual dependency isn't a bug — see `Vine.ref` to break the
/// cycle deliberately instead of restructuring around this error.
final class CyclicDependencyError extends Error {
  CyclicDependencyError(this.path);

  /// The cycle, root first: `path.first == path.last`.
  final List<Object?> path;

  @override
  String toString() => 'CyclicDependencyError: ${path.join(' -> ')}\n'
      'A vine ended up depending on itself while resolving. If this is a '
      'genuine mutual dependency (not a mistake), break it with '
      'Vine.ref<T>(): declare the ref, tap it lazily at call-time inside '
      'one side, and bind the real vine to it with ..bindTo(vine).';
}

/// Thrown by `tap(ref)` when [ref] was never bound with `ref.bindTo(vine)`
/// before something tried to read through it.
final class UntiedRefError extends Error {
  UntiedRefError(this.ref);

  /// The unbound ref, for identification in the message/debugger.
  final Object ref;

  @override
  String toString() => 'UntiedRefError: $ref was tapped before it was bound.\n'
      'Call `ref.bindTo(vine)` (typically right after declaring the vine '
      'that implements the ref) before anything taps the ref.';
}

/// Thrown when a [Vine.computed] body taps a [Vine.future] that is still
/// pending (`AsyncLoading`). `computed` bodies must be synchronous and
/// pure, so there is no way for them to "wait" for the future to settle —
/// depend on `tap.async` inside a `Vine.future`/effect body instead, or
/// restructure so the computed only reads already-settled data.
final class AsyncInSyncContextError extends Error {
  AsyncInSyncContextError(this.vine);

  /// The pending future vine that was tapped.
  final Object vine;

  @override
  String toString() =>
      'AsyncInSyncContextError: a Vine.computed body tapped $vine while it '
      'was still pending (AsyncLoading).\n'
      'computed bodies must be synchronous and pure — they cannot wait for '
      'a future vine to settle. Read it from a Vine.future or effect body '
      'instead (where `tap.async` can await it), or check '
      '`tap(vine).hasValue` first and branch.';
}

/// Thrown when a [Vine.future] or effect body taps (for tracking purposes)
/// a vine *after* its first `await` has already suspended it. Only taps
/// before the first suspension are tracked as dependencies — see the
/// dual-mode rule in the package README for why.
final class TrackingAfterSuspendError extends Error {
  TrackingAfterSuspendError(this.vine);

  /// The vine that was tapped too late to be tracked.
  final Object vine;

  @override
  String toString() =>
      'TrackingAfterSuspendError: tapped $vine for tracking after this '
      'body had already suspended on an earlier await.\n'
      'Only taps before the first await establish a dependency edge (so '
      'the vine knows what to re-run on). Move this tap above the first '
      'await, or use `tap.async(vine)` here if you only need the value '
      '(not to track it).';
}

/// Thrown by any [Garden] operation once [Garden.dispose] has completed.
final class GardenDisposedError extends Error {
  GardenDisposedError();

  @override
  String toString() =>
      'GardenDisposedError: this Garden has already been disposed and can '
      'no longer be used.';
}
