/// [Resource] — the tri-state for an asynchronous value: [Loading],
/// [Ready] with data, or [ResourceError] (optionally holding stale
/// last-known-good data).
library;

import 'package:meta/meta.dart';

import 'result.dart';

/// The state of an asynchronous value as it loads, arrives, or fails:
/// [Loading], [Ready] with data of type [T], or [ResourceError] — which
/// may retain the last-known-good data for a stale-while-revalidate UI.
/// Sealed, so a `switch` over a [Resource] is exhaustive and
/// compiler-checked. Named `Resource` following the Android/Jetpack
/// `Resource` prior art.
///
/// ```dart
/// ResourceBuilder<User>(
///   resource: state,
///   loading: (_) => const ProgressSkeleton(),
///   ready: (_, user) => ProfileView(user),
///   error: (_, error, previous) => previous != null
///       ? ProfileView(previous)          // stale data + banner
///       : RetryView(onRetry: bloc.reload),
/// );
/// ```
@immutable
sealed class Resource<T> {
  const Resource();

  /// Creates a [Resource] representing an in-flight operation.
  const factory Resource.loading() = Loading<T>;

  /// Creates a [Resource] holding the successfully-loaded [data].
  const factory Resource.ready(T data) = Ready<T>;

  /// Creates a [Resource] representing a failed operation. [previousData]
  /// optionally carries the last-known-good value, for a
  /// stale-while-revalidate UI that keeps showing it alongside the error.
  const factory Resource.error(
    Object error, {
    StackTrace? stackTrace,
    T? previousData,
  }) = ResourceError<T>;

  /// Whether this is [Loading].
  bool get isLoading => this is Loading<T>;

  /// Whether this is [Ready].
  bool get hasData => this is Ready<T>;

  /// Whether this is [ResourceError].
  bool get hasError => this is ResourceError<T>;

  /// Reduces this [Resource] to a single value of type [R] by handling
  /// all three states — the primary way to consume a [Resource] without
  /// a `switch`.
  R fold<R>({
    required R Function() onLoading,
    required R Function(T data) onData,
    required R Function(Object error, StackTrace? stackTrace, T? previous)
        onError,
  }) =>
      switch (this) {
        Loading() => onLoading(),
        Ready(:final data) => onData(data),
        ResourceError(:final error, :final stackTrace, :final previousData) =>
          onError(error, stackTrace, previousData),
      };

  /// Transforms the data. [Loading] passes through unchanged; a
  /// [ResourceError]'s `previousData` is mapped too when present, so
  /// stale-while-revalidate UIs keep seeing transformed data.
  Resource<R> map<R>(R Function(T data) transform) => switch (this) {
        Loading() => Resource<R>.loading(),
        Ready(:final data) => Resource<R>.ready(transform(data)),
        ResourceError(:final error, :final stackTrace, :final previousData) =>
          Resource<R>.error(
            error,
            stackTrace: stackTrace,
            previousData: previousData == null ? null : transform(previousData),
          ),
      };

  /// Chains another [Resource]-returning step onto the data, flattening
  /// the result — the monadic bind. [Loading] and [ResourceError]
  /// propagate without calling [transform]; a [ResourceError]'s
  /// `previousData` is dropped rather than guessed at, since deriving an
  /// [R] from it would mean calling [transform] just to discard the
  /// [Resource] it returns.
  Resource<R> flatMap<R>(Resource<R> Function(T data) transform) =>
      switch (this) {
        Loading() => Resource<R>.loading(),
        Ready(:final data) => transform(data),
        ResourceError(:final error, :final stackTrace) => Resource<R>.error(
            error,
            stackTrace: stackTrace,
          ),
      };

  /// The current value: the data if [Ready], the last-known-good data if
  /// [ResourceError], or `null` if [Loading].
  T? get dataOrNull => switch (this) {
        Loading() => null,
        Ready(:final data) => data,
        ResourceError(:final previousData) => previousData,
      };

  /// Currently identical to [dataOrNull]. Reserved as the extension point
  /// for a future `Refreshing<T>` state (a [Loading] that also carries
  /// previous data for a reload-in-place UI) — at that point this getter
  /// would keep surfacing the previous value through a reload while
  /// [dataOrNull] would not.
  T? get dataOrPrevious => dataOrNull;

  /// Turns a [ResourceError] into [Ready] via [fallback]; [Loading] and
  /// [Ready] pass through untouched.
  Resource<T> recover(T Function(Object error) fallback) => switch (this) {
        Loading() => this,
        Ready() => this,
        ResourceError(:final error) => Resource<T>.ready(fallback(error)),
      };
}

/// An in-flight [Resource]. Every [Loading] is equal to every other
/// [Loading], regardless of type argument — there's no data to compare.
final class Loading<T> extends Resource<T> {
  /// Creates a [Resource] representing an in-flight operation.
  const Loading();

  @override
  bool operator ==(Object other) => other is Loading;

  @override
  int get hashCode => 'Loading'.hashCode;

  @override
  String toString() => 'Loading';
}

/// A successfully-loaded [Resource], holding [data].
///
/// Two [Ready]s are equal when their data is, regardless of how each
/// one's type argument was inferred.
final class Ready<T> extends Resource<T> {
  /// The loaded data.
  final T data;

  /// Creates a [Resource] holding the successfully-loaded [data].
  const Ready(this.data);

  @override
  bool operator ==(Object other) => other is Ready && other.data == data;

  @override
  int get hashCode => Object.hash('Ready', data);

  @override
  String toString() => 'Ready($data)';
}

/// A failed [Resource], holding an [error], the [stackTrace] that
/// produced it when known, and optionally [previousData] retained from
/// before the failure for a stale-while-revalidate UI.
final class ResourceError<T> extends Resource<T> {
  /// The error.
  final Object error;

  /// The stack trace at the point [error] was thrown, if known.
  final StackTrace? stackTrace;

  /// The last-known-good data, if any was retained across the failure.
  final T? previousData;

  /// Creates a [Resource] representing a failed operation.
  const ResourceError(this.error, {this.stackTrace, this.previousData});

  @override
  bool operator ==(Object other) =>
      other is ResourceError &&
      other.error == error &&
      other.stackTrace == stackTrace &&
      other.previousData == previousData;

  @override
  int get hashCode =>
      Object.hash('ResourceError', error, stackTrace, previousData);

  @override
  String toString() => 'ResourceError($error, previousData: $previousData)';
}

/// Bridges [Result] into [Resource] — useful when a repository already
/// returns [Result] but a UI layer wants the tri-state [Resource].
extension ResultResourceExt<T> on Result<T> {
  /// Converts to [Resource]: [Success] becomes [Ready], [Failure] becomes
  /// [ResourceError] (with no `previousData` — a bare [Result] carries
  /// none to retain).
  Resource<T> toResource() => fold(
        onSuccess: Resource<T>.ready,
        onFailure: (error, stackTrace) =>
            Resource<T>.error(error, stackTrace: stackTrace),
      );
}
