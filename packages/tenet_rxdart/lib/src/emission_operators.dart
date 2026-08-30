import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:tenet/tenet.dart';

import 'callback_emitter.dart';

/// Pipes [body]'s own `emit` calls through [transform] before they reach
/// the real emitter — the general bridge that makes *any* rxdart `Stream`
/// operator usable around a Ripple's emissions, not just the two this
/// package wraps by name ([rxThrottle]/[rxDebounce]).
///
/// ```dart
/// rxTransform(myRipple, (emissions) => emissions.bufferTime(
///   const Duration(seconds: 1),
/// ).map((batch) => batch.last));
/// ```
///
/// [transform] runs once per Ripple invocation, over a fresh `Stream<S>`
/// fed by this call's own `emit`s — it never sees emissions from a
/// different event or a different Ripple invocation. This waits for
/// [transform]'s output stream to fully drain (so a trailing, delayed
/// value — the whole point of debounce/throttle — still reaches the real
/// emitter) before returning, even if [body] itself already finished or
/// threw; [body]'s own error, if any, is what this rethrows afterward.
RippleBody<S, E> rxTransform<S, E>(
  RippleBody<S, E> body,
  Stream<S> Function(Stream<S> emissions) transform,
) {
  return (event, emit) async {
    final controller = StreamController<S>();
    final drained = Completer<void>();
    transform(controller.stream).listen(
      emit.call,
      onDone: () {
        if (!drained.isCompleted) drained.complete();
      },
      onError: (Object e, StackTrace st) {
        if (!drained.isCompleted) drained.completeError(e, st);
      },
      cancelOnError: true,
    );

    Object? bodyError;
    StackTrace? bodyStack;
    try {
      await body(event, CallbackEmitter<S>(controller.add));
    } catch (e, st) {
      bodyError = e;
      bodyStack = st;
    } finally {
      await controller.close();
    }

    try {
      await drained.future;
    } catch (_) {
      // A transform-stream error (from a custom `transform`) is only
      // rethrown here when `body` itself didn't already fail — body's
      // error, if any, takes precedence below since it happened first.
      if (bodyError == null) rethrow;
    }

    if (bodyError != null) {
      Error.throwWithStackTrace(bodyError, bodyStack!);
    }
  };
}

/// Rate-limits [body]'s emissions via rxdart's `throttleTime`, instead of
/// `tenet`'s own `throttled`. Unlike `throttled`, this supports rxdart's
/// `trailing` option (emit the last value in the window too, not just the
/// first).
///
/// This throttles [body]'s own `emit` calls *within one invocation* — a
/// Ripple that emits several progress values in a burst and only wants
/// the store bothered with some of them. It does **not** rate-limit
/// repeated `runRipple`/`dispatch` calls (e.g. a search box re-dispatching
/// on every keystroke); for that, apply `.throttleTime`/`.debounceTime`
/// directly to the `Stream<E>` of incoming events and drive the store
/// with it via `StoreRx.runRippleStream`/`dispatchStream`.
///
/// See [Stream.throttleTime] (from `package:rxdart/rxdart.dart`) for the
/// exact semantics of [leading]/[trailing].
RippleBody<S, E> rxThrottle<S, E>(
  RippleBody<S, E> body,
  Duration duration, {
  bool leading = true,
  bool trailing = false,
}) =>
    rxTransform(
      body,
      (emissions) => emissions.throttleTime(duration,
          leading: leading, trailing: trailing),
    );

/// Delays [body]'s emissions via rxdart's `debounceTime`, instead of
/// hand-rolling one: only a value not followed by another within
/// [duration] reaches the real emitter — unlike `tenet`'s `throttled`,
/// which is leading-edge and never delays a value to wait for silence.
///
/// Like [rxThrottle], this debounces [body]'s own `emit` calls *within
/// one invocation*, not repeated `runRipple`/`dispatch` calls — see
/// [rxThrottle]'s doc comment for the distinction and where to look
/// instead (`StoreRx`) for debouncing repeated calls.
///
/// See [Stream.debounceTime] (from `package:rxdart/rxdart.dart`).
RippleBody<S, E> rxDebounce<S, E>(RippleBody<S, E> body, Duration duration) =>
    rxTransform(body, (emissions) => emissions.debounceTime(duration));
