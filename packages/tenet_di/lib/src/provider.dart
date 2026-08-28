import 'ref.dart';

/// A declarative recipe for building a value of type [T] — the identity
/// token consumers pass to `container.resolve`/`container.observe`/
/// `ref.observe` wherever they need [T]. A provider is declared once, as
/// a top-level `final`, and the *provider instance itself* (not its
/// type) is the cache key a [ProviderContainer] uses — two providers
/// built with equal `create` functions are still two independent
/// entries.
///
/// Providers are lazy: [create] doesn't run until something actually
/// resolves the provider, and its result is cached in the container
/// from then on (until invalidated).
abstract class ProviderBase<T> {
  /// Creates a provider, optionally named for debugging/error messages.
  const ProviderBase({this.name});

  /// An optional name shown in error messages and `toString()`.
  final String? name;

  /// Builds this provider's value. Called by a [ProviderContainer], at
  /// most once per container until the value is invalidated, never
  /// directly by application code.
  T create(Ref ref);

  /// Called once, immediately after [create] produces [value], so a
  /// provider whose value is itself a live, mutable object (like
  /// `StateProvider`'s `StateController`) can wire that object up to call
  /// [notifyChanged] whenever it changes in place — without the
  /// container needing to know about every provider kind that does this.
  /// Most providers don't override this; [value] never changes identity
  /// for a plain [Provider], so there's nothing to wire up.
  void attach(T value, void Function() notifyChanged) {}

  /// An override that always returns [value], never calling [create].
  /// Pass this to `ProviderContainer(overrides: [...])`, typically in
  /// tests, to swap a real dependency for a fake one.
  ProviderOverride<T> overrideWithValue(T value) =>
      ProviderOverride._(this, (ref) => value);

  /// An override that calls [create] instead of this provider's own
  /// `create` — for a fake that still needs to read other providers via
  /// [Ref], unlike [overrideWithValue].
  ProviderOverride<T> overrideWith(T Function(Ref ref) create) =>
      ProviderOverride._(this, create);

  @override
  String toString() => name ?? '$runtimeType#$hashCode';
}

/// The simplest, most common provider: wraps a plain `create` function.
/// Use this for services, repositories, configuration — anything that,
/// once built, doesn't change identity for the container's lifetime.
/// For a value that changes over time and should trigger rebuilds when it
/// does, see `StateProvider`.
final class Provider<T> extends ProviderBase<T> {
  /// Creates a provider that builds its value by calling [_create].
  const Provider(this._create, {super.name});

  final T Function(Ref ref) _create;

  @override
  T create(Ref ref) => _create(ref);
}

/// Replaces [provider] with a fixed recipe inside one [ProviderContainer]
/// — built via [ProviderBase.overrideWithValue]/[ProviderBase.overrideWith],
/// never constructed directly.
final class ProviderOverride<T> {
  const ProviderOverride._(this.provider, this.create);

  /// The provider being overridden.
  final ProviderBase<T> provider;

  /// The replacement recipe.
  final T Function(Ref ref) create;
}
