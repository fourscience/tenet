import 'package:casus/casus.dart';
import 'package:test/test.dart';

Result<int> parseAge(String input) {
  final n = int.tryParse(input);
  if (n == null) return Result.failure('not a number: $input');
  if (n < 0) return Result.failure('negative age: $n');
  return Result.success(n);
}

void main() {
  group('construction and identity', () {
    test('Success holds a value; isSuccess/isFailure agree', () {
      const r = Success<int>(5);
      expect(r.isSuccess, isTrue);
      expect(r.isFailure, isFalse);
    });

    test('Failure holds a failure and optional stack trace', () {
      final st = StackTrace.current;
      final r = Failure<int>('bad', st);
      expect(r.isSuccess, isFalse);
      expect(r.isFailure, isTrue);
      expect(r.failure, 'bad');
      expect(r.stackTrace, st);
    });

    test('Result.success / Result.failure factories match Success/Failure', () {
      expect(const Result<int>.success(1), const Success<int>(1));
      expect(const Result<int>.failure('x'), const Failure<int>('x'));
    });
  });

  group('switch pattern matching', () {
    test('exhaustive switch destructures Success/Failure', () {
      final results = [parseAge('30'), parseAge('nope'), parseAge('-1')];
      final described = results
          .map(
            (r) => switch (r) {
              Success(:final value) => 'age=$value',
              Failure(:final failure) => 'error=$failure',
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

  group('fold', () {
    test('calls the matching branch only', () {
      expect(
        parseAge('30')
            .fold(onSuccess: (v) => 'ok:$v', onFailure: (e, st) => 'err:$e'),
        'ok:30',
      );
      expect(
        parseAge('x')
            .fold(onSuccess: (v) => 'ok:$v', onFailure: (e, st) => 'err:$e'),
        'err:not a number: x',
      );
    });
  });

  group('map / flatMap', () {
    test('map transforms Success, passes Failure through untouched', () {
      expect(parseAge('30').map((v) => v * 2), const Success<int>(60));
      expect(
        parseAge('x').map((v) => v * 2),
        const Failure<int>('not a number: x'),
      );
    });

    test('map preserves the stack trace on a Failure', () {
      final st = StackTrace.current;
      final mapped = Result<int>.failure('bad', st).map((v) => v * 2);
      expect(mapped, isA<Failure<int>>());
      expect((mapped as Failure<int>).stackTrace, st);
    });

    test('flatMap left identity: success(v).flatMap(f) == f(v)', () {
      Result<int> f(int v) => Result.success(v * 2);
      expect(Result.success(3).flatMap(f), f(3));
    });

    test('flatMap chains fallible operations and flattens', () {
      Result<int> halveIfEven(int v) =>
          v.isEven ? Result.success(v ~/ 2) : Result.failure('$v is odd');

      expect(parseAge('30').flatMap(halveIfEven), const Success<int>(15));
      expect(
        parseAge('31').flatMap(halveIfEven),
        const Failure<int>('31 is odd'),
      );
    });

    test('flatMap short-circuits on Failure without calling transform', () {
      var called = false;
      Result<int> f(int v) {
        called = true;
        return Result.success(v);
      }

      final result = parseAge('x').flatMap(f);
      expect(called, isFalse);
      expect(result, const Failure<int>('not a number: x'));
    });
  });

  group('unwrapping', () {
    test('getOrElse returns the fixed fallback', () {
      expect(parseAge('30').getOrElse(-1), 30);
      expect(parseAge('x').getOrElse(-1), -1);
    });

    test('getOrElseWith computes a fallback from the failure', () {
      expect(parseAge('30').getOrElseWith((e) => -1), 30);
      expect(parseAge('x').getOrElseWith((e) => -1), -1);
    });

    test('recover turns a Failure into a new Result', () {
      final recovered = parseAge('x').recover((e) => Result.success(0));
      expect(recovered, const Success<int>(0));
      expect(
        parseAge('30').recover((e) => Result.success(0)),
        const Success<int>(30),
      );
    });

    test('unwrap returns the value on Success', () {
      expect(parseAge('30').unwrap(), 30);
    });

    test(
      'unwrap throws ResultUnwrapException carrying the original failure',
      () {
        final st = StackTrace.current;
        final result = Result<int>.failure('boom', st);
        try {
          result.unwrap();
          fail('expected ResultUnwrapException');
        } on ResultUnwrapException catch (e) {
          expect(e.failure, 'boom');
          expect(e.stackTrace, st);
        }
      },
    );
  });

  group('onSuccess / onFailure', () {
    test(
      'onSuccess fires exactly once on Success and returns the same result',
      () {
        var calls = 0;
        final result = Result<int>.success(1)
          ..onSuccess((v) => calls++)
          ..onFailure((e, st) => fail('should not be called'));
        expect(calls, 1);
        expect(result, const Success<int>(1));
      },
    );

    test(
      'onFailure fires exactly once on Failure and returns the same result',
      () {
        var calls = 0;
        final result = Result<int>.failure('bad')
          ..onSuccess((v) => fail('should not be called'))
          ..onFailure((e, st) => calls++);
        expect(calls, 1);
        expect(result, const Failure<int>('bad'));
      },
    );
  });

  group('guard / guardAsync', () {
    test(
      'guard captures a thrown exception into Failure with a stack trace',
      () {
        final result = Result.guard(() => int.parse('not a number'));
        expect(result.isFailure, isTrue);
        final failure = result as Failure<int>;
        expect(failure.failure, isA<FormatException>());
        expect(failure.stackTrace, isNotNull);
      },
    );

    test('guard returns Success when body succeeds', () {
      final result = Result.guard(() => int.parse('42'));
      expect(result, const Success<int>(42));
    });

    test('guardAsync captures an exception thrown after an await', () async {
      final result = await Result.guardAsync<int>(() async {
        await Future<void>.delayed(Duration.zero);
        throw StateError('async boom');
      });
      expect(result.isFailure, isTrue);
      final failure = result as Failure<int>;
      expect(failure.failure, isA<StateError>());
      expect(failure.stackTrace, isNotNull);
    });

    test(
      'guardAsync returns Success when the future completes normally',
      () async {
        final result = await Result.guardAsync(() async {
          await Future<void>.delayed(Duration.zero);
          return 7;
        });
        expect(result, const Success<int>(7));
      },
    );
  });

  group('toEither', () {
    test('Success becomes Right', () {
      expect(
        const Result<int>.success(1).toEither(),
        const Right<Object, int>(1),
      );
    });

    test('Failure becomes Left, dropping the stack trace', () {
      final either = Result<int>.failure('bad', StackTrace.current).toEither();
      expect(either, const Left<Object, int>('bad'));
    });
  });

  group('equality across variants', () {
    test('Success and Failure are never equal to each other', () {
      const Object success = Success<int>(1);
      const Object failure = Failure<int>(1);
      expect(success == failure, isFalse);
      expect(failure == success, isFalse);
    });

    test('Success is not equal to a same-valued Either.Right', () {
      const Object success = Success<int>(1);
      const Object right = Right<Object, int>(1);
      expect(success == right, isFalse);
    });

    test('toString is debug-friendly', () {
      expect(const Success<int>(5).toString(), 'Success(5)');
      expect(const Failure<int>('bad').toString(), 'Failure(bad)');
    });
  });
}
