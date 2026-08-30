/// Flutter bindings for `vine`: [Trellis] owns the garden for a widget
/// subtree, [TrellisScope] shadows it for a sub-scope, and
/// `context.tap`/`watch`/`set`/`refresh` give widgets the same reactive
/// primitives a pure-Dart `Garden` does — `context.watch` rebuilds the
/// element whenever what it watched actually changes, with fine-grained
/// per-vine precision (equality-gated, dynamically re-tracked, same as
/// `Vine.computed`).
///
/// ```dart
/// void main() => runApp(
///   Trellis(garden: Garden(vines: [...]).grow(), child: const MyApp()),
/// );
///
/// class Counter extends VineWidget {
///   const Counter({super.key});
///   @override
///   Widget build(BuildContext context) {
///     final count = context.watch(counterVine);
///     return Text('$count');
///   }
/// }
/// ```
library;

export 'package:vine/vine.dart';

export 'src/context_extensions.dart';
export 'src/errors.dart';
export 'src/suspended_vine.dart';
export 'src/trellis.dart';
export 'src/vine_widget.dart';
