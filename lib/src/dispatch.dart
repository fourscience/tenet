/// Dispatch taxonomy: Intent / Command / Event.
///
/// [Store.dispatch] (see `store.dart`) predates this taxonomy and remains
/// supported for simple cases: one event type driving a Flow and/or an
/// Echo, with no need to separate "what triggered this" from "what
/// changed". This taxonomy exists for the cases where that separation
/// earns its keep — larger features where screens, internal writes, and
/// broadcast facts benefit from being three different types instead of
/// one overloaded one:
///
///   * [Intent]  — imperative, present tense: "do this". From the
///     outside (UI, another feature). The only thing screens should send.
///   * [Command] — imperative, exact change: "set state to this".
///     Produced internally (typically by an [Intent] handler) and is the
///     only legal write instruction alongside a Flow.
///   * [Event]   — declarative, past tense: "this happened". Broadcast to
///     Echoes only; can never change state.
library;

/// Base type for all Intent/Command/Event messages. Sealed so exhaustive
/// switches over message kinds are compiler-enforced: [Intent], [Command]
/// and [Event] are the only direct subtypes, but each of them stays open
/// for consumers to extend freely.
sealed class Dispatch {
  const Dispatch();
}

/// A request originating OUTSIDE the feature (UI, user, another feature).
/// Intents are the only thing screens are allowed to send — see
/// `Store.send`.
///
/// An Intent may execute a [Command], launch a Ripple, publish an
/// [Event], or any combination — decided by its registered
/// `IntentHandler`. Intents never mutate state directly; they ask.
abstract class Intent extends Dispatch {
  const Intent();
}

/// An exact, synchronous state change — alongside a Flow, the only legal
/// write instruction. Commands are produced by an Intent handler and
/// executed via `Store.execute` (or `IntentContext.execute`); state logic
/// lives with the command itself, not scattered across handlers.
///
/// Rule of thumb: if you can express a change as `(state) => newState`
/// without needing to register it against an event type up front, it's a
/// Command, not a Flow.
///
/// A Ripple launched via `IntentContext.launch` can execute Commands too,
/// even after an `await` — it just needs to capture the `IntentContext`
/// from its enclosing handler by closure and call `ctx.execute(...)` once
/// its async work is done, instead of (or alongside) emitting raw state
/// through its `StateEmitter`. A Ripple started any other way (plain
/// `Store.runRipple`, outside the Intent system) still only has that
/// `StateEmitter` and commits through `emit(state)` as it always has.
abstract class Command<S> extends Dispatch {
  const Command();

  /// Name recorded as the transaction's `source` in the ledger, unless
  /// `Store.execute` is called with an explicit override. Defaults to the
  /// command's runtime type, mirroring `Feature.name`.
  String get name => runtimeType.toString();

  /// The pure transition this command encodes.
  S reduce(S state);
}

/// A fact that HAPPENED, past tense. Broadcast to Echoes via
/// `Store.publish`; nothing else consumes an Event, and publishing one
/// can never change state.
abstract class Event extends Dispatch {
  const Event();
}

/// Published automatically by every commit the store makes — from a
/// dispatched Flow, a Ripple emission, an optimistic commit or its
/// rollback, and an executed Command alike. Echoes that only care that
/// "state changed" can subscribe to this instead of duplicating the
/// per-event-type wiring for every Flow/Command in the feature.
final class EventCommitted extends Event {
  /// Name of the Flow/Ripple/Command that produced the change — the same
  /// string recorded as the transaction's `source` in the ledger.
  final String source;

  const EventCommitted(this.source);
}
