# casus_flutter

Flutter bindings for [`casus`](../casus): `ResourceBuilder` renders a
`Resource<T>` — loading/data/error, with stale-while-revalidate support —
by delegating straight to `Resource.fold`. No hidden logic, no implicit
retry button; composable, not opinionated.

```dart
ResourceBuilder<User>(
  resource: state,
  loading: (_) => const ProgressSkeleton(),
  ready: (_, user) => ProfileView(user),
  error: (_, error, previousData) => previousData != null
      ? ProfileView(previousData)      // stale data + banner
      : RetryView(onRetry: bloc.reload),
);
```

This package re-exports `casus` in full, so an app only needs to depend
on `casus_flutter` to get `Result`, `Either`, `Option`, `Resource`, and
`ResourceBuilder`.

## Installation

```yaml
dependencies:
  casus_flutter: ^1.0.0
```

## Usage

`ResourceBuilder<T>` takes the `Resource<T>` to render and three
builders, one per state:

- `loading` — called while the resource is `Loading`.
- `ready` — called with the data when the resource is `Ready`.
- `error` — called with the error and, if the failure carried one, the
  `previousData` from a stale-while-revalidate load. It's the caller's
  choice what to do with `previousData`: show it alongside an error
  banner, ignore it and show a retry view, or something else entirely —
  `ResourceBuilder` doesn't decide for you.

```dart
final Resource<User> state = await repo.getUser('42').then((r) => r.toResource());
```

See [`casus`](../casus)'s README for the full `Result`/`Either`/`Option`/
`Resource` API this widget builds on.

## Example

A small counter-profile app exercising `ResourceBuilder` across all three
states lives in [`example/`](example) — run it with `flutter run` from
that directory.

## Development

```
flutter pub get
flutter analyze
flutter test
```

This package only adds the Flutter SDK dependency and `ResourceBuilder`
on top of `casus`, which has none beyond `meta`.
