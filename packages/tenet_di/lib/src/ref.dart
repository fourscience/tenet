import 'provider.dart';

/// What a [ProviderBase.create] function gets to build its value with.
///
/// This is the only way a provider may reach another provider or register
/// cleanup — there is no ambient/global lookup, so a provider's
/// dependencies are always visible in its own `create` function.
abstract interface class Ref {
  /// Reads [provider]'s current value without subscribing to future
  /// changes — a one-off read. Use this for values you don't need to
  /// react to (e.g. reading a config value once).
  T read<T>(ProviderBase<T> provider);

  /// Reads [provider]'s current value AND subscribes to it: if
  /// [provider]'s value changes later (its own state changed, or it was
  /// invalidated), whatever is currently being built from this [Ref] — a
  /// provider's `create`, or a Flutter widget — is invalidated/rebuilt
  /// too, recursively.
  T watch<T>(ProviderBase<T> provider);

  /// Registers [callback] to run when the provider owning this [Ref] is
  /// invalidated or the container is disposed — the place to close
  /// streams, cancel timers, or release any other resource the provider
  /// acquired in its `create` function.
  void onDispose(void Function() callback);
}
