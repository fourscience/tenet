/// Flutter bindings for `tenet_di`: [ProviderScope] owns a
/// `ProviderContainer` for a widget subtree, and [ConsumerWidget]/
/// [Consumer] rebuild automatically when the providers they
/// [WidgetRef.observe] change.
///
/// ```dart
/// void main() => runApp(const ProviderScope(child: MyApp()));
///
/// class GreetingText extends ConsumerWidget {
///   const GreetingText({super.key});
///
///   @override
///   Widget build(BuildContext context, WidgetRef ref) =>
///       Text(ref.observe(greetingProvider));
/// }
/// ```
library;

export 'package:tenet_di/tenet_di.dart';

export 'src/consumer.dart';
export 'src/context_extensions.dart';
export 'src/provider_scope.dart';
export 'src/widget_ref.dart';
