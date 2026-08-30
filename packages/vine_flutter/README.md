# vine_flutter

Flutter bindings for [`vine`](../vine): `Trellis` exposes an already-built
`Garden` to a widget subtree, and `context.watch`/`VineWidget`/
`VineBuilder` rebuild automatically — with fine-grained, per-vine
precision — when the vine they watched actually changes.

```dart
final counterVine = Vine.cell(0);

void main() => runApp(
  Trellis(garden: Garden().grow(), child: const MyApp()),
);

class CounterText extends VineWidget {
  const CounterText({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.watch(counterVine);
    return Text('Count: $count');
  }
}
```

This package re-exports `vine` in full, so an app only needs to depend on
`vine_flutter` to get `Vine`, `Garden`, `AsyncValue`, and everything on
this page.

## Installation

```yaml
dependencies:
  vine_flutter: ^0.1.0
```

## Usage

### 1. Build a `Garden` and expose it with `Trellis`

```dart
void main() => runApp(
  Trellis(garden: Garden(vines: [...]).grow(), child: const MyApp()),
);
```

Unlike a DI container that creates itself, `Trellis` doesn't own the
`Garden`'s lifecycle — you built and `grow()`ed it, so you're the one who
`dispose()`s it (typically never, for a process-wide garden that lives as
long as the app does).

### 2. `context.watch` inside a `VineWidget`

```dart
class GreetingText extends VineWidget {
  const GreetingText({super.key});

  @override
  Widget build(BuildContext context) {
    final greeting = context.watch(greetingVine);
    return Text(greeting);
  }
}
```

`context.watch` only works inside a `VineWidget`/`VineBuilder`/
`SuspendedVine` — fine-grained "only rebuild for the specific vine this
build actually watched" tracking needs a dedicated `Element`, which a bare
`BuildContext` extension can't provide (see the source doc comment on
`VineContextExtension` for why). Calling it from a context that doesn't
support it throws `NoVineWatchSupportError` with a fix.

Only vines watched during the *most recent* build stay subscribed, so
call `watch` unconditionally from the top of `build`, not behind a
condition that can flip between builds — the same rule `Vine.computed`'s
own dynamic re-tracking follows.

For a one-off widget, skip the subclass and use `VineBuilder`:

```dart
VineBuilder(
  builder: (context, child) => Text(context.watch(greetingVine)),
)
```

### 3. Read or write without subscribing

```dart
ElevatedButton(
  onPressed: () => context.set(counterVine, context.tap(counterVine) + 1),
  child: const Text('Increment'),
)
```

`context.tap`/`context.set`/`context.refresh` work from *any* context
under a `Trellis` — button handlers, `initState`, anywhere a subscription
would be pointless — and never cause a rebuild by themselves.

### 4. Future vines: `SuspendedVine`

```dart
SuspendedVine(
  vine: profileVine,
  builder: (context, profile) => Text(profile.name),
  loading: () => const CircularProgressIndicator(),
  error: (error, stackTrace) => Text('Failed: $error'),
)
```

Rebuilds on every transition. Stale-while-revalidate: once data has
arrived once, a later refresh keeps `builder` on screen with the previous
data instead of falling back to `loading`/`error` — those are only
reached before the first successful load.

### 5. Scoped overrides: `TrellisScope`

```dart
await tester.pumpWidget(
  TrellisScope(
    overrides: [repositoryVine.override((tap) => FakeRepository())],
    child: const MyApp(),
  ),
);
```

`TrellisScope` — unlike `Trellis` — *does* own the child `Garden` it
`growScope()`s, disposing it when the scope leaves the tree. It needs an
ancestor `Trellis`/`TrellisScope` to grow from (a widget test typically
wraps its own root `Trellis` around it, or nests `TrellisScope` for a
subtree's worth of overrides within a real app).

## Example

A small counter app exercising `Trellis`, `VineWidget`, `Vine.cell`, and a
derived `Vine.computed` lives in [`example/`](example) — run it with
`flutter run` from that directory.

## Development

```
flutter pub get
flutter analyze
flutter test
```

This package only adds the Flutter SDK dependency on top of `vine`, which
has none.
