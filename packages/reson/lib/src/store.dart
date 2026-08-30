import 'dart:async';

import 'core.dart';
import 'dispatch.dart';
import 'flow_scope.dart';
import 'transaction.dart';

/// The orchestrator: [Store] owns a feature's state, ledger and dispatch —
/// and nothing else (SRP). Flow/Echo/Intent registration is exposed
/// through narrow interfaces ([FlowRegistry], [EchoRegistry],
/// [IntentRegistry]) so authors of one never see the others (ISP).

/// Observer hook for the ledger — used by devtools and the test harness.
typedef TransactionObserver<S> = void Function(Transaction<S> transaction);

/// Unhandled-error hook for Echoes and Ripples.
typedef ErrorHandler = void Function(Object error, StackTrace stackTrace);

/// Failure hook specific to Echoes, additionally naming which one failed.
/// See [Store.onEchoError].
typedef EchoErrorHandler = void Function(
  String echoName,
  Object error,
  StackTrace stackTrace,
);

/// Notified whenever an Echo runs to completion without throwing. See
/// [Store.observeEchos].
typedef EchoObserver<S> = void Function(
  String echoName,
  Object? event,
  StateLens<S> lens,
);

/// The single owner of a feature's state.
///
/// Responsibilities (and nothing else):
///   * hold the current [state],
///   * run Flows purely and commit results,
///   * run Ripples inside a [FlowScope] with emission checks,
///   * notify Echoes (read-only),
///   * append every commit to the transaction ledger.
///
/// Subclass [Feature] per feature and register its Flows/Ripples/Echoes/
/// Intents.
abstract class Feature<S> {
  /// The initial state of the feature.
  S get initial;

  /// Optional name for debugging; defaults to the runtime type.
  ///
  /// That default reads `runtimeType.toString()`, which a release build
  /// with identifier obfuscation on (`flutter build ... --obfuscate`)
  /// mangles into an opaque, per-build string instead of the class's real
  /// name — the same thing that happens to obfuscated stack traces.
  /// Override this with an explicit literal if a feature's name needs to
  /// stay stable and readable in an obfuscated build (log lines, crash
  /// reports, anywhere the string itself is inspected rather than just
  /// compared for equality).
  String get name => runtimeType.toString();

  /// Override to register this feature's Flows. Called once by the [Store].
  void registerFlows(FlowRegistry<S> flows) {}

  /// Override to register this feature's Echoes. Called once by the
  /// [Store].
  void registerEchos(EchoRegistry<S> echos) {}

  /// Override to register this feature's [Intent] handlers. Called once
  /// by the [Store]. This is where "what happens when the user does X" is
  /// decided — a handler may [IntentContext.execute] a [Command],
  /// [IntentContext.launch] a Ripple, [IntentContext.publish] an [Event],
  /// or any combination.
  void registerIntents(IntentRegistry<S> intents) {}
}

/// Registration surface for Flows (Interface Segregation: Echo/Intent
/// authors never see this; Flow authors never see Echo/Intent
/// registration).
abstract class FlowRegistry<S> {
  /// Registers [flow] for events of type [E]. [name] becomes the ledger
  /// transaction's `source` (see [Transaction.source]) — pass one when
  /// `$E` on its own wouldn't read well there (e.g. `name: 'addItem'`
  /// instead of the default `'AddItem'`). Defaults to `E`'s type name —
  /// which, like [Feature.name], a release build with identifier
  /// obfuscation on mangles into an opaque string; pass an explicit
  /// [name] for a Flow whose ledger `source` needs to stay readable
  /// there.
  void flow<E>(Flow<S, E> flow, {String? name});
}

/// Registration surface for Echoes.
abstract class EchoRegistry<S> {
  /// Registers [body] as an Echo that reacts to events of type [E].
  ///
  /// An Echo receives every dispatched/published event that *is* an [E] —
  /// including instances of its subtypes — so `echo<Event>(...)` is a
  /// legitimate catch-all audit hook. [name] labels the Echo in error
  /// reports; it defaults to `E`'s type name — see [Feature.name]'s doc
  /// comment for why an explicit [name] matters in an obfuscated build.
  void echo<E>(EchoBody<S, E> body, {String? name});
}

