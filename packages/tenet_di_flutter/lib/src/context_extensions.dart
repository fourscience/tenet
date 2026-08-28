import 'package:flutter/widgets.dart';
import 'package:tenet_di/tenet_di.dart';

import 'provider_scope.dart';
import 'widget_ref.dart';

/// A one-off way to read a provider from a [BuildContext] outside of
/// `build` — e.g. inside a button's `onPressed` — without subclassing
/// [ConsumerWidget]/using `Consumer` and without subscribing to changes.
///
/// For anything read inside `build` that the widget should rebuild for,
/// use [WidgetRef.watch] via [ConsumerWidget]/`Consumer` instead.
extension ReadProviderExtension on BuildContext {
  /// Reads [provider]'s current value through the nearest ancestor
  /// [ProviderScope].
  T read<T>(ProviderBase<T> provider) =>
      ProviderScope.containerOf(this).read(provider);
}
