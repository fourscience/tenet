import 'container.dart';
import 'provider.dart';

/// The process-wide default [ProviderContainer], created the first time
/// anything touches it.
///
/// A [Ref] only ever sees providers reachable from its own `create`
/// function — there's no ambient lookup inside the provider graph itself
/// (see [Ref]'s doc comment). [rootContainer] is the escape hatch for
/// code that has no provider graph, no [Ref], and often no `BuildContext`
/// to thread one through at all: a `main()`, a background service, a
/// plain top-level function. [resolve] and [observe] below are sugar for
/// `rootContainer.resolve`/`rootContainer.observe` for exactly that case
/// — imported separately, from `package:tenet_di/global.dart`, not this
/// library; see that file's doc comment for why.
///
/// Prefer an explicitly-created [ProviderContainer] wherever one
/// naturally exists already — inside a `Ref`, inside a `WidgetRef`, or in
/// tests, where a fresh container per test (with its own
/// [ProviderBase.overrideWithValue]/[ProviderBase.overrideWith] overrides)
/// is what keeps tests from leaking state into one another.
/// [rootContainer] is one container shared by the whole process, so
/// widget tests in particular should almost never touch it — a
/// `ProviderScope` in a test creates its own container by default
/// specifically so it doesn't have to.
ProviderContainer get rootContainer => _root ??= ProviderContainer();

ProviderContainer? _root;

/// Resolves [provider] through [rootContainer] — sugar for
/// `rootContainer.resolve(provider)`, for call sites with no [Ref],
/// `WidgetRef`, or container of their own.
T resolve<T>(ProviderBase<T> provider) => rootContainer.resolve(provider);

/// Subscribes to [provider] through [rootContainer] — sugar for
/// `rootContainer.observe(provider, onChange)`.
void Function() observe<T>(
  ProviderBase<T> provider,
  void Function() onChange,
) =>
    rootContainer.observe(provider, onChange);

/// Disposes [rootContainer] (if one was ever created) and clears it, so
/// the next access to [rootContainer]/[resolve]/[observe] creates a
/// fresh one.
///
/// This exists almost exclusively for tests that touch [rootContainer]
/// and need a clean slate between runs — application code has little
/// reason to call it, since disposing the shared root container
/// invalidates every provider anything in the process might currently be
/// resolving through it.
void resetRootContainer() {
  _root?.dispose();
  _root = null;
}
