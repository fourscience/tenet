/// rxdart interop for `tenet`.
///
/// `retry`/`withTimeout`/`throttled`, `tenet`'s own Ripple combinators,
/// cover the common cases without pulling in a dependency. This package
/// is for reaching further: `rxThrottle`/`rxDebounce` back onto rxdart's
/// real `throttleTime`/`debounceTime` (trailing-edge support, dynamic
/// windows via [rxTransform]), and `rxRetry`/`rxRetryWhen` back onto
/// `Rx.retryWhen` (predicate/backoff logic beyond a fixed delay) — plus a
/// [Store] extension for driving dispatch straight from a `Stream<E>`
/// pipeline you've already built with any rxdart operator at all.
///
/// Two different things can want "debounce"/"throttle": rate-limiting the
/// emissions *within one Ripple invocation* (`rxThrottle`/`rxDebounce`),
/// or rate-limiting *repeated calls* — a search box re-dispatching on
/// every keystroke. The second is a `StoreRx.dispatchStream`/
/// `runRippleStream` call over a `Stream<E>` with `.debounceTime`/
/// `.throttleTime` already applied to it, not `rxDebounce`/`rxThrottle`.
///
/// ```dart
/// final resilientSync = rxRetry<CartState, SyncRequested>(
///   rxDebounce((event, emit) async { /* ... */ }, const Duration(seconds: 1)),
///   count: 3,
///   delay: const Duration(milliseconds: 200),
/// );
///
/// store.runRipple(resilientSync, event: SyncRequested(store.state.value));
/// ```
library;

export 'package:tenet/tenet.dart';

export 'src/emission_operators.dart';
export 'src/retry_operators.dart';
export 'src/stream_driver.dart';