/// Registration surface for [Intent] handlers — a third registry,
/// separate from Flows and Echoes.
abstract class IntentRegistry<S> {
  /// Maps [I] to a handler. The handler receives the intent and an
  /// [IntentContext] that exposes `execute`/`launch`/`publish`, but never
  /// raw state mutation.
  void on<I extends Intent>(IntentHandler<S, I> handler);
}

/// What an Intent handler may do. Deliberately narrow (ISP): no direct
/// state mutation, only orchestration.
abstract interface class IntentContext<S> {
  /// Executes a Command — the only legal write an Intent handler may
  /// trigger directly. Defaults [source] to `command.name`.
  void execute(Command<S> command, {String? source});

  /// Launches an async Ripple; returns its scope for lifetime control.
  /// The Ripple body's event parameter goes unused from this call
  /// path — the Intent itself is already in scope via closure, so there's
  /// nothing further to pass through it.
  FlowScope launch(RippleBody<S, Object?> ripple, {String source = 'ripple'});

  /// Broadcasts an Event to Echoes.
  void publish<E extends Event>(E event);

  /// The current state (read-only), for decision-making.
  S get state;
}

/// Handles intents of type [I] for a feature with state [S].
typedef IntentHandler<S, I extends Intent> = void Function(
    I intent, IntentContext<S> ctx);

/// The runtime implementation of a registered Flow.
/// Event types are erased to [Object?] here so heterogeneous Flows can
/// share one [Type]-keyed map; the single cast back to `E` happens once,
/// inside the wrapper closure built by [_FlowRegistryImpl.flow]. (Storing
/// a `Flow<S, E>` directly under a `Flow<S, Object?>`-typed field would be
/// unsound — function types are contravariant in their parameters, so no
/// generic-covariance trick can make that safe.)
final class _FlowEntry<S> {
  final String name;
  final S Function(S state, Object? event) run;
  _FlowEntry(this.name, this.run);
}

/// The runtime implementation of a registered Echo.
///
/// Event types are erased to [Object?] here, exactly as [_FlowEntry]
/// erases them, and for a second reason on top of that one: matching an
/// Echo by testing the *entry* against a type argument (as in
/// `entry is _EchoEntry(S, E)`) asks the question backwards. Generics are
/// covariant, so an entry registered for a narrow type is also an entry
/// of every wider one — an Echo registered for `Noticed` would match a
/// dispatch whose static type was merely `Object`, and then blow up
/// casting the event. [accepts] asks the question in the only direction
/// that is sound: does this actual, runtime event satisfy the type the
/// Echo was registered for?
final class _EchoEntry<S> {
  final String name;
  final bool Function(Object? event) accepts;
  final void Function(Object? event, StateLens<S> lens) run;
  _EchoEntry(this.name, this.accepts, this.run);
}

/// Concrete registry implementations (kept private; users get the abstract
/// interfaces above — ISP).
final class _FlowRegistryImpl<S> implements FlowRegistry<S> {
  final Map<Type, _FlowEntry<S>> _byType = {};

  @override
  void flow<E>(Flow<S, E> flow, {String? name}) {
    _byType[E] = _FlowEntry<S>(
      name ?? E.toString(),
      (state, event) => flow(state, event as E),
    );
  }
}

final class _EchoRegistryImpl<S> implements EchoRegistry<S> {
  final List<_EchoEntry<S>> _entries = [];

  @override
  void echo<E>(EchoBody<S, E> body, {String? name}) {
    _entries.add(_EchoEntry<S>(
      name ?? E.toString(),
      (event) => event is E,
      (event, lens) => body(event as E, lens),
    ));
  }
}

/// The runtime implementation of a registered Intent handler. Intent
/// types are erased to [Object?] here for the same reason [_FlowEntry]
/// erases event types — see that class's doc comment.
final class _IntentEntry<S> {
  final void Function(Object? intent, IntentContext<S> ctx) run;
  _IntentEntry(this.run);
}

final class _IntentRegistryImpl<S> implements IntentRegistry<S> {
  final Map<Type, _IntentEntry<S>> _byType = {};

  @override
  void on<I extends Intent>(IntentHandler<S, I> handler) {
    _byType[I] = _IntentEntry<S>((intent, ctx) => handler(intent as I, ctx));
  }
}

/// A read-only [StateLens] over the store's current state.
final class _StoreLens<S> implements StateLens<S> {
  final S Function() _read;
  _StoreLens(this._read);
  @override
  S get state => _read();
}

