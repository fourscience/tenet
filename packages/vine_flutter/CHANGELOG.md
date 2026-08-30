## 0.1.0

Ground-up rewrite of what was `tenet_di_flutter`, following `vine`'s
rewrite of `tenet_di`:

- `Trellis` (renamed from `ProviderScope`): exposes an already-`grow()`n
  `Garden` to a widget subtree. Unlike `ProviderScope`, it doesn't own or
  dispose the garden itself — you built it, you own its lifecycle. Also
  supports nesting: `TrellisScope` (new) *does* own and dispose the child
  scope it `growScope()`s, for a subtree's worth of overrides.
- `context.tap`/`context.set`/`context.refresh`: work from any context
  under a `Trellis`, mirroring `Garden`'s own read/write/refresh methods.
- `context.watch` (replacing `WidgetRef.observe`/`ConsumerWidget`): needs
  a dedicated `Element` for fine-grained per-vine rebuild tracking, so it
  only works inside `VineWidget`/`VineBuilder`/`SuspendedVine` — calling
  it elsewhere throws `NoVineWatchSupportError` with a fix. Carries
  forward the same defer-to-post-frame-callback fix `tenet_di_flutter`
  0.3.0 shipped for a change arriving mid-build.
- `SuspendedVine` (new): builds UI from a future-shaped vine's
  `AsyncValue`, with stale-while-revalidate built in — a refresh after the
  first successful load keeps the previous data on screen instead of
  falling back to a loading/error widget.
- Requires `vine ^0.1.0`.

## 0.3.0 (as `tenet_di_flutter`)

### Fixed

- A provider changing while another widget's build was still in progress
  — e.g. writing to a `StateProvider` from inside a `build` method —
  crashed every `ConsumerWidget`/`Consumer` observing it with "setState()
  or markNeedsBuild() called during build." Notifications that arrive
  during Flutter's build/layout/paint phase are now deferred to a
  post-frame callback, matching the framework's own guidance for this
  case; the observer still rebuilds, just on the following frame instead
  of crashing mid-build.

## 0.2.0 (as `tenet_di_flutter`)

- **Breaking:** `WidgetRef.read`/`.watch` are now `.resolve`/`.observe`,
  and the `BuildContext` extension (briefly `readProvider` in 0.1.1) is
  now `context.resolve`.
- Added an optional `container` parameter to `ProviderScope`, so the
  widget tree can share state with code reached through `tenet_di`'s
  `rootContainer`.
- Requires `tenet_di ^0.2.0`.

## 0.1.0 (as `tenet_di_flutter`)

- Initial release: `ProviderScope`, `ConsumerWidget`, `Consumer`,
  `WidgetRef`, and the `BuildContext.read` extension.
