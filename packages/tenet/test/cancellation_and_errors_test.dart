// Regression tests for the cancellation / error-reporting guarantees:
// every test here fails against the behavior that shipped in 0.3.0.
import 'dart:async';

import 'package:tenet/tenet.dart';
import 'package:test/test.dart';

// -- Test domain --------------------------------------------------------

class Bump {
  const Bump();
}

class Unregistered {
  const Unregistered();
}

class Noticed extends Event {
  const Noticed();
}

class AlsoNoticed extends Event {
  const AlsoNoticed();
}

/// Records every event each named Echo saw, without the feature needing a
/// back-reference to a test harness.
final List<(String, Object?)> echoLog = [];

class CounterFeature extends Feature<int> {
  @override
  int get initial => 0;

  @override
  void registerFlows(FlowRegistry<int> flows) {
    flows.flow<Bump>((s, e) => s + 1, name: 'bump');
  }

  @override
  void registerEchos(EchoRegistry<int> echos) {
    echos.echo<Noticed>((e, lens) => echoLog.add(('noticed', e)));
    // A deliberate catch-all: every Event, whatever its concrete type.
    echos.echo<Event>((e, lens) => echoLog.add(('any-event', e)));
  }
}

/// A feature whose only Echo throws, for the error-reporting tests.
class ThrowingEchoFeature extends Feature<int> {
  @override
  int get initial => 0;

  @override
  void registerEchos(EchoRegistry<int> echos) {
    echos.echo<Noticed>((e, lens) => throw StateError('echo blew up'));
  }
}

