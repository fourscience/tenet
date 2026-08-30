## 0.1.0

Ground-up rewrite of what was `tenet_di`: a plain, push-invalidated DI
container becomes `vine`, a dependency injection + reactive state
container built around one declaration type (`Vine`) and one read
primitive (`tap`).

- `Vine.value`/`single`/`transient`/`eager`: frozen declarations,
  identical in spirit to `tenet_di`'s `Provider`, but sharing one factory
  namespace with the reactive kinds below instead of a separate type.
- `Vine.cell`/`computed`/`future`: fine-grained reactivity — a `cell`
  write only recomputes/renotifies the `computed`/`future` nodes that
  actually tapped it (dynamic re-tracking drops stale edges), each node
  memoizes and applies an equality gate, and a diamond-shaped graph
  recomputes each node exactly once per wave. `future` is dual-mode
  (frozen-once if it never taps anything reactive, derived-async
  otherwise) and reads as an `AsyncValue<T>` that preserves the previous
  value through a loading/error transition (stale-while-revalidate).
- `Vine.each`/`eachAsync`: parameterized families, cached per `(family,
  key)`, disposed per-key.
- `Vine.ref`: a lazy forward-reference for a genuine mutual dependency,
  replacing a bare `StateError` on cycle detection with a documented way
  to break one deliberately.
- `Garden`: the container (renamed from `ProviderContainer`) — `tap`/
  `tapAsync` to read, `set` to write a cell, `watch`/`effect` to react,
  `refresh` to force a future to re-run, `growScope` for scoped overrides
  and scoped-singleton isolation (an unoverridden vine tapped first from
  a child scope gets its own instance, independent of the parent's), and
  `pump()` for deterministic tests.
- `.autoDispose`: a `computed`/`future`/`each` node drops its cached
  state (with a one-`pump()` grace period) once nothing is watching it.
- Named, hinted errors for every misuse the design intentionally rejects:
  `CyclicDependencyError`, `UntiedRefError`, `AsyncInSyncContextError`,
  `TrackingAfterSuspendError`, `GardenDisposedError`.

See the README's "differences from the spec" section for the handful of
places this implementation's Dart typing intentionally diverges from the
literal spec syntax (`tap.async`/`Garden.tapAsync`'s signature) or
simplifies a mechanism (no forced cancellation-into-await for a
superseded run — its result is discarded, not the run itself killed).
