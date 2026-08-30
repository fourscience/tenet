import 'package:flutter/widgets.dart';
import 'package:vine/vine.dart';

import 'errors.dart';

/// Exposes an existing, already-`grow()`n [garden] to the widget subtree
/// below it. Doesn't own [garden]'s lifecycle — you constructed and
/// `grow()`ed it, so you dispose it, typically never (a process-wide
/// garden usually just lives for the app's lifetime):
///
/// ```dart
/// void main() {
///   final garden = Garden(vines: [...]).grow();
///   runApp(Trellis(garden: garden, child: const MyApp()));
/// }
/// ```
///
/// For a subtree that needs its own scoped overrides (most commonly a
/// widget test), see [TrellisScope] instead — that one *does* own (and
/// disposes) the child `Garden` it creates.
final class Trellis extends StatelessWidget {
  /// Creates a widget exposing [garden] to [child]'s subtree.
  const Trellis({super.key, required this.garden, required this.child});

  /// The garden this subtree reads/writes/watches through.
  final Garden garden;

  /// The subtree that can reach [garden] via `Trellis.of`/`context.tap`/
  /// `context.watch`/etc.
  final Widget child;

  /// The nearest ancestor [Trellis]/[TrellisScope]'s garden.
  ///
  /// Throws [NoTrellisError] if there is no [Trellis] above [context].
  /// Pass `listen: true` only if the caller itself is meant to rebuild
  /// when the *garden reference itself* is replaced (rare — a
  /// [TrellisScope] swapping in a new child scope, say); most code
  /// should leave this false and instead watch individual vines through
  /// [context]'s `watch`/`tap` extensions.
  static Garden of(BuildContext context, {bool listen = false}) {
    final inherited = listen
        ? context.dependOnInheritedWidgetOfExactType<_InheritedTrellis>()
        : context.getInheritedWidgetOfExactType<_InheritedTrellis>();
    if (inherited == null) throw NoTrellisError();
    return inherited.garden;
  }

  @override
  Widget build(BuildContext context) =>
      _InheritedTrellis(garden: garden, child: child);
}

/// A child scope for [child]'s subtree: `growScope(vines:, overrides:)` off
/// the nearest ancestor [Trellis]/[TrellisScope], owned and disposed by
/// this widget when it's removed from the tree — the widget-tree
/// counterpart of `Garden.growScope`. Typically used to swap in test
/// doubles for a subtree:
///
/// ```dart
/// TrellisScope(
///   overrides: [repositoryVine.override((tap) => FakeRepository())],
///   child: const MyApp(),
/// )
/// ```
final class TrellisScope extends StatefulWidget {
  /// Creates a scope. [vines] is eagerly grown the same way
  /// `Garden(vines:)` is; [overrides] shadow the parent's vines for this
  /// subtree only.
  const TrellisScope({
    super.key,
    this.vines = const [],
    this.overrides = const [],
    required this.child,
  });

  /// Vines to eagerly construct/start for this scope.
  final List<Vine> vines;

  /// Overrides applied only within this scope.
  final List<VineOverride> overrides;

  /// The subtree that reads through this scope.
  final Widget child;

  @override
  State<TrellisScope> createState() => _TrellisScopeState();
}

final class _TrellisScopeState extends State<TrellisScope> {
  late final Garden _scope;

  @override
  void initState() {
    super.initState();
    _scope = Trellis.of(context)
        .growScope(vines: widget.vines, overrides: widget.overrides);
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Trellis(garden: _scope, child: widget.child);
}

final class _InheritedTrellis extends InheritedWidget {
  const _InheritedTrellis({required this.garden, required super.child});

  final Garden garden;

  @override
  bool updateShouldNotify(_InheritedTrellis oldWidget) =>
      !identical(garden, oldWidget.garden);
}
