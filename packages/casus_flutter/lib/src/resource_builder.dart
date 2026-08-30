import 'package:casus/casus.dart';
import 'package:flutter/widgets.dart';

/// Renders a [Resource] by delegating to [Resource.fold] — no hidden
/// logic, no implicit retry button, just the three builders the caller
/// supplies.
///
/// ```dart
/// ResourceBuilder<User>(
///   resource: state,
///   loading: (_) => const ProgressSkeleton(),
///   ready: (_, user) => ProfileView(user),
///   error: (_, error, previousData) => previousData != null
///       ? ProfileView(previousData)      // stale data + banner
///       : RetryView(onRetry: bloc.reload),
/// );
/// ```
///
/// [error] receives `previousData` from a [ResourceError] — the caller
/// decides whether to show stale data, a skeleton, or an error view.
class ResourceBuilder<T> extends StatelessWidget {
  /// The [Resource] to render.
  final Resource<T> resource;

  /// Builds the widget shown while [resource] is [Loading].
  final Widget Function(BuildContext context) loading;

  /// Builds the widget shown when [resource] is [Ready].
  final Widget Function(BuildContext context, T data) ready;

  /// Builds the widget shown when [resource] is a [ResourceError].
  /// [previousData] is the error's `previousData`, if any was retained.
  final Widget Function(BuildContext context, Object error, T? previousData)
      error;

  /// Creates a [ResourceBuilder] that renders [resource] via the supplied
  /// builders.
  const ResourceBuilder({
    super.key,
    required this.resource,
    required this.loading,
    required this.ready,
    required this.error,
  });

  @override
  Widget build(BuildContext context) => resource.fold(
        onLoading: () => loading(context),
        onData: (data) => ready(context, data),
        onError: (err, stackTrace, previousData) =>
            error(context, err, previousData),
      );
}
