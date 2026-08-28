# flow_state

A time-aware, effect-separated state management library for Dart and Flutter.

Core mental model, one sentence: **state is now, Flows change it purely,
Ripples fetch it asynchronously, Echoes react to it externally.**

Every piece of feature logic is exactly one of:

- **State** — a value that exists now.
- **Flow** — a pure, synchronous function `(State, Event) -> State`.
- **Ripple** — an async, cancellable process that commits typed states.
- **Echo** — a side-effect listener that may *read* state, never write it.

## Design principles

- **SRP** — `Store` owns state, the ledger, and dispatch, and nothing else.
- **OCP** — behaviors (`retry`, `withTimeout`, `debounced`) compose as
  decorators around a Ripple; no subclassing, no changes to `Store`.
- **LSP** — every `StateLens`/`StateEmitter` implementation is
  substitutable.
- **ISP** — `FlowRegistry` and `EchoRegistry` are narrow, separate
  interfaces; Flow authors never see Echo registration and vice versa.
- **DIP** — Ripples depend on the abstract `StateEmitter`, never on a
  concrete store.

## Package layout

```
lib/
  flow_state.dart            # public entry point (barrel export)
  flow_state_testing.dart    # test-only entry point (FeatureHarness)
  src/
    core.dart                # Flow, StateEmitter, StateLens, RippleBody, EchoBody
    transaction.dart         # Transaction — the time-travel ledger record
    flow_scope.dart          # FlowScope, ScopeDeadException
    store.dart                # Feature, FlowRegistry, EchoRegistry, Store
    combinators.dart         # retry, withTimeout, debounced
    testing/feature_harness.dart
```

`flow_state_testing.dart` is a separate entry point on purpose: production
code only imports `flow_state.dart`, so the test harness never ships in an
app bundle.

## Usage

```dart
import 'package:flow_state/flow_state.dart';

class AddItem {
  final String item;
  AddItem(this.item);
}

class CartState {
  final List<String> items;
  CartState([List<String>? items]) : items = List.unmodifiable(items ?? const []);
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

A Ripple runs async work and streams intermediate states back through a
[StateEmitter], inside a cancellable [FlowScope]:

```dart
store.runRipple<CheckoutRequested>(
  retry(
    withTimeout((event, emit) async {
      emit(state.copyWith(status: 'paying'));
      final result = await api.charge(event.total);
      emit(state.copyWith(status: result.ok ? 'done' : 'failed'));
    }, const Duration(seconds: 10)),
    max: 3,
  ),
  event: CheckoutRequested(42),
);
```

## Testing

```dart
import 'package:flow_state/flow_state.dart';
import 'package:flow_state/flow_state_testing.dart';
import 'package:test/test.dart';

test('adds an item', () {
  final harness = FeatureHarness(CartFeature());
  harness.dispatch(AddItem('x'));
  expect(harness.state.items, ['x']);
  expect(harness.transactions.map((t) => t.source), ['addItem']);
});
```

See `test/flow_state_test.dart` for the full test suite, which exercises
Flows, Ripples (including cancellation), Echoes, the `retry`/`withTimeout`/
`debounced` combinators, optimistic updates with rollback, and the
transaction ledger.

## Development

```
dart pub get
dart analyze
dart test
```
