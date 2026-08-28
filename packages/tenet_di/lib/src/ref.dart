import 'provider.dart';

/// What a [ProviderBase.create] function gets to build its value with.
///
/// This is the only way a provider may reach another provider or register
/// cleanup — there is no ambient/global lookup *inside a provider's
/// `create`*, so a provider's dependencies are always visible right there
/// in its own signature. (For code with no provider graph of its own to
/// participate in — a `main()`, a background service — see the top-level
/// `resolve`/`observe` in `root_container.dart`, which read through a
/// shared, lazily-created container instead.)
abstract interface class Ref {
  /// Resolves [provider]'s current value without subscribing to future
  /// changes — a one-off read. Use this for values you don't need to
  /// react to (e.g. reading a config value once).
  T resolve<T>(ProviderBase<T> provider);

  /// Resolves [provider]'s current value AND subscribes to it: if
  /// [provider]'s value changes later (its own state changed, or it was
  /// invalidated), whatever is currently being built from this [Ref] — a
  /// provider's `create`, or a Flutter widget — is invalidated/rebuilt
  /// too, recursively.
  T observe<T>(ProviderBase<T> provider);

  /// Registers [callback] to run when the provider owning this [Ref] is
  /// invalidated or the container is disposed — the place to close
  /// streams, cancel timers, or release any other resource the provider
  /// acquired in its `create` function.
  void onDispose(void Function() callback);
}
