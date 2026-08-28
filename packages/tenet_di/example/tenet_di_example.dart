// Runnable example for tenet_di — pure Dart, no Flutter involved.
//
// Run it with:
//   dart run example/tenet_di_example.dart

import 'package:tenet_di/tenet_di.dart';

/// A dependency with no dependencies of its own.
class Clock {
  DateTime now() => DateTime(2024, 1, 1); // fixed, for deterministic output
}

final clockProvider = Provider<Clock>((ref) => Clock(), name: 'clock');

/// A dependency that depends on another provider via `ref.watch`.
class Greeter {
  Greeter(this._clock);
  final Clock _clock;

  String greet(String name) => '[${_clock.now().year}] Hello, $name!';
}

final greeterProvider = Provider<Greeter>(
  (ref) => Greeter(ref.watch(clockProvider)),
  name: 'greeter',
);

/// A mutable, watchable dependency — StateProvider, not Provider.
final usernameProvider = StateProvider<String>(
  (ref) => 'guest',
  name: 'username',
);

/// A provider *derived* from a StateProvider: recomputed automatically
/// whenever usernameProvider's state changes, because it `ref.watch`ed it.
final welcomeMessageProvider = Provider<String>((ref) {
  final greeter = ref.watch(greeterProvider);
  final username = ref.watch(usernameProvider).state;
  return greeter.greet(username);
}, name: 'welcomeMessage');

void main() {
  final container = ProviderContainer();

  print(container.read(welcomeMessageProvider));

  // Subscribe to the derived provider — no manual re-wiring needed.
  final unsubscribe = container.listen(welcomeMessageProvider, () {
    print('(changed) ${container.read(welcomeMessageProvider)}');
  });

  // Mutating the StateProvider automatically invalidates and recomputes
  // welcomeMessageProvider, which notifies the listener above.
  container.read(usernameProvider).state = 'ada';
  container.read(usernameProvider).state = 'grace';
  container.read(usernameProvider).state = 'grace'; // no-op: same value

  unsubscribe();
  container.read(usernameProvider).state = 'ignored-after-unsubscribe';

  // Overrides — typically for tests, but usable anywhere a container is
  // constructed — swap a provider's recipe without touching the
  // providers that depend on it.
  final testContainer = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(
        Clock(), // a fake clock would go here in a real test
      ),
    ],
  );
  print('\nWith an overridden clock: '
      '${testContainer.read(welcomeMessageProvider)}');

  container.dispose();
  testContainer.dispose();
}
