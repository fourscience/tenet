# tenet

[![CI](https://github.com/fourscience/tenet/actions/workflows/ci.yaml/badge.svg)](https://github.com/fourscience/tenet/actions/workflows/ci.yaml)
[![pub package](https://img.shields.io/pub/v/tenet.svg)](https://pub.dev/packages/tenet)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A time-aware, effect-separated state management library for Dart and
Flutter.

Core mental model, one sentence: **state is now, Flows change it purely,
Ripples fetch it asynchronously, Echoes react to it externally.**

Every piece of feature logic is exactly one of:

| Concept | What it is | Can it touch state? |
|---|---|---|
| **State** | A value that exists now. | — |
| **Flow** | A pure, synchronous function `(State, Event) -> State`. | Writes, synchronously. |
| **Ripple** | An async, cancellable process that commits typed states over time. | Writes, asynchronously, through `StateEmitter`. |
| **Echo** | A side-effect listener (analytics, logging, navigation, ...). | Reads only, through `StateLens`. Never writes. |

That separation is enforced by the type system, not by convention: an Echo
literally has no method that could mutate state, and a Ripple can only
write through the narrow `StateEmitter` interface it's handed.

## Table of contents

- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Core concepts](#core-concepts)
  - [Flow](#flow--pure-synchronous-transitions)
  - [Ripple](#ripple--cancellable-async-processes)
  - [Echo](#echo--read-only-side-effects)
  - [Combinators: retry, withTimeout, debounced](#combinators-retry-withtimeout-debounced)
  - [Optimistic updates](#optimistic-updates)
  - [The transaction ledger](#the-transaction-ledger)
- [Testing](#testing)
- [Flutter integration](#flutter-integration)
- [Architecture](#architecture)
- [Package layout](#package-layout)
- [Development](#development)
- [Versioning and releases](#versioning-and-releases)
- [License](#license)

## Features

- **Strict effect separation** — pure state transitions, async processes,
  and side-effect listeners are three different types, so a code review
  can tell at a glance which category a change belongs to.
- **Structured cancellation** — every Ripple runs inside a hierarchical
  `FlowScope`; closing a scope (e.g. a screen's `dispose()`) cancels every
  Ripple spawned under it and turns late emissions into a loud
  `ScopeDeadException` instead of a silent, corrupting write.
- **Composable Ripple behavior** — `retry`, `withTimeout`, and `debounced`
  are plain decorators around a Ripple body. New behaviors are new
  functions, not new subclasses or changes to `Store` (Open/Closed).
- **Optimistic updates with automatic rollback** — commit instantly, roll
  back to the prior state if the backing Ripple fails.
- **A full transaction ledger** — every commit (Flow, Ripple, optimistic,
  rollback) is recorded with a monotonic sequence number, its before/after
  state, and a timestamp — time-travel debugging and devtools for free.
- **A dedicated test harness** — `FeatureHarness`, shipped behind a
  separate `tenet_testing.dart` entry point so it never ships inside an
  app bundle, drives a `Feature` in isolation and gives you fluent
  assertions over its ledger, its Echo calls, and its errors.
- **Zero Flutter dependency** — the core library is plain Dart, usable in
  a CLI, a server, or a Flutter app; see [Flutter integration](#flutter-integration)
  for how to wire it into widgets.

## Installation

```yaml
dependencies:
  tenet: ^0.1.0
```

Then:

```
dart pub get
```

The test harness lives at `package:tenet/tenet_testing.dart` — a second
entry point in this same package, not a separate dependency to add. See
[Testing](#testing).

## Quick start

```dart
import 'package:tenet/tenet.dart';

class AddItem {
  final String item;
  AddItem(this.item);
}

class CartState {
  final List<String> items;
  CartState([List<String>? items])
      : items = List.unmodifiable(items ?? const []);
}

class CartFeature extends Feature<CartState> {
  @override
  CartState get initial => CartState();

  @override
  void registerFlows(FlowRegistry<CartState> flows) {
    flows.flow<AddItem>(
      'addItem',
      (state, event) => CartState([...state.items, event.item]),
    );
  }
}

void main() {
  final store = Store<CartState>(CartFeature());
  store.dispatch(AddItem('apple'));
  print(store.state.items); // [apple]
}
```

A larger, runnable example covering every concept below — Flow, Ripple,
Echo, combinators, optimistic updates, and the ledger — lives in
[`example/tenet_example.dart`](example/tenet_example.dart):

```
dart run example/tenet_example.dart
```

## Core concepts

### Flow — pure, synchronous transitions

A `Flow<S, E>` is `S Function(S state, E event)`. It must be pure: no I/O,
no async, no side effects — which makes it trivially unit-testable and
hot-reload friendly. Register one per event type in
`Feature.registerFlows`:

```dart
flows.flow<RemoveItem>(
  'removeItem',
  (state, event) => state.copyWith(
    items: state.items.where((i) => i != event.id).toList(),
  ),
);
```

Dispatch synchronously through the `Store`:

```dart
store.dispatch(RemoveItem('sku-123'));
```

`dispatch` fails fast — it throws `StateError` — only when an event type
has **neither** a Flow **nor** an Echo registered. An Echo-only event
(e.g. one that exists purely to drive analytics) doesn't need a no-op Flow
just to be dispatchable.

### Ripple — cancellable async processes

A `RippleBody<S, E>` is `Future<void> Function(E event, StateEmitter<S> emit)`.
It runs async work and streams intermediate states back by calling `emit`
(which is directly callable: `emit(newState)`), inside a `FlowScope`:

```dart
final scope = store.runRipple<CheckoutRequested>(
  (event, emit) async {
    emit(state.copyWith(status: 'paying'));
    final result = await api.charge(event.total);
    emit(state.copyWith(status: result.ok ? 'done' : 'failed'));
  },
  event: CheckoutRequested(42),
);

// Later — e.g. in a widget's dispose():
scope.close(); // cancels the Ripple; any further emit() throws ScopeDeadException
```

`runRipple` is fire-and-forget by design (structured concurrency: you hold
the scope, you don't await the work). When you *do* need to know when a
Ripple's work is actually finished — most commonly in tests, or when
chaining dependent work — use `runRippleAndWait`, which returns a
`Future<FlowScope>` that completes once the Ripple settles:

```dart
final scope = await store.runRippleAndWait<CheckoutRequested>(
  ripple,
  event: CheckoutRequested(42),
);
scope.close();
```

Either way, failures are reported to `onError` handlers, never thrown at
the call site:

```dart
store.onError((error, stackTrace) => log.warning('ripple failed', error));
```

### Echo — read-only side effects

An `EchoBody<S, E>` is `void Function(E event, StateLens<S> lens)`. `lens`
exposes a `state` getter and nothing else — there is no write API for an
Echo to reach for, by construction:

```dart
echos.echo<CheckoutRequested>('analytics', (event, lens) {
  analytics.log('checkout_requested', {'status': lens.state.status});
});
```

Echoes fire whenever their event type is `dispatch`ed — whether or not
that type also has a Flow.

### Combinators: `retry`, `withTimeout`, `debounced`

Each combinator is a pure decorator: `RippleBody<S, E> -> RippleBody<S, E>`.
Compose them freely; none of them require any change to `Store` or
`Feature` (Open/Closed):

```dart
final resilientSync = retry<CounterState, SyncRequested>(
  withTimeout<CounterState, SyncRequested>(
    (event, emit) async { /* ... */ },
    const Duration(seconds: 10),
  ),
  max: 3,
  delay: const Duration(milliseconds: 200),
);

store.runRipple(resilientSync, event: SyncRequested(store.state.value));
```

- `retry(body, {required max, delay})` — retries on any thrown error, up
  to `max` times, with linear backoff of `delay` between attempts.
- `withTimeout(body, limit)` — fails with `TimeoutException` if `body`
  doesn't finish within `limit`.
- `debounced(body, window, {now})` — drops calls that arrive within
  `window` of the last one that actually ran; `now` is an injectable
  clock for deterministic tests.

### Optimistic updates

Commit a new state immediately, then run a Ripple in the background; if
it fails, the store rolls back to the state from before the optimistic
commit:

```dart
store.optimistic(
  optimisticState: state.copyWith(status: 'done'),
  ripple: (event, emit) async => api.confirm(),
  source: 'checkoutOptimistic',
);
```

Both the optimistic commit and — if it happens — the rollback are
recorded in the ledger (`transaction.optimistic == true`, and the
rollback's `source` is `'$source-rollback'`), so you can always see what
actually happened.

### The transaction ledger

Every commit — Flow, Ripple, optimistic, rollback — is appended to
`store.ledger` as a `Transaction<S>`: `source`, `before`, `after`,
`optimistic`, a monotonic `sequence`, and a `timestamp`. This is time-travel
debugging and a devtools observer hook for free:

```dart
final unsubscribe = store.observe((txn) => print(txn));
// ...
unsubscribe();
```

## Testing

`tenet_testing.dart` is a separate entry point so production code (which
only imports `tenet.dart`) never pulls in test-only helpers. It exports
`FeatureHarness`, which drives a `Feature` in isolation:

```dart
import 'package:tenet/tenet.dart';
import 'package:tenet/tenet_testing.dart';
import 'package:test/test.dart';

test('adds an item', () {
  final harness = FeatureHarness(CartFeature());
  harness.dispatch(AddItem('x'));
  expect(harness.state.items, ['x']);
  expect(harness.transactions.map((t) => t.source), ['addItem']);
});

test('checkout Ripple commits paying then done', () async {
  final harness = FeatureHarness(CartFeature());
  await harness.runRipple(checkoutRipple, event: CheckoutRequested(5));
  expect(harness.state.status, 'done');
});
```

`FeatureHarness.runRipple` awaits the Ripple to actual completion
(including any real delays from `retry`/`withTimeout`/`debounced`) via
`Store.runRippleAndWait`, so assertions right after it are never racing
the Ripple's own timers.

See [`test/tenet_test.dart`](test/tenet_test.dart) for the full suite,
covering Flows, Ripple cancellation, Echoes, all three combinators,
optimistic rollback, and the ledger.

## Flutter integration

`tenet` has no Flutter dependency, so wiring a `Store` into widgets is a
few lines with whatever rebuild mechanism you already use. With a plain
`StatefulWidget`:

```dart
class CartPage extends StatefulWidget {
  const CartPage({super.key, required this.store});
  final Store<CartState> store;

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  late final void Function() _unsubscribe;

  @override
  void initState() {
    super.initState();
    _unsubscribe = widget.store.observe((_) => setState(() {}));
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('${widget.store.state.items}');
}
```

Give each screen its own `FlowScope` (`store.rootScope.spawn('cart-page')`)
for any Ripples it starts, and close that scope in `dispose()` so
navigating away cancels in-flight work instead of leaking it.

## Architecture

- **SRP** — `Store` owns state, the ledger, and dispatch, and nothing
  else.
- **OCP** — behaviors (`retry`, `withTimeout`, `debounced`) compose as
  decorators around a Ripple; adding one never means changing `Store` or
  `Feature`.
- **LSP** — every `StateLens`/`StateEmitter` implementation is
  substitutable; Echoes and Ripples never depend on a concrete type.
- **ISP** — `FlowRegistry` and `EchoRegistry` are narrow, separate
  interfaces; Flow authors never see Echo registration and vice versa.
- **DIP** — Ripples depend on the abstract `StateEmitter`, never on a
  concrete store.

## Package layout

```
lib/
  tenet.dart                 # public entry point (barrel export)
  tenet_testing.dart         # test-only entry point (FeatureHarness)
  src/
    core.dart                # Flow, StateEmitter, StateLens, RippleBody, EchoBody
    transaction.dart         # Transaction — the time-travel ledger record
    flow_scope.dart          # FlowScope, ScopeDeadException
    store.dart                # Feature, FlowRegistry, EchoRegistry, Store
    combinators.dart         # retry, withTimeout, debounced
    testing/feature_harness.dart
example/
  tenet_example.dart         # runnable, end-to-end example
test/
  tenet_test.dart            # full test suite
```

## Development

```
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart run example/tenet_example.dart
```

CI (`.github/workflows/ci.yaml`) runs the same four steps on every push
and pull request.

## Versioning and releases

`tenet` follows [Semantic Versioning](https://semver.org/). Every release
is recorded in [`CHANGELOG.md`](CHANGELOG.md). Publishing to pub.dev is
automated by `.github/workflows/publish.yaml`, which runs on version tags
(`v*.*.*`) after the same checks CI runs — see that workflow's header
comment for how to configure the `PUB_CREDENTIALS` secret it needs.

## License

[MIT](LICENSE)
