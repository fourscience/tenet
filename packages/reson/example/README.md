# reson examples

Two runnable, self-contained examples, one per dispatch model.

## `reson_example.dart`

Exercises the core Flow/Ripple/Echo model — a Flow, a Ripple wrapped in
the `retry`/`withTimeout` combinators, an Echo-driven audit log, an
optimistic update with rollback, and the transaction ledger — against a
small "counter with remote sync" feature.

```
dart pub get
dart run example/reson_example.dart
```

Expected output (transaction timestamps aside) is deterministic: two
Flow-driven increments, a Ripple that retries through two simulated
network failures before succeeding, an optimistic update that gets rolled
back because its Ripple fails, and the full ledger of everything that
happened.

## `intent_command_event_example.dart`

Exercises the optional Intent/Command/Event taxonomy — a screen-facing
`Intent`, two `Command`s (one executed synchronously by the Intent
handler, one executed from inside a Ripple after an `await`, via the
handler's captured `IntentContext`), a custom `Event`, and the automatic
`EventCommitted` every commit publishes for free — against a small
"session login" feature.

```
dart pub get
dart run example/intent_command_event_example.dart
```

Expected output is deterministic: an immediate "authenticating" commit,
a simulated 100ms auth call, then a "signedIn" commit with both the
custom `SessionStarted` Event and the automatic `EventCommitted` reaching
their Echoes, followed by the full ledger.
