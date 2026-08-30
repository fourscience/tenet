/// Monadic types for Dart: `Result`, `Either`, `Option` and `Resource`
/// (loading/data/error) — sealed, immutable, exhaustively
/// pattern-matchable, zero functional dependencies.
///
/// See `casus_flutter` for `ResourceBuilder`, a widget that renders a
/// [Resource] via `fold`.
library;

export 'src/either.dart';
export 'src/extensions.dart';
export 'src/option.dart';
export 'src/resource.dart';
export 'src/result.dart';
