# tenet_di

A minimal, Riverpod/Refena-flavored dependency injection library for
Dart — declarative providers, a lazy caching container, an
invalidation/notification graph, and testing overrides. Works with or
without Flutter; see [`tenet_di_flutter`](../tenet_di_flutter) for the
widget bindings.

```dart
final repositoryProvider = Provider<Repository>((ref) => Repository());

void main() {
  final container = ProviderContainer();
  final repository = container.resolve(repositoryProvider);
}
```

## Why another DI library

If you've used Riverpod or Refena, this should feel familiar on purpose:
declare a dependency once as a top-level `final`, resolve it from a
container, override it in tests. `tenet_di` is a deliberately small
subset of that idea — no code generation, no `.family`/`.autoDispose`
modifiers, no `AsyncValue` — just:

- **`Provider<T>`** — a cached, lazily-created dependency.
- **`StateProvider<T>`** — a mutable, observable one.
- **`ProviderContainer`** — owns instances, resolves the dependency
  graph, and notifies observers when something changes.
- **Overrides** — swap any provider's recipe, typically in tests.

That's the whole surface. It's enough to wire up services, repositories,
and `tenet` `Store`s without a global service locator or manual
constructor threading — and small enough to read start to finish in one
sitting.

## Installation

```yaml
dependencies:
  tenet_di: ^0.1.0
```

## Usage

### Declaring and resolving providers

```dart
final clockProvider = Provider<Clock>((ref) => Clock());

final greeterProvider = Provider<Greeter>(
  (ref) => Greeter(ref.observe(clockProvider)), // depends on another provider
);

final container = ProviderContainer();
final greeter = container.resolve(greeterProvider);
```

A provider's `create` function only runs on the first resolve; every
resolve after that returns the same cached instance until it's
invalidated. `ref.observe(other)` (rather than `ref.resolve(other)`)
both resolves `other`
*and* subscribes: if `other`'s value later changes, this provider is
invalidated and rebuilt too, recursively.

### Mutable state

```dart
final counterProvider = StateProvider<int>((ref) => 0);

container.resolve(counterProvider).state;              // 0
container.resolve(counterProvider).state = 5;           // notifies observers
container.resolve(counterProvider).update((n) => n + 1); // 6
```

Reading a `StateProvider` gives you its `StateController<T>`, not the
bare value — read `.state` off it. Anything that `ref.observe`d the
provider (another provider, or a Flutter widget through
`tenet_di_flutter`) is invalidated/rebuilt whenever `.state` changes.

### Subscribing directly

```dart
final unsubscribe = container.observe(counterProvider, () {
  print('now: ${container.resolve(counterProvider).state}');
});
// later:
unsubscribe();
```

This is the low-level primitive `tenet_di_flutter`'s `ConsumerWidget`/
`Consumer` build on. Most application code should prefer those over
calling `observe` directly.

### Testing with overrides

```dart
final container = ProviderContainer(
  overrides: [
    repositoryProvider.overrideWithValue(FakeRepository()),
    clockProvider.overrideWith((ref) => FixedClock(DateTime(2024))),
  ],
);
```

`overrideWithValue` skips `create` entirely; `overrideWith` replaces the
recipe but can still use `Ref` (e.g. to depend on another, un-overridden
provider).

### Disposal

```dart
final provider = Provider<Socket>((ref) {
  final socket = Socket.connect();
  ref.onDispose(socket.close);
  return socket;
});

container.invalidate(provider); // tears this one down; next resolve recreates it
container.dispose();            // tears everything down; container is unusable after
```

### No container of your own at hand?

A `main()`, a background service, a plain top-level function — anywhere
with no natural container (and, in Flutter, no `BuildContext`) to thread
through — can `resolve`/`observe` directly, without constructing or
importing a `ProviderContainer` type at all:

```dart
final greetingProvider = Provider<String>((ref) => 'hello');

void main() {
  print(resolve(greetingProvider)); // no container in sight
}
```

`resolve`/`observe` read through `rootContainer`, a single
[`ProviderContainer`](#usage) shared by the whole process and created
lazily the first time anything touches it — so code reached this way and
code reached through an explicit container/`ProviderScope` (if you pass
that same `rootContainer` to one — see `tenet_di_flutter`'s README) see
the same live state.

Prefer an explicitly-created container wherever one already exists —
inside a `Ref`, inside a `WidgetRef`, or in tests, where a fresh
container per test is what keeps overrides and state from one test
leaking into another. `rootContainer` is the exception for code with
nowhere else to get one from, not a default to reach for out of habit.
`resetRootContainer()` disposes it and clears it — mainly useful for
resetting state between tests that do touch it.

## What's intentionally not here

- **No `.family`/parameterized providers.** Model the parameter as part
  of the state a `StateProvider` holds, or as a constructor argument to a
  `Map`-backed service your own `Provider` builds.
- **No `AsyncValue`/`FutureProvider`.** A `Provider<Future<T>>` already
  works for the common case — resolve it and `await` the result. A richer
  loading/error/data wrapper is a natural extension, left out here to
  keep the core minimal.
- **No code generation.** Every provider above is exactly the Dart you'd
  write by hand.

## Development

```
dart pub get
dart analyze
dart test
dart run example/tenet_di_example.dart
```

This package has zero runtime dependencies (and no Flutter dependency at
all — see `tenet_di_flutter` for that).
