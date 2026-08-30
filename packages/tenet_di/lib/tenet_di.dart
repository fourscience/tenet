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
/// through? [rootContainer] is a shared default created lazily on first
/// use — `rootContainer.resolve(...)`/`rootContainer.observe(...)` work
/// out of the box; the bare top-level `resolve`/`observe` sugar around it
/// is one opt-in import away, at `package:tenet_di/global.dart` — see
/// that file's doc comment for why it isn't part of this one.
///
/// For a mutable, observable dependency, use [StateProvider] instead of a
/// plain [Provider]. See `tenet_di_flutter` for `ProviderScope`/
/// `ConsumerWidget`/`Consumer` — the same container, wired into widgets.
library;

export 'src/container.dart';
export 'src/provider.dart';
export 'src/ref.dart';
export 'src/root_container.dart' hide resolve, observe;
export 'src/state_provider.dart';
