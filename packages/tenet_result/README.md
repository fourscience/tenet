# tenet_result

A minimal, dependency-free `Result<T, E>` type for Dart: explicit, typed
success/failure instead of throwing, sized for Dart 3 pattern matching.

```dart
Result<int, String> parseAge(String input) {
  final n = int.tryParse(input);
  if (n == null) return Err('"$input" is not a number');
  if (n < 0) return Err('$n is not a plausible age');
  return Ok(n);
}

switch (parseAge(input)) {
  case Ok(value: final age): print('Age: $age');
  case Err(error: final e): print('Invalid: $e');
}
```

## Why

Exceptions are for exceptional, programmer-error conditions. A failure a
caller is expected to handle — validation, parsing, a lookup that might
miss — reads better, and is impossible to forget to handle, as an
explicit return value. `Result<T, E>` is that return value: a `sealed`
class with exactly two subtypes, `Ok<T, E>` and `Err<T, E>`, so a
`switch` over one is exhaustive and compiler-checked — there's no third
case to forget.

## Installation

```yaml
dependencies:
  tenet_result: ^0.1.0
```

## Usage

### Constructing

```dart
Result<int, String> ok = Ok(42);
Result<int, String> err = Err('failed');
// or, equivalently:
Result<int, String> ok2 = Result.ok(42);
Result<int, String> err2 = Result.err('failed');
```

### Consuming

```dart
// Exhaustive pattern matching (recommended):
switch (result) {
  case Ok(value: final v): ...
  case Err(error: final e): ...
}

// Or the equivalent expression form:
final message = result.match(
  ok: (v) => 'got $v',
  err: (e) => 'failed: $e',
);

// Or a plain nullable escape hatch:
final int? value = result.valueOrNull;
```

### Transforming

```dart
result.map((v) => v * 2);          // transform Ok, pass Err through
result.mapErr((e) => e.toUpperCase()); // transform Err, pass Ok through
result.flatMap((v) => otherFallibleCall(v)); // chain, short-circuiting on Err
```

### Unwrapping

```dart
result.getOrElse((e) => fallbackFor(e)); // compute a fallback from the error
result.getOrDefault(0);                  // a fixed fallback
result.getOrThrow();                     // throw the error (escape hatch — see below)
```

`getOrThrow` is for call sites that want to fail loudly instead of
handling the `Err` case — tests, `main()`, prototype code. Prefer
`match`/`getOrElse`/pattern matching in normal control flow, where a
failure is something the caller is actually expected to handle.

### Adapting exception-throwing code

```dart
final parsed = Result.guard(() => int.parse(input));
final response = await Result.guardAsync(() => http.get(url));
```

Both catch any thrown `Object` (including one thrown after an `await`,
for `guardAsync`) into an `Err<T, Object>`, so you don't need a
`try`/`catch` at every boundary between exception-throwing code (most of
the Dart/Flutter ecosystem) and `Result`-based code.

## Development

```
dart pub get
dart analyze
dart test
dart run example/tenet_result_example.dart
```

This package has zero runtime dependencies.
