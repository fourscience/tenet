/// Tenet — a time-aware, effect-separated state management library.
///
/// Core mental model (one sentence):
///   "State is now, Flows change it purely, Ripples fetch it asynchronously,
///    Echoes react to it externally."
///
/// Every piece of logic must be exactly ONE of:
///   * State  — a value that exists now.
///   * Flow   — a pure, synchronous function (State, Event) -> State.
///   * Ripple — an async, cancellable process that commits typed states.
///   * Echo   — a side-effect listener that may READ state, never WRITE it.
///
/// Design principles honored:
///   * SRP: each class owns exactly one concern.
///   * OCP: behaviors (debounce, retry, timeout) compose via wrappers.
///   * LSP: all Flow/Ripple/Echo variants are substitutable.
///   * ISP: narrow interfaces (Flow, Ripple, Echo) — consumers see only
///          what they need.
///   * DIP: effects depend on the abstract [StateEmitter], not concrete
///          APIs.
library tenet;

export 'src/combinators.dart';
export 'src/core.dart';
export 'src/dispatch.dart';
export 'src/flow_scope.dart';
export 'src/store.dart';
export 'src/transaction.dart';
