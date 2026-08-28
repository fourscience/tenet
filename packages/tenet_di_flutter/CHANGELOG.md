## 0.1.1

- Renamed the `BuildContext` extension method from `read` to
  `readProvider`. `package:provider` already defines `context.read<T>()`
  and `context.watch<T>()`, and two same-named extension members on the
  same type are an unresolvable ambiguity at the call site in Dart — not
  something an import prefix can quietly resolve the way a plain
  class-name clash can. Renaming lets a codebase already using
  `package:provider` add this package alongside it, unprefixed, and
  migrate one widget at a time instead of all at once.

## 0.1.0

- Initial release: `ProviderScope`, `ConsumerWidget`, `Consumer`,
  `WidgetRef`, and the `BuildContext.read` extension — Flutter bindings
  for `tenet_di`, re-exported in full.
