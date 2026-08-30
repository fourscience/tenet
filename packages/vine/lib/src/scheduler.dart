import 'dart:async';

import 'node.dart';

/// Owns the dirty-node queue for one [Garden]/scope tree: batches
/// multiple `set()`s in one turn into a single microtask-scheduled flush,
/// and backs `Garden.pump()` for deterministic tests.
///
/// Every [ReactiveNode] a scope creates has its `onDirty` hook pointed at
/// [schedule], so marking a node dirty (via [ReactiveNode.propagateChange]
/// or a direct `set`) always ends up here.
final class Scheduler {
  final Set<ReactiveNode> _queue = {};
  bool _flushScheduled = false;

  /// Enqueues [node] for the next flush, scheduling a microtask flush if
  /// one isn't already pending.
  void schedule(ReactiveNode node) {
    _queue.add(node);
    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(_flush);
    }
  }

  void _flush() {
    _flushScheduled = false;
    drainQueue();
  }

  /// Processes every currently-queued dirty node once: pulls a
  /// [ComputedNode] (recompute + notify if changed), starts a
  /// [FutureNode]'s next run, runs an [EffectNode], or just flushes a
  /// [CellNode]'s own watchers. Each of those can enqueue further nodes
  /// (their own dependents) mid-loop, which keeps draining until stable.
  void drainQueue() {
    while (_queue.isNotEmpty) {
      final node = _queue.first;
      _queue.remove(node);
      if (!node.dirty) continue;
      if (node is ComputedNode) {
        node.pull();
      } else if (node is FutureNode) {
        node.start();
      } else if (node is EffectNode) {
        node.runIfNeeded();
      } else if (node is CellNode) {
        node.dirty = false;
        node.notifyWatchers();
      }
    }
  }

  /// Flushes all pending synchronous reactive work, then yields to the
  /// event loop so already-in-flight microtasks and same-turn async
  /// continuations (e.g. a `Vine.future`/effect body's first `await` on
  /// an already-resolved future) get a chance to land and enqueue more
  /// work — repeating, bounded, until nothing new shows up.
  ///
  /// This drains *scheduled* async work, not real time: a body awaiting
  /// `Future.delayed(someNonZeroDuration)` needs that duration to
  /// actually elapse (or `package:fake_async`) — `pump()` won't fast
  /// forward a real timer.
  Future<void> pump({int maxIterations = 1000}) async {
    for (var i = 0; i < maxIterations; i++) {
      drainQueue();
      final wasEmpty = _queue.isEmpty;
      await Future<void>.delayed(Duration.zero);
      if (wasEmpty && _queue.isEmpty) return;
    }
  }
}
