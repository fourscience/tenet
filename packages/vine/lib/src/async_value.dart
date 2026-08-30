/// The state of a [Vine.future]: exactly one of loading, data, or error,
/// always remembering the most recent data seen so a UI never has to lose
/// content just because a refresh started — `value` keeps returning the
/// previous data through a subsequent [AsyncLoading]/[AsyncError].
sealed class AsyncValue<T> {
  const AsyncValue();

  /// The current data, or the most recent data seen before a loading/error
  /// transition. `null` only if no data has ever arrived.
  T? get value;

  /// Whether this is [AsyncLoading].
  bool get isLoading;

  /// Whether [value] is non-null because data has actually arrived at
  /// least once (as opposed to `T` merely being nullable).
  bool get hasValue;

  /// The error, if this is [AsyncError].
  Object? get error;

  /// The error's stack trace, if this is [AsyncError].
  StackTrace? get stackTrace;

  /// True when this is a loading state that already has previous data —
  /// i.e. a refresh in flight, not the first load. Useful for showing a
  /// spinner *over* stale content instead of blanking it.
  bool get isRefreshing => isLoading && hasValue;

  /// Pattern-matches on the current state.
  R when<R>({
    required R Function(T value) data,
    required R Function(AsyncError<T> error) error,
    required R Function() loading,
  });

  /// Runs [body], wrapping the outcome as [AsyncData] on success or
  /// [AsyncError] on failure — never throws.
  static Future<AsyncValue<T>> guard<T>(Future<T> Function() body) async {
    try {
      return AsyncData(await body());
    } catch (error, stackTrace) {
      return AsyncError(error, stackTrace);
    }
  }
}

/// Settled, successful state: [value] is always non-null-safe-typed data.
final class AsyncData<T> extends AsyncValue<T> {
  const AsyncData(this.value);

  @override
  final T value;

  @override
  bool get isLoading => false;

  @override
  bool get hasValue => true;

  @override
  Object? get error => null;

  @override
  StackTrace? get stackTrace => null;

  @override
  R when<R>({
    required R Function(T value) data,
    required R Function(AsyncError<T> error) error,
    required R Function() loading,
  }) =>
      data(value);

  @override
  bool operator ==(Object other) =>
      other is AsyncData<T> && other.value == value;

  @override
  int get hashCode => Object.hash(AsyncData<T>, value);

  @override
  String toString() => 'AsyncData<$T>($value)';
}

/// In-flight state. [previous] — the last data seen, if any — is what
/// [AsyncValue.value] returns while loading, so stale-while-revalidate
/// "just works": read `value` and `isLoading` together instead of
/// blanking the UI on every refresh.
final class AsyncLoading<T> extends AsyncValue<T> {
  const AsyncLoading([this.previous]);

  /// The last data seen before this load started, if any.
  final T? previous;

  @override
  T? get value => previous;

  @override
  bool get isLoading => true;

  @override
  bool get hasValue => previous != null;

  @override
  Object? get error => null;

  @override
  StackTrace? get stackTrace => null;

  @override
  R when<R>({
    required R Function(T value) data,
    required R Function(AsyncError<T> error) error,
    required R Function() loading,
  }) =>
      loading();

  @override
  bool operator ==(Object other) =>
      other is AsyncLoading<T> && other.previous == previous;

  @override
  int get hashCode => Object.hash(AsyncLoading<T>, previous);

  @override
  String toString() => 'AsyncLoading<$T>(previous: $previous)';
}

/// A run failed. [previous] is preserved the same way [AsyncLoading] does,
/// so [AsyncValue.value] still returns the last good data through an
/// error.
final class AsyncError<T> extends AsyncValue<T> {
  const AsyncError(this._error, this._stackTrace, [this.previous]);

  final Object _error;
  final StackTrace _stackTrace;

  /// The last data seen before this run failed, if any.
  final T? previous;

  @override
  T? get value => previous;

  @override
  bool get isLoading => false;

  @override
  bool get hasValue => previous != null;

  @override
  Object get error => _error;

  @override
  StackTrace get stackTrace => _stackTrace;

  @override
  R when<R>({
    required R Function(T value) data,
    required R Function(AsyncError<T> error) error,
    required R Function() loading,
  }) =>
      error(this);

  @override
  bool operator ==(Object other) =>
      other is AsyncError<T> &&
      other._error == _error &&
      other.previous == previous;

  @override
  int get hashCode => Object.hash(AsyncError<T>, _error, previous);

  @override
  String toString() => 'AsyncError<$T>($_error, previous: $previous)';
}
