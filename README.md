# tenet

[![CI](https://github.com/fourscience/tenet/actions/workflows/ci.yaml/badge.svg)](https://github.com/fourscience/tenet/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](packages/reson/LICENSE)

A small family of focused Dart/Flutter libraries, developed together in
one [Dart pub workspace](https://dart.dev/tools/pub/workspaces):

| Package | What it is | Flutter needed? |
|---|---|---|
| [`reson`](packages/reson) | A time-aware, effect-separated state management library — State/Flow/Ripple/Echo, plus an optional Intent/Command/Event taxonomy. | No |
| [`casus`](packages/casus) | A minimal `Result<T, E>` type: explicit, typed success/failure instead of throwing. | No |
| [`vine`](packages/vine) | A dependency injection + reactive state container — declarative `Vine`s (single/transient/eager/cell/computed/future/each), a `Garden` to tap/set/watch/effect them, scoped overrides, testing overrides. | No |
| [`vine_flutter`](packages/vine_flutter) | Flutter bindings for `vine`: `Trellis`, `VineWidget`, `context.watch`, `SuspendedVine`. | Yes |
| [`tenet_rxdart`](packages/tenet_rxdart) | rxdart interop for `reson`: rxdart-backed throttle/debounce/retry Ripple combinators, plus driving a `Store` from a `Stream<E>` pipeline. | No |

Each package is independently versioned and publishable, has its own
`CHANGELOG.md`/`LICENSE`/tests/example, and has no dependency on any
other package here except the one it explicitly binds to (`vine_flutter` → `vine`, `tenet_rxdart` → `reson`) — pick the
ones you need. Follow the link to a package above for its full README.

## Repository layout

```
packages/
  reson/               # state management (Flow/Ripple/Echo/Intent/Command/Event)
  casus/               # Result<T, E>
  vine/                  # DI + reactive state container (pure Dart)
  vine_flutter/           # DI + reactive state container, Flutter bindings
  tenet_rxdart/            # rxdart interop for reson
```

Every package lists `resolution: workspace` in its `pubspec.yaml` and is
declared under `workspace:` in the root `pubspec.yaml` — dependencies
resolve for all of them together, and a package can depend on a sibling
by name without a manual `path:` override.

## Development

Resolving the workspace needs the **Flutter SDK on `PATH`**, even though
four of the five packages have no Flutter dependency of their own: pub
workspaces resolve every member together, and `vine_flutter` (one
member) depends on the Flutter SDK, so plain `dart pub get` at the root
fails outright — `flutter pub get` is a superset that handles it.
Individual pure-Dart packages can still be analyzed/tested with the
plain `dart` commands once that initial resolution is done:

```
flutter pub get                 # resolves the whole workspace (once)
cd packages/reson && dart test  # plain `dart` commands work per-package after that
```

`vine_flutter` itself needs `flutter analyze`/`flutter test` instead
of the `dart` equivalents (it's the only package that actually uses
Flutter APIs), and its `example/` is a standalone Flutter app with its
own `flutter pub get`.

CI (`.github/workflows/ci.yaml`) runs format/analyze/test/example checks
for every package, in that order, on each push and pull request.

## Publishing

Each package publishes independently to pub.dev via a manually-triggered
workflow:

- `.github/workflows/publish.yaml` — `reson`, `casus`, `vine`,
  `tenet_rxdart` (pick one from the workflow's `package` input).
- `.github/workflows/publish-flutter.yaml` — `vine_flutter`.

Both authenticate via a `PUB_CREDENTIALS` repository secret — see either
workflow's header comment for one-time setup.

## License

Each package is MIT-licensed — see its own `LICENSE` file.
