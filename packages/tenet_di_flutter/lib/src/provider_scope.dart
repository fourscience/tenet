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
/// Only one [ProviderScope] is expected per widget subtree — this
/// package doesn't support nested scopes with layered overrides.
final class ProviderScope extends StatefulWidget {
  /// Creates a scope owning a fresh [ProviderContainer] for [child]'s
  /// subtree.
  const ProviderScope({
    super.key,
    this.overrides = const [],
    required this.child,
  });

  /// Overrides applied to the container this scope creates.
  final List<ProviderOverride<Object?>> overrides;

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
  late final ProviderContainer _container = ProviderContainer(
    overrides: widget.overrides,
  );

  @override
  void dispose() {
    _container.dispose();
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
