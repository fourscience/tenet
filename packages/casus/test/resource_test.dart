import 'package:casus/casus.dart';
import 'package:test/test.dart';

void main() {
  group('construction and identity', () {
    test('isLoading/hasData/hasError agree', () {
      expect(const Resource<int>.loading().isLoading, isTrue);
      expect(const Resource<int>.loading().hasData, isFalse);
      expect(const Resource<int>.loading().hasError, isFalse);

      expect(const Resource<int>.ready(1).hasData, isTrue);
      expect(const Resource<int>.ready(1).isLoading, isFalse);

      expect(Resource<int>.error('bad').hasError, isTrue);
      expect(Resource<int>.error('bad').hasData, isFalse);
    });
  });

  group('fold', () {
    test('handles all three states', () {
      String describe(Resource<int> r) => r.fold(
            onLoading: () => 'loading',
            onData: (d) => 'data:$d',
            onError: (e, st, prev) => 'error:$e,prev:$prev',
          );

      expect(describe(const Resource.loading()), 'loading');
      expect(describe(const Resource.ready(1)), 'data:1');
      expect(
        describe(Resource.error('bad', previousData: 0)),
        'error:bad,prev:0',
      );
    });
  });

  group('map', () {
    test('transforms Ready data', () {
      expect(
        const Resource<int>.ready(2).map((v) => v * 10),
        const Ready<int>(20),
      );
    });

    test('Loading passes through unchanged', () {
      expect(
        const Resource<int>.loading().map((v) => v * 10),
        isA<Loading<int>>(),
      );
    });

    test('preserves error and maps previousData', () {
      final mapped = Resource<int>.error(
        'bad',
        previousData: 2,
      ).map((v) => v * 10);
      expect(mapped, isA<ResourceError<int>>());
      final error = mapped as ResourceError<int>;
      expect(error.error, 'bad');
      expect(error.previousData, 20);
    });

    test('drops previousData when null', () {
      final mapped = Resource<int>.error('bad').map((v) => v * 10);
      expect((mapped as ResourceError<int>).previousData, isNull);
    });
  });

  group('flatMap', () {
    test('chains on Ready', () {
      Resource<int> halve(int v) => Resource.ready(v ~/ 2);
      expect(const Resource<int>.ready(4).flatMap(halve), const Ready<int>(2));
    });

    test('Loading propagates without calling transform', () {
      var called = false;
      Resource<int> f(int v) {
        called = true;
        return Resource.ready(v);
      }

      final result = const Resource<int>.loading().flatMap(f);
      expect(called, isFalse);
      expect(result, isA<Loading<int>>());
    });

    test('Error propagates without calling transform', () {
      var called = false;
      Resource<int> f(int v) {
        called = true;
        return Resource.ready(v);
      }

      final result = Resource<int>.error('bad').flatMap(f);
      expect(called, isFalse);
      expect(result, isA<ResourceError<int>>());
      expect((result as ResourceError<int>).error, 'bad');
    });
  });

  group('dataOrNull / dataOrPrevious', () {
    test('Loading has no data', () {
      expect(const Resource<int>.loading().dataOrNull, isNull);
      expect(const Resource<int>.loading().dataOrPrevious, isNull);
    });

    test('Ready surfaces its data', () {
      expect(const Resource<int>.ready(5).dataOrNull, 5);
    });

    test('Error surfaces previousData when present, else null', () {
      expect(Resource<int>.error('bad', previousData: 7).dataOrNull, 7);
      expect(Resource<int>.error('bad').dataOrNull, isNull);
    });
  });

  group('recover', () {
    test('turns Error into Ready via the fallback', () {
      expect(Resource<int>.error('bad').recover((e) => 0), const Ready<int>(0));
    });

    test('Loading/Ready pass through untouched', () {
      expect(
        const Resource<int>.loading().recover((e) => 0),
        isA<Loading<int>>(),
      );
      expect(
        const Resource<int>.ready(1).recover((e) => 0),
        const Ready<int>(1),
      );
    });
  });

  group('equality', () {
    test('every Loading is equal to every other Loading', () {
      const Object a = Loading<int>();
      const Object b = Loading<String>();
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('Ready equality is value-based', () {
      expect(const Ready<int>(1), const Ready<int>(1));
      expect(const Ready<int>(1) == const Ready<int>(2), isFalse);
    });

    test(
      'ResourceError equality compares error, stackTrace and previousData',
      () {
        final st = StackTrace.current;
        expect(
          ResourceError<int>('bad', stackTrace: st, previousData: 1),
          ResourceError<int>('bad', stackTrace: st, previousData: 1),
        );
        expect(
          ResourceError<int>('bad', previousData: 1) ==
              ResourceError<int>('bad', previousData: 2),
          isFalse,
        );
      },
    );
  });

  group('toResource', () {
    test('Success becomes Ready', () {
      expect(const Result<int>.success(1).toResource(), const Ready<int>(1));
    });

    test(
      'Failure becomes ResourceError with the stack trace, no previousData',
      () {
        final st = StackTrace.current;
        final resource = Result<int>.failure('bad', st).toResource();
        expect(resource, isA<ResourceError<int>>());
        final error = resource as ResourceError<int>;
        expect(error.error, 'bad');
        expect(error.stackTrace, st);
        expect(error.previousData, isNull);
      },
    );
  });
}
