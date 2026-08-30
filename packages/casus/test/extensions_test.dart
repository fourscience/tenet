import 'package:casus/casus.dart';
import 'package:test/test.dart';

void main() {
  group('NullableExt.asOption', () {
    test('null becomes None', () {
      const int? value = null;
      expect(value.asOption, isA<None<int>>());
    });

    test('non-null becomes Some', () {
      const int value = 5;
      expect(value.asOption, const Some<int>(5));
    });
  });

  group('ResultFutureExt.fold', () {
    test('awaits then reduces a Future<Result<T>>', () async {
      Future<Result<int>> ok() async => Result.success(1);
      Future<Result<int>> bad() async => Result.failure('bad');

      expect(
        await ok().fold(
          onSuccess: (v) => 'ok:$v',
          onFailure: (e, st) => 'err:$e',
        ),
        'ok:1',
      );
      expect(
        await bad().fold(
          onSuccess: (v) => 'ok:$v',
          onFailure: (e, st) => 'err:$e',
        ),
        'err:bad',
      );
    });
  });

  group('IterableResultExt.sequence', () {
    test('all Success collapses to Success(list)', () {
      final result = [
        const Result<int>.success(1),
        const Result<int>.success(2),
      ].sequence();
      expect(result, isA<Success<List<int>>>());
      expect((result as Success<List<int>>).value, [1, 2]);
    });

    test('the first Failure wins', () {
      final result = [
        const Result<int>.success(1),
        const Result<int>.failure('bad'),
        const Result<int>.success(3),
      ].sequence();
      expect(result, const Failure<List<int>>('bad'));
    });
  });

  group('IterableEitherExt.sequence', () {
    test('all Right collapses to Right(list)', () {
      final result = [
        const Either<String, int>.right(1),
        const Either<String, int>.right(2),
      ].sequence();
      expect(result, isA<Right<String, List<int>>>());
      expect((result as Right<String, List<int>>).value, [1, 2]);
    });

    test('the first Left wins', () {
      final result = [
        const Either<String, int>.right(1),
        const Either<String, int>.left('bad'),
        const Either<String, int>.right(3),
      ].sequence();
      expect(result, const Left<String, List<int>>('bad'));
    });
  });

  group('IterableTraverseResultExt.traverse', () {
    Future<Result<int>> doubleIfPositive(int v) async =>
        v > 0 ? Result.success(v * 2) : Result.failure('non-positive: $v');

    test('maps and collects into Success(list)', () async {
      final result = await [1, 2, 3].traverse(doubleIfPositive);
      expect(result, isA<Success<List<int>>>());
      expect((result as Success<List<int>>).value, [2, 4, 6]);
    });

    test('stops at the first failing element', () async {
      var callCount = 0;
      Future<Result<int>> tracked(int v) {
        callCount++;
        return doubleIfPositive(v);
      }

      final result = await [1, -1, 3].traverse(tracked);
      expect(result, const Failure<List<int>>('non-positive: -1'));
      expect(callCount, 2);
    });
  });
}
