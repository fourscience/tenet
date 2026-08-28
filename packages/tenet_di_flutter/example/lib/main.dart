// Runnable example Flutter app for tenet_di_flutter.
//
// Run it with:
//   cd example && flutter run

import 'package:flutter/material.dart';
import 'package:tenet_di_flutter/tenet_di_flutter.dart';

/// A mutable, observable dependency.
final counterProvider = StateProvider<int>((ref) => 0, name: 'counter');

/// A plain dependency with no state of its own.
class Greeter {
  String greet(int count) =>
      count == 0 ? 'Nothing counted yet.' : "You've counted to $count.";
}

final greeterProvider = Provider<Greeter>((ref) => Greeter(), name: 'greeter');

/// Derived from both providers above via `ref.observe` — recomputed, and
/// every widget observing it rebuilt, whenever `counterProvider` changes.
final messageProvider = Provider<String>((ref) {
  final greeter = ref.observe(greeterProvider);
  final count = ref.observe(counterProvider).state;
  return greeter.greet(count);
}, name: 'message');

void main() => runApp(const ProviderScope(child: MyApp()));

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          appBar: null,
          body: Center(child: CounterPage()),
        ),
      );
}

/// Reads the mutable state and rebuilds when it changes.
class CounterPage extends ConsumerWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.observe(counterProvider).state;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Count: $count', style: const TextStyle(fontSize: 32)),
        const SizedBox(height: 16),
        // A separate widget, observing a *derived* provider — it rebuilds
        // too, even though it never touches counterProvider directly.
        const MessageText(),
        const SizedBox(height: 24),
        ElevatedButton(
          // context.resolve: a one-off write, no subscription needed
          // for a button press.
          onPressed: () =>
              context.resolve(counterProvider).update((n) => n + 1),
          child: const Text('Increment'),
        ),
      ],
    );
  }
}

class MessageText extends ConsumerWidget {
  const MessageText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.observe(messageProvider);
    return Text(message, style: const TextStyle(fontStyle: FontStyle.italic));
  }
}
