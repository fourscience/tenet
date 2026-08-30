# vine

A dependency injection + reactive state container for Dart.

vine is dependency injection that fits in your head. Declare how things
are made with `Vine` — seven short factories. Read them with `tap`. When
something changes, change a cell: everything computed or future over it
updates, with fine-grained precision, stale-while-revalidate async, and
zero codegen. It works in pure Dart, tests deterministically with one
`pump()` call, and in Flutter you're one `Trellis` away from
`context.watch(anything)` — see
[`vine_flutter`](../vine_flutter).

```dart
final counter = Vine.cell(0);
final doubled = Vine.computed((tap) => tap(counter) * 2);

final garden = Garden().grow();
garden.watch(doubled, (value) => print('doubled: $value'));
garden.set(counter, 5); // prints "doubled: 10" once flushed
await garden.pump();
```

## Declarations

| Declaration | Shape | Semantics |
|---|---|---|
| `Vine.value(v)` | — | Constant; wraps an existing instance. |
| `Vine.single((tap) => T, {dispose})` | sync | Built on first tap, cached for the scope's lifetime. |
| `Vine.transient((tap) => T)` | sync | A fresh instance on every tap; not cached, no `dispose`. |
| `Vine.eager((tap) => T, {dispose})` | sync | Like `single`, but built at `garden.grow()`. |
| `Vine.cell(initial)` | writable | A reactive source: `tap` to read, `garden.set` to write. |
| `Vine.computed((tap) => T)` | sync, derived | Memoized; recomputes lazily when a tapped cell/computed/future changes. |
| `Vine.future((tap) async => T)` | async, dual-mode | Reads as `AsyncValue<T>`; re-runs when a vine tapped before its first `await` changes. |
| `Vine.each((tap, K key) => T)` | family | `family(key)` gives a per-key vine, cached per `(family, key)`. |
| `Vine.eachAsync((tap, K key) async => T)` | family, async | Like `each`, but each key is a `Vine.future`. |
| `Vine.ref<T>()` | — | A lazy forward-reference for breaking a genuine mutual dependency; `..bindTo(vine)`. |

Modifiers, applied immediately at declaration (they mutate and return the
same instance, so chain them right where you assign the `final`):

- `.autoDispose` — on `computed`/`future`/`each`/`eachAsync`: drop the
  cached state once nothing is watching it (after a one-`pump()` grace
  period, so a rapid unwatch-then-rewatch survives).
- `.eager` — on `future` only: start running at `garden.grow()` instead
  of waiting for the first tap.

## Reading and writing

```dart
final garden = Garden(
  vines: [...],       // eagerly built/started at grow()
  overrides: [...],   // vine.override((tap) => ...) — replace a body for this garden
  onError: (vine, error, stackTrace) {},
).grow();

garden.tap(v);              // sync vine -> T; future vine -> AsyncValue<T>. Never blocks.
await garden.tapAsync(v);   // future vine only -> raw T, awaited. Rethrows on failure.

garden.set(cell, value);            // write a cell (equal-value write is a no-op)
garden.refresh(futureVine);         // force a future to re-run
garden.watch(v, (value) { });       // -> disposer. Sync vine: T. Future vine: AsyncValue<T> on every transition.
garden.effect((tap) async { });     // -> disposer. Auto-tracked, reruns on change, serialized.
await garden.pump();                // flush pending reactive work — the determinism primitive for tests.

final child = garden.growScope(vines: [...], overrides: [...]); // scoped overrides + isolation
await garden.dispose();             // LIFO disposal, child scopes before parent.
```

