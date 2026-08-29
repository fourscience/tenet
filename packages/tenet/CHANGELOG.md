## 0.6.0

### Added

- `Store.observeEchos` — notified whenever an Echo runs to completion
  without throwing, with the Echo's `name`, the event it received, and a
  `StateLens` snapshot. A legitimate devtools/logging hook in its own
  right, and what `FeatureHarness.echoCalls` is now built on entirely.
- `EchoCall<S>` (in `tenet_testing.dart`) — one recorded Echo invocation,
  carrying both `event` and a `state` snapshot from the moment it fired.

### Changed (breaking)

- `FeatureHarness.echoCalls` now returns `List<EchoCall<S>>` instead of
  `List<Object?>`, and `FeatureHarness.recordEcho` is removed. Previously,
  asserting that an Echo fired required the `Feature` under test to carry
  a test-only static back-reference to the harness
  (`harness?.recordEcho(name, value)` inside the Echo body) — test
  plumbing leaking into otherwise-production code. `echoCalls` is now
  populated automatically via `Store.observeEchos`, so a `Feature` needs
  no test-specific code at all. Migrate a call site from
  `harness?.recordEcho('name', someValue)` inside an Echo body to reading
  `harness.echoCalls('name')` after the fact — `.event` for the event, or
  `.state` for what `someValue` used to derive from `lens.state`.

## 0.5.0

### Added

- `Store.onEchoError` — a failure hook specific to Echoes that additionally
  names which one failed (via the `name` passed to `EchoRegistry.echo`).
  Runs alongside `onError`/the `Zone` fallback, never instead of them.

### Changed (breaking)

- `debounced` is renamed to `throttled`. The behavior was never a debounce
  — it's leading-edge rate limiting (a call runs immediately, further
  calls within the window are dropped), not a delay-until-quiet debounce
  — and the old name would mislead anyone who knows the term. No behavior
  change, only the name.

## 0.4.0

Correctness pass over cancellation and error reporting. Every item below
was reproducible against 0.3.0 and now has a regression test.

### Fixed

- A Ripple can no longer commit state after it has finished. A
  `withTimeout` body kept running past its timeout and its later `emit`
  landed as a normal commit — the store reported a `TimeoutException` and
  then wrote the "timed out" value anyway. A Ripple's emitter is now
  settled when its future settles; a later emission is dropped and
  reported.
- `retry` no longer retries a cancelled Ripple. `ScopeDeadException` was
  caught as if it were a transient failure, so a Ripple whose scope had
  been closed ran its body `max + 1` times instead of once.
- Echo and Ripple failures are no longer swallowed when no `onError`
  handler is registered — they now go to the current `Zone`'s
  uncaught-error handler (in Flutter: the console and
  `FlutterError.onError`).
- `dispatch`, `publish` and Echo matching now route by the event's runtime
  type instead of the static type argument. Previously an event whose
  static type was wider than its real one (an `Object` variable, a generic
  forwarding wrapper) silently matched nothing on `publish`, and on
  `dispatch` slipped past the fail-fast check — generics are covariant, so
  an Echo registered for a narrow type also matched a wide one — and then
  threw a `TypeError` that the point above swallowed.
- `close()` now does what it always documented: it drops every ledger
  observer and error handler. It also refuses further
  `dispatch`/`send`/`execute`/`publish` with a `StateError`; previously a
  closed store still committed state and still notified observers.
- `runRipple`/`runRippleAndWait` on a closed store now report the failure
  instead of throwing `StateError` at the call site, matching their
  documented "never throws here" contract.
- `runRipple` now closes the scope it spawned itself once the Ripple
  settles. Every fire-and-forget Ripple used to leave a child scope
  attached to `rootScope` for the store's lifetime. A scope you pass in is
  still yours and is never closed for you.

### Added

- `Store.ledgerLimit` (default `1000`, `null` for unbounded) caps ledger
  growth, dropping the oldest transactions. `Transaction.sequence` still
  counts from the first commit, so trimmed history is visible as a gap.
- `Store.isClosed`.

### Changed (breaking)

- Routing by runtime type changes `dispatch<Base>(derivedInstance)`: it
  now looks for a Flow registered for the *derived* type. Register against
  the type you actually dispatch.
- A `Store` that outlives its `close()` now throws on use rather than
  silently continuing to work.
- The ledger is capped by default — pass `ledgerLimit: null` to restore
  0.3.0's unbounded behavior.

## 0.3.0

- **Breaking:** `FlowRegistry.flow` and `EchoRegistry.echo` now take the
  callback as the first positional argument and `name` as an optional
  named argument — `flows.flow<E>(name, callback)` is now
  `flows.flow<E>(callback, {name})`, and likewise for `echos.echo`. Both
  `name`s default to `E`'s type name when omitted, so the common case no
  longer needs a raw string at all. This matches the `Provider<T>(create,
  {name})` convention already used by `tenet_di`. A Flow's `name` is still
  consequential — it becomes the ledger transaction's `Transaction.source`
  — while an Echo's `name` remains a readability label only.

## 0.2.0

- Added an optional Intent/Command/Event dispatch taxonomy, additive
  alongside the existing Flow-based `dispatch`: `Intent` (the only thing
  a screen should send, via `Store.send`), `Command<S>` (the only other
  legal write besides a Flow, via `Store.execute`), and `Event`
  (broadcast-only, via `Store.publish`), all subtypes of a sealed
  `Dispatch`. Adds `Feature.registerIntents`, `IntentRegistry`,
  `IntentContext`, and the built-in `EventCommitted` Event that every
  commit — Flow, Ripple, optimistic, or Command — now publishes
  automatically.
- `FeatureHarness` gained matching `send`/`execute`/`publish` helpers.

## 0.1.0

- Initial release of `tenet`: `Store`, `Feature`, `FlowRegistry`,
  `EchoRegistry`, `FlowScope`, the `retry`/`withTimeout`/`debounced` Ripple
  combinators, and the `FeatureHarness` test toolkit.
