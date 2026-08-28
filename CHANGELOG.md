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
