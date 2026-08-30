// Regression test: FeatureHarness.echoCalls must work without the
// Feature under test needing a static back-reference to the harness.
import 'package:reson/reson.dart';
import 'package:reson/reson_testing.dart';
import 'package:test/test.dart';

class Ping {
  const Ping();
}

/// Deliberately carries no test-only field, no back-reference of any
/// kind — a plain production-shaped Feature.
class CleanFeature extends Feature<int> {
  @override
  int get initial => 0;

  @override
  void registerFlows(FlowRegistry<int> flows) {
    flows.flow<Ping>((s, e) => s + 1, name: 'ping');
  }

  @override
  void registerEchos(EchoRegistry<int> echos) {
    echos.echo<Ping>((event, lens) {}, name: 'pinged');
  }
}

void main() {
  test('echoCalls works with a Feature that has no test back-reference', () {
    final h = FeatureHarness<int>(CleanFeature());

    h.dispatch(const Ping());
    h.dispatch(const Ping());

    final calls = h.echoCalls('pinged');
    expect(calls, hasLength(2));
    expect(calls.map((c) => c.event), [const Ping(), const Ping()]);
    // state is a snapshot at the moment each Echo fired: after the Flow's
    // commit, since Echoes fire after Flows within the same dispatch.
    expect(calls.map((c) => c.state), [1, 2]);
    h.dispose();
  });

  test('echoCalls is empty for a name that never fired', () {
    final h = FeatureHarness<int>(CleanFeature());
    expect(h.echoCalls('pinged'), isEmpty);
    expect(h.echoCalls('nonexistent'), isEmpty);
    h.dispose();
  });
}
