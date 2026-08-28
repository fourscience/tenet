import 'provider.dart';
import 'ref.dart';

/// The scope that actually owns provider instances: the only place a
/// [ProviderBase.create] function ever runs. Everything is lazy — a
/// provider isn't created until the first [read]/[watch]/[listen] of it —
/// and cached from then on, so repeated reads of the same provider return
/// the same instance until it's invalidated.
///
/// ```dart
/// final container = ProviderContainer();
/// final repo = container.read(repositoryProvider);
/// container.dispose(); // tears everything down when done
/// ```
///
/// For tests, override any provider's recipe without touching the
/// providers a feature actually reads:
///
/// ```dart
/// final container = ProviderContainer(
///   overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
/// );
/// ```
final class ProviderContainer {
  /// Creates a container, optionally replacing some providers' recipes
  /// with [overrides] (see [ProviderBase.overrideWithValue] and
  /// [ProviderBase.overrideWith]).
  ProviderContainer({List<ProviderOverride<Object?>> overrides = const []}) {
    for (final override in overrides) {
      _overrides[override.provider] = override.create;
    }
  }

  final Map<ProviderBase, Object? Function(Ref ref)> _overrides = {};
  final Map<ProviderBase, _Node> _nodes = {};
  final Map<ProviderBase, Set<void Function()>> _externalListeners = {};
  final Set<ProviderBase> _creating = {};
  bool _disposed = false;

  /// Reads [provider]'s current value, creating it (and every provider it
  /// transitively watches) on first read. Does not subscribe to future
  /// changes — see [listen] for that.
  T read<T>(ProviderBase<T> provider) => _resolve(provider, watcher: null);

  /// Subscribes [onChange] to [provider]: called whenever its value
  /// changes (a watched `StateProvider`'s state was set, or [provider]
  /// itself — or something it transitively watches — was [invalidate]d).
  /// Returns a function that cancels the subscription.
  ///
  /// [onChange] receives no arguments; call [read] inside it for the
  /// fresh value. This is the low-level primitive the Flutter bindings
  /// (`tenet_di_flutter`'s `ConsumerWidget`/`Consumer`) build on; most
  /// application code should prefer those over calling this directly.
  void Function() listen<T>(
      ProviderBase<T> provider, void Function() onChange) {
    _checkNotDisposed();
    read(provider); // ensure it exists before anyone can be notified about it
    final listeners = _externalListeners.putIfAbsent(provider, () => {});
    listeners.add(onChange);
    return () => listeners.remove(onChange);
  }

  /// Tears down [provider]'s current value — runs its `ref.onDispose`
  /// callbacks and notifies listeners — then cascades to every provider
  /// that `ref.watch`ed it, recursively. The next [read] of any
  /// invalidated provider recreates it from scratch.
  void invalidate(ProviderBase provider) {
    _checkNotDisposed();
    _invalidate(provider);
  }

  /// Tears down every provider this container has created: runs all
  /// `ref.onDispose` callbacks and clears every cached value. The
  /// container itself cannot be used afterward. Idempotent.
  void dispose() {
    if (_disposed) return;
    for (final node in _nodes.values.toList()) {
      for (final disposer in node.disposers) {
        disposer();
      }
    }
    _nodes.clear();
    _externalListeners.clear();
    _disposed = true;
  }

  // `_Node` is deliberately NOT generic (see its doc comment) — `T` here
  // is only ever as reliable as the caller's own inference, and a call
  // site with a weak expected type (e.g. `print(container.read(p))`,
  // where `print` takes `Object?`) can silently widen `T` past what the
  // provider actually declares. Keying the cache on a `T`-typed node
  // would then crash a *later, unrelated* call once it inferred `T`
  // correctly and tried to cast the wrongly-typed cached node. Casting
  // only the erased `Object?` value at the point of return sidesteps
  // that: it succeeds as long as the value truly is a `T`, which
  // `provider.create`'s own return type already guarantees regardless of
  // what this particular call's `T` resolved to.
  T _resolve<T>(ProviderBase<T> provider, {ProviderBase? watcher}) {
    _checkNotDisposed();
    var node = _nodes[provider];
    if (node == null) {
      if (!_creating.add(provider)) {
        throw StateError(
          'Circular dependency detected while creating $provider.',
        );
      }
      final ref = _RefImpl(this, provider);
      final Object? value;
      try {
        final override = _overrides[provider];
        value = (override ?? provider.create)(ref);
      } finally {
        _creating.remove(provider);
      }
      node = _Node(value, ref.disposers);
      _nodes[provider] = node;
      provider.attach(value as T, () => _notifyChanged(provider));
    }
    if (watcher != null) {
      node.dependents.add(watcher);
    }
    return node.value as T;
  }

  void _notifyChanged(ProviderBase provider) {
    _notifyListeners(provider);
    final node = _nodes[provider];
    if (node == null) return;
    for (final dependent in List.of(node.dependents)) {
      _invalidate(dependent);
    }
  }

  void _invalidate(ProviderBase provider) {
    final node = _nodes.remove(provider);
    if (node == null) return;
    for (final disposer in node.disposers) {
      disposer();
    }
    _notifyListeners(provider);
    for (final dependent in List.of(node.dependents)) {
      _invalidate(dependent);
    }
  }

  void _notifyListeners(ProviderBase provider) {
    final listeners = _externalListeners[provider];
    if (listeners == null) return;
    for (final listener in List.of(listeners)) {
      listener();
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('This ProviderContainer has already been disposed.');
    }
  }
}

/// A cached provider value, its cleanup callbacks, and the set of other
/// providers that `ref.watch`ed it. Not generic on purpose — see the
/// comment on [ProviderContainer._resolve] for why.
final class _Node {
  _Node(this.value, this.disposers);
  final Object? value;
  final List<void Function()> disposers;
  final Set<ProviderBase> dependents = {};
}

final class _RefImpl implements Ref {
  _RefImpl(this._container, this._owner);

  final ProviderContainer _container;
  final ProviderBase _owner;
  final List<void Function()> disposers = [];

  @override
  T read<T>(ProviderBase<T> provider) => _container._resolve(provider);

  @override
  T watch<T>(ProviderBase<T> provider) =>
      _container._resolve(provider, watcher: _owner);

  @override
  void onDispose(void Function() callback) => disposers.add(callback);
}
