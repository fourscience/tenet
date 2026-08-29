import 'dart:async';

import 'package:tenet/tenet.dart';

/// Drives a [Store] from a `Stream<E>` you've already built with whatever
/// rxdart operators you want — `switchMap`, `debounceTime`, `retryWhen`,
/// anything — instead of composing `tenet`'s own combinators around a
/// single [RippleBody]. Each method subscribes to a stream and calls the
/// matching write method ([dispatch]/[send]/[runRipple]) for every value
/// it emits, until the returned [FlowScope] closes.
///
/// ```dart
/// final searchResults = searchBox.stream
///     .debounceTime(const Duration(milliseconds: 300))
///     .distinct()
///     .switchMap((query) => Stream.fromFuture(api.search(query)));
///
/// store.runRippleStream<SearchResults>(
///   searchResults,
///   (results, emit) async => emit(state.copyWith(results: results)),
/// );
/// ```
///
/// A failure — either [events] erroring, or the write method itself
/// throwing (e.g. [send] with no registered handler) — is never thrown
/// back into [events]' own subscription; it's reported to the current
/// [Zone]'s uncaught-error handler, the same place `Store`'s own
/// `onError`/`onEchoError` fall back to with no handler registered.
/// [Store.onError]/[Store.onEchoError] specifically only ever see
/// failures from Echoes/Ripples the store itself runs — this extension
/// lives outside the store, with no access to those private handler
/// lists, so route failures worth handling explicitly through the
/// stream itself (e.g. `events.handleError(...)`) rather than relying on
/// this fallback.
extension StoreRx<S> on Store<S> {
  /// Dispatches every value from [events] via [dispatch], until the
  /// returned [FlowScope] closes.
  FlowScope dispatchStream<E>(
    Stream<E> events, {
    String source = 'rx-stream',
    FlowScope? scope,
  }) =>
      _drive<E>(events, scope, source, dispatch<E>);

  /// Sends every [Intent] from [events] via [send], until the returned
  /// [FlowScope] closes.
  FlowScope sendStream(
    Stream<Intent> events, {
    String source = 'rx-stream',
    FlowScope? scope,
  }) =>
      _drive<Intent>(events, scope, source, send);

  /// Runs [body] as a Ripple for every value from [events] via
  /// [runRipple], until the returned [FlowScope] closes — each value gets
  /// its own Ripple invocation of [body], all sharing the one scope this
  /// returns (so closing it cancels every Ripple started this way, not
  /// just the most recent one).
  FlowScope runRippleStream<E>(
    Stream<E> events,
    RippleBody<S, E> body, {
    String source = 'rx-stream',
    FlowScope? scope,
  }) =>
      _drive<E>(
        events,
        scope,
        source,
        (e) => runRipple<E>(body, event: e, source: source),
      );

  FlowScope _drive<E>(
    Stream<E> events,
    FlowScope? scope,
    String source,
    void Function(E event) onEvent,
  ) {
    final effective = scope ?? rootScope.spawn('$source-scope');
    final sub = events.listen(
      (event) {
        if (effective.isDead) return;
        try {
          onEvent(event);
        } catch (e, st) {
          Zone.current.handleUncaughtError(e, st);
        }
      },
      onError: (Object e, StackTrace st) =>
          Zone.current.handleUncaughtError(e, st),
    );
    unawaited(effective.cancelled.whenComplete(sub.cancel));
    return effective;
  }
}
