// Runnable example Flutter app for vine_flutter.
//
// Run it with:
//   cd example && flutter run

import 'package:flutter/material.dart';
import 'package:vine_flutter/vine_flutter.dart';

/// A reactive source.
final counterVine = Vine.cell(0, name: 'counter');

/// A plain dependency with no state of its own.
class Greeter {
  String greet(int count) =>
      count == 0 ? 'Nothing counted yet.' : "You've counted to $count.";
}

final greeterVine = Vine.single((tap) => Greeter(), name: 'greeter');

/// Derived from both vines above — recomputed, and every widget watching
/// it rebuilt, whenever `counterVine` changes.
final messageVine = Vine.computed(
  (tap) => tap(greeterVine).greet(tap(counterVine)),
  name: 'message',
);

void main() => runApp(
      Trellis(
        garden: Garden(vines: [greeterVine, counterVine, messageVine]).grow(),
        child: const MyApp(),
      ),
    );

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(body: Center(child: CounterPage())),
      );
}

/// Reads the reactive cell and rebuilds when it changes.
class CounterPage extends VineWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.watch(counterVine);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Count: $count', style: const TextStyle(fontSize: 32)),
        const SizedBox(height: 16),
        // A separate widget, watching a *derived* vine — it rebuilds
        // too, even though it never touches counterVine directly.
        const MessageText(),
        const SizedBox(height: 24),
        ElevatedButton(
          // context.tap: a one-off write, no subscription needed for a
          // button press.
          onPressed: () =>
              context.set(counterVine, context.tap(counterVine) + 1),
          child: const Text('Increment'),
        ),
      ],
    );
  }
}

class MessageText extends VineWidget {
  const MessageText({super.key});

  @override
  Widget build(BuildContext context) {
    final message = context.watch(messageVine);
    return Text(message, style: const TextStyle(fontStyle: FontStyle.italic));
  }
}
