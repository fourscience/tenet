import 'package:flutter/widgets.dart';
import 'package:tenet_di/tenet_di.dart';

import 'provider_scope.dart';
import 'widget_ref.dart';

/// A widget that rebuilds when any provider it [WidgetRef.watch]es
/// changes. Subclass this the same way you would `StatelessWidget`, but
/// override `build(context, ref)` instead of `build(context)`:
///
/// ```dart
/// class GreetingText extends ConsumerWidget {
///   const GreetingText({super.key});
///
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     final greeting = ref.watch(greetingProvider);
///     return Text(greeting);
///   }
/// }
/// ```
///
/// For a one-off widget without a dedicated class, use [Consumer].
abstract class ConsumerWidget extends StatefulWidget {
  /// Creates a widget with access to a [WidgetRef] in [build].
  const ConsumerWidget({super.key});

  /// Builds this widget's UI. Called again whenever a provider read via
  /// `ref.watch` in the previous build changes.
  Widget build(BuildContext context, WidgetRef ref);

  @override
  State<ConsumerWidget> createState() => _ConsumerWidgetState();
}

/// [ConsumerWidget] as an inline builder, for a one-off widget that
/// doesn't need its own class:
///
/// ```dart
/// Consumer(
///   builder: (context, ref, child) => Text(ref.watch(greetingProvider)),
/// )
/// ```
final class Consumer extends ConsumerWidget {
  /// Creates a widget that delegates to [builder].
  const Consumer({super.key, required this.builder, this.child});

  /// Builds this widget's UI, given the current [WidgetRef] and the
  /// static [child] (if any) — the same "hoist the part that doesn't
  /// need to rebuild" pattern `AnimatedBuilder` uses.
  final Widget Function(BuildContext context, WidgetRef ref, Widget? child)
      builder;

  /// A subtree that doesn't depend on any watched provider, built once
  /// and passed through to [builder] on every rebuild.
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      builder(context, ref, child);
}

final class _ConsumerWidgetState extends State<ConsumerWidget> {
  _WidgetRefImpl? _ref;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final container = ProviderScope.containerOf(context);
    if (_ref == null || !identical(_ref!.container, container)) {
      _ref?.dispose();
      _ref = _WidgetRefImpl(container, _handleProviderChanged);
    }
  }

  @override
  void dispose() {
    _ref?.dispose();
    super.dispose();
  }

  void _handleProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ref = _ref!;
    ref.beginBuild();
    final child = widget.build(context, ref);
    ref.endBuild();
    return child;
  }
}

/// Tracks, per build, which providers were watched — subscribing to new
/// ones and unsubscribing from ones no longer watched — so the widget
/// only rebuilds for providers its *current* build actually depends on.
final class _WidgetRefImpl implements WidgetRef {
  _WidgetRefImpl(this.container, this._onChanged);

  final ProviderContainer container;
  final void Function() _onChanged;
  final Map<ProviderBase, void Function()> _subscriptions = {};
  Set<ProviderBase> _watchedThisBuild = {};

  @override
  T read<T>(ProviderBase<T> provider) => container.read(provider);

  @override
  T watch<T>(ProviderBase<T> provider) {
    _watchedThisBuild.add(provider);
    _subscriptions.putIfAbsent(
      provider,
      () => container.listen(provider, _onChanged),
    );
    return container.read(provider);
  }

  void beginBuild() => _watchedThisBuild = {};

  void endBuild() {
    final stale = _subscriptions.keys
        .where((provider) => !_watchedThisBuild.contains(provider))
        .toList();
    for (final provider in stale) {
      _subscriptions.remove(provider)?.call();
    }
  }

  void dispose() {
    for (final unsubscribe in _subscriptions.values) {
      unsubscribe();
    }
    _subscriptions.clear();
  }
}
