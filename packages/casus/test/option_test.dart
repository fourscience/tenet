import 'package:casus/casus.dart';
import 'package:test/test.dart';

void main() {
  group('construction', () {
    test('fromNullable(null) is None', () {
      expect(Option.fromNullable<int>(null), isA<None<int>>());
    });

    test('fromNullable(non-null) is Some', () {
      expect(Option.fromNullable(5), const Some<int>(5));
    });

    test('Option.some / Option.none factories match Some/None', () {
      expect(const Option<int>.some(1), const Some<int>(1));
      expect(const Option<int>.none(), isA<None<int>>());
    });

    test('isPresent/isAbsent agree', () {
      expect(const Some<int>(1).isPresent, isTrue);
      expect(const Some<int>(1).isAbsent, isFalse);
      expect(const None<int>().isPresent, isFalse);
      expect(const None<int>().isAbsent, isTrue);
    });
  });

  group('toNullable', () {
    test('Some(v) becomes v, None becomes null', () {
      expect(const Some<int>(5).toNullable(), 5);
      expect(const None<int>().toNullable(), isNull);
    });
  });

  group('map', () {
    test('transforms Some', () {
      expect(const Some<int>(2).map((v) => v + 1), const Some<int>(3));
    });

    test('Option map on None is None', () {
      expect(Option<int>.none().map((v) => v + 1), isA<None<int>>());
    });
  });

  group('flatMap', () {
    Option<int> parseAge(String s) => int.tryParse(s).asOption;
    Option<String> ageCategory(int age) =>
        age >= 18 ? const Option.some('adult') : const Option.none();

    test('chains present values', () {
      expect(parseAge('30').flatMap(ageCategory), const Some<String>('adult'));
    });

    test('short-circuits on None without calling transform', () {
      var called = false;
      Option<int> f(int v) {
        called = true;
        return Option.some(v);
      }

      final result = Option<int>.none().flatMap(f);
      expect(called, isFalse);
      expect(result, isA<None<int>>());
    });
  });

  group('filter', () {
    test('a Some that satisfies the predicate stays Some', () {
      expect(const Some<int>(4).filter((v) => v.isEven), const Some<int>(4));
    });

    test('a Some that fails the predicate becomes None', () {
      expect(const Some<int>(3).filter((v) => v.isEven), isA<None<int>>());
    });

    test('None stays None', () {
      expect(Option<int>.none().filter((v) => true), isA<None<int>>());
    });
  });

  group('unwrapping', () {
    test('getOrElse returns the value or the fallback', () {
      expect(const Some<int>(5).getOrElse(-1), 5);
      expect(const None<int>().getOrElse(-1), -1);
    });

    test('unwrap returns the value on Some', () {
      expect(const Some<int>(5).unwrap(), 5);
    });

    test('unwrap throws OptionUnwrapException on None', () {
      expect(
        () => const None<int>().unwrap(),
        throwsA(isA<OptionUnwrapException>()),
      );
    });
  });

  group('fold', () {
    test('calls the matching branch only', () {
      expect(
        const Some<int>(1).fold(onSome: (v) => 'some:$v', onNone: () => 'none'),
        'some:1',
      );
      expect(
        const None<int>().fold(onSome: (v) => 'some:$v', onNone: () => 'none'),
        'none',
      );
    });
  });

  group('onSome / onNone', () {
    test('fire exactly once for the matching case', () {
      var somes = 0;
      var nones = 0;
      const Option<int> some = Some(1);
      some
        ..onSome((v) => somes++)
        ..onNone(() => nones++);
      expect(somes, 1);
      expect(nones, 0);
    });
  });

  group('sequence', () {
    test('all Some collapses to Some(list)', () {
      final result = [
        const Option<int>.some(1),
        const Option<int>.some(2),
      ].sequence();
      expect(result.isPresent, isTrue);
      expect(result.toNullable(), [1, 2]);
    });

    test('one None makes the whole sequence None', () {
      final result = [
        const Option<int>.some(1),
        Option<int>.none(),
        const Option<int>.some(3),
      ].sequence();
      expect(result, isA<None<List<int>>>());
    });
  });

  group('equality', () {
    test('Some equality is value-based', () {
      expect(const Some<int>(1), const Some<int>(1));
      expect(const Some<int>(1) == const Some<int>(2), isFalse);
    });

    test('None equality holds across differently-inferred type arguments', () {
      const Object a = None<int>();
      const Object b = None<String>();
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('Some is never equal to None', () {
      const Object some = Some<int>(1);
      const Object none = None<int>();
      expect(some == none, isFalse);
      expect(none == some, isFalse);
    });

    test('toString is debug-friendly', () {
      expect(const Some<int>(5).toString(), 'Some(5)');
      expect(const None<int>().toString(), 'None');
    });
  });
}
