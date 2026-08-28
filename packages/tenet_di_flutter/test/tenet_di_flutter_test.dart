import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tenet_di_flutter/tenet_di_flutter.dart';

// Regression: package:provider puts a zero-argument `context.read<T>()`
// and `context.watch<T>()` on BuildContext. Two same-named extension
// members on the same type are an unresolvable ambiguity at the *call
// site* in Dart — this file wouldn't compile at all if
// ReadProviderExtension were still named `read` instead of
// `readProvider`. Redeclaring provider's exact shape here, in the same
// library as tenet_di_flutter's own BuildContext extension, is the
// regression test: if this file compiles and `context.readProvider(...)`
// below resolves unambiguously, the two packages can coexist unprefixed.
extension _FakeProviderPackageContext on BuildContext {
  T read<T>() => throw UnimplementedError('stands in for package:provider');
  T watch<T>() => throw UnimplementedError('stands in for package:provider');
}

final counterProvider = StateProvider<int>((ref) => 0);
final doubledProvider =
    Provider<int>((ref) => ref.watch(counterProvider).state * 2);

class CounterText extends ConsumerWidget {
  const CounterText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider).state;
    return Text('count: $count', textDirection: TextDirection.ltr);
  }
}

int consumerWidgetBuilds = 0;

class DoubledText extends ConsumerWidget {
  const DoubledText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    consumerWidgetBuilds++;
    final doubled = ref.watch(doubledProvider);
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

  testWidgets('ConsumerWidget rebuilds when a watched provider changes', (
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

    capturedContext.readProvider(counterProvider).state = 5;
    await tester.pump();

    expect(find.text('count: 5'), findsOneWidget);
    expect(find.text('count: 0'), findsNothing);
  });

  testWidgets(
    'a derived Provider rebuilds its own watchers when its dependency changes',
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

      capturedContext.readProvider(counterProvider).state = 3;
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
            final count = ref.watch(counterProvider).state;
            return Text('inline: $count', textDirection: TextDirection.ltr);
          },
        ),
      ),
    );
    expect(find.text('inline: 0'), findsOneWidget);
  });

  testWidgets(
    'readProvider resolves unambiguously alongside a package:provider-shaped '
    'read/watch extension in the same file',
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
      expect(capturedContext.readProvider(counterProvider).state, 0);
      expect(() => capturedContext.read<int>(), throwsUnimplementedError);
      expect(() => capturedContext.watch<int>(), throwsUnimplementedError);
    },
  );

  testWidgets('BuildContext.readProvider does not subscribe to changes', (
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
            context.readProvider(counterProvider); // one-off, no rebuild
            return const SizedBox();
          },
        ),
      ),
    );
    expect(reads, 1);

    capturedContext.readProvider(counterProvider).state = 1;
    await tester.pump();

    // The Builder above never watched the provider, so nothing should
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
            ref.watch(provider);
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
