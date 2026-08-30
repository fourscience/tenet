import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:vine/vine.dart';

import 'trellis.dart';

/// The machinery behind `context.watch` (see the `context_extensions.dart`
/// doc comment for why fine-grained per-vine rebuild tracking needs a
/// dedicated [Element] rather than a bare [BuildContext] extension):
/// tracks which vines *this build* actually watched, subscribing to new
/// ones and unsubscribing from ones no longer watched — so the element
/// only rebuilds for vines its most recent build actually depends on
/// (dynamic re-tracking, the same principle `Vine.computed`/effects use).
mixin VineWatchingElement on ComponentElement {
  final Map<Vine, void Function()> _subscriptions = {};
  Set<Vine> _watchedThisBuild = const {};

  /// Reads [v] and subscribes this element to it — called by
  /// `context.watch(v)`.
  T watchVine<T>(Vine<T> v) {
    final garden = Trellis.of(this);
    _watchedThisBuild = {..._watchedThisBuild, v};
    _subscriptions.putIfAbsent(
        v, () => garden.watch(v, (_) => _handleChanged()));
    return garden.tap(v);
  }

  void _handleChanged() {
    if (!mounted) return;
    // A vine can change while Flutter is mid-build/layout/paint of the
    // *current* frame (e.g. another widget writes a cell from inside its
    // own build method); calling markNeedsBuild synchronously in that
    // window hits "setState()/markNeedsBuild() called during build".
    // Deferring to the next frame's post-frame callback is what the
    // framework itself recommends for exactly this case.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) markNeedsBuild();
      });
    } else {
      markNeedsBuild();
    }
  }

  @override
  Widget build() {
    _watchedThisBuild = {};
    final result = super.build();
    final stale = _subscriptions.keys
        .where((v) => !_watchedThisBuild.contains(v))
        .toList();
    for (final v in stale) {
      _subscriptions.remove(v)?.call();
    }
    return result;
  }

  @override
  void unmount() {
    for (final unsubscribe in _subscriptions.values) {
      unsubscribe();
    }
    _subscriptions.clear();
    super.unmount();
  }
}

final class VineStatelessElement extends StatelessElement
    with VineWatchingElement {
  VineStatelessElement(super.widget);
}
