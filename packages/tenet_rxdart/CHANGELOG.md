## 0.1.0

- Initial release: `rxThrottle`/`rxDebounce`/`rxTransform` wrap a
  Ripple's own emissions with rxdart's `throttleTime`/`debounceTime`/any
  custom `Stream` transform; `rxRetry`/`rxRetryWhen` wrap `Rx.retryWhen`
  (with `rxRetry` preserving the never-retry-a-cancelled-scope guarantee
  `tenet`'s own `retry` enforces). `StoreRx.dispatchStream`/`sendStream`/
  `runRippleStream` drive a `Store` from a `Stream<E>` built with any
  rxdart operator.