/// The store — the only component allowed to commit state.
final class Store<S> {
  final Feature<S> _feature;
  final _FlowRegistryImpl<S> _flows = _FlowRegistryImpl<S>();
  final _EchoRegistryImpl<S> _echos = _EchoRegistryImpl<S>();
  final _IntentRegistryImpl<S> _intents = _IntentRegistryImpl<S>();

  final List<Transaction<S>> _ledger = [];
  final List<TransactionObserver<S>> _observers = [];
  final List<ErrorHandler> _errorHandlers = [];
  final List<EchoErrorHandler> _echoErrorHandlers = [];
  final List<EchoObserver<S>> _echoObservers = [];

  /// The root scope: Ripples registered as persistent run here.
  final FlowScope rootScope = FlowScope.root();

  /// How many transactions the ledger keeps, oldest dropped first, or
  /// `null` to keep every transaction for the store's lifetime.
  ///
  /// The ledger is an in-memory list that only ever grows, so an
  /// unbounded one is a slow leak in any long-lived process — a default
  /// cap keeps "time travel for free" from also meaning "unbounded
  /// memory for free". [Transaction.sequence] keeps counting from the
  /// first commit either way, so a trimmed ledger still tells you how
  /// many commits came before the ones it holds.
  final int? ledgerLimit;

  S _state;
  int _sequence = 0;
  bool _closed = false;

  /// Creates a store for [feature] and performs one-time registration.
  ///
  /// Pass [ledgerLimit] to change how much history the ledger keeps (or
  /// `null` for all of it) — see that field.
  Store(this._feature, {this.ledgerLimit = 1000})
      : assert(
          ledgerLimit == null || ledgerLimit > 0,
          'ledgerLimit must be positive, or null for an unbounded ledger.',
        ),
        _state = _feature.initial {
    _feature.registerFlows(_flows);
    _feature.registerEchos(_echos);
    _feature.registerIntents(_intents);
  }

  // -- Read API ----------------------------------------------------------

  /// The current state. Read-only; only Flows/Ripples can change it.
  S get state => _state;

  /// The transaction ledger (time travel), oldest first — the most recent
  /// [ledgerLimit] commits, or every commit when that is `null`.
  List<Transaction<S>> get ledger => List.unmodifiable(_ledger);

  /// Whether a flow for event type [E] has been registered.
  bool hasFlow<E>() => _flows._byType.containsKey(E);

  /// Whether [close] has been called. A closed store accepts no further
  /// dispatches, and its Ripples have all been cancelled.
  bool get isClosed => _closed;

  // -- Configuration (observer pattern, open for extension) --------------

  /// Adds a ledger observer (devtools, tests). Returns an unsubscriber.
  void Function() observe(TransactionObserver<S> observer) {
    _observers.add(observer);
    return () => _observers.remove(observer);
  }

  /// Adds a global error handler for Echo/Ripple failures.
  ///
  /// With no handler registered, failures go to the current [Zone]'s
  /// uncaught-error handler instead — the same place an unawaited
  /// future's error lands, and in Flutter that means the console and
  /// `FlutterError.onError`. An Echo that throws is never swallowed.
  void onError(ErrorHandler handler) => _errorHandlers.add(handler);

  /// Adds a handler for Echo failures specifically — the same error
  /// [onError] receives, plus the failing Echo's `name` (see
  /// [EchoRegistry.echo]) so a log line or crash report can say which one.
  /// Runs in addition to [onError]/the [Zone] fallback, never instead of
  /// them, so existing `onError` handlers see every failure exactly as
  /// before regardless of whether this is also registered.
  void onEchoError(EchoErrorHandler handler) => _echoErrorHandlers.add(handler);

  /// Observes every Echo that runs to completion without throwing —
  /// devtools, logging, or a test's way of asserting "this Echo fired"
  /// without the [Feature] under test needing any test-specific hook of
  /// its own. Returns an unsubscriber, matching [observe].
  ///
  /// `FeatureHarness` builds its Echo-call assertions (`echoCalls`)
  /// entirely on this — a [Feature] never needs to know it's being
  /// tested.
  void Function() observeEchos(EchoObserver<S> observer) {
    _echoObservers.add(observer);
    return () => _echoObservers.remove(observer);
  }

