// Runnable example for casus.
//
// Run it with:
//   dart run example/casus_example.dart

import 'package:casus/casus.dart';

/// Parses and validates an age from raw input — a fallible operation
/// modeled without throwing.
Result<int> parseAge(String input) {
  final n = int.tryParse(input);
  if (n == null) return Result.failure('"$input" is not a number');
  if (n < 0 || n > 150) return Result.failure('$n is not a plausible age');
  return Result.success(n);
}

/// A second fallible step, chained via [Result.flatMap].
Result<String> ageCategory(int age) {
  if (age < 18) return const Result.success('minor');
  if (age < 65) return const Result.success('adult');
  return const Result.success('senior');
}

sealed class FieldError {
  const FieldError();

  String get message;
}

final class EmptyEmail extends FieldError {
  const EmptyEmail();

  @override
  String get message => 'email must not be empty';
}

final class ShortPassword extends FieldError {
  const ShortPassword();

  @override
  String get message => 'password must be at least 8 characters';
}

Either<FieldError, String> validateEmail(String email) =>
    email.isEmpty ? const Either.left(EmptyEmail()) : Either.right(email);

Either<FieldError, String> validatePassword(String password) =>
    password.length < 8
        ? const Either.left(ShortPassword())
        : Either.right(password);

void main() {
  // --- Result: exception-free error handling ---
  for (final input in ['30', 'thirty', '-5', '9']) {
    final parsed = parseAge(input);
    final described = switch (parsed) {
      Success(:final value) => 'age $value',
      Failure(:final failure) => 'invalid ($failure)',
    };
    print('parseAge("$input") -> $described');
  }

  final category = parseAge('42').flatMap(ageCategory);
  print('\ncategory for "42": ${category.getOrElse('unknown')}');

  final divided = Result.guard(() => 100 ~/ int.parse('0'));
  print('100 ~/ 0 via guard: $divided');

  // --- Either: a validation chain ---
  print(
    '\nvalidating "" / "short": '
    '${validateEmail('').flatMap((_) => validatePassword('short')).fold(onLeft: (e) => 'invalid: ${e.message}', onRight: (_) => 'valid')}',
  );
  print(
    'validating "a@b.com" / "longenough": '
    '${validateEmail('a@b.com').flatMap((_) => validatePassword('longenough')).fold(onLeft: (e) => 'invalid: ${e.message}', onRight: (_) => 'valid')}',
  );

  // --- Option: an explicit stand-in for a nullable value ---
  final Map<String, int> ages = {'ada': 36};
  final Option<int> adaAge = ages['ada'].asOption;
  final Option<int> unknownAge = ages['unknown'].asOption;
  print('\nada.getOrElse(-1): ${adaAge.getOrElse(-1)}');
  print('unknown.getOrElse(-1): ${unknownAge.getOrElse(-1)}');

  // --- Resource: the tri-state for an asynchronous value ---
  const Resource<String> loading = Resource.loading();
  const Resource<String> ready = Resource.ready('profile loaded');
  final Resource<String> stale = Resource.error(
    'network down',
    previousData: 'cached profile',
  );
  for (final resource in [loading, ready, stale]) {
    final described = resource.fold(
      onLoading: () => 'loading…',
      onData: (data) => 'data: $data',
      onError: (error, stackTrace, previous) => previous != null
          ? 'stale data ($previous) after error: $error'
          : 'error: $error',
    );
    print(described);
  }
}
