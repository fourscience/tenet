/// A minimal, Riverpod/Refena-flavored dependency injection library for
/// Dart — works with or without Flutter.
///
/// Declare a dependency once, as a top-level `final`:
///
/// ```dart
/// final repositoryProvider = Provider<Repository>((ref) => Repository());
/// ```
///
/// Resolve it from a [ProviderContainer] — the only place a provider's
/// `create` function ever actually runs, lazily and cached:
///
/// ```dart
/// final container = ProviderContainer();
/// final repository = container.resolve(repositoryProvider);
/// ```
///
/// No container of your own at hand — a `main()`, a background service,
/// anywhere with no natural container or `BuildContext` to thread
/// through? Use the top-level [resolve]/[observe], which read through
/// [rootContainer], a shared default created lazily on first use.
///
/// For a mutable, observable dependency, use [StateProvider] instead of a
/// plain [Provider]. See `tenet_di_flutter` for `ProviderScope`/
/// `ConsumerWidget`/`Consumer` — the same container, wired into widgets.
library;

export 'src/container.dart';
export 'src/provider.dart';
export 'src/ref.dart';
export 'src/root_container.dart';
export 'src/state_provider.dart';