  void _report(Object error, StackTrace st) {
    if (_errorHandlers.isEmpty) {
      // Never drop it on the floor: a feature with no error handler is
      // the common case, and a silently swallowed Echo/Ripple failure is
      // indistinguishable from one that never ran.
      Zone.current.handleUncaughtError(error, st);
      return;
    }
    for (final h in List.of(_errorHandlers)) {
      h(error, st);
    }
  }

  void _checkOpen(String operation) {
    if (_closed) {
      throw StateError(
        'Cannot $operation on a closed Store for feature '
        '"${_feature.name}". close() cancels every Ripple and drops every '
        'observer; create a new Store instead of reusing a closed one.',
      );
    }
  }

  // -- Commit (single write path) -----------------------------------------

  Transaction<S> _commit(
    S next, {
    required String source,
    bool optimistic = false,
  }) {
    final txn = Transaction<S>(
      source: source,
      before: _state,
      after: next,
      optimistic: optimistic,
      sequence: _sequence++,
      timestamp: DateTime.now(),
    );
    _state = next;
    _ledger.add(txn);
    final limit = ledgerLimit;
    if (limit != null && _ledger.length > limit) {
      _ledger.removeRange(0, _ledger.length - limit);
    }
    for (final o in List.of(_observers)) {
      o(txn);
    }
    // Every commit — Flow, Ripple emission, optimistic commit or rollback,
    // executed Command — is announced the same way, so Echoes that only
    // care that "state changed" don't need per-source wiring. This goes
    // straight to _fireEchos rather than through publish() so that a
    // commit already in flight (an optimistic rollback landing after the
    // store closed, say) still finishes announcing itself instead of
    // throwing from publish()'s closed-store guard.
    _fireEchos(EventCommitted(source));
    return txn;
  }

  // -- Dispatch: Flows ------------------------------------------------------

  /// Dispatches a synchronous event: runs the Flow registered for the
  /// event's runtime type (if any) and notifies every Echo that accepts it
  /// (if any).
  ///
  /// Routing is by `event.runtimeType`, never by the static type argument
  /// [E] — matching [send], and so that handing this method a value whose
  /// static type is wider than its real one (an `Object` variable, a
  /// generic forwarding wrapper) still reaches the Flow that was actually
  /// registered instead of silently finding nothing.
  ///
  /// An event needs only a Flow, only Echoes, or both — an Echo-only event
  /// (e.g. one that just triggers analytics) never needs a no-op Flow just
  /// to be dispatchable. Throws [StateError] only when the event has
  /// neither a Flow nor any Echo — a loud failure is preferable to a
  /// silent no-op (fail fast).
  ///
  /// This predates the [Intent]/[Command]/[Event] taxonomy below, and one
  /// event type here plays both roles — it's the trigger AND, via the
  /// Echo it also reaches, the notification. That's fine for a feature
  /// where nothing needs those separated. When it does, prefer [send] +
  /// [Intent] + [Command]: [Intent] is what a screen can call, [Command]
  /// is the only thing that writes, and [Event] is what gets broadcast —
  /// three types instead of one overloaded one.
  void dispatch<E>(E event) {
    _checkOpen('dispatch $E');
    final type = event.runtimeType;
    final entry = _flows._byType[type];
    if (entry == null && !_echos._entries.any((e) => e.accepts(event))) {
      throw StateError(
        'No Flow or Echo registered for event type $type in feature '
        '"${_feature.name}". Did you forget flows.flow<$type>(...) or '
        'echos.echo<$type>(...) in registerFlows/registerEchos?',
      );
    }
    if (entry != null) {
      final next = entry.run(_state, event);
      if (!identical(next, _state) && next != _state) {
        _commit(next, source: entry.name);
      }
    }
    _fireEchos(event);
  }

  // -- Dispatch: Intents / Commands / Events -------------------------------

  /// Sends an [Intent]. The store routes it to the [IntentHandler]
  /// registered for its runtime type. This is the only method
  /// screens/widgets should call to trigger feature behavior when a
  /// feature uses the Intent/Command/Event taxonomy.
  ///
  /// Throws [StateError] if no handler was registered for the intent's
  /// type — fail fast, matching [dispatch].
  void send(Intent intent) {
    _checkOpen('send ${intent.runtimeType}');
    final entry = _intents._byType[intent.runtimeType];
    if (entry == null) {
      throw StateError(
        'No Intent handler registered for ${intent.runtimeType} in '
        'feature "${_feature.name}". Did you forget '
        'intents.on<${intent.runtimeType}>(...) in registerIntents?',
      );
    }
    entry.run(intent, _IntentContextImpl<S>(this));
  }

