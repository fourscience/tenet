import 'package:test/test.dart';
import 'package:vine/vine.dart';

void main() {
  group('Vine.value', () {
    test('returns the exact instance given', () {
      final marker = Object();
      final vine = Vine.value(marker);
      final garden = Garden().grow();
      expect(identical(garden.tap(vine), marker), isTrue);
    });
  });

  group('Vine.single', () {
    test('is lazy: create does not run until tapped', () {
      var ran = false;
      final vine = Vine.single((tap) {
        ran = true;
        return 1;
      });
      Garden().grow();
      expect(ran, isFalse, reason: 'declaring/growing must not construct it');
      final garden = Garden(vines: [vine]).grow();
      expect(ran, isFalse,
          reason: 'listing it in vines: does not force it either');
      garden.tap(vine);
      expect(ran, isTrue);
    });

    test('returns the same instance on every tap within one scope', () {
      final vine = Vine.single((tap) => Object());
      final garden = Garden().grow();
      final first = garden.tap(vine);
      final second = garden.tap(vine);
      expect(identical(first, second), isTrue);
    });

    test('runs create only once even under concurrent-looking taps', () {
      var calls = 0;
      final vine = Vine.single((tap) {
        calls++;
        return calls;
      });
      final garden = Garden().grow();
      garden.tap(vine);
      garden.tap(vine);
      garden.tap(vine);
      expect(calls, 1);
    });

    test('resolves a transitive dependency', () {
      final a = Vine.single((tap) => 1);
      final b = Vine.single((tap) => tap(a) + 1);
      final c = Vine.single((tap) => tap(b) + 1);
      final garden = Garden().grow();
      expect(garden.tap(c), 3);
    });

    test('runs dispose exactly once, in LIFO order, on garden dispose',
        () async {
      final order = <String>[];
      final a = Vine.single((tap) => 'a', dispose: (_) => order.add('a'));
      final b = Vine.single((tap) {
        tap(a);
        return 'b';
      }, dispose: (_) => order.add('b'));
      final garden = Garden().grow();
      garden.tap(b); // constructs a, then b, in that order
      await garden.dispose();
      expect(order, ['b', 'a']);
      await garden.dispose(); // idempotent
      expect(order, ['b', 'a']);
    });
  });

  group('Vine.transient', () {
    test('constructs a fresh instance on every tap', () {
      var calls = 0;
      final vine = Vine.transient((tap) => calls++);
      final garden = Garden().grow();
      expect(garden.tap(vine), 0);
      expect(garden.tap(vine), 1);
      expect(garden.tap(vine), 2);
    });
  });

  group('Vine.eager', () {
    test('is constructed at grow(), before any tap', () {
      var ran = false;
      final vine = Vine.eager((tap) {
        ran = true;
        return 1;
      });
      final garden = Garden(vines: [vine]);
      expect(ran, isFalse);
      garden.grow();
      expect(ran, isTrue);
    });

    test('not listed in vines: is not grown eagerly despite the modifier', () {
      var ran = false;
      Vine.eager((tap) {
        ran = true;
        return 1;
      });
      Garden().grow(); // vine never passed in `vines:`
      expect(ran, isFalse);
    });
  });

  group('Vine.ref', () {
    test('resolves the bound vine at read time', () {
      final ref = Vine.ref<int>();
      final real = Vine.single((tap) => 42);
      ref.bindTo(real);
      final garden = Garden().grow();
      expect(garden.tap(ref), 42);
    });

    test('throws UntiedRefError when tapped before binding', () {
      final ref = Vine.ref<int>();
      final garden = Garden().grow();
      expect(() => garden.tap(ref), throwsA(isA<UntiedRefError>()));
    });

    test('breaks a genuine mutual dependency', () {
      final bRef = Vine.ref<B>();
      final a = Vine.single((tap) => A(() => tap(bRef).name));
      final b = Vine.single((tap) => B(tap(a)));
      bRef.bindTo(b);
      final garden = Garden().grow();
      final resolvedA = garden.tap(a);
      expect(resolvedA.describeB(), 'b-of-a');
    });
  });

  group('cycles', () {
    test('direct self-dependency throws CyclicDependencyError with a path', () {
      late Vine<int> self;
      self = Vine.single((tap) => tap(self));
      final garden = Garden().grow();
      expect(
        () => garden.tap(self),
        throwsA(isA<CyclicDependencyError>().having(
          (e) => e.path.length,
          'path length',
          greaterThanOrEqualTo(2),
        )),
      );
    });

    test('transitive a -> b -> a throws CyclicDependencyError', () {
      late Vine<int> a;
      late Vine<int> b;
      a = Vine.single((tap) => tap(b) + 1);
      b = Vine.single((tap) => tap(a) + 1);
      final garden = Garden().grow();
      expect(() => garden.tap(a), throwsA(isA<CyclicDependencyError>()));
    });
  });
}

class A {
  A(this._describeB);
  final String Function() _describeB;
  String describeB() => _describeB();
}

class B {
  B(this.fromA);
  final A fromA;
  String get name => 'b-of-a';
}
