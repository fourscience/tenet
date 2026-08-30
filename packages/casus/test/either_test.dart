import 'package:casus/casus.dart';
import 'package:test/test.dart';

sealed class FieldError {
  const FieldError();
}

final class EmptyField extends FieldError {
  const EmptyField();
}

Either<FieldError, String> email(String value) =>
    value.isEmpty ? const Either.left(EmptyField()) : Either.right(value);

Either<FieldError, String> password(String value) =>
    value.length < 8 ? const Either.left(EmptyField()) : Either.right(value);

void main() {
  group('construction and identity', () {
    test('Left/Right isLeft/isRight agree', () {
      const left = Left<String, int>('bad');
      const right = Right<String, int>(1);
      expect(left.isLeft, isTrue);
      expect(left.isRight, isFalse);
      expect(right.isLeft, isFalse);
      expect(right.isRight, isTrue);
    });

    test('Either.left / Either.right factories match Left/Right', () {
      expect(const Either<String, int>.left('x'), const Left<String, int>('x'));
      expect(const Either<String, int>.right(1), const Right<String, int>(1));
    });
  });

  group('fold', () {
    test('calls the matching branch only', () {
      const Either<String, int> left = Left('bad');
      const Either<String, int> right = Right(1);
      expect(
        left.fold(onLeft: (l) => 'left:$l', onRight: (r) => 'right:$r'),
        'left:bad',
      );
      expect(
        right.fold(onLeft: (l) => 'left:$l', onRight: (r) => 'right:$r'),
        'right:1',
      );
    });
  });

  group('map / mapLeft independence', () {
    test('map transforms Right, leaves Left untouched', () {
      const Either<String, int> right = Right(2);
      const Either<String, int> left = Left('bad');
      expect(right.map((r) => r * 10), const Right<String, int>(20));
      expect(left.map((r) => r * 10), const Left<String, int>('bad'));
    });

    test('mapLeft transforms Left, leaves Right untouched', () {
      const Either<String, int> right = Right(2);
      const Either<String, int> left = Left('bad');
      expect(
        left.mapLeft((l) => l.toUpperCase()),
        const Left<String, int>('BAD'),
      );
      expect(
        right.mapLeft((l) => l.toUpperCase()),
        const Right<String, int>(2),
      );
    });
  });

  group('flatMap', () {
    test('Right flatMap chains', () {
      Either<String, int> halveIfEven(int v) =>
          v.isEven ? Either.right(v ~/ 2) : const Either.left('odd');
      expect(
        const Either<String, int>.right(4).flatMap(halveIfEven),
        const Right<String, int>(2),
      );
    });

    test('Left short-circuits without calling transform', () {
      var called = false;
      Either<String, int> f(int v) {
        called = true;
        return Either.right(v);
      }

      const Either<String, int> left = Left('bad');
      final result = left.flatMap(f);
      expect(called, isFalse);
      expect(result, const Left<String, int>('bad'));
    });

    test('validation chain: both fields valid', () {
      final result = email('a@b.com').flatMap((_) => password('longenough'));
      expect(result, isA<Right<FieldError, String>>());
    });

    test('validation chain: short-circuits on the first invalid field', () {
      final result = email('').flatMap((_) => password('longenough'));
      expect(result, const Left<FieldError, String>(EmptyField()));
    });
  });

  group('swap', () {
    test('exchanges the two channels', () {
      expect(
        const Either<String, int>.left('x').swap(),
        const Right<int, String>('x'),
      );
      expect(
        const Either<String, int>.right(1).swap(),
        const Left<int, String>(1),
      );
    });
  });

  group('getOrElse', () {
    test('returns the right value, or the fallback on Left', () {
      expect(const Either<String, int>.right(5).getOrElse(-1), 5);
      expect(const Either<String, int>.left('bad').getOrElse(-1), -1);
    });
  });

  group('onLeft / onRight', () {
    test('fire exactly once for the matching side', () {
      var lefts = 0;
      var rights = 0;
      const Either<String, int> right = Right(1);
      right
        ..onLeft((l) => lefts++)
        ..onRight((r) => rights++);
      expect(lefts, 0);
      expect(rights, 1);
    });
  });

  group('toResult', () {
    test('Right becomes Success', () {
      expect(
        const Either<Object, int>.right(1).toResult(),
        const Success<int>(1),
      );
    });

    test('Left becomes Failure', () {
      expect(
        const Either<Object, int>.left('bad').toResult(),
        const Failure<int>('bad'),
      );
    });
  });

  group('equality', () {
    test('Left/Right equality is value-based', () {
      expect(const Left<String, int>('a'), const Left<String, int>('a'));
      expect(const Right<String, int>(1), const Right<String, int>(1));
      expect(
        const Left<String, int>('a') == const Left<String, int>('b'),
        isFalse,
      );
    });

    test('Left and Right are never equal to each other', () {
      const Object left = Left<int, int>(1);
      const Object right = Right<int, int>(1);
      expect(left == right, isFalse);
      expect(right == left, isFalse);
    });
  });
}
