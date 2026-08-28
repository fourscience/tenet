/// Testing toolkit for `flow_state` — kept as a separate entry point from
/// [flow_state.dart] so production code never has to pull in test-only
/// helpers such as [FeatureHarness].
library flow_state_testing;

export 'src/testing/feature_harness.dart';