  /// Executes [command] through the pure write path: commits
  /// `command.reduce(state)` when it actually changes the state.
  /// Intended for [IntentHandler]s (via [IntentContext.execute]) and
  /// tests — not for widgets, which should [send] an [Intent] instead.
  ///
  /// [source] defaults to `command.name`, so the ledger stays meaningful
  /// without every call site having to supply its own label.
  void execute(Command<S> command, {String? source}) {
    _checkOpen('execute ${command.runtimeType}');
    final next = command.reduce(_state);
    if (next != _state) {
      _commit(next, source: source ?? command.name);
    }
  }

  /// Broadcasts an explicit [Event] to Echoes (e.g. a Ripple or Intent
  /// handler announcing something happened). No state change is
  /// possible here — by design, [Event] has no write API at all.
  ///
  /// Like [dispatch] and [send], routing is by the event's runtime type,
  /// so publishing through a variable typed as plain [Event] still
  /// reaches the Echoes registered for what it actually is.
  void publish<E extends Event>(E event) {
    _checkOpen('publish ${event.runtimeType}');
    _fireEchos(event);
  }

  /// Optimistically commits [optimisticState] immediately and then runs
  /// [ripple]. If the Ripple fails, state rolls back to [before]; on
  /// success the Ripple's emissions win.
  ///
  /// Returns the scope the optimistic Ripple runs in, so callers control
  /// its lifetime.
  FlowScope optimistic({
    required S optimisticState,
    required RippleBody<S, Object?> ripple,
    String source = 'optimistic',
  }) {
    _checkOpen('run an optimistic update');
    final before = _state;
    _commit(optimisticState, source: source, optimistic: true);
    final scope = rootScope.spawn('$source-scope');
    unawaited(
      _runRippleBody(ripple, event: Object(), scope: scope, source: source)
          .then((succeeded) {
        if (!succeeded && _state == optimisticState) {
          _commit(before, source: '$source-rollback');
        }
      }).whenComplete(scope.close),
    );
    return scope;
  }

  // -- Dispatch: Ripples ------------------------------------------------------

  /// Runs [ripple] inside [scope] for event [event]. Emissions from the
  /// Ripple are committed through the single write path. Returns the scope
  /// so callers can close it early (e.g. on screen dispose).
  ///
  /// When no [scope] is given this spawns one off [rootScope] and closes
  /// it once the Ripple settles — otherwise every fire-and-forget Ripple
  /// would leave a child scope pinned to [rootScope] for the store's
  /// lifetime. A [scope] you pass in is yours: it is never closed here.
  ///
  /// Fire-and-forget: failures are routed to [onError], never thrown here
  /// — including trying to start one on a closed store, which reports a
  /// [StateError] and returns the (already dead) [rootScope]. Use
  /// [runRippleAndWait] when the caller needs to know when the Ripple's
  /// work is actually done.
  FlowScope runRipple<E>(
    RippleBody<S, E> ripple, {
    required E event,
    String source = 'ripple',
    FlowScope? scope,
  }) {
    if (_closed) return _reportClosedRipple(source);
    final owned = scope == null;
    final effective = scope ?? rootScope.spawn('$source-scope');
    unawaited(
      _runRippleBody(ripple, event: event, scope: effective, source: source)
          .whenComplete(() {
        if (owned) effective.close();
      }),
    );
    return effective;
  }

  /// Like [runRipple], but returns a future that completes once the Ripple
  /// finishes — successfully or not. A failure is still routed to
  /// [onError] before this future completes; it is never thrown here
  /// either. Most useful in tests, where "run this Ripple and then assert"
  /// needs a real completion signal instead of a fire-and-forget scope.
  ///
  /// Unlike [runRipple], a scope this spawns itself is left open when the
  /// future completes, so the caller can still inspect it; close it when
  /// done.
  Future<FlowScope> runRippleAndWait<E>(
    RippleBody<S, E> ripple, {
    required E event,
    String source = 'ripple',
    FlowScope? scope,
  }) async {
    if (_closed) return _reportClosedRipple(source);
    final effective = scope ?? rootScope.spawn('$source-scope');
    await _runRippleBody(ripple,
        event: event, scope: effective, source: source);
    return effective;
  }

