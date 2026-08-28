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
///
/// Deliberately named `readProvider`, not `read`: `package:provider`
/// already puts a zero-argument `context.read<T>()` on [BuildContext]
/// (`context.watch<T>()` too), and Dart reports a same-named extension
/// member on the same type as an unresolvable ambiguity — not something
/// an import prefix can quietly paper over the way a plain class-name
/// collision can. Naming this differently means a codebase already
/// using `package:provider` can add this package alongside it,
/// unprefixed, and migrate one widget at a time instead of all at once.
extension ReadProviderExtension on BuildContext {
  /// Reads [provider]'s current value through the nearest ancestor
  /// [ProviderScope].
  T readProvider<T>(ProviderBase<T> provider) =>
      ProviderScope.containerOf(this).read(provider);
}
