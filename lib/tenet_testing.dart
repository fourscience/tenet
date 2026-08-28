/// Testing toolkit for `tenet` — kept as a separate entry point from
/// [tenet.dart] so production code never has to pull in test-only
/// helpers such as [FeatureHarness].
library tenet_testing;

export 'src/testing/feature_harness.dart';
