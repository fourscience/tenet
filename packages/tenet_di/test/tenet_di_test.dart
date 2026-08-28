import 'package:tenet_di/tenet_di.dart';
import 'package:test/test.dart';

void main() {
  group('Provider: lazy, cached, identity-keyed', () {
    test('create does not run until the first read', () {
      var creations = 0;
      final provider = Provider<int>((ref) {
        creations++;
        return 1;
      });
      final container = ProviderContainer();
      expect(creations, 0);
      container.read(provider);
      expect(creations, 1);
      container.dispose();
    });

    test('repeated reads return the same cached instance', () {
      var creations = 0;
      final provider = Provider<Object>((ref) {
        creations++;
        return Object();
      });
      final container = ProviderContainer();
      final a = container.read(provider);
      final b = container.read(provider);
      expect(identical(a, b), isTrue);
      expect(creations, 1);
      container.dispose();
    });

    test('two containers never share state', () {
      final provider = Provider<Object>((ref) => Object());
      final c1 = ProviderContainer();
      final c2 = ProviderContainer();
      expect(identical(c1.read(provider), c2.read(provider)), isFalse);
      c1.dispose();
      c2.dispose();
    });

    test(
      'a read under a weak call-site context does not poison later reads',
      () {
        // Regression test: `print` takes `Object?`, which is a weak
        // enough expected type that Dart's generic inference for
        // `read<T>` can resolve T to Object? here instead of String, even
        // though `provider` unambiguously declares String. A `_Node`
        // that was generic on the *inferred* T (rather than erasing to
        // Object? internally) would cache a wrongly-typed node here and
        // crash on a later, unrelated, correctly-typed read/listen of
        // the same provider.
        final provider = Provider<String>((ref) => 'hello');
        final container = ProviderContainer();

        // ignore: avoid_print
        print(container.read(provider));

        final String value = container.read(provider);
        expect(value, 'hello');
        expect(
          () => container.listen(provider, () {}),
          returnsNormally,
        );

        container.dispose();
      },
    );
  });

  group('Ref: dependency graph', () {
    test('a provider can watch another provider from its create function', () {
      final nameProvider = Provider<String>((ref) => 'ada');
      final greetingProvider = Provider<String>(
        (ref) => 'hello, ${ref.watch(nameProvider)}',
      );
      final container = ProviderContainer();
      expect(container.read(greetingProvider), 'hello, ada');
      container.dispose();
    });

    test(
      'invalidating a watched provider cascades to recreate its dependent',
      () {
        var dependentCreations = 0;
        final nameProvider = StateProvider<String>((ref) => 'ada');
        final greetingProvider = Provider<String>((ref) {
          dependentCreations++;
          return 'hello, ${ref.watch(nameProvider).state}';
        });
        final container = ProviderContainer();

        expect(container.read(greetingProvider), 'hello, ada');
        expect(dependentCreations, 1);

        container.read(nameProvider).state = 'grace';

        expect(container.read(greetingProvider), 'hello, grace');
        expect(dependentCreations, 2);

        container.dispose();
      },
    );

    test('ref.read does not establish a watch dependency', () {
      var dependentCreations = 0;
      final nameProvider = StateProvider<String>((ref) => 'ada');
      final greetingProvider = Provider<String>((ref) {
        dependentCreations++;
        return 'hello, ${ref.read(nameProvider).state}';
      });
      final container = ProviderContainer();

      expect(container.read(greetingProvider), 'hello, ada');
      container.read(nameProvider).state = 'grace';
      // No cascade: greetingProvider only *read* nameProvider, so it's
      // still holding the stale, already-computed value.
      expect(container.read(greetingProvider), 'hello, ada');
      expect(dependentCreations, 1);

      container.dispose();
    });

    test('a circular watch is reported, not stack-overflowed', () {
      late Provider<int> a;
      late Provider<int> b;
      a = Provider<int>((ref) => ref.watch(b));
      b = Provider<int>((ref) => ref.watch(a));
      final container = ProviderContainer();
      expect(() => container.read(a), throwsStateError);
      container.dispose();
    });
  });

  group('StateProvider', () {
    test('reading gives a StateController; state starts at the initial value',
        () {
      final counter = StateProvider<int>((ref) => 0);
      final container = ProviderContainer();
      expect(container.read(counter).state, 0);
      container.dispose();
    });

    test('setting state notifies listen()ers', () {
      final counter = StateProvider<int>((ref) => 0);
      final container = ProviderContainer();
      final seen = <int>[];
      container.listen(counter, () => seen.add(container.read(counter).state));

      container.read(counter).state = 1;
      container.read(counter).state = 2;

      expect(seen, [1, 2]);
      container.dispose();
    });

    test('setting state to an equal value does not notify', () {
      final counter = StateProvider<int>((ref) => 0);
      final container = ProviderContainer();
      var notifications = 0;
      container.listen(counter, () => notifications++);

      container.read(counter).state = 0; // same as initial
      expect(notifications, 0);

      container.read(counter).state = 1;
      expect(notifications, 1);

      container.dispose();
    });

    test('update() derives the next state from the current one', () {
      final counter = StateProvider<int>((ref) => 5);
      final container = ProviderContainer();
      container.read(counter).update((n) => n + 1);
      expect(container.read(counter).state, 6);
      container.dispose();
    });

    test('a listen() subscription survives a dependent cascade', () {
      // Regression check: the subscription is keyed by provider identity,
      // not by the specific internal node instance, which gets replaced
      // whenever a watched dependency invalidates this provider.
      final counter = StateProvider<int>((ref) => 0);
      final doubled = Provider<int>((ref) => ref.watch(counter).state * 2);

      final container = ProviderContainer();
      final seen = <int>[];
      container.listen(doubled, () => seen.add(container.read(doubled)));

      container.read(counter).state = 1;
      container.read(counter).state = 2;

      expect(seen, [2, 4]);
      container.dispose();
    });
  });

  group('overrides', () {
    test('overrideWithValue replaces the value without calling create', () {
      var realCreations = 0;
      final provider = Provider<String>((ref) {
        realCreations++;
        return 'real';
      });
      final container = ProviderContainer(
        overrides: [provider.overrideWithValue('fake')],
      );
      expect(container.read(provider), 'fake');
      expect(realCreations, 0);
      container.dispose();
    });

    test('overrideWith replaces the recipe but can still use Ref', () {
      final nameProvider = Provider<String>((ref) => 'real');
      final greetingProvider = Provider<String>(
        (ref) => 'hello, ${ref.watch(nameProvider)}',
      );
      final container = ProviderContainer(
        overrides: [nameProvider.overrideWith((ref) => 'fake')],
      );
      expect(container.read(greetingProvider), 'hello, fake');
      container.dispose();
    });
  });

  group('disposal', () {
    test('onDispose runs when the provider is invalidated', () {
      var disposed = false;
      final provider = Provider<int>((ref) {
        ref.onDispose(() => disposed = true);
        return 1;
      });
      final container = ProviderContainer();
      container.read(provider);
      expect(disposed, isFalse);
      container.invalidate(provider);
      expect(disposed, isTrue);
      container.dispose();
    });

    test(
        'onDispose runs for every created provider when the container is disposed',
        () {
      final disposedNames = <String>[];
      final a = Provider<int>((ref) {
        ref.onDispose(() => disposedNames.add('a'));
        return 1;
      }, name: 'a');
      final b = Provider<int>((ref) {
        ref.onDispose(() => disposedNames.add('b'));
        return ref.watch(a) + 1;
      }, name: 'b');

      final container = ProviderContainer();
      container.read(b);
      container.dispose();

      expect(disposedNames.toSet(), {'a', 'b'});
    });

    test('invalidating cascades disposal to dependents', () {
      final disposedNames = <String>[];
      final a = StateProvider<int>((ref) => 0, name: 'a');
      final b = Provider<int>((ref) {
        ref.onDispose(() => disposedNames.add('b'));
        return ref.watch(a).state + 1;
      }, name: 'b');

      final container = ProviderContainer();
      container.read(b);
      container.read(a).state = 5; // invalidates b, which disposes

      expect(disposedNames, ['b']);
      container.dispose();
    });

    test('using a disposed container throws', () {
      final provider = Provider<int>((ref) => 1);
      final container = ProviderContainer();
      container.read(provider);
      container.dispose();
      expect(() => container.read(provider), throwsStateError);
    });

    test('dispose is idempotent', () {
      final container = ProviderContainer();
      container.dispose();
      expect(container.dispose, returnsNormally);
    });
  });

  test('toString includes a provider\'s name when given', () {
    final named = Provider<int>((ref) => 1, name: 'answer');
    final unnamed = Provider<int>((ref) => 1);
    expect(named.toString(), 'answer');
    expect(unnamed.toString(), contains('Provider'));
  });
}
