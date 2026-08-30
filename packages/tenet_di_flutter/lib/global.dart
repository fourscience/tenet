/// Re-exports `tenet_di`'s opt-in top-level `resolve`/`observe` sugar, so
/// an app that only depends on `tenet_di_flutter` directly (with
/// `tenet_di` pulled in transitively) doesn't need to add `tenet_di` to
/// its own `pubspec.yaml` just to import this. See
/// `package:tenet_di/global.dart`'s doc comment for why this is a
/// separate, opt-in import rather than part of the main
/// `tenet_di_flutter.dart`.
library;

export 'package:tenet_di/global.dart';
