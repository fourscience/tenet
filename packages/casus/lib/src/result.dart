/// [Result] — the outcome of a fallible operation: [Success] with a
/// value, or [Failure] with the error and stack trace that produced it.
library;

import 'package:meta/meta.dart';

import 'either.dart';

/// The outcome of an operation that can fail: [Success] with a value of
/// type [T], or [Failure] with an [Object] error and (whenever it's
/// available) the [StackTrace] that produced it. Sealed, so a `switch`
/// over a [Result] is exhaustive and compiler-checked:
///
/// ```dart
/// switch (result) {
///   case Success(:final value): print('got $value');
///   case Failure(:final failure, :final stackTrace):
///     print('failed: $failure');
/// }
/// ```
///
/// Prefer this over letting an exception propagate through business logic
/// — a [Failure] is a value the caller can inspect, transform, and
/// recover from, and its stack trace travels with it instead of being
/// lost the moment the `catch` block ends.
@immutable
sealed class Result<T> {
  const Result();

  /// Creates a successful [Result] holding [value].
  const factory Result.success(T value) = Success<T>;

  /// Creates a failed [Result] holding [failure] and, whenever caught
  /// from an exception, its [stackTrace] — always pass one when adapting
  /// a `catch` block by hand; [guard]/[guardAsync] do this for you.
  const factory Result.failure(Object failure, [StackTrace? stackTrace]) =
      Failure<T>;

  /// Runs [body], catching anything it throws into a [Failure] together
  /// with the stack trace at the point it was thrown. The synchronous
  /// counterpart to [guardAsync].
  ///
  /// ```dart
  /// final parsed = Result.guard(() => int.parse(input));
  /// ```
  static Result<T> guard<T>(T Function() body) {
    try {
      return Result<T>.success(body());
    } catch (error, stackTrace) {
      return Result<T>.failure(error, stackTrace);
    }
  }

  /// Runs [body], catching anything it throws — including after an
  /// `await` — into a [Failure] together with its stack trace.
  ///
  /// ```dart
  /// final response = await Result.guardAsync(() => http.get(url));
  /// ```
  static Future<Result<T>> guardAsync<T>(Future<T> Function() body) async {
    try {
      return Result<T>.success(await body());
    } catch (error, stackTrace) {
      return Result<T>.failure(error, stackTrace);
    }
  }

  /// Whether this is [Success].
  bool get isSuccess => this is Success<T>;

  /// Whether this is [Failure].
  bool get isFailure => this is Failure<T>;