  FlowScope _reportClosedRipple(String source) {
    _report(
      StateError(
        'Cannot run the Ripple "$source" on a closed Store for feature '
        '"${_feature.name}"; close() has already cancelled every Ripple.',
      ),
      StackTrace.current,
    );
    return rootScope;
  }

  /// Runs [ripple], reporting (never throwing) any failure. Returns whether
  /// it completed without error.
  Future<bool> _runRippleBody<E>(
    RippleBody<S, E> ripple, {
    required Object? event,
    required FlowScope scope,
    required String source,
  }) async {
    final emitter = _GuardedEmitter<S>(this, scope, source);
    try {
      await ripple(event as E, emitter);
      return true;
    } catch (e, st) {
      _report(e, st);
      return false;
    } finally {
      // A Ripple's emissions are only valid while the Ripple is still
      // running. Work that outlives its own future — the body of a
      // `withTimeout` that kept going after the timeout fired, a stray
      // detached future — is a ghost write, and would otherwise commit
      // state the store already considers settled.
      emitter.settle();
    }
  }

  // -- Dispatch: Echoes (read-only) --------------------------------------------

  void _fireEchos(Object? event) {
    final lens = _StoreLens<S>(() => _state);
    for (final entry in List.of(_echos._entries)) {
      if (!entry.accepts(event)) continue;
      try {
        entry.run(event, lens);
        for (final o in List.of(_echoObservers)) {
          o(entry.name, event, lens);
        }
      } catch (e, st) {
        for (final h in List.of(_echoErrorHandlers)) {
          h(entry.name, e, st);
        }
        _report(e, st);
      }
    }
  }

  /// Closes the store: kills the root scope (so every Ripple dies), drops
  /// every ledger observer and error handler, and refuses any further
  /// [dispatch]/[send]/[execute]/[publish]/[optimistic]. Idempotent.
  ///
  /// The ledger and the final [state] stay readable — closing ends the
  /// store's writes, it doesn't erase its history.
  void close() {
    if (_closed) return;
    _closed = true;
    rootScope.close();
    _observers.clear();
    _errorHandlers.clear();
    _echoErrorHandlers.clear();
    _echoObservers.clear();
  }
}

/// Emitter that enforces scope liveness before committing — the "late
/// emission after cancellation" guarantee.
final class _GuardedEmitter<S> implements StateEmitter<S> {
  final Store<S> _store;
  final FlowScope _scope;
  final String _source;
  bool _settled = false;

  _GuardedEmitter(this._store, this._scope, this._source);

  /// Marks the owning Ripple as finished; emissions after this point are
  /// ghost writes. Called by [Store._runRippleBody] once the Ripple's
  /// future settles.
  void settle() => _settled = true;

  @override
  void call(S state) {
    if (_scope.isDead) {
      throw ScopeDeadException(_scope.name);
    }
    if (_settled) {
      // Deliberately reported rather than thrown: by definition nothing
      // is awaiting this emission's Ripple any more, and a throw here
      // would land in a detached future — where, after a
      // `Future.timeout`, the Dart runtime discards it silently.
      _store._report(
        StateError(
          'Ripple "$_source" emitted after it had already finished; the '
          'emission was dropped. Work that outlives its Ripple (e.g. the '
          'body of a withTimeout that kept running past the timeout) must '
          'not commit state.',
        ),
        StackTrace.current,
      );
      return;
    }
    _store._commit(state, source: _source);
  }
}

/// The concrete [IntentContext] handed to every [IntentHandler]. It only
/// ever calls back through [Store]'s public API — `execute`, `runRipple`,
/// `publish`, `state` — so, unlike [_GuardedEmitter], it needs no private
/// access to [Store] at all.
final class _IntentContextImpl<S> implements IntentContext<S> {
  final Store<S> _store;
  _IntentContextImpl(this._store);

  @override
  void execute(Command<S> command, {String? source}) =>
      _store.execute(command, source: source);

  @override
  FlowScope launch(
    RippleBody<S, Object?> ripple, {
    String source = 'ripple',
  }) =>
      _store.runRipple<Object?>(ripple, event: null, source: source);

  @override
  void publish<E extends Event>(E event) => _store.publish<E>(event);

  @override
  S get state => _store.state;
}
