import 'async_value.dart';
import 'node.dart';
import 'scope.dart';
import 'tap.dart';

/// A declarative recipe for building a value of type [T] — the identity
/// token consumers pass to `garden.tap`/`garden.watch`/`tap` wherever they
/// need [T]. A vine is declared once, as a top-level `final`, and the
/// *vine instance itself* (not its type) is the cache key a scope uses.
///
/// Never constructed directly — use the [Vine] static factories:
/// [Vine.value], [Vine.single], [Vine.transient], [Vine.eager],
/// [Vine.cell], [Vine.computed], [Vine.future], [Vine.each],
/// [Vine.eachAsync], [Vine.ref].
abstract class Vine<T> {
  Vine({this.name});

  /// An optional name shown in error messages and `toString()`.
  final String? name;

  /// A constant that never runs a body — `tap` just returns [value]
  /// as-is. Useful for wiring in an instance you already have (a test
  /// double, a value threaded in from outside the graph).
  static Vine<T> value<T>(T value, {String? name}) =>
      ValueVine<T>(value, name: name);

  /// Constructed on first tap, then cached for the rest of the scope's
  /// lifetime. `create`'s taps are plain, untracked reads — a single
  /// vine is frozen: it never re-runs once built, regardless of what it
  /// tapped. Pass [dispose] to run cleanup when the owning scope is
  /// disposed.
  static FrozenVine<T> single<T>(
    T Function(Tap tap) create, {
    void Function(T value)? dispose,
    String? name,
  }) =>
      FrozenVine<T>._(create, FrozenKind.single, dispose: dispose, name: name);

  /// Like [single], but never cached: `create` runs again on every tap,
  /// producing a fresh instance each time. Per the spec, `transient` does
  /// not support `dispose` — there's no single cached instance whose
  /// lifetime a dispose callback could meaningfully attach to.
  static FrozenVine<T> transient<T>(T Function(Tap tap) create,
          {String? name}) =>
      FrozenVine<T>._(create, FrozenKind.transient, name: name);

  /// Like [single], but constructed eagerly at `garden.grow()` instead of
  /// waiting for the first tap.
  static FrozenVine<T> eager<T>(
    T Function(Tap tap) create, {
    void Function(T value)? dispose,
    String? name,
  }) =>
      FrozenVine<T>._(create, FrozenKind.eager, dispose: dispose, name: name);

  /// A reactive source. Read with `tap`, written with `garden.set`. A
  /// write equal to the current value (`==`) is a no-op — no dependents
  /// are notified.
  static CellVine<T> cell<T>(T initial, {String? name}) =>
      CellVine<T>(initial, name: name);

  /// A synchronous, memoized derivation. `create` must be pure and
  /// synchronous: every cell/computed/future it taps (before returning)
  /// becomes a tracked dependency, and the body re-runs — lazily, the
  /// next time something pulls it — whenever one of those changes.
  /// Tapping a still-[AsyncLoading] future vine from inside `create`
  /// throws [AsyncInSyncContextError].
  static ComputedVine<T> computed<T>(T Function(Tap tap) create,
          {String? name}) =>
      ComputedVine<T>(create, name: name);

  /// A dual-mode async derivation. On first tap the body is scheduled and
  /// the vine reads as `AsyncLoading` until it settles; taps before the
  /// body's first `await` are tracked the same way [computed]'s are, so
  /// the body re-runs whenever one of them changes (if it never taps
  /// anything reactive, it behaves as a plain load-once). See the
  /// package README for the full dual-mode rule and race-safety notes.
  static FutureVine<T> future<T>(Future<T> Function(Tap tap) create,
          {String? name}) =>
      FutureVine<T>(create, name: name);

