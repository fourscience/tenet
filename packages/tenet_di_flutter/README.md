# tenet_di_flutter

Flutter bindings for [`tenet_di`](../tenet_di): `ProviderScope` owns the
container for a widget subtree, and `ConsumerWidget`/`Consumer` rebuild
automatically when the providers they observe change — a minimal,
Riverpod/Refena-flavored developer experience, with no code generation.

```dart
void main() => runApp(const ProviderScope(child: MyApp()));

final counterProvider = StateProvider<int>((ref) => 0);

class CounterText extends ConsumerWidget {
  const CounterText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.observe(counterProvider).state;
    return Text('Count: $count');
  }
}
```

This package re-exports `tenet_di` in full, so an app only needs to
depend on `tenet_di_flutter` to get `Provider`, `StateProvider`,
`ProviderContainer`, and everything on this page.

## Installation

```yaml
dependencies:
  tenet_di_flutter: ^0.2.0
```

## Usage

### 1. Wrap your app in a `ProviderScope`

```dart
void main() => runApp(const ProviderScope(child: MyApp()));
```

This owns the `ProviderContainer` for everything below it, and disposes
it when the scope is removed from the tree. One `ProviderScope` per app
is the common case; this package doesn't support nested scopes with
layered overrides.

### 2. Observe providers in a `ConsumerWidget`

```dart
class GreetingText extends ConsumerWidget {
  const GreetingText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final greeting = ref.observe(greetingProvider);
    return Text(greeting);
  }
}
```

`ref.observe` both resolves the current value and subscribes this widget
to future changes — including changes cascading in from a `StateProvider`
this provider itself `ref.observe`d. Only providers observed during the
*most recent* build stay subscribed, so call `observe` unconditionally
from the top of `build`, not behind a condition that can flip between
builds.

For a one-off widget, skip the subclass and use `Consumer`:

```dart
Consumer(
  builder: (context, ref, child) => Text(ref.observe(greetingProvider)),
)
```

### 3. Resolve or write without subscribing

```dart
ElevatedButton(
  onPressed: () => context.resolve(counterProvider).update((n) => n + 1),
  child: const Text('Increment'),
)
```

`context.resolve` is for one-off reads/writes outside `build` — button
handlers, `initState`, anywhere a subscription would be pointless. It
never causes a rebuild by itself.

It's `resolve`, not `read`/`watch`: `package:provider` already defines
`context.read<T>()`/`context.watch<T>()` on `BuildContext` (and
`flutter_bloc` re-exports both as-is), and Dart treats two same-named
extension members on the same type as an unresolvable ambiguity, not
something an import prefix can quietly resolve the way a plain
class-name clash can. Naming this differently means you can add
`tenet_di_flutter` to a codebase that already uses
`package:provider`/`flutter_bloc`, unprefixed, and migrate one widget at
a time instead of all at once. `Ref`/`WidgetRef`'s own `resolve`/
`observe` never had this problem — they're methods on this package's own
interfaces, not extensions on `BuildContext` — but got the same names for
consistency.

### 4. No `BuildContext` at hand either?

`tenet_di`'s top-level `resolve`/`observe` (re-exported here) work
without any container, scope, or `BuildContext` — see
[`tenet_di`'s README](../tenet_di/README.md#no-container-of-your-own-at-hand)
for the full story. Pass that same `rootContainer` to `ProviderScope` to
make the widget tree share state with code reached that way:

```dart
void main() => runApp(
  ProviderScope(container: rootContainer, child: const MyApp()),
);
```

Leaving `container` unset (the default) is right for almost every app —
each `ProviderScope` then owns a private container, which is what keeps
widget tests isolated from one another. Reach for `container:
rootContainer` only when something outside the widget tree genuinely
needs to see the same live state.

### 5. Testing

```dart
await tester.pumpWidget(
  ProviderScope(
    overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
    child: const MyApp(),
  ),
);
```

`ProviderScope.overrides` works exactly like `ProviderContainer`'s — see
[`tenet_di`'s README](../tenet_di/README.md#testing-with-overrides) for
the full rundown of `overrideWithValue`/`overrideWith`. `overrides` only
applies to a container `ProviderScope` creates itself, so it can't be
combined with an explicit `container:`.

## Example

A small counter app exercising `ProviderScope`, `ConsumerWidget`,
`StateProvider`, and a derived `Provider` lives in
[`example/`](example) — run it with `flutter run` from that directory.

## Development

```
flutter pub get
flutter analyze
flutter test
```

This package only adds the Flutter SDK dependency on top of `tenet_di`,
which has none.
