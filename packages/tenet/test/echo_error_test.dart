// Regression test: EchoRegistry.echo's `name` must actually reach error
// reports, as the README promises — onEchoError is additive and must
// never change what onError/the Zone already see.
import 'package:tenet/tenet.dart';
import 'package:test/test.dart';

class Ping {
  const Ping();
}

class Feat extends Feature<int> {
  @override
  int get initial => 0;

  @override
  void registerEchos(EchoRegistry<int> echos) {
    echos.echo<Ping>((e, lens) => throw StateError('boom'), name: 'alerts');
  }
}

void main() {
  test('onEchoError receives the failing Echo\'s registered name', () {
    final store = Store<int>(Feat());
    final calls = <(String, Object)>[];
    store.onEchoError((name, error, st) => calls.add((name, error)));
    store.onError((_, __) {}); // keep the Zone quiet for this test

    store.dispatch(const Ping());

    expect(calls, hasLength(1));
    expect(calls.single.$1, 'alerts');
    expect(calls.single.$2, isA<StateError>());
    store.close();
  });

  test('onEchoError runs alongside onError, not instead of it', () {
    final store = Store<int>(Feat());
    var echoErrors = 0;
    var generalErrors = 0;
    store.onEchoError((_, __, ___) => echoErrors++);
    store.onError((_, __) => generalErrors++);

    store.dispatch(const Ping());

    expect(echoErrors, 1);
    expect(generalErrors, 1,
        reason: 'onError must see every failure it '
            'always has, whether or not onEchoError is also registered');
    store.close();
  });

  test('onError alone still works exactly as before, with no onEchoError', () {
    final store = Store<int>(Feat());
    final errors = <Object>[];
    store.onError((e, _) => errors.add(e));

    store.dispatch(const Ping());

    expect(errors.single, isA<StateError>());
    store.close();
  });
}
