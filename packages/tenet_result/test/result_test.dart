import 'package:tenet_result/tenet_result.dart';
import 'package:test/test.dart';

Result<int, String> parseAge(String input) {
  final n = int.tryParse(input);
  if (n == null) return Err('not a number: $input');
  if (n < 0) return Err('negative age: $n');
  return Ok(n);
}

void main() {
  group('construction and identity', () {
    test('Ok holds a value; isOk/isErr agree', () {
      const r = Ok<int, String>(5);
      expect(r.isOk, isTrue);
      expect(r.isErr, isFalse);
      expect(r.valueOrNull, 5);
      expect(r.errorOrNull, isNull);
    });

    test('Err holds an error; isOk/isErr agree', () {
      const r = Err<int, String>('bad');
      expect(r.isOk, isFalse);
      expect(r.isErr, isTrue);
      expect(r.valueOrNull, isNull);
      expect(r.errorOrNull, 'bad');
    });

    test('Result.ok / Result.err factories match Ok/Err directly', () {
      expect(const Result<int, String>.ok(1), const Ok<int, String>(1));
      expect(
        const Result<int, String>.err('x'),
        const Err<int, String>('x'),
      );
    });

    test('Ok/Err equality is value-based', () {
      expect(const Ok<int, String>(1), const Ok<int, String>(1));
      expect(const Ok<int, String>(1) == const Ok<int, String>(2), isFalse);
      expect(const Err<int, String>('a'), const Err<int, String>('a'));
    });
  });

  group('switch pattern matching', () {
    test('exhaustive switch destructures Ok/Err', () {
      final results = [parseAge('30'), parseAge('nope'), parseAge('-1')];
      final described = results
          .map(
            (r) => switch (r) {
              Ok(value: final age) => 'age=$age',
              Err(error: final e) => 'error=$e',
            },
          )
          .toList();
      expect(described, [
        'age=30',
        'error=not a number: nope',
        'error=negative age: -1',
      ]);
    });
  });

  group('match', () {
    test('calls the matching branch only', () {
      expect(
        parseAge('30').match(ok: (v) => 'ok:$v', err: (e) => 'err:$e'),
        'ok:30',
      );
      expect(
        parseAge('x').match(ok: (v) => 'ok:$v', err: (e) => 'err:$e'),
        'err:not a number: x',
      );
    });
  });

  group('map / mapErr / flatMap', () {
    test('map transforms Ok, passes Err through untouched', () {
      expect(parseAge('30').map((v) => v * 2), const Ok<int, String>(60));
      expect(
        parseAge('x').map((v) => v * 2),
        const Err<int, String>('not a number: x'),
      );
    });

    test('mapErr transforms Err, passes Ok through untouched', () {
      expect(
        parseAge('x').mapErr((e) => e.toUpperCase()),
        const Err<int, String>('NOT A NUMBER: X'),
      );
      expect(parseAge('30').mapErr((e) => e.toUpperCase()), const Ok(30));
    });

    test('flatMap chains fallible operations and flattens', () {
      Result<int, String> halveIfEven(int v) =>
          v.isEven ? Ok(v ~/ 2) : Err('$v is odd');

      expect(parseAge('30').flatMap(halveIfEven), const Ok<int, String>(15));
      expect(
        parseAge('31').flatMap(halveIfEven),
        const Err<int, String>('31 is odd'),
      );
      // Short-circuits: the original Err propagates without calling into
      // the chained function at all.
      expect(
        parseAge('x').flatMap(halveIfEven),
        const Err<int, String>('not a number: x'),
      );
    });
  });

  group('unwrapping', () {
    test('getOrElse computes a fallback from the error', () {
      expect(parseAge('30').getOrElse((e) => -1), 30);
      expect(parseAge('x').getOrElse((e) => -1), -1);
    });

    test('getOrDefault returns a fixed fallback', () {
      expect(parseAge('30').getOrDefault(0), 30);
      expect(parseAge('x').getOrDefault(0), 0);
    });

    test('getOrThrow returns the value on Ok', () {
      expect(parseAge('30').getOrThrow(), 30);
    });

    test('getOrThrow throws the error object when it is one', () {
      final result = Result<int, Object>.err(Exception('boom'));
      expect(result.getOrThrow, throwsA(isException));
    });

    test('getOrThrow throws a non-Exception error object directly', () {
      // Dart lets you `throw` any non-null Object, not just Exceptions —
      // a plain String error is thrown as-is.
      expect(
        () => const Err<int, String>('bad').getOrThrow(),
        throwsA('bad'),
      );
    });

    test('getOrThrow wraps a null error in StateError', () {
      // Dart disallows `throw null` outright, so a nullable error type
      // holding null falls back to a StateError instead of crashing on
      // the throw itself.
      const result = Err<int, String?>(null);
      expect(result.getOrThrow, throwsStateError);
    });
  });

  group('guard / guardAsync', () {
    test('guard captures a thrown exception into Err', () {
      final result = Result.guard(() => int.parse('not a number'));
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<FormatException>());
    });

    test('guard returns Ok when body succeeds', () {
      final result = Result.guard(() => int.parse('42'));
      expect(result, const Ok<int, Object>(42));
    });

    test('guardAsync captures an exception thrown after an await', () async {
      final result = await Result.guardAsync(() async {
        await Future<void>.delayed(Duration.zero);
        throw StateError('async boom');
      });
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<StateError>());
    });

    test('guardAsync returns Ok when the future completes normally', () async {
      final result = await Result.guardAsync(() async {
        await Future<void>.delayed(Duration.zero);
        return 7;
      });
      expect(result, const Ok<int, Object>(7));
    });
  });

  test('toString is debug-friendly', () {
    expect(const Ok<int, String>(5).toString(), 'Ok(5)');
    expect(const Err<int, String>('bad').toString(), 'Err(bad)');
  });
}
