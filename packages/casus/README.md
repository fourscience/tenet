# casus

Monadic types for Dart: `Result`, `Either`, `Option` and `Resource`
(loading/data/error) — sealed, immutable, exhaustively
pattern-matchable, dependency-light.

```dart
Result<int> parseAge(String input) {
  final n = int.tryParse(input);
  if (n == null) return Result.failure('"$input" is not a number');
  if (n < 0) return Result.failure('$n is not a plausible age');
  return Result.success(n);
}

switch (parseAge(input)) {
  case Success(value: final age): print('Age: $age');
  case Failure(failure: final e): print('Invalid: $e');
}
```

For the Flutter-facing widget layer (`ResourceBuilder`), see
[`casus_flutter`](../casus_flutter).

## Why

Exceptions are for exceptional, programmer-error conditions; a caller
shouldn't have to guess from a signature whether a function might throw,
or wrap every call in `try`/`catch` to find out. A failure a caller is
expected to handle — validation, parsing, a lookup that might miss, an
async load that's still in flight — reads better, and is impossible to
forget to handle, as an explicit return value. Every type here is
`sealed`, so a `switch` over one is exhaustive and compiler-checked, and
every variant is an immutable `final class` with value-based `==`.

## Installation

```yaml
dependencies:
  casus: ^1.0.0
```

## `Result<T>` — Success or Failure

The outcome of a fallible operation: `Success<T>` with a value, or
`Failure<T>` with an `Object` error and (whenever it's known) the
`StackTrace` that produced it — never discarded, always carried with the
failure.

```dart
Result<int> ok = Result.success(1);
Result<int> err = Result.failure('bad', StackTrace.current);

ok.map((v) => v * 2);              // Success(2)
ok.flatMap((v) => otherFallibleCall(v)); // chain, short-circuiting on Failure
ok.getOrElse(0);                   // 0 on Failure, the value on Success
ok.fold(onSuccess: (v) => '$v', onFailure: (e, st) => 'error: $e');

ok
  ..onSuccess(syncCache)            // telescoping side effects
  ..onFailure((e, st) => telemetry.report(e, st));
```

### Adapting exception-throwing code

```dart
final parsed = Result.guard(() => int.parse(input));
final response = await Result.guardAsync(() => http.get(url));
```

Both catch anything thrown — including after an `await`, for
`guardAsync` — into a `Failure` that carries the stack trace at the
point it was thrown, so you don't need a `try`/`catch` at every boundary
between exception-throwing code (most of the Dart ecosystem) and
`Result`-based code.

### Repository example

```dart
class UserRepository {
  Future<Result<User>> getUser(String id) => Result.guardAsync(() async {
        final dto = await api.fetchUser(id);
        return User.fromDto(dto);
      });
}

final profile = await repo.getUser('42');
profile.fold(
  onSuccess: show,
  onFailure: (e, st) => crashlytics.recordError(e, st),
);
```

## `Either<L, R>` — Left or Right

A general-purpose two-channel union, for when the error type shouldn't be
pinned to `Object` the way `Result`'s is. By convention the right channel
is the "correct" one — `map`/`flatMap` operate on it — and left carries
an error or alternate outcome:

```dart
Either<FieldError, Credentials> validate(FormData f) =>
    email(f.email).flatMap((_) => password(f.password)).map(Credentials.new);
```

`mapLeft` transforms the left channel independently of `map`, `swap`
exchanges the two channels, and `toResult()`/`Result.toEither()` convert
between the two (lossy: `Either` has no stack-trace slot).

## `Option<T>` — Some or None

An explicit stand-in for a nullable value, for API boundaries where
"absent" is a case the caller must handle rather than an incidental
`null`:

```dart
Option<int> age = Option.fromNullable(nullableAge);
age.map((v) => v + 1).getOrElse(0);
nullableAge.asOption; // same lift, as an extension on T?
```

`filter` narrows a `Some` down to `None` when a predicate fails,
`sequence()` on an `Iterable<Option<T>>` collapses a list of options into
one (first `None` wins), and `unwrap()` — like `Result.unwrap()` — is for
tests only, throwing `OptionUnwrapException` on `None`.

## `Resource<T>` — Loading, Ready, or an error with stale data

The tri-state for an asynchronous value, named `Resource` after the
Android/Jetpack `Resource` prior art: `Loading`, `Ready` with data, or an
error that may retain the last-known-good data for a
stale-while-revalidate UI.

```dart
Resource<User> state = const Resource.loading();
state = Resource.ready(user);
state = Resource.error(exception, stackTrace: st, previousData: user);

state.fold(
  onLoading: () => showSpinner(),
  onData: (user) => showProfile(user),
  onError: (e, st, previous) => previous != null
      ? showProfile(previous) // stale data + banner
      : showRetry(),
);

state.dataOrNull; // the data if Ready, the stale data if errored, else null
```

`Result<T>.toResource()` bridges a repository that already returns
`Result` into the tri-state a UI wants. See
[`casus_flutter`](../casus_flutter)'s `ResourceBuilder` for rendering a
`Resource` directly as a widget.

## Collections and futures

```dart
[Result.success(1), Result.success(2)].sequence();      // Success([1, 2])
[Option.some(1), Option<int>.none()].sequence();         // None
[Either.right(1), Either.left('x')].sequence();           // Left('x')

await ids.traverse(repo.getUser); // Future<Result<List<User>>>, first Failure wins

await futureResult.fold(onSuccess: ..., onFailure: ...); // await + fold in one step
```

## Unwrapping (tests only)

```dart
result.unwrap(); // throws ResultUnwrapException on Failure
option.unwrap();  // throws OptionUnwrapException on None
```

`unwrap()` exists for tests and prototypes. Production code should use
`fold`/`getOrElse`/`recover`/pattern matching, where a failure or absence
is a case the caller is expected to handle rather than an escape hatch
that throws.

## Development

```
dart pub get
dart analyze
dart test
dart run example/casus_example.dart
```

This package depends only on `meta`.
