// Runnable example for vine.
//
// Run it with:
//   dart run example/vine_example.dart

import 'package:vine/vine.dart';

/// A plain dependency with no state of its own — a [Vine.single].
class Greeter {
  String greet(String name) => 'Hello, $name!';
}

final greeterVine = Vine.single((tap) => Greeter(), name: 'greeter');

/// A reactive source.
final nameCell = Vine.cell('world', name: 'name');

/// Derived, memoized, and re-run only when [nameCell] actually changes.
final greetingVine = Vine.computed(
  (tap) => tap(greeterVine).greet(tap(nameCell)),
  name: 'greeting',
);

/// A flaky remote call: fails the first attempt, then succeeds — modeled
/// as a [Vine.future] that reacts to [nameCell] too.
final class FlakyRemote {
  var _attempts = 0;
  Future<String> fetchProfile(String name) async {
    _attempts++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (_attempts == 1) throw Exception('simulated network error');
    return '$name#$_attempts';
  }
}

final remoteVine = Vine.single((tap) => FlakyRemote());
final profileVine = Vine.future<String>(
  (tap) => tap(remoteVine).fetchProfile(tap(nameCell)),
  name: 'profile',
);

Future<void> main() async {
  final garden = Garden(vines: [greeterVine, nameCell, greetingVine]).grow();

  // -- tap: a plain, unsubscribed read --
  print('== tap ==');
  print(garden.tap(greetingVine)); // Hello, world!

  // -- watch: fires again whenever the computed's value actually changes --
  print('\n== watch ==');
  final unsubscribe =
      garden.watch(greetingVine, (value) => print('watch: $value'));
  garden.set(nameCell, 'vine'); // triggers a notification
  garden.set(nameCell, 'vine'); // same value -> equality gate -> no-op
  await garden.pump();
  unsubscribe();

  // -- Vine.future: AsyncLoading -> AsyncError (first attempt) -> retry via
  // refresh -> AsyncData, all driven by the SAME nameCell dependency --
  print('\n== Vine.future ==');
  print(garden.tap(profileVine)); // AsyncLoading<String>(previous: null)
  try {
    await garden.tapAsync(profileVine);
  } catch (error) {
    print('first attempt failed: $error');
  }
  await garden.refresh(profileVine); // retries the same body
  print(garden.tap(profileVine)); // AsyncData<String>(vine#2)

  // -- effect: auto-tracked, reruns on change, serialized --
  print('\n== effect ==');
  final log = <String>[];
  final stopEffect = garden.effect((tap) async {
    log.add('effect saw: ${tap(nameCell)}');
  });
  garden.set(nameCell, 'reactive');
  await garden.pump();
  log.forEach(print);
  stopEffect();

  // -- growScope: an override + scoped-singleton isolation, both --
  print('\n== growScope ==');
  final testScope = garden.growScope(
    overrides: [greeterVine.override((tap) => Greeter())],
  );
  testScope.set(nameCell, 'scoped'); // does not affect the parent's cell
  print('scoped:  ${testScope.tap(greetingVine)}');
  print('parent:  ${garden.tap(greetingVine)}');

  await testScope.dispose();
  await garden.dispose();
}
