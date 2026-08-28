# tenet example

A runnable, self-contained example exercising every Tenet concept — Flow,
Ripple, Echo, the `retry`/`withTimeout` combinators, optimistic updates
with rollback, and the transaction ledger — against a small "counter with
remote sync" feature.

Run it from the package root:

```
dart pub get
dart run example/tenet_example.dart
```

Expected output (transaction timestamps aside) is deterministic: two
Flow-driven increments, a Ripple that retries through two simulated
network failures before succeeding, an optimistic update that gets rolled
back because its Ripple fails, and the full ledger of everything that
happened.
