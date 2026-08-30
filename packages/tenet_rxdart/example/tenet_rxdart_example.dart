// Runnable example for tenet_rxdart.
//
// Run it with:
//   dart run example/tenet_rxdart_example.dart

import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:tenet_rxdart/tenet_rxdart.dart';

/// Requests a (simulated) remote sync of a value.
class SyncRequested {
  final int value;
  const SyncRequested(this.value);
}

class SyncState {
  final int value;
  final String status; // 'idle' | 'syncing' | 'synced'
  const SyncState({this.value = 0, this.status = 'idle'});

  SyncState copyWith({int? value, String? status}) =>
      SyncState(value: value ?? this.value, status: status ?? this.status);

  @override
  String toString() => 'SyncState(value: $value, status: $status)';
}

class SyncFeature extends Feature<SyncState> {
  @override
  SyncState get initial => const SyncState();
}

/// A flaky remote API: fails the first attempt, then succeeds.
final class FlakyRemote {
  var _attempt = 0;
  Future<void> push(int value) async {
    _attempt++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (_attempt < 2) throw Exception('simulated network error');
  }
}

Future<void> main() async {
  final store = Store<SyncState>(SyncFeature());
  final remote = FlakyRemote();
  store.onError((error, _) => print('[error] $error'));

  // -- rxRetry: retry via Rx.retryWhen, same shape as reson's own retry --
  print('== rxRetry ==');
  final resilientSync = rxRetry<SyncState, SyncRequested>(
    (event, emit) async {
      emit(store.state.copyWith(status: 'syncing'));
      await remote.push(event.value);
      emit(store.state.copyWith(value: event.value, status: 'synced'));
    },
    count: 3,
    delay: const Duration(milliseconds: 50),
  );
  await store.runRippleAndWait<SyncRequested>(
    resilientSync,
    event: const SyncRequested(5),
  );
  print('After rxRetry: ${store.state}');

  // -- rxDebounce: debounces a single Ripple's OWN rapid emit() calls,
  // not repeated runRipple/dispatch calls (see StoreRx below for that) --
  print('\n== rxDebounce ==');
  final debouncedProgress = rxDebounce<SyncState, SyncRequested>(
    (event, emit) async {
      // Simulates a chatty progress source emitting faster than anyone
      // downstream should care about — only the value after 30ms of
      // silence should actually reach the store.
      for (var pct = 0; pct <= 100; pct += 25) {
        emit(store.state.copyWith(value: pct, status: 'syncing'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      emit(store.state.copyWith(status: 'synced'));
    },
    const Duration(milliseconds: 30),
  );
  final commits = <int>[];
  final unsubscribe = store.observe((t) => commits.add(t.sequence));
  await store.runRippleAndWait<SyncRequested>(
    debouncedProgress,
    event: const SyncRequested(0),
  );
  unsubscribe();
  print('Progress commits that survived debounce: ${commits.length} of 6 '
      'emit() calls (expected 2: the last "syncing" value, then "synced")');

  // -- StoreRx.dispatchStream: drive dispatch from a Stream<E> built with --
  // -- ordinary rxdart operators, entirely outside reson's own combinators --
  print('\n== StoreRx.dispatchStream ==');
  final controller = StreamController<SyncRequested>();
  final pipeline =
      controller.stream.debounceTime(const Duration(milliseconds: 30));
  final driveScope = store.runRippleStream<SyncRequested>(
    pipeline,
    (event, emit) async =>
        emit(store.state.copyWith(value: event.value, status: 'synced')),
  );
  controller
    ..add(const SyncRequested(1))
    ..add(const SyncRequested(2))
    ..add(const SyncRequested(3));
  await Future<void>.delayed(const Duration(milliseconds: 60));
  print('After debounced pipeline: ${store.state}');
  driveScope.close();
  await controller.close();

  print('\nLedger:');
  for (final txn in store.ledger) {
    print('  $txn');
  }

  store.close();
}
