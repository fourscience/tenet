// Regression tests for the Ok/Err equality contract. Before 0.2.0, `==`
// compared type arguments, which made it asymmetric while `hashCode`
// stayed type-agnostic — so Set/Map membership depended on insertion
// order.
//
// Every comparison here is deliberately between two *statically unrelated*
// types (e.g. `Result<int, String>` vs `Ok<int, dynamic>`) — that mismatch
// is exactly the scenario the bug was in, so values are widened to
// `Object` to keep the analyzer from flagging it as a mistake rather than
// the point of the test.
import 'package:tenet_result/tenet_result.dart';
import 'package:test/test.dart';

Result<int, String> computeOk() => const Ok(1);
Result<int, String> computeErr() => const Err('nope');

void main() {
  group('Ok equality', () {
    test('is symmetric across differently-inferred type arguments', () {
      final Object actual = computeOk(); // Ok<int, String>
      const Object literal = Ok<int, dynamic>(1); // what a bare Ok(1) infers

      expect(actual == literal, isTrue);
      expect(literal == actual, isTrue, reason: '== must be symmetric');
    });

    test('agrees with hashCode', () {
      final actual = computeOk();
      const literal = Ok<int, dynamic>(1);
      expect(actual, literal);
      expect(actual.hashCode, literal.hashCode);
    });

    test('gives Set membership that does not depend on insertion order', () {
      final Object actual = computeOk();
      const Object literal = Ok<int, dynamic>(1);

      expect({actual, literal}, hasLength(1));
      expect({literal, actual}, hasLength(1));
    });

    test('still distinguishes different values', () {
      expect(const Ok<int, String>(1), isNot(const Ok<int, String>(2)));
    });

    test('is never equal to an Err, in either direction', () {
      const Object ok = Ok<String, String>('x');
      const Object err = Err<String, String>('x');
      expect(ok == err, isFalse);
      expect(err == ok, isFalse);
    });
  });

  group('Err equality', () {
    test('is symmetric across differently-inferred type arguments', () {
      final Object actual = computeErr(); // Err<int, String>
      const Object literal = Err<dynamic, String>('nope');

      expect(actual == literal, isTrue);
      expect(literal == actual, isTrue);
    });

    test('gives Set membership that does not depend on insertion order', () {
      final Object actual = computeErr();
      const Object literal = Err<dynamic, String>('nope');

      expect({actual, literal}, hasLength(1));
      expect({literal, actual}, hasLength(1));
    });

    test('still distinguishes different errors', () {
      expect(
        const Err<int, String>('a'),
        isNot(const Err<int, String>('b')),
      );
    });
  });

  group('as Map keys', () {
    test('a result looked up under a differently-inferred type is found', () {
      final map = <Object, String>{computeOk(): 'found'};
      expect(map[const Ok<int, dynamic>(1)], 'found');
    });
  });
}