void main() {
  setUp(echoLog.clear);

  group('late emissions', () {
    test('a withTimeout body that outlives its timeout cannot commit', () {
      // The timeout fires at 10ms; the body emits at 60ms. That emission
      // must be dropped, not committed over state the store already
      // considers settled.
      return fakeAsyncish(() async {
        final store = Store<int>(CounterFeature());
        final errors = <Object>[];
        store.onError((e, _) => errors.add(e));

        final slow = withTimeout<int, Object?>((event, emit) async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          emit(1234);
        }, const Duration(milliseconds: 10));

        await store.runRippleAndWait<Object?>(slow, event: null);
        expect(store.state, 0, reason: 'timed out before emitting');
        expect(errors.single, isA<TimeoutException>());

        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(store.state, 0, reason: 'the late emission must be dropped');
        expect(
          errors.whereType<StateError>().single.message,
          contains('emitted after it had already finished'),
        );
        store.close();
      });
    });

    test('an emission after a Ripple finishes is reported, not committed',
        () async {
      final store = Store<int>(CounterFeature());
      final errors = <Object>[];
      store.onError((e, _) => errors.add(e));

      late StateEmitter<int> escaped;
      await store.runRippleAndWait<Object?>(
        (event, emit) async => escaped = emit,
        event: null,
      );

      escaped(99);
      expect(store.state, 0);
      expect(errors.single, isA<StateError>());
      store.close();
    });
  });

  group('retry', () {
    test('never retries a Ripple whose scope was cancelled', () async {
      final store = Store<int>(CounterFeature());
      store.onError((_, __) {});
      var attempts = 0;

      final scope = store.rootScope.spawn('doomed');
      scope.close();

      final body = retry<int, Object?>((event, emit) async {
        attempts++;
        emit(1); // throws ScopeDeadException: the scope is already dead
      }, max: 5);

      await store.runRippleAndWait<Object?>(body, event: null, scope: scope);
      expect(attempts, 1, reason: 'cancellation is terminal, not transient');
      store.close();
    });

    test('still retries genuinely transient failures', () async {
      final store = Store<int>(CounterFeature());
      var attempts = 0;
      final body = retry<int, Object?>((event, emit) async {
        attempts++;
        if (attempts < 3) throw Exception('transient');
        emit(7);
      }, max: 3);

      await store.runRippleAndWait<Object?>(body, event: null);
      expect(attempts, 3);
      expect(store.state, 7);
      store.close();
    });
  });

  group('error reporting', () {
    test('an Echo failure reaches the Zone when no onError is registered',
        () async {
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        final store = Store<int>(ThrowingEchoFeature());
        store.publish(const Noticed()); // no onError registered at all
        store.close();
      }, (e, _) => uncaught.add(e))!;

      expect(
        uncaught.single,
        isA<StateError>().having((e) => e.message, 'message', 'echo blew up'),
        reason: 'a thrown Echo must never vanish silently',
      );
    });

    test('a registered onError still takes precedence over the Zone', () async {
      final uncaught = <Object>[];
      final handled = <Object>[];
      await runZonedGuarded(() async {
        final store = Store<int>(ThrowingEchoFeature());
        store.onError((e, _) => handled.add(e));
        store.publish(const Noticed());
        store.close();
      }, (e, _) => uncaught.add(e))!;

      expect(handled, hasLength(1));
      expect(uncaught, isEmpty);
    });
  });

  group('routing by runtime type', () {
    test('dispatch of a statically-upcast event still finds its Flow', () {
      final store = Store<int>(CounterFeature());
      final Object event = const Bump(); // static type widened to Object
      store.dispatch(event);
      expect(store.state, 1, reason: 'routing must follow the runtime type');
      store.close();
    });

    test('an upcast event with no Flow or Echo still fails fast', () {
      final store = Store<int>(CounterFeature());
      final Object event = const Unregistered();
      expect(() => store.dispatch(event), throwsStateError);
      store.close();
    });

    test('publish through an Event-typed variable reaches its Echoes', () {
      final store = Store<int>(CounterFeature());
      const Event upcast = Noticed();
      store.publish(upcast);
      expect(
        echoLog.map((e) => e.$1),
        containsAll(<String>['noticed', 'any-event']),
      );
      store.close();
    });

    test('an Echo registered for a supertype receives subtypes', () {
      final store = Store<int>(CounterFeature());
      store.publish(const AlsoNoticed());
      expect(echoLog.map((e) => e.$1), ['any-event']);
      expect(echoLog.single.$2, isA<AlsoNoticed>());
      store.close();
    });

    test('an Echo never receives an event of an unrelated type', () {
      final store = Store<int>(CounterFeature());
      store.dispatch(const Bump()); // Bump is not an Event
      expect(echoLog.map((e) => e.$1), ['any-event'],
          reason: 'only the automatic EventCommitted, never the Noticed echo');
      expect(echoLog.single.$2, isA<EventCommitted>());
      store.close();
    });
  });

  group('close', () {
    test('drops observers and refuses further writes', () {
      final store = Store<int>(CounterFeature());
      var observed = 0;
      store.observe((_) => observed++);

      store.dispatch(const Bump());
      expect(observed, 1);

      store.close();
      expect(store.isClosed, isTrue);
      expect(() => store.dispatch(const Bump()), throwsStateError);
      expect(() => store.publish(const Noticed()), throwsStateError);
      expect(observed, 1, reason: 'the observer was dropped by close()');
      expect(store.state, 1, reason: 'no write landed after close()');
    });

    test('keeps state and ledger readable', () {
      final store = Store<int>(CounterFeature());
      store.dispatch(const Bump());
      store.close();
      expect(store.state, 1);
      expect(store.ledger.single.source, 'bump');
    });

    test('is idempotent', () {
      final store = Store<int>(CounterFeature());
      store.close();
      expect(store.close, returnsNormally);
    });

    test('starting a Ripple afterwards reports instead of throwing', () {
      final store = Store<int>(CounterFeature());
      final errors = <Object>[];
      store.onError((e, _) => errors.add(e));
      store.close();

      // close() drops error handlers, so this lands in the Zone; the point
      // of the test is that it does not throw at the call site.
      runZonedGuarded(() {
        expect(
          () => store.runRipple<Object?>((e, emit) async {}, event: null),
          returnsNormally,
        );
      }, (e, _) => errors.add(e));

      expect(errors.whereType<StateError>(), isNotEmpty);
    });
  });

  group('scope lifetime', () {
    test('a Ripple closes the scope it spawned itself', () async {
      final store = Store<int>(CounterFeature());
      final scope = store.runRipple<Object?>((e, emit) async {}, event: null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(scope.isDead, isTrue,
          reason: 'otherwise every fire-and-forget Ripple pins a child scope '
              'to rootScope for the store\'s lifetime');
      store.close();
    });

    test('a caller-supplied scope is left alone', () async {
      final store = Store<int>(CounterFeature());
      final mine = store.rootScope.spawn('mine');
      await store.runRippleAndWait<Object?>(
        (e, emit) async {},
        event: null,
        scope: mine,
      );
      expect(mine.isDead, isFalse, reason: 'the caller owns this scope');
      mine.close();
      store.close();
    });
  });

  group('ledger', () {
    test('is capped by default, dropping the oldest transactions', () {
      final store = Store<int>(CounterFeature(), ledgerLimit: 5);
      for (var i = 0; i < 20; i++) {
        store.dispatch(const Bump());
      }
      expect(store.ledger, hasLength(5));
      expect(
        store.ledger.map((t) => t.sequence),
        [15, 16, 17, 18, 19],
        reason: 'sequence numbers keep counting from the first commit',
      );
      expect(store.state, 20);
      store.close();
    });

    test('keeps everything when ledgerLimit is null', () {
      final store = Store<int>(CounterFeature(), ledgerLimit: null);
      for (var i = 0; i < 50; i++) {
        store.dispatch(const Bump());
      }
      expect(store.ledger, hasLength(50));
      store.close();
    });

    test('rejects a non-positive limit', () {
      expect(
        () => Store<int>(CounterFeature(), ledgerLimit: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

/// Runs [body] and returns its future — a seam kept deliberately thin so
/// the timing-sensitive test above reads the same as the others.
Future<void> fakeAsyncish(Future<void> Function() body) => body();
