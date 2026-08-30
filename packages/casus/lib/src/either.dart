/// [Either] — a general-purpose two-channel union: [Left] (conventionally
/// the error/alternate channel) or [Right] (conventionally the "correct",
/// primary channel).
library;

import 'package:meta/meta.dart';

import 'result.dart';

/// A value that is one of two types: [Left] holding an [L], or [Right]
/// holding an [R]. Sealed, so a `switch` over an [Either] is exhaustive
/// and compiler-checked.
///
/// By convention the right channel is the "correct"/primary one — map/
/// flatMap operate on it — and the left channel carries an error or
/// alternate outcome, mirroring [Result]'s success/failure without tying
/// the error type to `Object`:
///
/// ```dart
/// Either<FieldError, Credentials> validate(FormData f) =>
///     email(f.email).flatMap((_) => password(f.password)).map(Credentials.new);
/// ```
@immutable
sealed class Either<L, R> {
  const Either();

  /// Creates an [Either] holding [value] on the left channel.
  const factory Either.left(L value) = Left<L, R>;

  /// Creates an [Either] holding [value] on the right channel.
  const factory Either.right(R value) = Right<L, R>;

  /// Whether this is [Left].
  bool get isLeft => this is Left<L, R>;

  /// Whether this is [Right].
  bool get isRight => this is Right<L, R>;

  /// Reduces this [Either] to a single value of type [R2] by handling
  /// both channels — the primary way to consume an [Either] without a
  /// `switch`.
  R2 fold<R2>({
    required R2 Function(L value) onLeft,
    required R2 Function(R value) onRight,
  }) =>
      switch (this) {
        Left(:final value) => onLeft(value),
        Right(:final value) => onRight(value),
      };

  /// Transforms the right-channel value; a [Left] passes through
  /// untouched.
  Either<L, R2> map<R2>(R2 Function(R value) transform) => switch (this) {
        Left(:final value) => Either<L, R2>.left(value),
        Right(:final value) => Either<L, R2>.right(transform(value)),
      };

  /// Transforms the left-channel value (typically an error); a [Right]
  /// passes through untouched. Use this to adapt one error type to
  /// another as it crosses a layer boundary.
  Either<L2, R> mapLeft<L2>(L2 Function(L value) transform) => switch (this) {
        Left(:final value) => Either<L2, R>.left(transform(value)),
        Right(:final value) => Either<L2, R>.right(value),
      };

  /// Chains another [Either]-returning step onto a right-channel value,
  /// flattening the result — the monadic bind. A [Left] short-circuits
  /// without calling [transform].
  Either<L, R2> flatMap<R2>(Either<L, R2> Function(R value) transform) =>
      switch (this) {
        Left(:final value) => Either<L, R2>.left(value),
        Right(:final value) => transform(value),
      };

  /// Exchanges the two channels: [Left] becomes [Right] and vice versa.
  Either<R, L> swap() => switch (this) {
        Left(:final value) => Either<R, L>.right(value),
        Right(:final value) => Either<R, L>.left(value),
      };

  /// The right-channel value, or [fallback] if this is [Left].
  R getOrElse(R fallback) => switch (this) {
        Left() => fallback,
        Right(:final value) => value,
      };

  /// Runs [action] for its side effect if this is [Left], then returns
  /// this same [Either] unchanged — for telescoping onLeft/onRight calls.
  Either<L, R> onLeft(void Function(L value) action) {
    if (this case Left(:final value)) action(value);
    return this;
  }

  /// Runs [action] for its side effect if this is [Right], then returns
  /// this same [Either] unchanged — for telescoping onLeft/onRight calls.
  Either<L, R> onRight(void Function(R value) action) {
    if (this case Right(:final value)) action(value);
    return this;
  }

  /// Converts to [Result]: [Right] becomes [Success], [Left] becomes
  /// [Failure] with no stack trace (an [Either] carries none). Assumes
  /// the left value is non-null, since [Result.failure] requires a
  /// non-null [Object].
  Result<R> toResult() => switch (this) {
        Left(:final value) => Result<R>.failure(value as Object),
        Right(:final value) => Result<R>.success(value),
      };
}

/// The left channel of an [Either], holding a [value].
///
/// Two [Left]s are equal when their values are, regardless of how each
/// one's type arguments were inferred — see [Some] in `option.dart` for
/// why type arguments are deliberately left out of the comparison.
final class Left<L, R> extends Either<L, R> {
  /// The left-channel value.
  final L value;

  /// Creates an [Either] holding [value] on the left channel.
  const Left(this.value);

  @override
  bool operator ==(Object other) => other is Left && other.value == value;

  @override
  int get hashCode => Object.hash('Left', value);

  @override
  String toString() => 'Left($value)';
}

/// The right channel of an [Either], holding a [value].
///
/// Two [Right]s are equal when their values are, regardless of how each
/// one's type arguments were inferred.
final class Right<L, R> extends Either<L, R> {
  /// The right-channel value.
  final R value;

  /// Creates an [Either] holding [value] on the right channel.
  const Right(this.value);

  @override
  bool operator ==(Object other) => other is Right && other.value == value;

  @override
  int get hashCode => Object.hash('Right', value);

  @override
  String toString() => 'Right($value)';
}
