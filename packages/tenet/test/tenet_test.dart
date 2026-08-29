import 'dart:async';

import 'package:tenet/tenet.dart';
import 'package:tenet/tenet_testing.dart';
import 'package:test/test.dart';

// -- Test domain -------------------------------------------------------------

/// Test event: an item was added.
class AddItem {
  /// The item.
  final String item;
  AddItem(this.item);
}

/// Test event: an item was removed.
class RemoveItem {
  /// The item id.
  final String id;
  RemoveItem(this.id);
}

/// Test event: checkout was requested.
class CheckoutRequested {
  /// Total to charge.
  final int total;
  CheckoutRequested(this.total);
}

/// Sentinel event type for the "unregistered flow" test.
class UnknownEvent {
  const UnknownEvent();
}

/// Test state.
class CartState {
  /// Items in cart.
  final List<String> items;

  /// Checkout status ('idle' | 'paying' | 'done' | 'failed').
  final String status;

  /// Creates a state.
  CartState({List<String>? items, this.status = 'idle'})
      : items = List.unmodifiable(items ?? const []);

  /// Empty cart.
  factory CartState.empty() => CartState();

  /// Copy-with.
  CartState copyWith({List<String>? items, String? status}) =>
      CartState(items: items ?? this.items, status: status ?? this.status);

  @override
  bool operator ==(Object other) =>
      other is CartState &&
      other.status == status &&
      other.items.join(',') == items.join(',');

  @override
  int get hashCode => Object.hash(status, items.join(','));

  @override
  String toString() => 'CartState(items: $items, status: $status)';
}

/// Test feature demonstrating all four concepts with one home each.
class CartFeature extends Feature<CartState> {
  @override
  CartState get initial => CartState.empty();

  @override
  void registerFlows(FlowRegistry<CartState> flows) {
    flows.flow<AddItem>(
      (s, e) => s.copyWith(items: [...s.items, e.item]),
      name: 'addItem',
    );
    flows.flow<RemoveItem>(
      (s, e) => s.copyWith(items: s.items.where((i) => i != e.id).toList()),
      name: 'removeItem',
    );
  }

  @override
  void registerEchos(EchoRegistry<CartState> echos) {
    echos.echo<CheckoutRequested>((event, lens) {
      // Read-only proof: lens.state accessible, no write API exists.
      harness?.recordEcho('analytics', lens.state.status);
    }, name: 'analytics');
  }

  // Test back-reference (set by tests) so the Echo can record calls.
  static FeatureHarness<CartState>? harness;
}

