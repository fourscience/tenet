# tenet_di_flutter

Flutter bindings for [`tenet_di`](../tenet_di): `ProviderScope` owns the
container for a widget subtree, and `ConsumerWidget`/`Consumer` rebuild
automatically when the providers they watch change — a minimal,
Riverpod/Refena-flavored developer experience, with no code generation.

```dart
void main() => runApp(const ProviderScope(child: MyApp()));

final counterProvider = StateProvider<int>((ref) => 0);

class CounterText extends ConsumerWidget {
  const CounterText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider).state;
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
  tenet_di_flutter: ^0.1.0
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

### 2. Watch providers in a `ConsumerWidget`

```dart
class GreetingText extends ConsumerWidget {
  const GreetingText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final greeting = ref.watch(greetingProvider);
    return Text(greeting);
  }
}
```

`ref.watch` both reads the current value and subscribes this widget to
future changes — including changes cascading in from a `StateProvider`
this provider itself `ref.watch`ed. Only providers watched during the
*most recent* build stay subscribed, so call `watch` unconditionally
from the top of `build`, not behind a condition that can flip between
builds.

For a one-off widget, skip the subclass and use `Consumer`:

```dart
Consumer(
  builder: (context, ref, child) => Text(ref.watch(greetingProvider)),
)
```

### 3. Read or write without subscribing

```dart
ElevatedButton(
  onPressed: () => context.readProvider(counterProvider).update((n) => n + 1),
  child: const Text('Increment'),
)
```

`context.readProvider` is for one-off reads/writes outside `build` —
button handlers, `initState`, anywhere a subscription would be
pointless. It never causes a rebuild by itself.

It's `readProvider`, not `read`: `package:provider` already defines
`context.read<T>()`/`context.watch<T>()`, and Dart treats two
same-named extension members on the same type as an unresolvable
ambiguity, not something an import prefix can quietly resolve the way a
plain class-name clash can. Naming this differently means you can add
`tenet_di_flutter` to a codebase that already uses `package:provider`,
unprefixed, and migrate one widget at a time instead of all at once.

### 4. Testing

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
the full rundown of `overrideWithValue`/`overrideWith`.

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
