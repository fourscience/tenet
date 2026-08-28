// Runnable example for the `tenet` package.
//
// Demonstrates all four Tenet concepts against a small "counter with
// remote sync" feature:
//   * Flow      — `Increment` bumps the counter purely and synchronously.
//   * Ripple    — `SyncRequested` pushes the counter to a simulated remote
//                 service, wrapped in the `retry` and `withTimeout`
//                 combinators.
//   * Echo      — every event is logged to an audit trail, read-only.
//   * Optimistic — `store.optimistic` commits a new value immediately and
//                 rolls back automatically if the Ripple fails.
//
// Run it with:
//   dart run example/tenet_example.dart

import 'dart:async';

import 'package:tenet/tenet.dart';

/// Bumps the counter by [amount]. Handled by a Flow.
class Increment {
  final int amount;
  const Increment(this.amount);
}

/// Requests a (simulated) remote sync of the current counter value.
/// Handled by a Ripple.
class SyncRequested {
  final int value;
  const SyncRequested(this.value);
}

/// State for the counter feature.
class CounterState {
  final int value;

  /// 'synced' | 'syncing' | 'failed'
  final String syncStatus;

  const CounterState({this.value = 0, this.syncStatus = 'synced'});

  CounterState copyWith({int? value, String? syncStatus}) => CounterState(
        value: value ?? this.value,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  @override
  String toString() => 'CounterState(value: $value, syncStatus: $syncStatus)';
}

/// Wires a Flow, a Ripple and two Echoes around [CounterState].
class CounterFeature extends Feature<CounterState> {
  @override
  CounterState get initial => const CounterState();

  @override
  void registerFlows(FlowRegistry<CounterState> flows) {
    flows.flow<Increment>(
      (state, event) => state.copyWith(value: state.value + event.amount),
      name: 'increment',
    );
  }

  @override
  void registerEchos(EchoRegistry<CounterState> echos) {
    echos.echo<Increment>((event, lens) {
      print('[audit] +${event.amount} -> ${lens.state.value}');
    }, name: 'audit');
    echos.echo<SyncRequested>((event, lens) {
      print('[audit] sync requested for value ${event.value}');
    }, name: 'audit');
  }
}

/// A deliberately flaky remote API: fails the first two attempts, then
/// succeeds — enough to exercise the `retry` combinator below.
final class FlakyRemote {
  var _attempt = 0;

  Future<void> push(int value) async {
    _attempt++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_attempt < 3) {
      throw Exception('simulated network error (attempt $_attempt)');
    }
  }
}

Future<void> main() async {
  final store = Store<CounterState>(CounterFeature());
  final remote = FlakyRemote();

  store.onError((error, stackTrace) => print('[error] $error'));

  // -- Flow: pure, synchronous transitions ----------------------------------
  store.dispatch(const Increment(1));
  store.dispatch(const Increment(4));
  print('After Flows: ${store.state}');

  // -- Ripple: async work, decorated with retry + a timeout -----------------
  // Combinators compose without touching Store or Feature (OCP).
  final syncRipple = retry<CounterState, SyncRequested>(
    withTimeout<CounterState, SyncRequested>((event, emit) async {
      emit(store.state.copyWith(syncStatus: 'syncing'));
      await remote.push(event.value);
      emit(store.state.copyWith(syncStatus: 'synced'));
    }, const Duration(seconds: 2)),
    max: 3,
    delay: const Duration(milliseconds: 100),
  );

  // Echoes only ever fire through `dispatch` — never through `runRipple` —
  // so dispatching the event first is what drives the audit Echo above.
  // `SyncRequested` has an Echo but no Flow registered, and that alone is
  // enough for `dispatch` to accept it (see "fail fast" in the README).
  final syncEvent = SyncRequested(store.state.value);
  store.dispatch(syncEvent);
  final scope = await store.runRippleAndWait<SyncRequested>(
    syncRipple,
    event: syncEvent,
  );
  scope.close();
  print('After Ripple: ${store.state}');

  // -- Optimistic update: commit instantly, roll back on failure ------------
  // `optimistic` is intentionally fire-and-forget, so a short delay here
  // gives its rollback time to land before we print the final state.
  store.optimistic(
    optimisticState: store.state.copyWith(value: store.state.value + 100),
    ripple: (event, emit) async {
      throw Exception('server rejected the optimistic update');
    },
    source: 'optimisticBump',
  );
  await Future<void>.delayed(const Duration(milliseconds: 50));
  print('After optimistic rollback: ${store.state}');

  // -- Ledger: full time-trail with monotonic sequences, for free -----------
  print('\nLedger:');
  for (final txn in store.ledger) {
    print('  $txn');
  }

  store.close();
}
