/// A minimal, Riverpod/Refena-flavored dependency injection library for
/// Dart — works with or without Flutter.
///
/// Declare a dependency once, as a top-level `final`:
///
/// ```dart
/// final repositoryProvider = Provider<Repository>((ref) => Repository());
/// ```
///
/// Read it from a [ProviderContainer] — the only place a provider's
/// `create` function ever actually runs, lazily and cached:
///
/// ```dart
/// final container = ProviderContainer();
/// final repository = container.read(repositoryProvider);
/// ```
///
/// For a mutable, watchable dependency, use [StateProvider] instead of a
/// plain [Provider]. See `tenet_di_flutter` for `ProviderScope`/
/// `ConsumerWidget`/`Consumer` — the same container, wired into widgets.
library;

export 'src/container.dart';
export 'src/provider.dart';
export 'src/ref.dart';
export 'src/state_provider.dart';
