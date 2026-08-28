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
  final repository = container.read(repositoryProvider);
}
```

## Why another DI library

If you've used Riverpod or Refena, this should feel familiar on purpose:
declare a dependency once as a top-level `final`, read it from a
container, override it in tests. `tenet_di` is a deliberately small
subset of that idea — no code generation, no `.family`/`.autoDispose`
modifiers, no `AsyncValue` — just:

- **`Provider<T>`** — a cached, lazily-created dependency.
- **`StateProvider<T>`** — a mutable, watchable one.
- **`ProviderContainer`** — owns instances, resolves the dependency
  graph, and notifies watchers when something changes.
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

### Declaring and reading providers

```dart
final clockProvider = Provider<Clock>((ref) => Clock());

final greeterProvider = Provider<Greeter>(
  (ref) => Greeter(ref.watch(clockProvider)), // depends on another provider
);

final container = ProviderContainer();
final greeter = container.read(greeterProvider);
```

A provider's `create` function only runs on the first read; every read
after that returns the same cached instance until it's invalidated.
`ref.watch(other)` (rather than `ref.read(other)`) both reads `other`
*and* subscribes: if `other`'s value later changes, this provider is
invalidated and rebuilt too, recursively.

### Mutable state

```dart
final counterProvider = StateProvider<int>((ref) => 0);

container.read(counterProvider).state;              // 0
container.read(counterProvider).state = 5;           // notifies watchers
container.read(counterProvider).update((n) => n + 1); // 6
```

Reading a `StateProvider` gives you its `StateController<T>`, not the
bare value — read `.state` off it. Anything that `ref.watch`ed the
provider (another provider, or a Flutter widget through
`tenet_di_flutter`) is invalidated/rebuilt whenever `.state` changes.

### Subscribing directly

```dart
final unsubscribe = container.listen(counterProvider, () {
  print('now: ${container.read(counterProvider).state}');
});
// later:
unsubscribe();
```

This is the low-level primitive `tenet_di_flutter`'s `ConsumerWidget`/
`Consumer` build on. Most application code should prefer those over
calling `listen` directly.

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

container.invalidate(provider); // tears this one down; next read recreates it
container.dispose();            // tears everything down; container is unusable after
```

## What's intentionally not here

- **No `.family`/parameterized providers.** Model the parameter as part
  of the state a `StateProvider` holds, or as a constructor argument to a
  `Map`-backed service your own `Provider` builds.
- **No `AsyncValue`/`FutureProvider`.** A `Provider<Future<T>>` already
  works for the common case — read it and `await` the result. A richer
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
