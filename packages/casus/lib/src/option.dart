/// [Option] — an explicit stand-in for a nullable value: [Some] holding a
/// present value, or [None] holding nothing at all.
library;

import 'package:meta/meta.dart';

/// A value that may or may not be present — [Some] with a value of type
/// [T], or [None]. Sealed, so a `switch` over an [Option] is exhaustive
/// and compiler-checked:
///
/// ```dart
/// switch (option) {
///   case Some(:final value): print('got $value');
///   case None(): print('nothing');
/// }
/// ```
///
/// Prefer this over a nullable `T?` at API boundaries where "absent" is a
/// first-class outcome the caller must handle, not an incidental `null`.
@immutable
sealed class Option<T> {
  const Option();

  /// Creates a present [Option] holding [value].
  const factory Option.some(T value) = Some<T>;

  /// Creates an absent [Option].
  const factory Option.none() = None<T>;

  /// Lifts a nullable value into an [Option]: `null` becomes [None],
  /// anything else becomes [Some].
  static Option<T> fromNullable<T>(T? value) =>
      value == null ? Option<T>.none() : Option<T>.some(value);

  /// Whether this is [Some].
  bool get isPresent => this is Some<T>;

  /// Whether this is [None].
  bool get isAbsent => this is None<T>;

  /// The value if [Some], or `null` if [None].
  T? toNullable() => switch (this) {
        Some(:final value) => value,
        None() => null,
      };

  /// Transforms the value if [Some]; a [None] passes through untouched.
  Option<R> map<R>(R Function(T value) transform) => switch (this) {
        Some(:final value) => Option<R>.some(transform(value)),
        None() => Option<R>.none(),
      };

  /// Chains another [Option]-returning step onto a present value,
  /// flattening the result — the monadic bind. Use this instead of [map]
  /// when [transform] itself returns an [Option].
  ///
  /// ```dart
  /// Option<int> parseAge(String s) => int.tryParse(s).asOption;
  /// Option<String> ageCategory(int age) =>
  ///     age >= 18 ? const Option.some('adult') : const Option.none();
  ///
  /// parseAge('30').flatMap(ageCategory); // Some('adult')
  /// parseAge('x').flatMap(ageCategory);  // None — short-circuits
  /// ```
  Option<R> flatMap<R>(Option<R> Function(T value) transform) => switch (this) {
        Some(:final value) => transform(value),
        None() => Option<R>.none(),
      };

  /// Keeps a [Some] only if its value satisfies [predicate]; otherwise (or
  /// if already [None]) returns [None].
  Option<T> filter(bool Function(T value) predicate) => switch (this) {
        Some(:final value) => predicate(value) ? this : Option<T>.none(),
        None() => this,
      };

  /// The value, or [fallback] if this is [None].
  T getOrElse(T fallback) => switch (this) {
        Some(:final value) => value,
        None() => fallback,
      };

  /// The value, or throws [OptionUnwrapException] if this is [None].
  ///
  /// For tests and prototypes only — prefer [fold]/[getOrElse]/pattern
  /// matching wherever a missing value is a case production code must
  /// handle.
  T unwrap() => switch (this) {
        Some(:final value) => value,
        None() => throw const OptionUnwrapException(),
      };

  /// Reduces this [Option] to a single value of type [R] by handling both
  /// cases — the primary way to consume an [Option] without a `switch`.
  R fold<R>({
    required R Function(T value) onSome,
    required R Function() onNone,
  }) =>
      switch (this) {
        Some(:final value) => onSome(value),
        None() => onNone(),
      };

  /// Runs [action] for its side effect if this is [Some], then returns
  /// this same [Option] unchanged — for telescoping onSome/onNone calls.
  Option<T> onSome(void Function(T value) action) {
    if (this case Some(:final value)) action(value);
    return this;
  }

  /// Runs [action] for its side effect if this is [None], then returns
  /// this same [Option] unchanged — for telescoping onSome/onNone calls.
  Option<T> onNone(void Function() action) {
    if (this is None<T>) action();
    return this;
  }
}

/// A present [Option], holding a [value].
///
/// Two [Some]s are equal when their values are, regardless of how each
/// one's type argument was inferred — comparing type arguments too would
/// make `==` asymmetric, since generics are covariant.
final class Some<T> extends Option<T> {
  /// The present value.
  final T value;

  /// Creates a present [Option] holding [value].
  const Some(this.value);

  @override
  bool operator ==(Object other) => other is Some && other.value == value;

  @override
  int get hashCode => Object.hash('Some', value);

  @override
  String toString() => 'Some($value)';
}

/// An absent [Option].
///
/// Every [None] is equal to every other [None], regardless of type
/// argument — there's no value to compare, so the type alone shouldn't
/// make two "nothing"s unequal.
final class None<T> extends Option<T> {
  /// Creates an absent [Option].
  const None();

  @override
  bool operator ==(Object other) => other is None;

  @override
  int get hashCode => 'None'.hashCode;

  @override
  String toString() => 'None';
}

/// Thrown by [Option.unwrap] when called on a [None].
final class OptionUnwrapException implements Exception {
  /// Creates an [OptionUnwrapException].
  const OptionUnwrapException();

  /// The exception message.
  String get message => 'unwrap() called on None';

  @override
  String toString() => 'OptionUnwrapException: $message';
}
