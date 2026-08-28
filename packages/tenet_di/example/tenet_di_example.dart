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

/// A dependency that depends on another provider via `ref.observe`.
class Greeter {
  Greeter(this._clock);
  final Clock _clock;

  String greet(String name) => '[${_clock.now().year}] Hello, $name!';
}

final greeterProvider = Provider<Greeter>(
  (ref) => Greeter(ref.observe(clockProvider)),
  name: 'greeter',
);

/// A mutable, observable dependency — StateProvider, not Provider.
final usernameProvider = StateProvider<String>(
  (ref) => 'guest',
  name: 'username',
);

/// A provider *derived* from a StateProvider: recomputed automatically
/// whenever usernameProvider's state changes, because it `ref.observe`d it.
final welcomeMessageProvider = Provider<String>((ref) {
  final greeter = ref.observe(greeterProvider);
  final username = ref.observe(usernameProvider).state;
  return greeter.greet(username);
}, name: 'welcomeMessage');

void main() {
  final container = ProviderContainer();

  print(container.resolve(welcomeMessageProvider));

  // Subscribe to the derived provider — no manual re-wiring needed.
  final unsubscribe = container.observe(welcomeMessageProvider, () {
    print('(changed) ${container.resolve(welcomeMessageProvider)}');
  });

  // Mutating the StateProvider automatically invalidates and recomputes
  // welcomeMessageProvider, which notifies the observer above.
  container.resolve(usernameProvider).state = 'ada';
  container.resolve(usernameProvider).state = 'grace';
  container.resolve(usernameProvider).state = 'grace'; // no-op: same value

  unsubscribe();
  container.resolve(usernameProvider).state = 'ignored-after-unsubscribe';

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
      '${testContainer.resolve(welcomeMessageProvider)}');

  container.dispose();
  testContainer.dispose();

  // No container of your own at hand — no Ref, no WidgetRef, no
  // BuildContext? The top-level resolve/observe read through
  // rootContainer, a shared default created lazily on first use.
  print('\nVia the root container: ${resolve(welcomeMessageProvider)}');
}