  /// A parameterized family of synchronous vines: calling the result with
  /// a key (`family(key)`) gives a `Vine<T>`-like instance, cached per
  /// `(family, key)` on the owning scope. Recursive families (e.g. a tree
  /// node keyed by id, tapping its own children by id) work the same way
  /// any other recursive resolution does.
  static EachVine<K, T> each<K, T>(T Function(Tap tap, K key) create,
          {String? name}) =>
      EachVine<K, T>(create, name: name);

  /// Like [each], but each per-key instance is a [Vine.future] instead of
  /// a synchronous one.
  static EachAsyncVine<K, T> eachAsync<K, T>(
          Future<T> Function(Tap tap, K key) create,
          {String? name}) =>
      EachAsyncVine<K, T>(create, name: name);

  /// A lazy, mutable forward-reference for breaking a genuine mutual
  /// dependency: declare the ref, tap it (at call-time, inside a closure —
  /// never during another vine's own construction) from one side, and
  /// bind the real vine to it with `..bindTo(vine)` from the other.
  /// Tapping an unbound ref throws [UntiedRefError].
  static VineRef<T> ref<T>({String? name}) => VineRef<T>(name: name);

  @override
  String toString() => name ?? '$runtimeType#$hashCode';
}

/// A constant vine — see [Vine.value].
final class ValueVine<T> extends Vine<T> {
  ValueVine(this.value, {super.name});

  final T value;
}

enum FrozenKind { single, transient, eager }

/// A [Vine.single]/[Vine.transient]/[Vine.eager] vine.
final class FrozenVine<T> extends Vine<T> {
  FrozenVine._(this.create, this.kind, {this.dispose, super.name});

  final T Function(Tap tap) create;
  final FrozenKind kind;
  final void Function(T value)? dispose;

  bool get isTransient => kind == FrozenKind.transient;
  bool get isEager => kind == FrozenKind.eager;
  bool get hasDispose => dispose != null;

  /// Invokes [dispose] with [value], cast back to `T` here — inside this
  /// generic method `T` is still concrete, unlike at a caller working
  /// with an erased/raw `FrozenVine`, where `dispose` itself can't be
  /// read and called directly (its parameter is contravariant in `T`,
  /// so it doesn't survive erasure to `FrozenVine<dynamic>` the way a
  /// plain covariant field does).
  void invokeDispose(Object? value) => dispose?.call(value as T);

  /// Replaces this vine's body within a `Garden`/scope — see
  /// `Garden(overrides:)`/`Garden.growScope(overrides:)`.
  VineOverride override(T Function(Tap tap) create) =>
      VineOverride._(this, create);
}

/// A [Vine.cell] — see there for semantics.
final class CellVine<T> extends Vine<T> {
  CellVine(this.initial, {super.name});

  final T initial;

  /// Overrides this cell's initial value within a `Garden`/scope. The
  /// replacement is itself a `(tap) => T` body (run once, like any other
  /// frozen creation) so an override can still depend on other vines.
  VineOverride override(T Function(Tap tap) create) =>
      VineOverride._(this, create);
}

/// A [Vine.computed] — see there for semantics.
final class ComputedVine<T> extends Vine<T> {
  ComputedVine(this.create, {super.name});

  final T Function(Tap tap) create;
  bool internalAutoDispose = false;

  /// When watcher count reaches 0, this vine's cached value is dropped
  /// (after a grace period ending at the next `pump()`/microtask
  /// boundary) rather than kept forever. Re-tapping after a drop re-runs
  /// `create` from scratch. Apply this immediately when declaring the
  /// vine — it mutates and returns the same instance, so it must be the
  /// very last thing chained before the result is assigned to its `final`.
  ComputedVine<T> get autoDispose {
    internalAutoDispose = true;
    return this;
  }

  VineOverride override(T Function(Tap tap) create) =>
      VineOverride._(this, create);
}

