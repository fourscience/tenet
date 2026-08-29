import 'dart:async';

import '../../tenet.dart';

/// A single recorded call to a named Echo — see [FeatureHarness.echoCalls].
///
/// Carries both the [event] the Echo received and a snapshot of [state] at
/// that moment, since assertions commonly want one or the other (or both):
/// [event] to check what triggered the Echo, [state] to prove the Echo's
/// [StateLens] reflected the store's live state at the time.
final class EchoCall<S> {
  /// The event the Echo received.
  final Object? event;

  /// A snapshot of the store's state at the moment the Echo ran.
  final S state;

  /// Creates a record of one Echo invocation.
  const EchoCall(this.event, this.state);

  @override
  String toString() => 'EchoCall($event, $state)';
}

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
///
/// Echo assertions need no cooperation from the [Feature] under test — no
/// test-only field or back-reference on it — because [echoCalls] is built
/// entirely on [Store.observeEchos], a store-level hook any Echo already
/// passes through:
///
/// ```dart
/// expect(harness.echoCalls('analytics').map((c) => c.state.status), ['idle']);
/// ```
final class FeatureHarness<S> {
  /// The store under test.
  final Store<S> store;

  final List<Transaction<S>> _transactions = [];
  final Map<String, List<EchoCall<S>>> _echoCalls = {};

  /// Errors reported by Echoes/Ripples since harness creation.
  final List<(Object, StackTrace)> errors = [];

  /// Creates a harness; automatically installs a ledger observer, an Echo
  /// observer (backing [echoCalls]), and an error collector (access via
  /// [errors]).
  FeatureHarness(Feature<S> feature) : store = Store<S>(feature) {
    store.observe((t) => _transactions.add(t));
    store.onError((e, st) => errors.add((e, st)));
    store.observeEchos(
      (name, event, lens) =>
          (_echoCalls[name] ??= []).add(EchoCall(event, lens.state)),
    );
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

  /// Every call the Echo named [name] (see [EchoRegistry.echo]'s `name`)
  /// has received, oldest first — each with the event it got and a
  /// snapshot of [state] at that moment. Empty if that Echo was never
  /// reached, whether because it doesn't exist or because nothing
  /// matching its event type has fired yet.
  List<EchoCall<S>> echoCalls(String name) =>
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

  /// Advances fake time and flushes microtasks — helper for throttle tests.
  Future<void> pump([Duration duration = Duration.zero]) async {
    await Future<void>.delayed(duration);
  }

  /// Closes the store (kills all persistent ripples).
  void dispose() => store.close();
}