Inside a vine body (or `garden.effect`'s body), read with the `Tap`
you're handed:

```dart
tap(v)             // plain value, or AsyncValue<T> snapshot for a future vine
await tap.async(v) // await a future vine's raw T (see "differences" below)
tap.unscoped(v)    // read from the root scope, skipping scope shadowing
```

Tracking rules: a `single`/`transient`/`each` body's taps are always
plain, untracked reads (frozen — the body never re-runs). A `computed`
body's taps are tracked, and tapping a still-pending future throws
`AsyncInSyncContextError` (computed must be synchronous and pure). A
`future`/`effect` body's taps are tracked up to its first suspension —
tapping something new (not already tracked) after that throws
`TrackingAfterSuspendError`.

## AsyncValue

```dart
sealed class AsyncValue<T> {
  T? get value;       // data, or the previous data while loading/erroring
  bool get isLoading;
  bool get hasValue;
  bool get isRefreshing; // isLoading && hasValue
  Object? get error;
  StackTrace? get stackTrace;
  R when<R>({required R Function(T) data, required R Function(AsyncError<T>) error, required R Function() loading});
}
```

`AsyncData<T>` / `AsyncLoading<T>` / `AsyncError<T>` — `previous` is
always preserved across a transition, so a UI reading `.value` never
loses content just because a refresh started (stale-while-revalidate).
`AsyncValue.guard(() async => ...)` wraps a call as `AsyncData`/`AsyncError`.

## Scopes, cycles, disposal

`growScope` creates a child: an override declared there shadows the same
vine in an ancestor (nearest scope wins), and a vine *without* an
override that's tapped there for the first time gets its **own**
instance — independent of the parent's or any sibling's ("scoped
singleton" isolation; a vine already resolved through a shared ancestor
is unaffected). Scopes dispose before their parent, most-recently-created
child first.

A genuine cycle (`a` taps `b` taps `a`) throws `CyclicDependencyError`
with the path (`a -> b -> a`). A deliberate mutual dependency uses
`Vine.ref` instead:

```dart
final bRef = Vine.ref<B>();
final a = Vine.single((tap) => A(() => tap(bRef))); // taps bRef lazily, at call time
final b = Vine.single((tap) => B(tap(a)))..bindTo(bRef);
```

## Differences from the v5 spec

This package implements the spec closely, with a few deliberate, narrow
adaptations — mostly forced by what Dart's generic type system can and
can't express, not shortcuts taken for convenience:

- **`tap.async(v)` instead of a bare `await tap(v)`.** The spec writes
  `tap(v)`/`await tap(v)` as the same call, letting `await` pick between
  an `AsyncValue<T>` snapshot and the raw awaited `T`. Dart has no way for
  one identically-typed generic method to return two different shapes
  depending on whether the caller happens to `await` it — the return type
  is fixed at the call site regardless. Splitting it into `tap(v)` (always
  the snapshot) and `tap.async(v)` (always awaits the raw data,
  specifically typed to accept only a future-shaped vine) keeps both
  operations fully sound rather than relying on an unchecked cast that
  would eventually crash. `Garden.tapAsync`/`tap.async` are otherwise
  exactly the spec's `tapAsync`, including the dedupe/rethrow behavior.
- **No forced cancellation-into-await for a superseded run.** The spec
  describes an in-flight run being cancelled via an `OperationCancelled`
  thrown into its own awaits when superseded. This package instead uses a
  monotonic generation counter: a superseded run's result is discarded
  (never written back to `state`, never notifies watchers) exactly as the
  spec requires, but the run itself is not forcibly unwound — it keeps
  executing to completion in the background before its result is thrown
  away. Every spec-listed test around race safety and stale-result
  discarding is satisfied by this; the difference is only observable if a
  superseded run has side effects of its own after the point that
  superseded it, which is already a code smell independent of this
  library.
- **`.autoDispose`'s drop trigger is `Garden.watch`'s own disposer** (and,
  transitively, another reactive node's dependency edge going away).
  Disposing a `garden.effect()` that was the *last* thing keeping a
  dependency alive doesn't currently re-check that dependency on its own
  — it'll still get swept the next time anything else touches its watcher
  count. Flutter's `context.watch` (in `vine_flutter`) goes through the
  same `Garden.watch` path, so this covers the common case; a narrower
  gap than the spec's fully general "watcher count" accounting.
- **Family-level overrides use `.overrideCreate`, not `.override`,
  specifically on `EachVine`/`EachAsyncVine`.** Every other vine kind
  keeps the plain `.override(...)` name. Dart's `@override` annotation
  resolution gets confused by an instance member also literally named
  `override` in a class that uses `@override` elsewhere (as these two
  classes do, on `toString`) — a real, narrow language quirk, not a
  naming preference.

## Package layout

```
lib/
  vine.dart          # public export
  src/
    vine.dart        # Vine declarations, VineOverride, VineRef
    async_value.dart  # sealed AsyncValue
    garden.dart      # Garden: public API
    scope.dart       # resolution/caching/family cache/disposal/cycle detection
    tap.dart         # Tap
    node.dart        # reactive nodes + DependencyTracker
    scheduler.dart   # microtask batching, pump()
    errors.dart      # named errors
```

## Explicitly out of scope

Cross-isolate gardens (one garden per isolate), late runtime re-binding
(construct a new `Garden`/`growScope` instead of replacing a body after
the fact — use `overrides` at construction), state persistence, a devtools
extension, and codegen are all left for a future package, per the spec.
`transient` + `dispose` is a compile-time-unavailable combination by
design (there is no cached instance for a dispose callback to attach to).
