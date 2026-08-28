import 'dart:async';

import 'core.dart';

/// Composable behavior wrappers for Ripples: retry, timeout, debounce.
/// Each is a pure decorator of [RippleBody] — open/closed principle in
/// action: new behaviors require no changes to `Store` or `Feature`.

/// Retries [body] up to [max] times with linear backoff of [delay].
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
      } catch (_) {
        attempt++;
        if (attempt > max) rethrow;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
      }
    }
  };
}

/// Fails with [TimeoutException] if [body] does not finish within [limit].
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
