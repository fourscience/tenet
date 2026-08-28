import 'package:tenet_di/tenet_di.dart';
import 'package:test/test.dart';

void main() {
  group('Provider: lazy, cached, identity-keyed', () {
    test('create does not run until the first resolve', () {
      var creations = 0;
      final provider = Provider<int>((ref) {
        creations++;
        return 1;
      });
      final container = ProviderContainer();
      expect(creations, 0);
      container.resolve(provider);
      expect(creations, 1);
      container.dispose();
    });

    test('repeated resolves return the same cached instance', () {
      var creations = 0;
      final provider = Provider<Object>((ref) {
        creations++;
        return Object();
      });
      final container = ProviderContainer();
      final a = container.resolve(provider);
      final b = container.resolve(provider);
      expect(identical(a, b), isTrue);
      expect(creations, 1);
      container.dispose();
    });

    test('two containers never share state', () {
      final provider = Provider<Object>((ref) => Object());
      final c1 = ProviderContainer();
      final c2 = ProviderContainer();
      expect(identical(c1.resolve(provider), c2.resolve(provider)), isFalse);
      c1.dispose();
      c2.dispose();
    });

    test(
      'a resolve under a weak call-site context does not poison later ones',
      () {
        // Regression test: `print` takes `Object?`, which is a weak
        // enough expected type that Dart's generic inference for
        // `resolve<T>` can bind T to Object? here instead of String, even
        // though `provider` unambiguously declares String. A `_Node`
        // that was generic on the *inferred* T (rather than erasing to
        // Object? internally) would cache a wrongly-typed node here and
        // crash on a later, unrelated, correctly-typed resolve/observe of
        // the same provider.
        final provider = Provider<String>((ref) => 'hello');
        final container = ProviderContainer();

        // ignore: avoid_print
        print(container.resolve(provider));

        final String value = container.resolve(provider);
        expect(value, 'hello');
        expect(
          () => container.observe(provider, () {}),
          returnsNormally,
        );

        container.dispose();
      },
    );
  });

  group('Ref: dependency graph', () {
    test('a provider can observe another provider from its create function',
        () {
      final nameProvider = Provider<String>((ref) => 'ada');
      final greetingProvider = Provider<String>(
        (ref) => 'hello, ${ref.observe(nameProvider)}',
      );
      final container = ProviderContainer();
      expect(container.resolve(greetingProvider), 'hello, ada');
      container.dispose();
    });

    test(
      'invalidating an observed provider cascades to recreate its dependent',
      () {
        var dependentCreations = 0;
        final nameProvider = StateProvider<String>((ref) => 'ada');
        final greetingProvider = Provider<String>((ref) {
          dependentCreations++;
          return 'hello, ${ref.observe(nameProvider).state}';
        });
        final container = ProviderContainer();

        expect(container.resolve(greetingProvider), 'hello, ada');
        expect(dependentCreations, 1);

        container.resolve(nameProvider).state = 'grace';

        expect(container.resolve(greetingProvider), 'hello, grace');
        expect(dependentCreations, 2);

        container.dispose();
      },
    );

    test('ref.resolve does not establish an observe dependency', () {
      var dependentCreations = 0;
      final nameProvider = StateProvider<String>((ref) => 'ada');
      final greetingProvider = Provider<String>((ref) {
        dependentCreations++;
        return 'hello, ${ref.resolve(nameProvider).state}';
      });
      final container = ProviderContainer();

      expect(container.resolve(greetingProvider), 'hello, ada');
      container.resolve(nameProvider).state = 'grace';
      // No cascade: greetingProvider only *resolved* nameProvider, so
      // it's still holding the stale, already-computed value.
      expect(container.resolve(greetingProvider), 'hello, ada');
      expect(dependentCreations, 1);

      container.dispose();
    });

    test('a circular observe is reported, not stack-overflowed', () {
      late Provider<int> a;
      late Provider<int> b;
      a = Provider<int>((ref) => ref.observe(b));
      b = Provider<int>((ref) => ref.observe(a));
      final container = ProviderContainer();
      expect(() => container.resolve(a), throwsStateError);
      container.dispose();
    });
  });

  group('StateProvider', () {
    test(
        'resolving gives a StateController; state starts at the initial '
        'value', () {
      final counter = StateProvider<int>((ref) => 0);
      final container = ProviderContainer();
      expect(container.resolve(counter).state, 0);
      container.dispose();
    });

    test('setting state notifies observers', () {
      final counter = StateProvider<int>((ref) => 0);
      final container = ProviderContainer();
      final seen = <int>[];
      container.observe(
        counter,
        () => seen.add(container.resolve(counter).state),
      );

      container.resolve(counter).state = 1;
      container.resolve(counter).state = 2;

      expect(seen, [1, 2]);
      container.dispose();
    });

    test('setting state to an equal value does not notify', () {
      final counter = StateProvider<int>((ref) => 0);
      final container = ProviderContainer();
      var notifications = 0;
      container.observe(counter, () => notifications++);

      container.resolve(counter).state = 0; // same as initial
      expect(notifications, 0);

      container.resolve(counter).state = 1;
      expect(notifications, 1);

      container.dispose();
    });

    test('update() derives the next state from the current one', () {
      final counter = StateProvider<int>((ref) => 5);
      final container = ProviderContainer();
      container.resolve(counter).update((n) => n + 1);
      expect(container.resolve(counter).state, 6);
      container.dispose();
    });

    test('an observe() subscription survives a dependent cascade', () {
      // Regression check: the subscription is keyed by provider identity,
      // not by the specific internal node instance, which gets replaced
      // whenever an observed dependency invalidates this provider.
      final counter = StateProvider<int>((ref) => 0);
      final doubled = Provider<int>((ref) => ref.observe(counter).state * 2);

      final container = ProviderContainer();
      final seen = <int>[];
      container.observe(doubled, () => seen.add(container.resolve(doubled)));

      container.resolve(counter).state = 1;
      container.resolve(counter).state = 2;

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
      expect(container.resolve(provider), 'fake');
      expect(realCreations, 0);
      container.dispose();
    });

    test('overrideWith replaces the recipe but can still use Ref', () {
      final nameProvider = Provider<String>((ref) => 'real');
      final greetingProvider = Provider<String>(
        (ref) => 'hello, ${ref.observe(nameProvider)}',
      );
      final container = ProviderContainer(
        overrides: [nameProvider.overrideWith((ref) => 'fake')],
      );
      expect(container.resolve(greetingProvider), 'hello, fake');
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
      container.resolve(provider);
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
        return ref.observe(a) + 1;
      }, name: 'b');

      final container = ProviderContainer();
      container.resolve(b);
      container.dispose();

      expect(disposedNames.toSet(), {'a', 'b'});
    });

    test('invalidating cascades disposal to dependents', () {
      final disposedNames = <String>[];
      final a = StateProvider<int>((ref) => 0, name: 'a');
      final b = Provider<int>((ref) {
        ref.onDispose(() => disposedNames.add('b'));
        return ref.observe(a).state + 1;
      }, name: 'b');

      final container = ProviderContainer();
      container.resolve(b);
      container.resolve(a).state = 5; // invalidates b, which disposes

      expect(disposedNames, ['b']);
      container.dispose();
    });

    test('using a disposed container throws', () {
      final provider = Provider<int>((ref) => 1);
      final container = ProviderContainer();
      container.resolve(provider);
      container.dispose();
      expect(() => container.resolve(provider), throwsStateError);
    });

    test('dispose is idempotent', () {
      final container = ProviderContainer();
      container.dispose();
      expect(container.dispose, returnsNormally);
    });
  });

  group('root container', () {
    // rootContainer is process-wide, so every test in this group starts
    // from a clean slate — otherwise a provider created by one test would
    // still be cached (or, worse, disposed) when the next one runs.
    tearDown(resetRootContainer);

    test('is created lazily and reused across accesses', () {
      var creations = 0;
      final provider = Provider<int>((ref) {
        creations++;
        return 1;
      });
      expect(creations, 0);
      resolve(provider);
      resolve(provider);
      expect(creations, 1);
    });

    test('resolve reads through the same rootContainer every call', () {
      final provider = Provider<String>((ref) => 'hello');
      expect(resolve(provider), 'hello');
      expect(identical(rootContainer.resolve(provider), resolve(provider)),
          isTrue);
    });

    test('observe subscribes through rootContainer', () {
      final counter = StateProvider<int>((ref) => 0);
      final seen = <int>[];
      final unsubscribe = observe(
        counter,
        () => seen.add(resolve(counter).state),
      );

      resolve(counter).state = 1;
      resolve(counter).state = 2;
      expect(seen, [1, 2]);

      unsubscribe();
      resolve(counter).state = 3;
      expect(seen, [1, 2]); // unsubscribed: no further notifications
    });

    test('resetRootContainer disposes the old container and starts fresh', () {
      var disposed = false;
      final provider = Provider<int>((ref) {
        ref.onDispose(() => disposed = true);
        return 1;
      });
      resolve(provider);
      expect(disposed, isFalse);

      resetRootContainer();
      expect(disposed, isTrue);

      var creations = 0;
      final freshProvider = Provider<int>((ref) {
        creations++;
        return 1;
      });
      resolve(freshProvider);
      // A genuinely new container, not a cache that happened to survive.
      expect(creations, 1);
    });

    test('resetRootContainer is safe before rootContainer is ever touched', () {
      resetRootContainer();
      expect(resetRootContainer, returnsNormally);
    });
  });

  test('toString includes a provider\'s name when given', () {
    final named = Provider<int>((ref) => 1, name: 'answer');
    final unnamed = Provider<int>((ref) => 1);
    expect(named.toString(), 'answer');
    expect(unnamed.toString(), contains('Provider'));
  });
}
