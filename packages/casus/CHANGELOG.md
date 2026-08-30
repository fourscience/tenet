## 1.0.0

**Breaking: complete redefinition of the package.** `Result<T, E>`/`Ok`/
`Err` are replaced by four types — `Result<T>`, `Either<L, R>`,
`Option<T>`, and `Resource<T>` — covering explicit error handling, a
general two-channel union, an explicit nullable stand-in, and the
loading/data/error tri-state for asynchronous values. Widgets for
rendering a `Resource` (`ResourceBuilder`) now live in the separate
[`casus_flutter`](../casus_flutter) package, so this one stays pure Dart.

- `Result<T>`: `Success<T>`/`Failure<T>` (an `Object` error plus, whenever
  known, the `StackTrace` that produced it — never discarded). Adds
  `map`/`flatMap`/`fold`/`recover`/`getOrElse`/`getOrElseWith`/
  `onSuccess`/`onFailure`/`unwrap`/`toEither`, and `Result.guard`/
  `Result.guardAsync` to adapt exception-throwing code, now always
  capturing the stack trace alongside the error.
- `Either<L, R>`: `Left<L, R>`/`Right<L, R>`, with `map`/`mapLeft`/
  `flatMap`/`fold`/`swap`/`getOrElse`/`onLeft`/`onRight`/`toResult`.
- `Option<T>`: `Some<T>`/`None<T>`, with `map`/`flatMap`/`filter`/`fold`/
  `getOrElse`/`onSome`/`onNone`/`unwrap`, and `Option.fromNullable`/
  `toNullable`.
- `Resource<T>`: `Loading<T>`/`Ready<T>`/`ResourceError<T>` (the last
  optionally retaining `previousData` for a stale-while-revalidate UI),
  with `fold`/`map`/`flatMap`/`dataOrNull`/`dataOrPrevious`/`recover`, and
  `Result<T>.toResource()` to bridge from a `Result`-returning
  repository.
- Extensions: `Future<Result<T>>.fold`, `T?.asOption`, `sequence()` on
  `Iterable<Option<T>>`/`Iterable<Result<T>>`/`Iterable<Either<L, R>>`,
  and `Iterable<T>.traverse` for an async, `Result`-returning mapping
  step.
- Adds a `meta` dependency (for `@immutable`); still has no other
  functional dependencies.

## 0.2.0

### Fixed

- `Ok`/`Err` violated the `==`/`hashCode` contract. Equality compared type
  arguments (`other is Ok<T, E>`), and because generics are covariant that
  made it asymmetric: with `actual` of type `Ok<int, String>` and
  `literal` of type `Ok<int, dynamic>`, `literal == actual` was `true`
  while `actual == literal` was `false` — yet both hashed the same. The
  practical fallout was `Set`/`Map` membership that depended on insertion
  order: `{actual, literal}` held two elements, `{literal, actual}` held
  one. Equality is now decided by the case (`Ok` vs `Err`) and the payload
  alone, so it is symmetric regardless of how each side's type arguments
  were inferred.

## 0.1.0

- Initial release: `Result<T, E>`, `Ok`, `Err`, `map`/`mapErr`/`flatMap`,
  `match`, `getOrElse`/`getOrDefault`/`getOrThrow`, and the
  `Result.guard`/`Result.guardAsync` exception-adapter helpers.
