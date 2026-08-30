import 'package:flutter/widgets.dart';

import 'vine_element.dart';

/// A widget that rebuilds when any vine `context.watch` inside its
/// `build` changes. Subclass this the same way you would `StatelessWidget`
/// — `context.watch`/`context.tap`/`context.set`/`context.refresh` all
/// work directly on the `context` passed to `build`:
///
/// ```dart
/// class GreetingText extends VineWidget {
///   const GreetingText({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final greeting = context.watch(greetingVine);
///     return Text(greeting);
///   }
/// }
/// ```
///
/// For a one-off widget without a dedicated class, use [VineBuilder].
abstract class VineWidget extends StatelessWidget {
  /// Creates a widget whose `build`'s `context` supports `context.watch`.
  const VineWidget({super.key});

  @override
  StatelessElement createElement() => VineStatelessElement(this);
}

/// [VineWidget] as an inline builder, for a one-off widget that doesn't
/// need its own class:
///
/// ```dart
/// VineBuilder(
///   builder: (context, child) => Text(context.watch(greetingVine)),
/// )
/// ```
final class VineBuilder extends VineWidget {
  /// Creates a widget that delegates to [builder].
  const VineBuilder({super.key, required this.builder, this.child});

  /// Builds this widget's UI, given the current `context` (with
  /// `context.watch` support) and the static [child] (if any) — the same
  /// "hoist the part that doesn't need to rebuild" pattern
  /// `AnimatedBuilder` uses.
  final Widget Function(BuildContext context, Widget? child) builder;

  /// A subtree that doesn't depend on any watched vine, built once and
  /// passed through to [builder] on every rebuild.
  final Widget? child;

  @override
  Widget build(BuildContext context) => builder(context, child);
}
