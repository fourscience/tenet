import 'package:flutter/widgets.dart';
import 'package:vine/vine.dart';

import 'errors.dart';
import 'trellis.dart';
import 'vine_element.dart';

/// The Flutter-widget-tree counterpart of [Tap]/[Garden]'s read/write/react
/// API. `tap`/`set`/`refresh`/`scope` work from any [BuildContext] under a
/// [Trellis]; `watch` additionally needs fine-grained *per-vine* rebuild
/// tracking (only rebuild this element when the specific vine it watched
/// actually changes, dropping a vine it stops watching the same way
/// `Vine.computed` drops a dependency it stops tapping) — Flutter's own
/// [InheritedWidget] mechanism can't express that (it rebuilds every
/// dependent on any change to one shared value), so `watch` only works
/// from a [VineWidget]/[VineBuilder]/`SuspendedVine` context; see
/// [NoVineWatchSupportError].
extension VineContextExtension on BuildContext {
  /// Reads [v] through the nearest ancestor [Trellis], without
  /// subscribing — a one-off read, e.g. inside a button's `onPressed`, or
  /// from a context that doesn't support [watch].
  T tap<T>(Vine<T> v) => Trellis.of(this).tap(v);

  /// Reads [v] AND subscribes: this element rebuilds whenever [v]'s value
  /// changes. Only valid from a [VineWidget]/[VineBuilder]/`SuspendedVine`
  /// context — throws [NoVineWatchSupportError] otherwise.
  ///
  /// Only vines watched during the *most recent* build stay subscribed —
  /// call this unconditionally, from the top of `build`, the same way
  /// you'd read a field; don't guard it behind a condition that can
  /// change between builds.
  T watch<T>(Vine<T> v) {
    final element = this;
    if (element is! VineWatchingElement) throw NoVineWatchSupportError();
    return element.watchVine(v);
  }

  /// Writes [cell] through the nearest ancestor [Trellis].
  void set<T>(CellVine<T> cell, T value) => Trellis.of(this).set(cell, value);

  /// Forces [v] to re-run through the nearest ancestor [Trellis].
  Future<void> refresh<T>(FutureVine<T> v,
          [Future<T> Function(Tap tap)? body]) =>
      Trellis.of(this).refresh(v, body);

  /// The nearest ancestor [Trellis]/[TrellisScope]'s garden — for
  /// anything needing the `Garden` itself (e.g. `growScope`, `effect`,
  /// `pump` in a test) rather than one of the sugar methods above.
  Garden get scope => Trellis.of(this);
}
