import 'package:flutter/widgets.dart';
import 'package:tenet_di/tenet_di.dart';

/// Owns a [ProviderContainer] for the widget subtree below it, and
/// disposes it when this widget is removed from the tree. Wrap your
/// `runApp(...)` call in one:
///
/// ```dart
/// void main() => runApp(
///   const ProviderScope(child: MyApp()),
/// );
/// ```
///
/// [overrides] work exactly like [ProviderContainer]'s — typically for
/// swapping real dependencies with fakes in a widget test:
///
/// ```dart
/// await tester.pumpWidget(
///   ProviderScope(
///     overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
///     child: const MyApp(),
///   ),
/// );
/// ```
///
/// By default every `ProviderScope` owns a fresh container — this is
/// what keeps widget tests isolated from one another. Pass [container]
/// explicitly to use one you created yourself instead — most commonly
/// `rootContainer`, so state a widget reads through this scope and state
/// pure-Dart code resolves through the top-level `resolve`/`observe`
/// (both from `tenet_di`) are the same live state:
///
/// ```dart
/// void main() => runApp(
///   ProviderScope(container: rootContainer, child: const MyApp()),
/// );
/// ```
///
/// A `ProviderScope` never disposes a [container] you passed in — you
/// created it, so you own its lifecycle; that also means [overrides]
/// isn't valid alongside an explicit [container] (there's no `create`
/// call left for an override to replace).
///
/// Only one [ProviderScope] is expected per widget subtree — this
/// package doesn't support nested scopes with layered overrides.
final class ProviderScope extends StatefulWidget {
  /// Creates a scope. With no [container] given (the common case), a
  /// fresh [ProviderContainer] — owned and disposed by this widget — is
  /// created for [child]'s subtree, optionally with [overrides]. Pass
  /// [container] to use one you created and own instead; see the class
  /// doc comment.
  const ProviderScope({
    super.key,
    this.overrides = const [],
    this.container,
    required this.child,
  });

  /// Overrides applied to the container this scope creates. Ignored (and
  /// must be empty) when [container] is given.
  final List<ProviderOverride<Object?>> overrides;

  /// An existing container to use instead of creating one. When given,
  /// this scope reads from and writes to exactly this container, and
  /// never disposes it — the caller retains ownership.
  final ProviderContainer? container;

  /// The subtree that can read providers through this scope.
  final Widget child;

  /// The nearest ancestor [ProviderScope]'s container.
  ///
  /// Throws a [FlutterError] if there is no [ProviderScope] above
  /// [context]. Pass `listen: true` only if the caller itself is meant
  /// to rebuild when the *scope* is replaced (rare — most code should
  /// leave this false and instead watch individual providers through
  /// [WidgetRef]/`Consumer`).
  static ProviderContainer containerOf(
    BuildContext context, {
    bool listen = false,
  }) {
    final inherited = listen
        ? context.dependOnInheritedWidgetOfExactType<_InheritedProviderScope>()
        : context.getInheritedWidgetOfExactType<_InheritedProviderScope>();
    if (inherited == null) {
      throw FlutterError(
        'No ProviderScope found in context.\n'
        'Wrap your app (or the widget subtree using providers) in a '
        'ProviderScope.',
      );
    }
    return inherited.container;
  }

  @override
  State<ProviderScope> createState() => _ProviderScopeState();
}

final class _ProviderScopeState extends State<ProviderScope> {
  late final ProviderContainer _container =
      widget.container ?? ProviderContainer(overrides: widget.overrides);
  late final bool _ownsContainer = widget.container == null;

  @override
  void initState() {
    super.initState();
    assert(
      widget.container == null || widget.overrides.isEmpty,
      'overrides is only applied to a container ProviderScope creates '
      'itself; pass overrides to ProviderContainer(...) directly and '
      'hand the result to ProviderScope(container: ...) instead.',
    );
  }

  @override
  void dispose() {
    if (_ownsContainer) _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _InheritedProviderScope(container: _container, child: widget.child);
}

final class _InheritedProviderScope extends InheritedWidget {
  const _InheritedProviderScope({
    required this.container,
    required super.child,
  });

  final ProviderContainer container;

  @override
  bool updateShouldNotify(_InheritedProviderScope oldWidget) =>
      !identical(container, oldWidget.container);
}
