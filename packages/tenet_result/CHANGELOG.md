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
