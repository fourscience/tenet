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
  - [Combinators: retry, withTimeout, throttled](#combinators-retry-withtimeout-throttled)
  - [Optimistic updates](#optimistic-updates)
  - [The transaction ledger](#the-transaction-ledger)
- [Dispatch taxonomy: Intent, Command, Event](#dispatch-taxonomy-intent-command-event)
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
- **Composable Ripple behavior** — `retry`, `withTimeout`, and `throttled`
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
- **An optional Intent/Command/Event taxonomy** — for features where
  `dispatch`'s one-type-plays-every-role model gets ambiguous, `send` +
  `Intent` + `Command` split "what triggered this", "what's allowed to
  write", and "what happened" into three separate types instead. See
  [Dispatch taxonomy](#dispatch-taxonomy-intent-command-event).

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
      (state, event) => CartState([...state.items, event.item]),
      name: 'addItem',
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
  (state, event) => state.copyWith(
    items: state.items.where((i) => i != event.id).toList(),
  ),
  name: 'removeItem',
);
```

`name` becomes the ledger transaction's `source` — see
[The transaction ledger](#the-transaction-ledger) — and defaults to `E`'s
type name (`'RemoveItem'` here) if you don't pass one.

Dispatch synchronously through the `Store`:

```dart
store.dispatch(RemoveItem('sku-123'));
```

`dispatch` fails fast — it throws `StateError` — only when an event has
**neither** a Flow **nor** an Echo registered. An Echo-only event (e.g.
one that exists purely to drive analytics) doesn't need a no-op Flow just
to be dispatchable.

Routing follows the event's **runtime** type, never the static type at the
call site — the same rule `send` and `publish` use. Passing an event
through a variable or generic wrapper that widens its static type still
reaches the Flow and Echoes it was registered against, instead of quietly
matching nothing.

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

With no handler registered, failures go to the current `Zone`'s
uncaught-error handler instead — the same place an unawaited future's
error lands, which in Flutter means the console and `FlutterError.onError`.
A Ripple or Echo that throws is never silently swallowed.

A Ripple's `emit` is only live while the Ripple itself is: once its future
settles, a later emission from work that outlived it is dropped and
reported rather than committed. That is what keeps a `withTimeout` body
that keeps running past its timeout from writing state the store already
considers settled — see [Combinators](#combinators-retry-withtimeout-throttled).

### Echo — read-only side effects

An `EchoBody<S, E>` is `void Function(E event, StateLens<S> lens)`. `lens`
exposes a `state` getter and nothing else — there is no write API for an
Echo to reach for, by construction:

```dart
echos.echo<CheckoutRequested>((event, lens) {
  analytics.log('checkout_requested', {'status': lens.state.status});
}, name: 'analytics');
```

`name` is optional here too, defaulting to `E`'s type name.

Echoes fire whenever a matching event is `dispatch`ed or `publish`ed —
whether or not that type also has a Flow. Matching is by "is the event an
`E`?", so an Echo registered for a supertype receives every subtype, and
`echo<Event>(...)` is a legitimate catch-all audit hook.

An Echo that throws never takes down the dispatch that triggered it: the
error goes to `onError` (or the `Zone`, if none is registered) and the
remaining Echoes still run. Register `store.onEchoError((name, error,
stackTrace) => ...)` alongside `onError` when you need to know *which*
Echo failed — that's exactly the `name` from registration, so a log line
or crash report can say `'analytics' failed` instead of just `Exception`.

### Combinators: `retry`, `withTimeout`, `throttled`

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

- `retry(body, {required max, delay})` — retries on a thrown error, up to
  `max` times (so `body` runs at most `max + 1` times), waiting `delay`
  between attempts. A `ScopeDeadException` is never retried: the scope was
  cancelled, so every further attempt would do real work only to fail the
  same way.
- `withTimeout(body, limit)` — fails with `TimeoutException` if `body`
  doesn't finish within `limit`. Dart cannot abort a future, so `body`
  itself keeps running — but it can no longer change state, since the
  store settles the Ripple's emitter when the timeout fires. Give `body` a
  real cancellation path (race `scope.cancelled`, close the `HttpClient`)
  if the work itself must stop, not just its effect on state.
- `throttled(body, window, {now})` — a call runs immediately, then any
  further call within `window` of the last one that actually ran is
  dropped; `now` is an injectable clock for deterministic tests. This is a
  throttle, not a debounce: it never delays a call to wait for input to
  settle, it only rate-limits how often `body` can run.

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

The ledger keeps the most recent 1000 transactions by default and drops
the oldest beyond that — an in-memory list that only grows is a slow leak
in a long-lived process. `sequence` keeps counting from the very first
commit regardless, so a trimmed ledger still tells you how much history
came before it:

```dart
Store<CartState>(CartFeature(), ledgerLimit: 200);   // keep less
Store<CartState>(CartFeature(), ledgerLimit: null);  // keep everything
```

### Closing a store

`store.close()` cancels every Ripple (by closing `rootScope`), drops every
ledger observer and error handler, and refuses any further
`dispatch`/`send`/`execute`/`publish` with a `StateError` — a closed store
is done, not merely quiet. `state` and `ledger` stay readable; closing
ends a store's writes, it doesn't erase its history. Starting a Ripple on
a closed store is reported through the usual error path rather than
thrown, since `runRipple` never throws at its call site.

## Dispatch taxonomy: Intent, Command, Event

`dispatch` (above) is enough for a feature where one event type driving a
Flow and/or an Echo is unambiguous. Some features outgrow that: the same
dispatched object ends up meaning both "the user asked for X" and "X is
what happened", and a widget can just as easily call `dispatch` as any
internal code can. `Intent`, `Command`, and `Event` split that back apart
into three sealed, purpose-built types — a `sealed class Dispatch` with
`Intent`, `Command<S>`, and `Event` as its only direct subtypes, each
still open for you to extend:

| Type | Direction | Meaning | Entry point |
|---|---|---|---|
| `Intent` | In, from outside (UI, another feature) | "Do this." The only thing a screen should send. | `store.send(intent)` |
| `Command<S>` | Internal only | "Set state to exactly this." The only legal write besides a Flow. | `store.execute(command)` |
| `Event` | Out, broadcast only | "This happened." Never changes state. | `store.publish(event)` |

An `Intent` is routed to a registered `IntentHandler`, which receives a
narrow `IntentContext<S>` — `execute`, `launch`, `publish`, and a
read-only `state` getter, nothing else (ISP: no direct state mutation):

```dart
class Increment extends Intent {
  const Increment();
}

class SetCount extends Command<CounterState> {
  final int value;
  const SetCount(this.value);

  @override
  String get name => 'setCount'; // ledger source; defaults to this already

  @override
  CounterState reduce(CounterState state) => CounterState(value: value);
}

class CounterFeature extends Feature<CounterState> {
  @override
  CounterState get initial => const CounterState();

  @override
  void registerIntents(IntentRegistry<CounterState> intents) {
    intents.on<Increment>((intent, ctx) {
      ctx.execute(SetCount(ctx.state.value + 1));
    });
  }
}

store.send(const Increment());
```

`IntentContext.launch` starts a Ripple exactly like `Store.runRipple`
does (same fire-and-forget contract, same `FlowScope` for lifetime
control) — the difference is what the Ripple can do with it. Because the
Ripple body can capture its handler's `ctx` by closure, it can call
`ctx.execute(...)` *after an await*, not just emit raw state through
`StateEmitter`:

```dart
intents.on<LogIn>((intent, ctx) {
  ctx.execute(const SetSessionStatus(status: 'authenticating'));
  ctx.launch((event, emit) async {
    await authApi.signIn(intent.username);
    ctx.execute(SetSessionStatus(username: intent.username, status: 'signedIn'));
    ctx.publish(SessionStarted(intent.username));
  }, source: 'authenticate');
});
```

Every commit — from a Flow, a Ripple emission, an optimistic commit or
rollback, or an executed Command alike — automatically publishes a
built-in `EventCommitted(source)` to Echoes, so "something in my state
changed" never needs per-source wiring:

```dart
echos.echo<EventCommitted>((event, lens) {
  log('commit from ${event.source} -> ${lens.state}');
}, name: 'devtools');
```

A full, runnable walkthrough — Intent, two Commands (one executed
synchronously, one from inside a Ripple after an await), a custom
`Event`, and the automatic `EventCommitted` — lives in
[`example/intent_command_event_example.dart`](example/intent_command_event_example.dart):

```
dart run example/intent_command_event_example.dart
```

This taxonomy is additive, not a replacement: `dispatch`/`FlowRegistry`
remain fully supported for features that don't need the extra
separation, and both can be used side by side in the same `Feature`.

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
(including any real delays from `retry`/`withTimeout`/`throttled`) via
`Store.runRippleAndWait`, so assertions right after it are never racing
the Ripple's own timers.

Asserting that an Echo fired needs no cooperation from the `Feature`
itself — no test-only field, no back-reference to the harness. Give the
Echo a `name` (as you'd want to anyway, for error reports) and read it
back through `harness.echoCalls(name)`, built entirely on
`Store.observeEchos`:

```dart
final harness = FeatureHarness(CartFeature());
harness.dispatch(AddItem('x'));
harness.dispatch(CheckoutRequested(10));

final calls = harness.echoCalls('analytics'); // List<EchoCall<CartState>>
expect(calls, hasLength(1));
expect(calls.single.event, isA<CheckoutRequested>());
expect(calls.single.state.status, 'idle'); // a snapshot at the moment it fired
```

See [`test/tenet_test.dart`](test/tenet_test.dart) for the Flow/Ripple/Echo
suite — Flows, Ripple cancellation, Echoes, all three combinators,
optimistic rollback, and the ledger — and
[`test/intent_command_event_test.dart`](test/intent_command_event_test.dart)
for the Intent/Command/Event suite, including the closure-captured-`ctx`
pattern above.

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
- **OCP** — behaviors (`retry`, `withTimeout`, `throttled`) compose as
  decorators around a Ripple; adding one never means changing `Store` or
  `Feature`.
- **LSP** — every `StateLens`/`StateEmitter` implementation is
  substitutable; Echoes and Ripples never depend on a concrete type.
- **ISP** — `FlowRegistry`, `EchoRegistry`, and `IntentRegistry` are
  narrow, separate registration interfaces; an `IntentContext` exposes
  only `execute`/`launch`/`publish`/`state` — no direct mutation.
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
    dispatch.dart            # Intent, Command, Event, EventCommitted
    store.dart                # Feature, FlowRegistry, EchoRegistry, IntentRegistry, Store
    combinators.dart         # retry, withTimeout, throttled
    testing/feature_harness.dart
example/
  tenet_example.dart                    # Flow/Ripple/Echo, end-to-end
  intent_command_event_example.dart     # Intent/Command/Event, end-to-end
test/
  tenet_test.dart                  # Flow/Ripple/Echo suite
  intent_command_event_test.dart   # Intent/Command/Event suite
```

## Development

```
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
dart run example/tenet_example.dart
dart run example/intent_command_event_example.dart
```

CI (`.github/workflows/ci.yaml`) runs the same checks on every push and
pull request.

## Versioning and releases

`tenet` follows [Semantic Versioning](https://semver.org/). Every release
is recorded in [`CHANGELOG.md`](CHANGELOG.md). Publishing to pub.dev is
automated by `.github/workflows/publish.yaml`, which runs on version tags
(`v*.*.*`) after the same checks CI runs — see that workflow's header
comment for how to configure the `PUB_CREDENTIALS` secret it needs.

## License

[MIT](LICENSE)
