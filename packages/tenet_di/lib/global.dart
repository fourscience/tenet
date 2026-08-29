/// Opt-in top-level `resolve`/`observe` sugar for [rootContainer] — sitting
/// in its own entrypoint, separate from the main `tenet_di.dart`, on
/// purpose.
///
/// `resolve` and `observe` are common enough words that pulling bare
/// top-level functions with those names into every importer's namespace by
/// default would undo exactly the collision-avoidance `Ref`/`WidgetRef`'s
/// naming already went through once (see `Ref`'s doc comment in
/// `ref.dart`) — except this time for *every* consumer of `tenet_di`, not
/// just ones that also happen to use `package:provider`. Most code that
/// already has a `Ref`, a `WidgetRef`, or a `ProviderContainer` in scope
/// doesn't need these at all; import this file only at the few call
/// sites — a `main()`, a background service, anywhere with no natural
/// container to thread through — that actually want the bare functions:
///
/// ```dart
/// import 'package:tenet_di/tenet_di.dart';
/// import 'package:tenet_di/global.dart';
///
/// void main() {
///   print(resolve(greetingProvider)); // sugar for rootContainer.resolve(...)
/// }
/// ```
library;

export 'src/root_container.dart' show resolve, observe;
