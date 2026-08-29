## 0.2.1

- Documented a `StateController` footgun: setting/`update`-ing skips
  notifying when the new value equals the old one, so mutating a
  `List`/`Set`/`Map` (or anything using default, identity-based `==`) in
  place and setting it back compares equal to itself and silently never
  notifies. No behavior change — `T` was always expected to be treated as
  immutable — this makes the expectation explicit in the doc comments and
  README, with a regression test demonstrating it.

## 0.2.0

- **Breaking:** renamed `Ref.read`/`ProviderContainer.read` to `resolve`,
  and `Ref.watch`/`ProviderContainer.listen` to `observe`. `read`/`watch`
  collided with the near-identical, extremely widely used
  `context.read`/`context.watch` from `package:provider` (also
  re-exported as-is by `flutter_bloc`) once `tenet_di_flutter` put a
  matching extension on `BuildContext` — a codebase already using either
  package couldn't add `tenet_di_flutter` alongside it without a compile
  error. `resolve`/`observe` are clear of `provider`, `flutter_bloc`,
  `get_it`, and `riverpod`'s own APIs.
- Added `rootContainer`: a process-wide default `ProviderContainer`,
  created lazily on first use, plus top-level `resolve`/`observe`/
  `resetRootContainer()` sugar around it — for code with no natural
  container (or, in Flutter, no `BuildContext`) to thread through, such
  as a `main()` or a background service.

## 0.1.0

- Initial release: `Provider`, `StateProvider`/`StateController`, `Ref`,
  `ProviderContainer` (lazy caching, dependency-graph invalidation
  cascade, `listen`, `invalidate`, `dispose`), and provider overrides for
  testing.
