import 'async_value.dart';
import 'node.dart';
import 'scope.dart';
import 'tap.dart';
import 'vine.dart';

/// The root of a vine graph — one per app (or one per test). Construct
/// it with the vines you want eagerly built, [Garden.grow] it, then read
/// through [tap]/[tapAsync], write through [set], and react through
/// [watch]/[effect].
///
/// ```dart
/// final garden = Garden(vines: [repositoryVine]).grow();
/// final repository = garden.tap(repositoryVine);
/// ```
final class Garden {
  /// Creates a garden. [vines] is the set to eagerly construct/start at
  /// [grow] — anything not listed there (or not `.eager`) is still fully
  /// usable, just built lazily on first tap instead. [overrides] replace
  /// some vines' bodies for this garden only.
  Garden({
    List<Vine> vines = const [],
    List<VineOverride> overrides = const [],
    this.onError,
  })  : _scope = Scope(overrides: overrides, onError: onError),
        _vines = vines;

  Garden._child(this._scope, this._vines, this.onError);

  final Scope _scope;
  final List<Vine> _vines;

  /// Observability hook: called whenever a `Vine.future`/effect run
  /// fails, including ones nobody is directly awaiting (a scheduler-
  /// triggered re-run, an eager start). Without this, such a failure is
  /// still captured in the vine's own `AsyncValue`/reported to the
  /// effect's own try/catch — this is purely for logging/telemetry.
  final void Function(Object vine, Object error, StackTrace stackTrace)?
      onError;

  /// Constructs every eager vine and starts every eager future. Returns
  /// this garden, so it chains with the constructor.
  Garden grow() {
    _scope.grow(_vines);
    return this;
  }

  /// Reads [v] without subscribing to future changes: the plain value
  /// for most vines, or the current `AsyncValue<T>` snapshot for a
  /// future vine. Never blocks.
  T tap<T>(Vine<T> v) => _scope.resolve(v) as T;

  /// Awaits [v]'s raw, unwrapped data — only valid on a future-shaped
  /// vine (`Vine.future`/`Vine.eachAsync`). Rethrows on failure;
  /// concurrent calls dedupe onto the same in-flight run.
  Future<T> tapAsync<T>(Vine<AsyncValue<T>> v) async {
    final data = await _scope.resolveAsync(v);
    return data as T;
  }

  /// Writes [cell]. A value equal (`==`) to the current one is a no-op —
  /// no dependents are notified.
  void set<T>(CellVine<T> cell, T value) => _scope.setCell(cell, value);

  /// Forces [v] (a future vine) to re-run, discarding any in-flight run
  /// — cascades to everything downstream through async edges. [body], if
  /// given, replaces [v]'s own body for this and every future run
  /// (matching the spec's `garden.refresh(v, altBody)`), not just a
  /// one-off retry of the same recipe.
  Future<void> refresh<T>(FutureVine<T> v,
          [Future<T> Function(Tap tap)? body]) =>
      _scope.refreshFuture(v, body);

  /// Subscribes [onChange] to [v]: fires with the plain value for a
  /// sync reactive vine (cell/computed/each), or with the `AsyncValue<T>`
  /// on *every* transition (loading → data → error → ...) for a future
  /// vine. Only cell/computed/future/each vines can be watched — a
  /// frozen vine never changes after its first tap. Returns a disposer.
  void Function() watch<T>(Vine<T> v, void Function(T value) onChange) {
    final node = _scope.ensureReactiveNode(v);
    final unsubscribe = node.addWatcher(() => onChange(_scope.resolve(v) as T));
    return () {
      unsubscribe();
      _scope.checkAutoDispose(v, node);
    };
  }

  /// Runs [body] now, then again whenever a cell/computed/future it
  /// tapped before its first `await`/`tap.async` changes — auto-tracked,
  /// and dynamically re-tracked on every run (a branch stops being read,
  /// it drops out of the dependency set). Runs are serialized: no
  /// overlapping runs, and a change arriving mid-run coalesces into
  /// exactly one rerun rather than starting a second one concurrently.
  /// Returns a disposer that cancels any in-flight run and stops future
  /// ones.
  void Function() effect(Future<void> Function(Tap tap) body) {
    late final EffectNode node;
    node = EffectNode((tracker) async {
      final tap = TapImpl(_scope, tracker: tracker);
      try {
        await body(tap);
      } catch (error, stackTrace) {
        onError?.call(node, error, stackTrace);
      }
    });
    node.onDirty = _scope.scheduler.schedule;
    node.runIfNeeded();
    return node.dispose;
  }

  /// Flushes all pending synchronous reactive work (batched `set`s,
  /// scheduled recomputes/reruns), then repeatedly yields to the event
  /// loop — bounded — so already-in-flight microtask-scheduled async
  /// work gets a chance to land and enqueue more too. The determinism
  /// primitive tests build on instead of manually `await`ing individual
  /// futures/effects. Does not fast-forward a real `Future.delayed`
  /// timer — await that directly, or use `package:fake_async`.
  Future<void> pump() => _scope.scheduler.pump();

  /// A child scope: a vine declared/overridden here shadows the same
  /// vine in an ancestor scope for anything tapped through this garden,
  /// and a non-overridden vine tapped here for the first time gets its
  /// own instance — independent of any ancestor's (see the "scoped
  /// singleton" note on [Scope]). Disposes before its parent.
  Garden growScope(
      {List<Vine> vines = const [], List<VineOverride> overrides = const []}) {
    final child = Garden._child(
      Scope(parent: _scope, overrides: overrides),
      vines,
      onError,
    );
    return child.grow();
  }

  /// Tears this garden down (and every child `growScope()` grew from it,
  /// most recently created first): stops effects, orphans in-flight
  /// async runs, and runs every `dispose` callback in LIFO order. Using
  /// the garden afterward throws `GardenDisposedError`. Idempotent.
  Future<void> dispose() => _scope.dispose();
}
