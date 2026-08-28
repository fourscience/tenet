/// Core abstractions shared by the rest of the library: the pure [Flow]
/// function type, the narrow write/read interfaces used to enforce the
/// effect boundaries between Flows, Ripples and Echoes, and the async
/// [RippleBody] / [EchoBody] function types.
library;

/// A pure, synchronous state transition.
///
/// Flows MUST be pure: no I/O, no async, no side effects. This makes them
/// trivially unit-testable and hot-reload friendly.
///
/// ```dart
/// final Flow<CartState, AddItem> addItem =
///     (state, event) => state.copyWith(items: [...state.items, event.item]);
/// ```
typedef Flow<S, E> = S Function(S state, E event);

/// The single, narrow interface through which async processes (Ripples)
/// publish intermediate states. (Dependency Inversion: Ripples depend on
/// this abstraction, never on the concrete `Store`.)
abstract interface class StateEmitter<S> {
  /// Commits [state] as the new current state of the owning feature.
  ///
  /// Throws [ScopeDeadException] if the owning `FlowScope` has been closed —
  /// this is how "late emission after cancellation" surfaces early in
  /// development rather than silently corrupting state.
  ///
  /// [StateEmitter] instances are callable directly: `emit(state)` is
  /// shorthand for `emit.call(state)`.
  void call(S state);
}

/// A read-only, strongly-typed view of a feature's state, given to Echoes.
///
/// Echoes may read but never write — enforced by this interface, which
/// exposes no mutation capability at all (type-level effect quarantine).
abstract interface class StateLens<S> {
  /// The current state snapshot.
  S get state;
}

/// An async, cancellable process.
///
/// A Ripple receives its input event plus a [StateEmitter] and runs to
/// completion — unless the `FlowScope` it runs in is closed (e.g. its
/// screen was disposed), in which case cancellation propagates through the
/// await chain.
typedef RippleBody<S, E> = Future<void> Function(E event, StateEmitter<S> emit);

/// A side-effect listener. Echoes react to state changes / events but can
/// never mutate state (they only ever see [StateLens]).
typedef EchoBody<S, E> = void Function(E event, StateLens<S> lens);
