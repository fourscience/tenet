import 'package:flutter/widgets.dart';
import 'package:tenet_di/tenet_di.dart';

import 'provider_scope.dart';
import 'widget_ref.dart';

/// A one-off way to resolve a provider from a [BuildContext] outside of
/// `build` — e.g. inside a button's `onPressed` — without subclassing
/// [ConsumerWidget]/using `Consumer` and without subscribing to changes.
///
/// For anything resolved inside `build` that the widget should rebuild
/// for, use [WidgetRef.observe] via [ConsumerWidget]/`Consumer` instead.
///
/// Deliberately not named `read`/`watch`: `package:provider` already
/// puts a zero-argument `context.read<T>()` on [BuildContext]
/// (`context.watch<T>()` too — `flutter_bloc` re-exports both as-is),
/// and Dart reports a same-named extension member on the same type as
/// an unresolvable ambiguity — not something an import prefix can
/// quietly paper over the way a plain class-name collision can. Naming
/// this `resolve` instead sidesteps that specific collision.
///
/// It doesn't, on its own, solve a *second* one: `tenet_di`'s `Provider`
/// and this package's `Consumer`/`ConsumerWidget` are plain classes with
/// the same names as `package:provider`'s, so importing the main
/// `tenet_di_flutter.dart` unprefixed alongside `package:provider`
/// unprefixed is an `ambiguous_import` error — unlike the extension
/// clash above, a plain class-name clash like this *is* exactly what an
/// import prefix is for. This extension lives in its own file for
/// precisely that reason: import the main library with a prefix, and
/// this file without one, and both packages' widgets are usable side by
/// side while you migrate:
///
/// ```dart
/// import 'package:provider/provider.dart';
/// import 'package:tenet_di_flutter/tenet_di_flutter.dart' as di;
/// import 'package:tenet_di_flutter/context_extensions.dart'; // unprefixed
///
/// final greeting = di.Provider<String>((ref) => 'hi');
///
/// class StillOnPackageProvider extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) =>
///       Consumer<String>(builder: (c, v, _) => Text(v)); // package:provider
/// }
///
/// class MigratedToTenet extends di.ConsumerWidget {
///   @override
///   Widget build(BuildContext context, di.WidgetRef ref) =>
///       Text(ref.observe(greeting));
/// }
///
/// class OneOffReadMidMigration extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) =>
///       Text(context.resolve(greeting)); // this extension, unprefixed
/// }
/// ```
///
/// Verified against `package:provider` directly: with this import shape,
/// `flutter analyze` reports no issues.
extension ResolveProviderExtension on BuildContext {
  /// Resolves [provider]'s current value through the nearest ancestor
  /// [ProviderScope].
  T resolve<T>(ProviderBase<T> provider) =>
      ProviderScope.containerOf(this).resolve(provider);
}
