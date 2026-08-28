import 'dart:async';

import '../../tenet.dart';

/// A test harness for a [Feature]: instantiates its [Store], records every
/// transaction, captures Echo invocations, and exposes helpers for fluent
/// assertions.
///
/// ```dart
/// final harness = FeatureHarness(CartFeature());
/// harness.dispatch(AddItem('x'));
/// expect(harness.state.items, ['x']);
/// expect(harness.transactions.map((t) => t.source), ['addItem']);
/// ```
final class FeatureHarness<S> {
  /// The store under test.
  final Store<S> store;

  final List<Transaction<S>> _transactions = [];
  final Map<String, List<Object?>> _echoCalls = {};

  /// Errors reported by Echoes/Ripples since harness creation.
  final List<(Object, StackTrace)> errors = [];

  /// Creates a harness; automatically installs a ledger observer and an
  /// error collector (access via [errors]).
  FeatureHarness(Feature<S> feature) : store = Store<S>(feature) {
    store.observe((t) => _transactions.add(t));
    store.onError((e, st) => errors.add((e, st)));
  }

  /// Current state.
  S get state => store.state;

  /// All transactions since harness creation.
  List<Transaction<S>> get transactions => List.unmodifiable(_transactions);

  /// The most recent state change, or null if none.
  Transaction<S>? get lastTransaction =>
      _transactions.isEmpty ? null : _transactions.last;

  /// Dispatches a sync event through the registered Flow for [E].
  void dispatch<E>(E event) => store.dispatch<E>(event);

  /// Sends an [Intent] through the registered [IntentHandler] for its
  /// type.
  void send(Intent intent) => store.send(intent);

  /// Executes a [Command] through the pure write path.
  void execute(Command<S> command, {String? source}) =>
      store.execute(command, source: source);

  /// Broadcasts an [Event] to Echoes.
  void publish<E extends Event>(E event) => store.publish<E>(event);

  /// Records that an Echo named [name] received [event]; used with
  /// [echoCalls] to assert Echo wiring without asserting internals.
  void recordEcho(String name, Object? event) =>
      (_echoCalls[name] ??= []).add(event);

  /// All events an Echo named [name] has received (via [recordEcho]).
  List<Object?> echoCalls(String name) =>
      List.unmodifiable(_echoCalls[name] ?? const []);

  /// Runs an async Ripple to completion inside the harness's root scope and
  /// awaits its emissions — including any real delays the Ripple or its
  /// combinators (retry backoff, timeout, ...) introduce.
  Future<void> runRipple<E>(
    RippleBody<S, E> ripple, {
    required E event,
  }) async {
    final scope = await store.runRippleAndWait<E>(
      ripple,
      event: event,
      source: 'harness-ripple',
    );
    scope.close();
  }

  /// Advances fake time and flushes microtasks — helper for debounce tests.
  Future<void> pump([Duration duration = Duration.zero]) async {
    await Future<void>.delayed(duration);
  }

  /// Closes the store (kills all persistent ripples).
  void dispose() => store.close();
}
