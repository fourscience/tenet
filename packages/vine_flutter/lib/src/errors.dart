/// Thrown by `Trellis.of`/`context.tap`/`context.watch`/etc. when there is
/// no [Trellis] (or [TrellisScope]) above the given [BuildContext].
final class NoTrellisError extends Error {
  @override
  String toString() => 'NoTrellisError: no Trellis found in context.\n'
      'Wrap your app (or the widget subtree reading vines) in a Trellis:\n'
      '  Trellis(garden: garden, child: const MyApp())';
}

/// Thrown by `context.watch` when [BuildContext] doesn't belong to an
/// [Element] that supports it — only [VineWidget]/[VineBuilder]/
/// [SuspendedVine] do. `context.tap`/`context.set`/`context.refresh`
/// work from any context under a [Trellis]; only fine-grained rebuild
/// tracking needs the dedicated element.
final class NoVineWatchSupportError extends Error {
  @override
  String toString() =>
      'NoVineWatchSupportError: context.watch was called from a context '
      "that doesn't support it.\n"
      'Only VineWidget/VineBuilder/SuspendedVine bodies can '
      'context.watch(vine) — use context.tap(vine) instead for a one-off '
      'read, or wrap the reading widget in a VineWidget/VineBuilder.';
}
