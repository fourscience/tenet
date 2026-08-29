import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:tenet/tenet.dart';

import 'callback_emitter.dart';

/// One attempt at running [body] for [event], as a `Stream<S>`: every
/// `emit` becomes a stream value, completion closes the stream, and a
/// thrown error becomes a stream error — the shape `Rx.retry`/
/// `Rx.retryWhen` need from a `streamFactory`, since they re-invoke it
/// fresh for each attempt.
Stream<S> _attempt<S, E>(RippleBody<S, E> body, E event) {
  final controller = StreamController<S>();
  unawaited(
    body(event, CallbackEmitter<S>(controller.add)).then(
      (_) => controller.close(),
      onError: (Object e, StackTrace st) {
        controller.addError(e, st);
        controller.close();
      },
    ),
  );
  return controller.stream;
}

/// Retries [body] via rxdart's `Rx.retryWhen`, giving full control over
/// backoff/predicate logic: [retryWhenFactory] gets the failure and
/// decides whether/when to retry by returning a `Stream<void>` — retrying
/// once that stream emits its first value, or propagating the failure (as
/// the sole error, if [retryWhenFactory] passes the same `error`/
/// `stackTrace` through) if it emits an error instead.
///
/// [body] re-runs from scratch on every attempt — same as `tenet`'s own
/// `retry` — since there is no way to resume a partially-run Ripple.
/// Unlike [rxRetry], this does **not** special-case `ScopeDeadException`:
/// pass a [retryWhenFactory] that re-throws it (`(e, s) => e is
/// ScopeDeadException ? Stream.error(e, s) : ...`) to keep that
/// guarantee, or use [rxRetry] for it built in.
///
/// See `Rx.retryWhen`'s doc comment (`package:rxdart/rxdart.dart`) for
/// worked examples of [retryWhenFactory].
RippleBody<S, E> rxRetryWhen<S, E>(
  RippleBody<S, E> body,
  Stream<void> Function(Object error, StackTrace stackTrace) retryWhenFactory,
) {
  return (event, emit) async {
    await for (final s in Rx.retryWhen(
      () => _attempt(body, event),
      retryWhenFactory,
    )) {
      emit(s);
    }
  };
}

/// Retries [body] via rxdart's `Rx.retryWhen`, up to [count] times, with a
/// fixed [delay] between attempts — an `rxRetryWhen` preset matching
/// `tenet`'s own `retry` signature and semantics (including never
/// retrying a `ScopeDeadException`, since a cancelled scope means every
/// further attempt would do real work only to fail the same way), for
/// projects that want the rest of their Ripple pipeline built from rxdart
/// operators without giving up that guarantee.
///
/// [body] runs at most `count + 1` times in total, same as `tenet`'s
/// `retry`. Use [rxRetryWhen] directly for backoff, jitter, or
/// error-type-specific retry logic beyond a fixed delay.
RippleBody<S, E> rxRetry<S, E>(
  RippleBody<S, E> body, {
  required int count,
  Duration delay = Duration.zero,
}) {
  return (event, emit) async {
    var attempt = 0;
    final retrying = rxRetryWhen<S, E>(body, (error, stackTrace) {
      if (error is ScopeDeadException) {
        return Stream<void>.error(error, stackTrace);
      }
      attempt++;
      if (attempt > count) return Stream<void>.error(error, stackTrace);
      return delay > Duration.zero
          ? Stream<void>.fromFuture(Future<void>.delayed(delay))
          : Stream<void>.value(null);
    });
    await retrying(event, emit);
  };
}
