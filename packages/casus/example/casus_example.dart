// Runnable example for casus.
//
// Run it with:
//   dart run example/casus_example.dart

import 'package:casus/casus.dart';

/// Parses and validates an age from raw input — a fallible operation
/// modeled without throwing.
Result<int, String> parseAge(String input) {
  final n = int.tryParse(input);
  if (n == null) return Err('"$input" is not a number');
  if (n < 0 || n > 150) return Err('$n is not a plausible age');
  return Ok(n);
}

/// A second fallible step, chained via [Result.flatMap].
Result<String, String> ageCategory(int age) {
  if (age < 18) return const Ok('minor');
  if (age < 65) return const Ok('adult');
  return const Ok('senior');
}

void main() {
  for (final input in ['30', 'thirty', '-5', '9']) {
    // switch-based pattern matching — the exhaustive, idiomatic Dart 3 way.
    final parsed = parseAge(input);
    final described = switch (parsed) {
      Ok(value: final age) => 'age $age',
      Err(error: final e) => 'invalid ($e)',
    };
    print('parseAge("$input") -> $described');
  }

  // Chaining two fallible steps with flatMap — short-circuits on the
  // first Err, just like an early return would, but as an expression.
  final category = parseAge('42').flatMap(ageCategory);
  print('\ncategory for "42": ${category.getOrElse((e) => 'unknown: $e')}');

  final badCategory = parseAge('nope').flatMap(ageCategory);
  print(
    'category for "nope": ${badCategory.getOrElse((e) => 'unknown: $e')}',
  );

  // Adapting exception-throwing code with guard, instead of a try/catch
  // at every call site.
  final divided = Result.guard(() => 100 ~/ int.parse('0'));
  print('\n100 ~/ 0 via guard: $divided');
}
