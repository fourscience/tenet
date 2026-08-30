/// Extensions gluing [Result], [Either], [Option], nullable types, and
/// `Iterable`/`Future` together.
library;

import 'either.dart';
import 'option.dart';
import 'result.dart';

/// Consumes a `Future<Result<T>>` without an intermediate `await`.
extension ResultFutureExt<T> on Future<Result<T>> {
  /// Awaits this future, then reduces its [Result] to a single value of
  /// type [R] by handling both cases.
  Future<R> fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object failure, StackTrace? stackTrace) onFailure,
  }) async {
    final result = await this;
    return result.fold(onSuccess: onSuccess, onFailure: onFailure);
  }
}

/// Lifts a nullable value into an [Option].
extension NullableExt<T> on T? {
  /// `null` becomes [None], anything else becomes [Some].
  Option<T> get asOption => Option.fromNullable<T>(this);
}

/// Collapses a list of [Option]s into a single one.
extension IterableOptionExt<T> on Iterable<Option<T>> {
  /// [Some] with the collected list of values if every element is
  /// [Some]; the first [None] encountered otherwise.
  Option<List<T>> sequence() {
    final values = <T>[];
    for (final option in this) {
      switch (option) {
        case Some(:final value):
          values.add(value);
        case None():
          return Option<List<T>>.none();
      }
    }
    return Option<List<T>>.some(values);
  }
}

/// Collapses a list of [Result]s into a single one.
extension IterableResultExt<T> on Iterable<Result<T>> {
  /// [Success] with the collected list of values if every element
  /// succeeded; the first [Failure] encountered otherwise.
  Result<List<T>> sequence() {
    final values = <T>[];
    for (final result in this) {
      switch (result) {
        case Success(:final value):
          values.add(value);
        case Failure(:final failure, :final stackTrace):
          return Result<List<T>>.failure(failure, stackTrace);
      }
    }
    return Result<List<T>>.success(values);
  }
}

/// Collapses a list of [Either]s into a single one.
extension IterableEitherExt<L, R> on Iterable<Either<L, R>> {
  /// [Right] with the collected list of values if every element is
  /// [Right]; the first [Left] encountered otherwise.
  Either<L, List<R>> sequence() {
    final values = <R>[];
    for (final either in this) {
      switch (either) {
        case Right(:final value):
          values.add(value);
        case Left(:final value):
          return Either<L, List<R>>.left(value);
      }
    }
    return Either<L, List<R>>.right(values);
  }
}

/// Maps each element through an async, [Result]-returning step and
/// collapses the results into one.
extension IterableTraverseResultExt<T> on Iterable<T> {
  /// Awaits [transform] applied to each element in order, stopping at
  /// (and returning) the first [Failure]; otherwise returns [Success]
  /// with the collected list of transformed values.
  ///
  /// ```dart
  /// final users = await ids.traverse(repo.getUser);
  /// ```
  Future<Result<List<R>>> traverse<R>(
    Future<Result<R>> Function(T value) transform,
  ) async {
    final values = <R>[];
    for (final item in this) {
      final result = await transform(item);
      switch (result) {
        case Success(:final value):
          values.add(value);
        case Failure(:final failure, :final stackTrace):
          return Result<List<R>>.failure(failure, stackTrace);
      }
    }
    return Result<List<R>>.success(values);
  }
}
