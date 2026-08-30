import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:tenet_rxdart/tenet_rxdart.dart';
import 'package:test/test.dart';

class Bump {
  const Bump();
}

class CounterFeature extends Feature<int> {
  @override
  int get initial => 0;

  @override
  void registerFlows(FlowRegistry<int> flows) {
    flows.flow<Bump>((s, e) => s + 1, name: 'bump');
  }
}

void main() {
  group('rxTransform', () {
    test('applies an arbitrary stream transform to emissions', () async {
      final store = Store<int>(CounterFeature());
      final doubled = rxTransform<int, Object?>(
        (event, emit) async {
          emit(1);
          emit(2);
        },
        (emissions) => emissions.map((v) => v * 10),
      );

      final seen = <int>[];
      store.observe((t) => seen.add(t.after));
      await store.runRippleAndWait<Object?>(doubled, event: null);

      expect(seen, [10, 20]);
      store.close();
    });

    test('waits for a delayed transform to drain before returning', () async {
      final store = Store<int>(CounterFeature());
      final delayed = rxTransform<int, Object?>(
        (event, emit) async => emit(1),
        (emissions) => emissions.asyncMap((v) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return v;
        }),
      );

      final stopwatch = Stopwatch()..start();
      await store.runRippleAndWait<Object?>(delayed, event: null);
      stopwatch.stop();

      expect(store.state, 1);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(35));
      store.close();
    });

    test('rethrows body\'s own error after the transform drains', () async {
      final store = Store<int>(CounterFeature());
      final errors = <Object>[];
      store.onError((e, _) => errors.add(e));

      final failing = rxTransform<int, Object?>(
        (event, emit) async {
          emit(1);
          throw StateError('boom');
        },
        (emissions) => emissions,
      );

      await store.runRippleAndWait<Object?>(failing, event: null);
      expect(store.state, 1, reason: 'the emission before the throw lands');
      expect(errors.single, isA<StateError>());
      store.close();
    });
  });

  group('rxThrottle', () {
    test('drops emissions within the window (leading edge, default)', () async {
      final store = Store<int>(CounterFeature());
      final seen = <int>[];
      store.observe((t) => seen.add(t.after));

      final throttled = rxThrottle<int, Object?>(
        (event, emit) async {
          emit(1);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          emit(2); // inside the 100ms window -> dropped by default
        },
        const Duration(milliseconds: 100),
      );

      await store.runRippleAndWait<Object?>(throttled, event: null);
      expect(seen, [1]);
      store.close();
    });

    test('trailing: true also emits the last value in the window', () async {
      final store = Store<int>(CounterFeature());
      final seen = <int>[];
      store.observe((t) => seen.add(t.after));

      final throttled = rxThrottle<int, Object?>(
        (event, emit) async {
          emit(1);
          emit(2);
        },
        const Duration(milliseconds: 30),
        trailing: true,
      );

      await store.runRippleAndWait<Object?>(throttled, event: null);
      expect(seen, [1, 2]);
      store.close();
    });
  });

  group('rxDebounce', () {
    test('only the last value in a burst survives', () async {
      final store = Store<int>(CounterFeature());
      final seen = <int>[];
      store.observe((t) => seen.add(t.after));

      final debounced = rxDebounce<int, Object?>(
        (event, emit) async {
          emit(1);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          emit(2);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          emit(3);
        },
        const Duration(milliseconds: 30),
      );

      await store.runRippleAndWait<Object?>(debounced, event: null);
      expect(seen, [3], reason: 'debounce waits for silence, unlike throttle');
      store.close();
    });

    test('two well-separated values both survive', () async {
      final store = Store<int>(CounterFeature());
      final seen = <int>[];
      store.observe((t) => seen.add(t.after));

      final debounced = rxDebounce<int, Object?>(
        (event, emit) async {
          emit(1);
          await Future<void>.delayed(const Duration(milliseconds: 60));
          emit(2);
        },
        const Duration(milliseconds: 20),
      );

      await store.runRippleAndWait<Object?>(debounced, event: null);
      expect(seen, [1, 2]);
      store.close();
    });
  });

  group('rxRetry', () {
    test('retries transient failures up to count times', () async {
      final store = Store<int>(CounterFeature());
      var attempts = 0;
      final flaky = rxRetry<int, Object?>(
        (event, emit) async {
          attempts++;
          if (attempts < 3) throw Exception('transient');
          emit(7);
        },
        count: 3,
      );

      await store.runRippleAndWait<Object?>(flaky, event: null);
      expect(attempts, 3);
      expect(store.state, 7);
      store.close();
    });

    test('gives up after exhausting count and reports the last error',
        () async {
      final store = Store<int>(CounterFeature());
      var attempts = 0;
      final errors = <Object>[];
      store.onError((e, _) => errors.add(e));

      final alwaysFails = rxRetry<int, Object?>(
        (event, emit) async {
          attempts++;
          throw Exception('attempt $attempts');
        },
        count: 2,
      );

      await store.runRippleAndWait<Object?>(alwaysFails, event: null);
      expect(attempts, 3, reason: '1 initial + 2 retries');
      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains('attempt 3'));
      store.close();
    });

    test('never retries a Ripple whose scope was cancelled', () async {
      final store = Store<int>(CounterFeature());
      store.onError((_, __) {});
      var attempts = 0;

      final scope = store.rootScope.spawn('doomed');
      scope.close();

      final body = rxRetry<int, Object?>(
        (event, emit) async {
          attempts++;
          emit(1); // throws ScopeDeadException: the scope is already dead
        },
        count: 5,
      );

      await store.runRippleAndWait<Object?>(body, event: null, scope: scope);
      expect(attempts, 1, reason: 'cancellation is terminal, not transient');
      store.close();
    });

    test('honors a fixed delay between attempts', () async {
      final store = Store<int>(CounterFeature());
      var attempts = 0;
      final flaky = rxRetry<int, Object?>(
        (event, emit) async {
          attempts++;
          if (attempts < 2) throw Exception('transient');
          emit(1);
        },
        count: 3,
        delay: const Duration(milliseconds: 40),
      );

      final stopwatch = Stopwatch()..start();
      await store.runRippleAndWait<Object?>(flaky, event: null);
      stopwatch.stop();

      expect(attempts, 2);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(35));
      store.close();
    });
  });

  group('rxRetryWhen', () {
    test('gives full control over the retry decision', () async {
      final store = Store<int>(CounterFeature());
      var attempts = 0;
      final custom = rxRetryWhen<int, Object?>(
        (event, emit) async {
          attempts++;
          if (attempts < 4) throw Exception('retry me');
          emit(9);
        },
        (error, stackTrace) => attempts < 4
            ? Stream<void>.value(null)
            : Stream<void>.error(error, stackTrace),
      );

      await store.runRippleAndWait<Object?>(custom, event: null);
      expect(attempts, 4);
      expect(store.state, 9);
      store.close();
    });
  });

  group('StoreRx.dispatchStream', () {
    test('dispatches every event from the stream', () async {
      final store = Store<int>(CounterFeature());
      final controller = StreamController<Bump>();

      final scope = store.dispatchStream<Bump>(controller.stream);

      controller.add(const Bump());
      controller.add(const Bump());
      await Future<void>.delayed(Duration.zero);

      expect(store.state, 2);
      scope.close();
      await controller.close();
      store.close();
    });

    test('stops dispatching once the returned scope closes', () async {
      final store = Store<int>(CounterFeature());
      final controller = StreamController<Bump>();

      final scope = store.dispatchStream<Bump>(controller.stream);
      controller.add(const Bump());
      await Future<void>.delayed(Duration.zero);
      expect(store.state, 1);

      scope.close();
      controller.add(const Bump());
      await Future<void>.delayed(Duration.zero);
      expect(store.state, 1, reason: 'no longer listening after scope.close()');

      await controller.close();
      store.close();
    });

    test('an rx-transformed stream (debounced) still drives the store',
        () async {
      final store = Store<int>(CounterFeature());
      final controller = StreamController<Bump>();
      final debounced =
          controller.stream.debounceTime(const Duration(milliseconds: 30));

      final scope = store.dispatchStream<Bump>(debounced);

      controller.add(const Bump());
      controller.add(const Bump());
      controller.add(const Bump());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(store.state, 1, reason: 'debounce collapsed the burst to one');

      scope.close();
      await controller.close();
      store.close();
    });
  });

  group('StoreRx.runRippleStream', () {
    test('runs a Ripple for each stream value', () async {
      final store = Store<int>(CounterFeature());
      final controller = StreamController<int>();

      final scope = store.runRippleStream<int>(
        controller.stream,
        (n, emit) async => emit(n * 100),
      );

      controller.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(store.state, 100);

      controller.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(store.state, 200);

      scope.close();
      await controller.close();
      store.close();
    });
  });
}
