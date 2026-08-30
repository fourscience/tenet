# tenet_rxdart

[rxdart](https://pub.dev/packages/rxdart) interop for
[`tenet`](../tenet): use rxdart's real operators for throttle/debounce/
retry instead of (or alongside) `tenet`'s own `retry`/`withTimeout`/
`throttled` combinators, and drive a `Store` straight from a `Stream<E>`
pipeline built with any rxdart operator at all.

`tenet` itself stays dependency-free — this is a separate, opt-in
package, so adding it (and rxdart) is a choice you make, not something
`tenet` forces on you.

## Installation

```yaml
dependencies:
  tenet_rxdart: ^0.1.0
  rxdart: ^0.28.0 # for building your own Stream pipelines (see below)
```

## Two different "debounce"s

This is the one thing to get right before reaching for this package:
"debounce"/"throttle" can mean two different things, and they map to two
different APIs here.

**Rate-limiting the emissions *within one Ripple invocation*** — a Ripple
that calls `emit` several times in a burst and only wants the store
bothered with some of them:

```dart
final resilientSync = rxDebounce<CartState, SyncRequested>(
  (event, emit) async {
    for (final progress in chattyProgressSource) {
      emit(state.copyWith(progress: progress)); // fires rapidly
    }
  },
  const Duration(milliseconds: 300),
);

store.runRipple(resilientSync, event: SyncRequested(store.state.value));
```

**Rate-limiting *repeated calls*** — a search box re-dispatching on every
keystroke. That's not `rxDebounce`/`rxThrottle` (which only ever see one
invocation's own emissions) — it's `.debounceTime`/`.throttleTime` applied
to the `Stream<E>` of incoming events, driven into the store via
`StoreRx`:

```dart
final debouncedQueries = searchBox.stream.debounceTime(
  const Duration(milliseconds: 300),
);

store.runRippleStream<String>(
  debouncedQueries,
  (query, emit) async => emit(state.copyWith(results: await api.search(query))),
);
```

## Ripple combinators: `rxThrottle`, `rxDebounce`, `rxTransform`, `rxRetry`, `rxRetryWhen`

Each is a drop-in alongside `tenet`'s own `retry`/`withTimeout`/
`throttled` — same shape, `RippleBody<S, E> -> RippleBody<S, E>` — so they
compose the same way:

```dart
final resilientSync = rxRetry<CartState, SyncRequested>(
  rxDebounce((event, emit) async { /* ... */ }, const Duration(seconds: 1)),
  count: 3,
  delay: const Duration(milliseconds: 200),
);
```

- **`rxThrottle(body, duration, {leading, trailing})`** — rxdart's
  `throttleTime`. Unlike `tenet`'s `throttled`, `trailing: true` also
  emits the last value in the window, not just the first.
- **`rxDebounce(body, duration)`** — rxdart's `debounceTime`: only a value
  not followed by another within `duration` reaches the real emitter.
  `tenet` has no built-in equivalent — `throttled` is leading-edge and
  never delays a value waiting for silence.
- **`rxTransform(body, transform)`** — the general escape hatch behind
  both: pipes `body`'s emissions through *any* `Stream<S> Function
  (Stream<S>)`, so every other rxdart operator (`bufferTime`, `sample`,
  your own custom transform) is usable too, not just the two named above.
- **`rxRetry(body, {required count, delay})`** — a safe `rxRetryWhen`
  preset matching `tenet`'s own `retry` signature: `count` retries, a
  fixed `delay` between attempts, and — the one behavior it's not safe to
  drop — a `ScopeDeadException` (the Ripple's scope was cancelled) is
  never retried.
- **`rxRetryWhen(body, retryWhenFactory)`** — the raw `Rx.retryWhen`,
  for backoff, jitter, or error-type-specific retry logic beyond a fixed
  delay. Does **not** special-case `ScopeDeadException` on its own — pass
  a `retryWhenFactory` that re-throws it if you need that guarantee
  without using `rxRetry`.

## `StoreRx`: driving a `Store` from a `Stream<E>`

For a pipeline built entirely from rxdart operators — `switchMap`,
`debounceTime`, `retryWhen`, however elaborate — `StoreRx` extension
methods subscribe to it and call the matching write method for every
value, until the returned `FlowScope` closes:

```dart
final searchResults = searchBox.stream
    .debounceTime(const Duration(milliseconds: 300))
    .distinct()
    .switchMap((query) => Stream.fromFuture(api.search(query)));

final scope = store.runRippleStream<SearchResults>(
  searchResults,
  (results, emit) async => emit(state.copyWith(results: results)),
);

// Later — e.g. a screen's dispose():
scope.close();
```

- **`dispatchStream(events)`** — calls `Store.dispatch` per event.
- **`sendStream(events)`** — calls `Store.send` per `Intent`.
- **`runRippleStream(events, body)`** — calls `Store.runRipple` per event,
  all sharing the one returned scope.

A failure — the stream erroring, or the write method itself throwing
(e.g. `send` with no registered handler) — goes to the current `Zone`'s
uncaught-error handler, the same fallback `Store.onError`/`onEchoError`
use with no handler registered. This extension lives outside `Store`, so
it has no access to those handlers' private lists; route anything worth
handling explicitly through the stream itself (`events.handleError(...)`)
instead.

## Example

A runnable example covering `rxRetry`, `rxDebounce`, and
`StoreRx.runRippleStream` lives in
[`example/tenet_rxdart_example.dart`](example/tenet_rxdart_example.dart):

```
dart run example/tenet_rxdart_example.dart
```

## Development

```
dart pub get
dart analyze
dart test
```

## License

MIT — see [LICENSE](LICENSE).
