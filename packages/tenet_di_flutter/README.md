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

This package re-exports `tenet_di`, so an app only needs to depend on
`tenet_di_flutter` to get `Provider`, `StateProvider`, `ProviderContainer`,
and everything on this page — except the top-level `resolve`/`observe`
sugar, which stays behind its own opt-in import; see
[section 4](#4-no-buildcontext-at-hand-either) below.

## Installation

```yaml
dependencies:
  tenet_di_flutter: ^0.4.0
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
class-name clash can. `Ref`/`WidgetRef`'s own `resolve`/`observe` never
had this problem — they're methods on this package's own interfaces, not
extensions on `BuildContext` — but got the same names for consistency.

That sidesteps the extension collision, but `Provider`/`Consumer` are
still plain classes with the same names as `package:provider`'s — see
[Coexisting with `package:provider`](#coexisting-with-packageprovider)
for how to actually run both side by side.

## Coexisting with `package:provider`

Adding `tenet_di_flutter` to a codebase that already uses
`package:provider` (or `flutter_bloc`, which re-exports it) and migrating
one widget at a time needs one more step beyond the `resolve`/`read`
naming above: `tenet_di`'s `Provider` and this package's
`Consumer`/`ConsumerWidget` are plain classes with the same names as
`package:provider`'s, so importing `tenet_di_flutter.dart` unprefixed
alongside `package:provider` unprefixed is an `ambiguous_import` error.
Unlike the extension-method collision, this *is* exactly what an import
prefix is for — prefix the main library, and import `context_extensions`
(the piece with no colliding class names) on its own, unprefixed:

```dart
import 'package:provider/provider.dart';
import 'package:tenet_di_flutter/tenet_di_flutter.dart' as di;
import 'package:tenet_di_flutter/context_extensions.dart'; // unprefixed

final greeting = di.Provider<String>((ref) => 'hi');

class StillOnPackageProvider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Consumer<String>(builder: (c, v, _) => Text(v)); // package:provider
}

class MigratedToTenet extends di.ConsumerWidget {
  @override
  Widget build(BuildContext context, di.WidgetRef ref) =>
      Text(ref.observe(greeting));
}

class OneOffReadMidMigration extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Text(context.resolve(greeting)); // the extension, still unprefixed
}
```

Verified against `package:provider` directly: with this import shape,
`flutter analyze` reports no issues.

### 4. No `BuildContext` at hand either?

`rootContainer` (re-exported here) works without any container, scope, or
`BuildContext` — see
[`tenet_di`'s README](../tenet_di/README.md#no-container-of-your-own-at-hand)
for the full story. Pass that same `rootContainer` to `ProviderScope` to
make the widget tree share state with code reached that way:

```dart
void main() => runApp(
  ProviderScope(container: rootContainer, child: const MyApp()),
);
```

For the bare top-level `resolve`/`observe` functions themselves (sugar
for `rootContainer.resolve`/`rootContainer.observe`), add one more,
separate import — `package:tenet_di_flutter/global.dart` — rather than
`tenet_di_flutter.dart` alone:

```dart
import 'package:tenet_di_flutter/tenet_di_flutter.dart';
import 'package:tenet_di_flutter/global.dart';

print(resolve(greetingProvider));
```

Kept opt-in for the same reason as in `tenet_di` itself: see
[`tenet_di`'s README](../tenet_di/README.md#no-container-of-your-own-at-hand).

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
