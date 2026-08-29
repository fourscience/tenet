import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tenet_di_flutter/global.dart'; // opt-in: bare resolve/observe
import 'package:tenet_di_flutter/tenet_di_flutter.dart';

// Regression: package:provider puts a zero-argument `context.read<T>()`
// and `context.watch<T>()` on BuildContext. Two same-named extension
// members on the same type are an unresolvable ambiguity at the *call
// site* in Dart — this file wouldn't compile at all if
// ResolveProviderExtension put `read`/`watch` on BuildContext instead of
// `resolve`. Redeclaring provider's exact shape here, in the same
// library as tenet_di_flutter's own BuildContext extension, is the
// regression test: if this file compiles and `context.resolve(...)`
// below resolves unambiguously, the two packages can coexist unprefixed.
extension _FakeProviderPackageContext on BuildContext {
  T read<T>() => throw UnimplementedError('stands in for package:provider');
  T watch<T>() => throw UnimplementedError('stands in for package:provider');
}

final counterProvider = StateProvider<int>((ref) => 0);
final doubledProvider =
    Provider<int>((ref) => ref.observe(counterProvider).state * 2);

class CounterText extends ConsumerWidget {
  const CounterText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.observe(counterProvider).state;
    return Text('count: $count', textDirection: TextDirection.ltr);
  }
}

int consumerWidgetBuilds = 0;

class DoubledText extends ConsumerWidget {
  const DoubledText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    consumerWidgetBuilds++;
    final doubled = ref.observe(doubledProvider);
    return Text('doubled: $doubled', textDirection: TextDirection.ltr);
  }
}

void main() {
  setUp(() {
    consumerWidgetBuilds = 0;
  });

  testWidgets('ConsumerWidget renders the initial provider value', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: CounterText()),
    );
    expect(find.text('count: 0'), findsOneWidget);
  });

  testWidgets('ConsumerWidget rebuilds when an observed provider changes', (
    tester,
  ) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      ProviderScope(
        child: Builder(
          builder: (context) {
            capturedContext = context;
            return const CounterText();
          },
        ),
      ),
    );
    expect(find.text('count: 0'), findsOneWidget);

    capturedContext.resolve(counterProvider).state = 5;
    await tester.pump();

    expect(find.text('count: 5'), findsOneWidget);
    expect(find.text('count: 0'), findsNothing);
  });

  testWidgets(
    'a derived Provider rebuilds its own observers when its dependency changes',
    (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (context) {
              capturedContext = context;
              return const DoubledText();
            },
          ),
        ),
      );
      expect(find.text('doubled: 0'), findsOneWidget);
      expect(consumerWidgetBuilds, 1);

      capturedContext.resolve(counterProvider).state = 3;
      await tester.pump();

      expect(find.text('doubled: 6'), findsOneWidget);
      expect(consumerWidgetBuilds, 2);
    },
  );

  testWidgets('Consumer works as an inline builder', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, child) {
            final count = ref.observe(counterProvider).state;
            return Text('inline: $count', textDirection: TextDirection.ltr);
          },
        ),
      ),
    );
    expect(find.text('inline: 0'), findsOneWidget);
  });

  testWidgets(
    'context.resolve resolves unambiguously alongside a '
    'package:provider-shaped read/watch extension in the same file',
    (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      // Both extensions are in scope in this file; each name resolves to
      // exactly one declaration, so both compile and run without a
      // "defined in multiple extensions" error.
      expect(capturedContext.resolve(counterProvider).state, 0);
      expect(() => capturedContext.read<int>(), throwsUnimplementedError);
      expect(() => capturedContext.watch<int>(), throwsUnimplementedError);
    },
  );

  testWidgets('BuildContext.resolve does not subscribe to changes', (
    tester,
  ) async {
    var reads = 0;
    late BuildContext capturedContext;
    await tester.pumpWidget(
      ProviderScope(
        child: Builder(
          builder: (context) {
            capturedContext = context;
            reads++;
            context.resolve(counterProvider); // one-off, no rebuild
            return const SizedBox();
          },
        ),
      ),
    );
    expect(reads, 1);

    capturedContext.resolve(counterProvider).state = 1;
    await tester.pump();

    // The Builder above never observed the provider, so nothing should
    // have triggered it to rebuild.
    expect(reads, 1);
  });

  testWidgets('overrides swap a provider without touching consumers', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [counterProvider.overrideWith((ref) => StateController(99))],
        child: const CounterText(),
      ),
    );
    expect(find.text('count: 99'), findsOneWidget);
  });

  testWidgets(
    'ProviderScope(container: rootContainer) unifies widget-tree and '
    'top-level state',
    (tester) async {
      addTearDown(resetRootContainer);
      await tester.pumpWidget(
        ProviderScope(container: rootContainer, child: const CounterText()),
      );
      expect(find.text('count: 0'), findsOneWidget);

      // Mutated from plain Dart code, with no BuildContext in sight.
      resolve(counterProvider).state = 7;
      await tester.pump();

      expect(find.text('count: 7'), findsOneWidget);
    },
  );

  testWidgets(
    'ProviderScope(container: ...) never disposes a container it was given',
    (tester) async {
      final container = ProviderContainer();
      await tester.pumpWidget(
        ProviderScope(container: container, child: const SizedBox()),
      );
      await tester.pumpWidget(const SizedBox()); // unmounts the scope

      expect(() => container.resolve(counterProvider), returnsNormally);
      container.dispose();
    },
  );

  testWidgets('overrides alongside an explicit container asserts', (
    tester,
  ) async {
    final container = ProviderContainer();
    await tester.pumpWidget(
      ProviderScope(
        container: container,
        overrides: [counterProvider.overrideWith((ref) => StateController(1))],
        child: const SizedBox(),
      ),
    );
    expect(tester.takeException(), isAssertionError);
    container.dispose();
  });

  testWidgets('disposing the ProviderScope disposes its container', (
    tester,
  ) async {
    var disposed = false;
    final provider = Provider<int>((ref) {
      ref.onDispose(() => disposed = true);
      return 1;
    });

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, child) {
            ref.observe(provider);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(disposed, isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(disposed, isTrue);
  });

  testWidgets('ProviderScope.containerOf throws with no ancestor scope', (
    tester,
  ) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox();
        },
      ),
    );
    expect(
      () => ProviderScope.containerOf(capturedContext),
      throwsA(isA<FlutterError>()),
    );
  });
}