/// A [Vine.future] — see there for semantics. Extends `Vine<AsyncValue<T>>`
/// (not `Vine<T>`): `tap`/`garden.tap`/`context.watch` on a future vine
/// give you the `AsyncValue<T>` snapshot; `garden.tapAsync`/`tap.async`
/// give you the awaited, unwrapped `T` (rethrowing on failure).
final class FutureVine<T> extends Vine<AsyncValue<T>> {
  FutureVine(this.create, {super.name});

  final Future<T> Function(Tap tap) create;
  bool internalAutoDispose = false;
  bool internalEager = false;

  /// See [ComputedVine.autoDispose] — same semantics, applied to the
  /// cached `AsyncValue` instead of a plain value.
  FutureVine<T> get autoDispose {
    internalAutoDispose = true;
    return this;
  }

  /// Starts running at `garden.grow()` instead of waiting for the first
  /// tap.
  FutureVine<T> get eager {
    internalEager = true;
    return this;
  }

  VineOverride override(Future<T> Function(Tap tap) create) =>
      VineOverride._(this, create);

  /// Gets-or-creates this vine's [FutureNode] with `T` correctly reified
  /// — called from [Scope] through a plain (erased) `Vine` reference, so
  /// this has to happen here, inside `FutureVine<T>`'s own generic scope,
  /// rather than in [Scope] itself: `AsyncValue<T>` is a real generic
  /// wrapper (unlike a plain value), and a `FutureNode`/`AsyncValue`
  /// built with the wrong reified type argument can never be cast back
  /// to the right one, no matter what `Scope` does with `dynamic`/`as T`
  /// at its own erased call sites.
  FutureNode<T> ensureNode(Scope scope) => scope.ensureFutureNode<T>(
        key: this,
        overrideKey: this,
        body: (tap) => create(tap),
        autoDispose: internalAutoDispose,
        eager: internalEager,
      );
}

/// A [Vine.each] family — see there. Calling it with a key returns the
/// per-key [VineInstance] to tap.
final class EachVine<K, T> {
  EachVine(this.create, {this.name});

  final T Function(Tap tap, K key) create;
  final String? name;
  bool internalAutoDispose = false;

  /// See [ComputedVine.autoDispose] — applies per-key: each key's
  /// instance is independently dropped once *its own* watcher count
  /// reaches 0.
  EachVine<K, T> get autoDispose {
    internalAutoDispose = true;
    return this;
  }

  VineInstance<K, T> call(K key) => VineInstance<K, T>._(this, key);

  /// Replaces every key's body within a `Garden`/scope — matched by the
  /// family, not any one key's `VineInstance`. Named `overrideCreate`,
  /// not `override`, only because a member literally named `override`
  /// in a class that also uses the `@override` annotation elsewhere (as
  /// this one does, on `toString`) confuses Dart's annotation
  /// resolution — every other vine kind's override method keeps the
  /// plain `override` name.
  VineOverride overrideCreate(T Function(Tap tap, K key) create) =>
      VineOverride._(this, create);

  @override
  String toString() => name ?? 'EachVine<$K, $T>#$hashCode';
}

/// One `family(key)` slot of a [Vine.each] family — a [Vine] like any
/// other, cached per `(family, key)`.
final class VineInstance<K, T> extends Vine<T> {
  VineInstance._(this.family, this.key) : super(name: family.name);

  final EachVine<K, T> family;
  final K key;

  @override
  bool operator ==(Object other) =>
      other is VineInstance<K, T> && other.family == family && other.key == key;

  @override
  int get hashCode => Object.hash(family, key);

  @override
  String toString() => '${family.name ?? 'EachVine<$K, $T>'}($key)';

  /// Builds the `(tap) => T` body for this specific key, from inside
  /// `VineInstance<K, T>`'s own generic scope — [family]'s `create` takes
  /// a `K key` parameter (contravariant), so calling it through an
  /// erased `VineInstance`/`EachVine` reference (as [Scope] otherwise
  /// would) fails at runtime the same way a `dispose` callback would;
  /// see [FrozenVine.invokeDispose]'s doc comment for the general shape
  /// of the problem.
  T Function(Tap tap) createBody() => (tap) => family.create(tap, key);

