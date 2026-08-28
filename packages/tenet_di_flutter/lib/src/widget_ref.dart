import 'package:tenet_di/tenet_di.dart';

/// What a [ConsumerWidget]/`Consumer` builder gets to resolve providers
/// with — the Flutter counterpart of [Ref].
abstract interface class WidgetRef {
  /// Resolves [provider]'s current value without subscribing this widget
  /// to future changes — a one-off read, e.g. inside a button's
  /// `onPressed`.
  T resolve<T>(ProviderBase<T> provider);

  /// Resolves [provider]'s current value AND subscribes this widget to
  /// it: the widget rebuilds whenever [provider]'s value changes.
  ///
  /// Only providers observed during the *most recent* build stay
  /// subscribed — call this unconditionally, from the top of `build`,
  /// the same way you'd use a `StatefulWidget`'s fields; don't guard it
  /// behind a condition that can change between builds.
  T observe<T>(ProviderBase<T> provider);
}