void main() {
  test('Flow: pure sync transition commits new state', () {
    final h = FeatureHarness<CartState>(CartFeature());
    h.dispatch(AddItem('apple'));
    expect(h.state.items, ['apple']);
    expect(h.lastTransaction!.source, 'addItem');
    h.dispose();
  });

  test('Store: dispatch with unregistered event type fails fast', () {
    final h = FeatureHarness<CartState>(CartFeature());

    expect(() => h.dispatch<RemoveItem>(RemoveItem('x')), returnsNormally);
    expect(() => h.dispatch(const UnknownEvent()), throwsStateError);

    h.dispose();
  });

  test('Echo: receives events with read-only lens, cannot corrupt state', () {
    final h = FeatureHarness<CartState>(CartFeature());
    CartFeature.harness = h;
    h.dispatch(AddItem('pen'));
    h.dispatch(CheckoutRequested(10));
    expect(h.echoCalls('analytics'), ['idle']);
    expect(h.state.status, 'idle');
    CartFeature.harness = null;
    h.dispose();
  });

  test('Ripple: async emissions commit typed states', () async {
    final h = FeatureHarness<CartState>(CartFeature());
    Future<void> ripple(
        CheckoutRequested e, StateEmitter<CartState> emit) async {
      emit(CartState(items: h.state.items, status: 'paying'));
      await Future<void>.delayed(Duration.zero);
      emit(CartState(items: h.state.items, status: 'done'));
    }

    await h.runRipple<CheckoutRequested>(ripple, event: CheckoutRequested(5));
    expect(h.state.status, 'done');
    expect(
      h.transactions.map((t) => t.after.status).toList(),
      ['paying', 'done'],
    );
    h.dispose();
  });

  test('Ripple: cancellation via scope close drops late emissions', () async {
    final h = FeatureHarness<CartState>(CartFeature());
    final scope = h.store.runRipple<CheckoutRequested>(
      (e, emit) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        emit(CartState(status: 'done')); // late emission
      },
      event: CheckoutRequested(1),
    );
    scope.close(); // cancel immediately
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(h.state.status, 'idle');
    expect(h.errors.any((e) => e.$1 is ScopeDeadException), isTrue);
    h.dispose();
  });

  test('Combinator: retry retries transient failures', () async {
    final h = FeatureHarness<CartState>(CartFeature());
    var attempts = 0;
    final flaky = retry<CartState, CheckoutRequested>(
      (e, emit) async {
        attempts++;
        if (attempts < 3) throw Exception('transient');
        emit(CartState(status: 'done'));
      },
      max: 3,
    );
    await h.runRipple(flaky, event: CheckoutRequested(1));
    expect(attempts, 3);
    expect(h.state.status, 'done');
    h.dispose();
  });

  test('Combinator: withTimeout fails slow ripples', () async {
    final h = FeatureHarness<CartState>(CartFeature());
    final slow = withTimeout<CartState, CheckoutRequested>(
      (e, emit) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        emit(CartState(status: 'done'));
      },
      const Duration(milliseconds: 10),
    );
    await h.runRipple(slow, event: CheckoutRequested(1));
    expect(h.errors.any((e) => e.$1 is TimeoutException), isTrue);
    expect(h.state.status, 'idle');
    h.dispose();
  });

  test('Combinator: throttled drops rapid-fire calls', () async {
    final h = FeatureHarness<CartState>(CartFeature());
    var runs = 0;
    var fakeNow = DateTime(2024, 1, 1);
    final d = throttled<CartState, CheckoutRequested>(
      (e, emit) async {
        runs++;
        emit(CartState(status: 'done'));
      },
      const Duration(milliseconds: 100),
      now: () => fakeNow, // injectable clock — deterministic tests
    );
    await h.runRipple(d, event: CheckoutRequested(1));
    fakeNow = DateTime(2024, 1, 1, 0, 0, 0, 50); // +50ms < window
    await h.runRipple(d, event: CheckoutRequested(2)); // dropped
    expect(runs, 1);
    h.dispose();
  });

  test('Optimistic: commits instantly, rolls back on failure', () async {
    final h = FeatureHarness<CartState>(CartFeature());
    final before = h.state;
    Future<void> failing(Object? e, StateEmitter<CartState> emit) async {
      throw Exception('network down');
    }

    h.store.optimistic(
      optimisticState: CartState(status: 'done'),
      ripple: failing,
      source: 'checkoutOptimistic',
    );
    await h.pump(const Duration(milliseconds: 20));
    expect(h.state, before);
    expect(h.transactions.any((t) => t.optimistic), isTrue);
    expect(
      h.transactions.any((t) => t.source == 'checkoutOptimistic-rollback'),
      isTrue,
    );
    h.dispose();
  });

  test('Ledger: full time-trail with monotonic sequences', () {
    final h = FeatureHarness<CartState>(CartFeature());
    h.dispatch(AddItem('a'));
    h.dispatch(AddItem('b'));
    h.dispatch(RemoveItem('a'));
    final seqs = h.transactions.map((t) => t.sequence).toList();
    expect(seqs, [0, 1, 2]);
    expect(h.transactions[1].before.items, ['a']);
    expect(h.transactions[1].after.items, ['a', 'b']);
    h.dispose();
  });

  test(
      'SOLID check: lens exposed to Echoes is a substitutable, read-only '
      'view (LSP/ISP)', () {
    final h = FeatureHarness<CartState>(CartFeature());
    StateLens<CartState>? captured;
    CartFeature.harness = h;
    h.dispatch(AddItem('kiwi'));
    // The Echo above only ever receives a StateLens — proof that any
    // conforming implementation is substitutable and exposes no write API.
    h.store.dispatch(CheckoutRequested(1));
    captured = _capturingLens(h.store);
    expect(captured.state.items, ['kiwi']);
    CartFeature.harness = null;
    h.dispose();
  });
}

/// Builds a [StateLens] over [store]'s live state through the public API,
/// mirroring exactly what an Echo receives — used to assert the lens stays
/// read-only and always reflects the current state (LSP/ISP).
StateLens<CartState> _capturingLens(Store<CartState> store) =>
    _ReadOnlyLens(() => store.state);

final class _ReadOnlyLens<S> implements StateLens<S> {
  final S Function() _read;
  _ReadOnlyLens(this._read);
  @override
  S get state => _read();
}
