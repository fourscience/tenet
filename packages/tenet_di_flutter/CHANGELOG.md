## 0.3.0

### Fixed

- A provider changing while another widget's build was still in progress
  — e.g. writing to a `StateProvider` from inside a `build` method —
  crashed every `ConsumerWidget`/`Consumer` observing it with "setState()
  or markNeedsBuild() called during build." Notifications that arrive
  during Flutter's build/layout/paint phase are now deferred to a
  post-frame callback, matching the framework's own guidance for this
  case; the observer still rebuilds, just on the following frame instead
  of crashing mid-build.

## 0.2.0

- **Breaking:** `WidgetRef.read`/`.watch` are now `.resolve`/`.observe`,
  and the `BuildContext` extension (briefly `readProvider` in 0.1.1) is
  now `context.resolve`. Settled on `resolve`/`observe` package-wide —
  matching the rename in `tenet_di` 0.2.0 — instead of stopping at the
  `BuildContext` extension alone, so the vocabulary is consistent from
  `Ref` down to `ProviderContainer`. `package:provider` already defines
  `context.read<T>()`/`context.watch<T>()` (`flutter_bloc` re-exports
  both as-is), and two same-named extension members on the same type are
  an unresolvable ambiguity at the call site in Dart — not something an
  import prefix can quietly resolve the way a plain class-name clash
  can. Renaming lets a codebase already using
  `package:provider`/`flutter_bloc` add this package alongside it,
  unprefixed, and migrate one widget at a time instead of all at once.
- Added an optional `container` parameter to `ProviderScope`, so the
  widget tree can share state with code reached through `tenet_di`'s
  `rootContainer` (or any other container you create and own yourself)
  instead of always getting a private one. Left unset, behavior is
  unchanged: each `ProviderScope` still owns and disposes a fresh
  container, which is what keeps widget tests isolated.
- Requires `tenet_di ^0.2.0`.

## 0.1.0

- Initial release: `ProviderScope`, `ConsumerWidget`, `Consumer`,
  `WidgetRef`, and the `BuildContext.read` extension — Flutter bindings
  for `tenet_di`, re-exported in full.
