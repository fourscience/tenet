import 'async_value.dart';
import 'node.dart';
import 'scope.dart';
import 'vine.dart';

/// What every vine body (and `garden.effect`) gets to read other vines
/// with. Two entry points cover the whole spec:
///
/// - `tap(v)` — a snapshot: the plain value for a sync vine, or the
///   current `AsyncValue<T>` for a future vine. Never suspends.
/// - `await tap.async(v)` — awaits a future vine's *raw*, unwrapped data,
///   rethrowing on failure. (The spec writes this as `await tap(v)`; Dart
///   can't give one identically-typed method two different return shapes
///   for the same call, so this package spells it `tap.async(v)` instead
///   — see the README's "deviations from the spec" section.)
///
/// Inside a `Vine.single`/`transient`/`each` body, every tap is a plain,
/// untracked read. Inside `Vine.computed`, every tap before the (sync)
/// body returns is tracked, and tapping a still-pending future vine
/// throws [AsyncInSyncContextError]. Inside `Vine.future`/`effect`,
/// every tap before the first `await`/`tap.async` is tracked; a *new*
/// tracked dependency reached after that throws
/// [TrackingAfterSuspendError] — reading something already tracked, or a
/// non-reactive (frozen) vine, is always fine.
abstract interface class Tap {
  /// Reads [v]: the plain value for most vines, or the current
  /// `AsyncValue<T>` snapshot for a `Vine.future`/`Vine.eachAsync`
  /// instance.
  T call<T>(Vine<T> v);

  /// Awaits [v]'s raw, unwrapped data — only valid on a future-shaped
  /// vine (one whose `tap()` type is `AsyncValue<T>`). Rethrows on
  /// failure; concurrent callers dedupe onto the same in-flight run.
  Future<T> async<T>(Vine<AsyncValue<T>> v);

  /// Reads [v] from the root scope, skipping any scope shadowing between
  /// here and the root.
  T unscoped<T>(Vine<T> v);
}

final class TapImpl implements Tap {
  TapImpl(this.scope, {this.tracker, this.isComputedContext = false});

  final Scope scope;

  /// Non-null while running a tracked body (`Vine.computed`,
  /// `Vine.future`, or `garden.effect`); null for a plain untracked read
  /// (`Vine.single`/`transient`/`each` bodies, `garden.tap`,
  /// `tap.unscoped`).
  final DependencyTracker? tracker;
  final bool isComputedContext;
  bool _suspended = false;

  bool get _trackingAllowed => tracker == null || !_suspended;

  @override
  T call<T>(Vine<T> v) {
    final result = scope.resolve(
      v,
      tracker: tracker,
      trackingAllowed: _trackingAllowed,
      isComputedContext: isComputedContext,
    );
    return result as T;
  }

  @override
  Future<T> async<T>(Vine<AsyncValue<T>> v) async {
    final future = scope.resolveAsync(
      v,
      tracker: tracker,
      trackingAllowed: _trackingAllowed,
    );
    if (tracker != null) _suspended = true;
    final data = await future;
    return data as T;
  }

  @override
  T unscoped<T>(Vine<T> v) {
    final result = scope.root.resolve(
      v,
      tracker: tracker,
      trackingAllowed: _trackingAllowed,
      isComputedContext: isComputedContext,
    );
    return result as T;
  }
}
