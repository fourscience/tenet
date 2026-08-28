import 'dart:async';

import 'core.dart';
import 'flow_scope.dart';

/// Composable behavior wrappers for Ripples: retry, timeout, debounce.
/// Each is a pure decorator of [RippleBody] — open/closed principle in
/// action: new behaviors require no changes to `Store` or `Feature`.

/// Retries [body] after a failure, up to [max] times, waiting a fixed
/// [delay] between attempts — so the body runs at most `max + 1` times in
/// total (one initial attempt plus [max] retries).
///
/// A [ScopeDeadException] is never retried: it means the Ripple's scope
/// was cancelled (its screen was disposed, say), so every further attempt
/// would fail the same way while doing real work — retrying cancelled
/// work is worse than not retrying at all.
RippleBody<S, E> retry<S, E>(
  RippleBody<S, E> body, {
  required int max,
  Duration delay = Duration.zero,
}) {
  return (event, emit) async {
    var attempt = 0;
    while (true) {
      try {
        await body(event, emit);
        return;
      } on ScopeDeadException {
        rethrow;
      } catch (_) {
        attempt++;
        if (attempt > max) rethrow;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
      }
    }
  };
}

/// Fails with [TimeoutException] if [body] does not finish within [limit].
///
/// Dart has no way to abort a future, so [body] itself keeps running after
/// the timeout — but it can no longer change state: the store settles the
/// Ripple's emitter as soon as this returns, and a late `emit` from the
/// still-running body is dropped and reported instead of committed. Give
/// [body] a real cancellation path (racing `FlowScope.cancelled`, an
/// `HttpClient` you close) if the work itself needs to stop, not just its
/// effect on state.
RippleBody<S, E> withTimeout<S, E>(RippleBody<S, E> body, Duration limit) {
  return (event, emit) => body(event, emit).timeout(limit);
}

/// Ignores rapid successive invocations; only the first call within
/// [window] runs — later calls inside the window become no-ops.
RippleBody<S, E> debounced<S, E>(
  RippleBody<S, E> body,
  Duration window, {
  DateTime Function()? now,
}) {
  DateTime? lastRun;
  final clock = now ?? DateTime.now;
  return (event, emit) async {
    final t = clock();
    if (lastRun != null && t.difference(lastRun!) < window) return;
    lastRun = t;
    await body(event, emit);
  };
}
