import 'package:flutter/widgets.dart';
import 'package:vine/vine.dart';

import 'context_extensions.dart';
import 'vine_widget.dart';

/// Builds UI from a future-shaped vine's [AsyncValue], rebuilding on every
/// transition (loading → data → error → ...):
///
/// ```dart
/// SuspendedVine(
///   vine: profileVine,
///   builder: (context, profile) => Text(profile.name),
///   loading: () => const CircularProgressIndicator(),
///   error: (error, stackTrace) => Text('Failed: $error'),
/// )
/// ```
///
/// Stale-while-revalidate: if [AsyncValue.hasValue] is already true when a
/// refresh transitions to loading (or fails), [builder] keeps being used
/// with that previous data instead of falling back to [loading]/[error] —
/// so a refresh never blanks content that's already on screen. [loading]/
/// [error] are only reached the first time, before any data has ever
/// arrived; both default to an empty box if omitted.
final class SuspendedVine<T> extends VineWidget {
  /// Creates a widget driven by [vine]'s `AsyncValue<T>`.
  const SuspendedVine({
    super.key,
    required this.vine,
    required this.builder,
    this.loading,
    this.error,
  });

  /// The future-shaped vine (`Vine.future`/`Vine.eachAsync` instance) to
  /// watch.
  final Vine<AsyncValue<T>> vine;

  /// Builds the UI for [T] data — either freshly arrived, or preserved
  /// from before a loading/error transition (see the class doc comment).
  final Widget Function(BuildContext context, T data) builder;

  /// Builds the UI shown while loading, only when there's no previous
  /// data to fall back to. Defaults to an empty box.
  final Widget Function()? loading;

  /// Builds the UI shown on failure, only when there's no previous data
  /// to fall back to. Defaults to an empty box.
  final Widget Function(Object error, StackTrace stackTrace)? error;

  @override
  Widget build(BuildContext context) {
    final value = context.watch(vine);
    return value.when(
      data: (data) => builder(context, data),
      loading: () {
        if (value.hasValue) return builder(context, value.value as T);
        return loading?.call() ?? const SizedBox.shrink();
      },
      error: (asyncError) {
        if (asyncError.hasValue) return builder(context, asyncError.value as T);
        return error?.call(asyncError.error, asyncError.stackTrace) ??
            const SizedBox.shrink();
      },
    );
  }
}
