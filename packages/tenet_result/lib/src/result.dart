/// A type-safe, exception-free way to represent "either a value, or a
/// reason it's missing" — the common `Result`/`Either` pattern, sized for
/// Dart 3 pattern matching.
library;

/// The outcome of an operation that can fail: either [Ok] with a value of
/// type [T], or [Err] with an error of type [E]. Sealed, so a `switch`
/// over a [Result] is exhaustive and compiler-checked:
///
/// ```dart
/// switch (parseAge(input)) {
///   case Ok(value: final age): print('Age: $age');
///   case Err(error: final e): print('Invalid: $e');
/// }
/// ```
///
/// Prefer this over throwing when a failure is an expected, handleable
/// outcome (validation, parsing, a lookup that might miss) rather than a
/// programmer error or a truly exceptional condition.
sealed class Result<T, E> {
  const Result();

  /// Creates a successful result holding [value].
  const factory Result.ok(T value) = Ok<T, E>;

  /// Creates a failed result holding [error].
  const factory Result.err(E error) = Err<T, E>;

  /// Runs [body], catching any thrown [Object] into an [Err]. The
  /// synchronous counterpart to [guardAsync].
  ///
  /// ```dart
  /// final parsed = Result.guard(() => int.parse(input));
  /// ```
  static Result<T, Object> guard<T>(T Function() body) {
    try {
      return Ok(body());
    } catch (e) {
      return Err(e);
    }
  }

  /// Runs [body], catching any thrown [Object] — including one thrown
  /// after an `await` — into an [Err].
  ///
  /// ```dart
  /// final response = await Result.guardAsync(() => http.get(url));
  /// ```
  static Future<Result<T, Object>> guardAsync<T>(
    Future<T> Function() body,
  ) async {
    try {
      return Ok(await body());
    } catch (e) {
      return Err(e);
    }
  }

  /// Whether this is [Ok].
  bool get isOk => this is Ok<T, E>;

  /// Whether this is [Err].
  bool get isErr => this is Err<T, E>;

  /// The success value, or `null` if this is [Err].
  T? get valueOrNull => switch (this) {
        Ok(value: final v) => v,
        Err() => null,
      };

  /// The error, or `null` if this is [Ok].
  E? get errorOrNull => switch (this) {
        Ok() => null,
        Err(error: final e) => e,
      };

  /// Reduces this result to a single value of type [R] by handling both
  /// cases — the primary way to consume a [Result] without a `switch`.
  R match<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  }) =>
      switch (this) {
        Ok(value: final v) => ok(v),
        Err(error: final e) => err(e),
      };

  /// Transforms the success value, leaving an [Err] untouched.
  Result<R, E> map<R>(R Function(T value) transform) => switch (this) {
        Ok(value: final v) => Ok(transform(v)),
        Err(error: final e) => Err(e),
      };

  /// Transforms the error, leaving an [Ok] untouched.
  Result<T, R> mapErr<R>(R Function(E error) transform) => switch (this) {
        Ok(value: final v) => Ok(v),
        Err(error: final e) => Err(transform(e)),
      };

  /// Chains another fallible operation onto a success value, flattening
  /// the result — the monadic bind. Use this instead of [map] when
  /// [transform] itself returns a [Result].
  Result<R, E> flatMap<R>(Result<R, E> Function(T value) transform) =>
      switch (this) {
        Ok(value: final v) => transform(v),
        Err(error: final e) => Err(e),
      };

  /// The success value, or the result of [orElse] applied to the error.
  T getOrElse(T Function(E error) orElse) => switch (this) {
        Ok(value: final v) => v,
        Err(error: final e) => orElse(e),
      };

  /// The success value, or [fallback] if this is an [Err].
  T getOrDefault(T fallback) => switch (this) {
        Ok(value: final v) => v,
        Err() => fallback,
      };

  /// The success value, or throws the error (via [StateError] if [E]
  /// isn't already something throwable).
  ///
  /// Prefer [match]/[getOrElse]/pattern matching in normal control flow;
  /// this is an escape hatch for call sites — tests, `main()`, prototype
  /// code — that want to fail loudly instead of handling the [Err] case.
  T getOrThrow() => switch (this) {
        Ok(value: final v) => v,
        Err(error: final e) =>
          throw (e is Object ? e : StateError('Result.getOrThrow: $e')),
      };
}

/// A successful [Result], holding a [value].
///
/// Two [Ok]s are equal when their values are, regardless of how each
/// one's type arguments were inferred: `Ok<int, String>(1)` equals
/// `Ok<int, dynamic>(1)`. Comparing type arguments instead would make
/// `==` asymmetric — generics are covariant, so `Ok<int, String>` is an
/// `Ok<int, dynamic>` but not the reverse — and an asymmetric `==` breaks
/// `Set`/`Map` membership in ways that depend on insertion order.
final class Ok<T, E> extends Result<T, E> {
  /// The success value.
  final T value;

  /// Creates a successful result holding [value].
  const Ok(this.value);

  @override
  bool operator ==(Object other) => other is Ok && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

/// A failed [Result], holding an [error].
///
/// Two [Err]s are equal when their errors are, regardless of type
/// arguments — see [Ok] for why the type arguments are deliberately left
/// out of the comparison.
final class Err<T, E> extends Result<T, E> {
  /// The error.
  final E error;

  /// Creates a failed result holding [error].
  const Err(this.error);

  @override
  bool operator ==(Object other) => other is Err && other.error == error;

  @override
  int get hashCode => Object.hash(Err, error);

  @override
  String toString() => 'Err($error)';
}
