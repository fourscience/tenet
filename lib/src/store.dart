import 'dart:async';

import 'core.dart';
import 'flow_scope.dart';
import 'transaction.dart';

/// The orchestrator: [Store] owns a feature's state, ledger and dispatch —
/// and nothing else (SRP). Flow/Echo registration is exposed through narrow
/// interfaces ([FlowRegistry], [EchoRegistry]) so authors of one never see
/// the other (ISP).

/// Observer hook for the ledger — used by devtools and the test harness.
typedef TransactionObserver<S> = void Function(Transaction<S> transaction);

/// Unhandled-error hook for Echoes and Ripples.
typedef ErrorHandler = void Function(Object error, StackTrace stackTrace);

/// The single owner of a feature's state.
///
/// Responsibilities (and nothing else):
///   * hold the current [state],
///   * run Flows purely and commit results,
///   * run Ripples inside a [FlowScope] with emission checks,
///   * notify Echoes (read-only),
///   * append every commit to the transaction ledger.
///
/// Subclass [Feature] per feature and register its Flows/Ripples/Echoes.
abstract class Feature<S> {
  /// The initial state of the feature.
  S get initial;

  /// Optional name for debugging; defaults to the runtime type.
  String get name => runtimeType.toString();

  /// Override to register this feature's Flows. Called once by the [Store].
  void registerFlows(FlowRegistry<S> flows) {}

  /// Override to register this feature's Echoes. Called once by the
  /// [Store].
  void registerEchos(EchoRegistry<S> echos) {}
}

/// Registration surface for Flows (Interface Segregation: Echo authors
/// never see this; Flow authors never see Echo registration).
abstract class FlowRegistry<S> {
  /// Registers a Flow under [name].
  void flow<E>(String name, Flow<S, E> flow);
}

/// Registration surface for Echoes.
abstract class EchoRegistry<S> {
  /// Registers an Echo that reacts to events of type [E].
  void echo<E>(String name, EchoBody<S, E> body);
}

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
final class _EchoEntry<S, E> {
  final String name;
  final EchoBody<S, E> body;
  _EchoEntry(this.name, this.body);
}

/// Concrete registry implementations (kept private; users get the abstract
/// interfaces above — ISP).
final class _FlowRegistryImpl<S> implements FlowRegistry<S> {
  final Map<Type, _FlowEntry<S>> _byType = {};

  @override
  void flow<E>(String name, Flow<S, E> flow) {
    _byType[E] = _FlowEntry<S>(name, (state, event) => flow(state, event as E));
  }
}

final class _EchoRegistryImpl<S> implements EchoRegistry<S> {
  final List<_EchoEntry<S, Object?>> _entries = [];

