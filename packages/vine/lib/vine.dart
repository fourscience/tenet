/// A dependency injection + reactive state container for Dart.
///
/// Declare how things are made with [Vine] — value/single/transient/
/// eager for plain dependencies, cell/computed/future for reactive ones,
/// each/eachAsync for parameterized families, ref for breaking a genuine
/// mutual dependency. Read them with `tap`. Change a cell and everything
/// computed or future over it updates — with fine-grained precision,
/// stale-while-revalidate async, and zero codegen. It works in pure Dart
/// and tests deterministically with one `garden.pump()` call; see
/// `vine_flutter` for `Trellis`/`context.watch`.
///
/// ```dart
/// final counter = Vine.cell(0);
/// final doubled = Vine.computed((tap) => tap(counter) * 2);
///
/// final garden = Garden().grow();
/// garden.watch(doubled, (value) => print('doubled: $value'));
/// garden.set(counter, 5); // prints "doubled: 10" once flushed
/// ```
library;

export 'src/async_value.dart';
export 'src/errors.dart';
export 'src/garden.dart';
export 'src/tap.dart' show Tap;
export 'src/vine.dart';
