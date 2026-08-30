import 'provider.dart';
import 'ref.dart';

/// A minimal, live, mutable holder for a value of type [T] — what a
/// [StateProvider] actually produces. Read `.state` for the current
/// value; set it (or call [update]) to change it and notify subscribers.
///
/// [T] must be treated as immutable: always set a *new* value rather than
/// mutating the current one in place. Notification is skipped whenever
/// `newValue == currentValue`, and for a mutable [T] with the default,
/// identity-based `==` (a plain `List`/`Set`/`Map`, or any class that
/// doesn't override `==`), mutating `state` in place and setting it back
/// compares equal to itself — same reference — so nothing notifies, even
/// though the contents changed:
///
/// ```dart
/// // Wrong: mutates the same list `state` already holds, then "sets" it
/// // back to itself — identical, so this never notifies.
/// controller.update((items) => items..add('x'));
///
/// // Right: a new list, so the old and new values compare unequal.
/// controller.update((items) => [...items, 'x']);
/// ```
final class StateController<T> {
  /// Creates a controller holding [initial].
  StateController(T initial) : _state = initial;

  T _state;
  final List<void Function(T value)> _listeners = [];

  /// The current value.
  T get state => _state;

  /// Sets the current value. A no-op (no notification) if [value] equals
  /// the current one — see the class doc comment for why that means [T]
  /// must be treated as immutable.
  set state(T value) {
    if (value == _state) return;
    _state = value;
    for (final listener in List.of(_listeners)) {
      listener(value);
    }
  }

  /// Sets the state to `updater(current state)` — sugar for the common
  /// "derive the next value from the current one" case. [updater] must
  /// return a new value rather than mutating [current] in place — see the
  /// class doc comment.
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

/// A provider for a value that changes over time. Resolving it — via
/// `container.resolve`/`ref.observe`/`ref.resolve` — gives you its
/// [StateController], not the raw value directly:
///
/// ```dart
/// final counterProvider = StateProvider<int>((ref) => 0);
///
/// container.resolve(counterProvider).state;      // 0
/// container.resolve(counterProvider).state = 5;  // notifies observers
/// container.resolve(counterProvider).update((n) => n + 1);
/// ```
///
/// Anything that `ref.observe`d this provider — another provider's
/// `create`, or a Flutter widget through `WidgetRef.observe` — is
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