  @override
  void echo<E>(String name, EchoBody<S, E> body) {
    _entries.add(_EchoEntry<S, E>(name, body));
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

  final List<Transaction<S>> _ledger = [];
  final List<TransactionObserver<S>> _observers = [];
  final List<ErrorHandler> _errorHandlers = [];

  /// The root scope: Ripples registered as persistent run here.
  final FlowScope rootScope = FlowScope.root();

  S _state;
  int _sequence = 0;

  /// Creates a store for [feature] and performs one-time registration.
  Store(this._feature) : _state = _feature.initial {
    _feature.registerFlows(_flows);
    _feature.registerEchos(_echos);
  }

  // -- Read API ----------------------------------------------------------

  /// The current state. Read-only; only Flows/Ripples can change it.
  S get state => _state;

  /// The full transaction ledger (time travel).
  List<Transaction<S>> get ledger => List.unmodifiable(_ledger);

  /// Whether a flow for event type [E] has been registered.
  bool hasFlow<E>() => _flows._byType.containsKey(E);

  // -- Configuration (observer pattern, open for extension) --------------

  /// Adds a ledger observer (devtools, tests). Returns an unsubscriber.
  void Function() observe(TransactionObserver<S> observer) {
    _observers.add(observer);
    return () => _observers.remove(observer);
  }

  /// Adds a global error handler for Echo/Ripple failures.
  void onError(ErrorHandler handler) => _errorHandlers.add(handler);

  void _report(Object error, StackTrace st) {
    for (final h in _errorHandlers) {
      h(error, st);
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
    for (final o in List.of(_observers)) {
      o(txn);
    }
    return txn;
  }

  // -- Dispatch: Flows ------------------------------------------------------

  /// Dispatches a synchronous event: runs the registered Flow of type [E]
  /// (if any) and notifies every registered Echo of type [E] (if any).
  ///
  /// An event needs only a Flow, only Echoes, or both — an Echo-only event
  /// (e.g. one that just triggers analytics) never needs a no-op Flow just
  /// to be dispatchable. Throws [StateError] only when [E] has neither a
  /// Flow nor any Echo registered — a loud failure is preferable to a
  /// silent no-op (fail fast).
  void dispatch<E>(E event) {
    final entry = _flows._byType[E];
    if (entry == null && !_echos._entries.any((e) => e is _EchoEntry<S, E>)) {
      throw StateError(
        'No Flow or Echo registered for event type $E in feature '
        '"${_feature.name}". Did you forget flows.flow<$E>(...) or '
        'echos.echo<$E>(...) in registerFlows/registerEchos?',
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
  /// so callers can close it (e.g. on screen dispose).
  ///
  /// Fire-and-forget: failures are routed to [onError], never thrown here.
  /// Use [runRippleAndWait] when the caller needs to know when the Ripple's
  /// work is actually done.
  FlowScope runRipple<E>(
    RippleBody<S, E> ripple, {
    required E event,
    String source = 'ripple',
    FlowScope? scope,
  }) {
    final effective = scope ?? rootScope.spawn('$source-scope');
    unawaited(
      _runRippleBody(ripple, event: event, scope: effective, source: source),
    );
    return effective;
  }

  /// Like [runRipple], but returns a future that completes once the Ripple
  /// finishes — successfully or not. A failure is still routed to
  /// [onError] before this future completes; it is never thrown here
  /// either. Most useful in tests, where "run this Ripple and then assert"
  /// needs a real completion signal instead of a fire-and-forget scope.
  Future<FlowScope> runRippleAndWait<E>(
    RippleBody<S, E> ripple, {
    required E event,
    String source = 'ripple',
    FlowScope? scope,
  }) async {
    final effective = scope ?? rootScope.spawn('$source-scope');
    await _runRippleBody(ripple,
        event: event, scope: effective, source: source);
    return effective;
  }

  /// Runs [ripple], reporting (never throwing) any failure. Returns whether
  /// it completed without error.
  Future<bool> _runRippleBody<E>(
    RippleBody<S, E> ripple, {
    required Object? event,
    required FlowScope scope,
    required String source,
  }) async {
    try {
      await ripple(
        event as E,
        _GuardedEmitter<S>(this, scope, source),
      );
      return true;
    } catch (e, st) {
      _report(e, st);
      return false;
    }
  }

  // -- Dispatch: Echoes (read-only) --------------------------------------------

  void _fireEchos<E>(E event) {
    final lens = _StoreLens<S>(() => _state);
    for (final entry in _echos._entries) {
      if (entry is _EchoEntry<S, E>) {
        try {
          entry.body(event, lens);
        } catch (e, st) {
          _report(e, st);
        }
      }
    }
  }

  /// Closes the store: kills the root scope (all ripples die), clears
  /// observers. Idempotent.
  void close() => rootScope.close();
}

/// Emitter that enforces scope liveness before committing — the "late
/// emission after cancellation" guarantee.
final class _GuardedEmitter<S> implements StateEmitter<S> {
  final Store<S> _store;
  final FlowScope _scope;
  final String _source;

  _GuardedEmitter(this._store, this._scope, this._source);

  @override
  void call(S state) {
    if (_scope.isDead) {
      throw ScopeDeadException(_scope.name);
    }
    _store._commit(state, source: _source);
  }
}
