import 'provider.dart';
import 'ref.dart';

/// A minimal, live, mutable holder for a value of type [T] — what a
/// [StateProvider] actually produces. Read `.state` for the current
/// value; set it (or call [update]) to change it and notify subscribers.
final class StateController<T> {
  /// Creates a controller holding [initial].
  StateController(T initial) : _state = initial;

  T _state;
  final List<void Function(T value)> _listeners = [];

  /// The current value.
  T get state => _state;

  /// Sets the current value. A no-op (no notification) if [value] equals
  /// the current one.
  set state(T value) {
    if (value == _state) return;
    _state = value;
    for (final listener in List.of(_listeners)) {
      listener(value);
    }
  }

  /// Sets the state to `updater(current state)` — sugar for the common
  /// "derive the next value from the current one" case.
  void update(T Function(T current) updater) => state = updater(_state);

  /// Subscribes [listener] to state changes. Returns an unsubscriber.
  /// This is a low-level hook `ProviderContainer` uses internally to
  /// notice changes; most code should watch the owning [StateProvider]
  /// through a [Ref]/`WidgetRef` instead of calling this directly.
  void Function() addListener(void Function(T value) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// A provider for a value that changes over time. Reading it — via
/// `container.read`/`ref.watch`/`ref.read` — gives you its
/// [StateController], not the raw value directly:
///
/// ```dart
/// final counterProvider = StateProvider<int>((ref) => 0);
///
/// container.read(counterProvider).state;      // 0
/// container.read(counterProvider).state = 5;  // notifies watchers
/// container.read(counterProvider).update((n) => n + 1);
/// ```
///
/// Anything that `ref.watch`ed this provider — another provider's
/// `create`, or a Flutter widget through `WidgetRef.watch` — is
/// invalidated/rebuilt whenever `.state` is set to a new value.
final class StateProvider<T> extends ProviderBase<StateController<T>> {
  /// Creates a provider whose initial state is computed by [_initial].
  const StateProvider(this._initial, {super.name});

  final T Function(Ref ref) _initial;

  @override
  StateController<T> create(Ref ref) => StateController<T>(_initial(ref));

  @override
  void attach(StateController<T> value, void Function() notifyChanged) {
    value.addListener((_) => notifyChanged());
  }
}
