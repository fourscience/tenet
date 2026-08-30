## 1.0.0

- Initial release: `ResourceBuilder<T>`, rendering a `Resource<T>` (from
  [`casus`](../casus)) via `fold` — a `loading`/`ready`/`error` builder
  per state, with `error` receiving the failed resource's
  `previousData` so the caller can choose stale data, a skeleton, or an
  error view. Re-exports `casus` in full, so an app only needs to depend
  on `casus_flutter`.