  /// Invokes a family-level override (from [EachVine.override], shaped
  /// `T Function(Tap, K)`) for this key — same reasoning as [createBody],
  /// needed because [Scope] only has the override as an untyped
  /// [Function].
  T invokeOverride(Function override, Tap tap) =>
      (override as T Function(Tap tap, K key))(tap, key);
}

/// A [Vine.eachAsync] family — see there.
final class EachAsyncVine<K, T> {
  EachAsyncVine(this.create, {this.name});

  final Future<T> Function(Tap tap, K key) create;
  final String? name;
  bool internalAutoDispose = false;

  /// See [ComputedVine.autoDispose].
  EachAsyncVine<K, T> get autoDispose {
    internalAutoDispose = true;
    return this;
  }

  FutureVineInstance<K, T> call(K key) => FutureVineInstance<K, T>._(this, key);

  /// Replaces every key's body within a `Garden`/scope — matched by the
  /// family, not any one key's `FutureVineInstance`. See
  /// [EachVine.overrideCreate]'s doc comment for why this isn't named
  /// plain `override`.
  VineOverride overrideCreate(Future<T> Function(Tap tap, K key) create) =>
      VineOverride._(this, create);

  @override
  String toString() => name ?? 'EachAsyncVine<$K, $T>#$hashCode';
}

/// One `family(key)` slot of a [Vine.eachAsync] family.
final class FutureVineInstance<K, T> extends Vine<AsyncValue<T>> {
  FutureVineInstance._(this.family, this.key) : super(name: family.name);

  final EachAsyncVine<K, T> family;
  final K key;

  @override
  bool operator ==(Object other) =>
      other is FutureVineInstance<K, T> &&
      other.family == family &&
      other.key == key;

  @override
  int get hashCode => Object.hash(family, key);

  @override
  String toString() => '${family.name ?? 'EachAsyncVine<$K, $T>'}($key)';

  /// See [VineInstance.createBody] — same reasoning.
  Future<T> Function(Tap tap) createBody() => (tap) => family.create(tap, key);

  /// See [VineInstance.invokeOverride] — same reasoning.
  Future<T> invokeOverride(Function override, Tap tap) =>
      (override as Future<T> Function(Tap tap, K key))(tap, key);

  /// See [FutureVine.ensureNode] — same reasoning (`AsyncValue<T>`
  /// reification), plus [createBody]/[invokeOverride] for the family's
  /// own key contravariance.
  FutureNode<T> ensureNode(Scope scope) => scope.ensureFutureNode<T>(
        key: this,
        overrideKey: family,
        body: createBody(),
        invokeOverride: invokeOverride,
        autoDispose: family.internalAutoDispose,
        eager: false,
      );
}

/// A lazy, mutable forward-reference — see [Vine.ref].
final class VineRef<T> extends Vine<T> {
  VineRef({super.name});

  Vine<T>? bound;

  /// Registers [vine] as what this ref resolves to. Call this once,
  /// typically right after declaring the vine that implements the ref —
  /// never inside another vine's own `create` (the point of a ref is to
  /// be read lazily, later, not resolved at construction time).
  void bindTo(Vine<T> vine) => bound = vine;
}

/// Replaces a vine's body within one `Garden`/scope — built via a
/// concrete vine's own `.override(...)`, never constructed directly. The
/// replacement function's shape depends on which vine it targets, so it's
/// carried untyped here and invoked with a matching cast by the scope
/// that applies it (mirroring how each vine's own `create` is stored).
final class VineOverride {
  const VineOverride._(this.vine, this.create);

  /// The vine (or, for an [EachVine]/[EachAsyncVine] family-level
  /// override, the family itself) being overridden — matched by
  /// identity.
  final Object vine;

  /// The replacement body.
  final Function create;
}
