import 'package:tenet/tenet.dart';

/// Adapts a plain `void Function(S)` (e.g. `StreamController.add`) into a
/// [StateEmitter] so it can stand in for the `emit` a [RippleBody] expects.
/// [StateEmitter] is an interface with a single `call` method rather than
/// a typedef, so a bare function value isn't automatically one — this is
/// the small bridge every rxdart wrapper in this package needs. Not part
/// of the public API.
final class CallbackEmitter<S> implements StateEmitter<S> {
  /// Creates an emitter that forwards every value to [_add].
  const CallbackEmitter(this._add);

  final void Function(S state) _add;

  @override
  void call(S state) => _add(state);
}