  /// Transforms the success value; a [Failure] passes through untouched,
  /// with its error and stack trace preserved exactly.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Success(:final value) => Result<R>.success(transform(value)),
        Failure(:final failure, :final stackTrace) => Result<R>.failure(
            failure,
            stackTrace,
          ),
      };

  /// Chains another [Result]-returning step onto a success value,
  /// flattening the result — the monadic bind. Use this instead of [map]
  /// when [transform] itself returns a [Result]; a [Failure]
  /// short-circuits without calling [transform].
  ///
  /// ```dart
  /// Result<Credentials> validate(FormData f) =>
  ///     email(f.email).flatMap((_) => password(f.password))
  ///         .map((_) => Credentials.fromForm(f));
  /// ```
  Result<R> flatMap<R>(Result<R> Function(T value) transform) => switch (this) {
        Success(:final value) => transform(value),
        Failure(:final failure, :final stackTrace) => Result<R>.failure(
            failure,
            stackTrace,
          ),
      };

  /// The value, or [fallback] if this is a [Failure].
  T getOrElse(T fallback) => switch (this) {
        Success(:final value) => value,
        Failure() => fallback,
      };

  /// The value, or the result of [orElse] applied to the failure —
  /// for a fallback that depends on what went wrong.
  T getOrElseWith(T Function(Object failure) orElse) => switch (this) {
        Success(:final value) => value,
        Failure(:final failure) => orElse(failure),
      };

  /// Turns a [Failure] into a new [Result] via [onFailure]; a [Success]
  /// passes through untouched.
  Result<T> recover(Result<T> Function(Object failure) onFailure) =>
      switch (this) {
        Success() => this,
        Failure(:final failure) => onFailure(failure),
      };

  /// The value, or throws a [ResultUnwrapException] carrying the original
  /// failure and stack trace if this is a [Failure].
  ///
  /// For tests and prototypes only — prefer [fold]/[recover]/pattern
  /// matching wherever a failure is a case production code must handle.
  T unwrap() => switch (this) {
        Success(:final value) => value,
        Failure(:final failure, :final stackTrace) =>
          throw ResultUnwrapException(
            failure,
            stackTrace,
          ),
      };

  /// Reduces this [Result] to a single value of type [R] by handling both
  /// cases — the primary way to consume a [Result] without a `switch`.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object failure, StackTrace? stackTrace) onFailure,
  }) =>
      switch (this) {
        Success(:final value) => onSuccess(value),
        Failure(:final failure, :final stackTrace) => onFailure(
            failure,
            stackTrace,
          ),
      };

  /// Runs [action] for its side effect if this is [Success], then returns
  /// this same [Result] unchanged — for telescoping onSuccess/onFailure
  /// calls.
  ///
  /// ```dart
  /// final r = await repo.save(order)
  ///     ..onSuccess(syncCache)
  ///     ..onFailure((e, st) => telemetry.report(e, st));
  /// ```
  Result<T> onSuccess(void Function(T value) action) {
    if (this case Success(:final value)) action(value);
    return this;
  }

  /// Runs [action] for its side effect if this is [Failure], then returns
  /// this same [Result] unchanged — for telescoping onSuccess/onFailure
  /// calls.
  Result<T> onFailure(
    void Function(Object failure, StackTrace? stackTrace) action,
  ) {
    if (this case Failure(:final failure, :final stackTrace)) {
      action(failure, stackTrace);
    }
    return this;
  }

  /// Converts to [Either]: [Success] becomes [Right], [Failure] becomes
  /// [Left]. [Either] has no slot for a stack trace, so it is discarded —
  /// use [fold]/[unwrap]/pattern matching directly when the stack trace
  /// matters.
  Either<Object, T> toEither() => switch (this) {
        Success(:final value) => Either<Object, T>.right(value),
        Failure(:final failure) => Either<Object, T>.left(failure),
      };
}

/// A successful [Result], holding a [value].
///
/// Two [Success]es are equal when their values are, regardless of how
/// each one's type argument was inferred — see [Some] in `option.dart`
/// for why the type argument is deliberately left out of the comparison.
final class Success<T> extends Result<T> {
  /// The success value.
  final T value;

  /// Creates a successful [Result] holding [value].
  const Success(this.value);

  @override
  bool operator ==(Object other) => other is Success && other.value == value;

  @override
  int get hashCode => Object.hash('Success', value);

  @override
  String toString() => 'Success($value)';
}

/// A failed [Result], holding a [failure] and, whenever available, the
/// [stackTrace] that produced it.
final class Failure<T> extends Result<T> {
  /// The error.
  final Object failure;

  /// The stack trace at the point [failure] was thrown, if known.
  final StackTrace? stackTrace;

  /// Creates a failed [Result] holding [failure] and [stackTrace].
  const Failure(this.failure, [this.stackTrace]);

  @override
  bool operator ==(Object other) =>
      other is Failure &&
      other.failure == failure &&
      other.stackTrace == stackTrace;

  @override
  int get hashCode => Object.hash('Failure', failure, stackTrace);

  @override
  String toString() => 'Failure($failure)';
}

/// Thrown by [Result.unwrap] when called on a [Failure]. Carries the
/// original [failure] and [stackTrace] so the caller doesn't lose them.
final class ResultUnwrapException implements Exception {
  /// The original failure being unwrapped.
  final Object failure;

  /// The original stack trace, if the [Result] carried one.
  final StackTrace? stackTrace;

  /// Creates a [ResultUnwrapException] wrapping [failure]/[stackTrace].
  const ResultUnwrapException(this.failure, [this.stackTrace]);

  @override
  String toString() =>
      'ResultUnwrapException: unwrap() called on Failure($failure)';
}
