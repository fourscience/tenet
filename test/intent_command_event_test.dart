import 'package:tenet/tenet.dart';
import 'package:tenet/tenet_testing.dart';
import 'package:test/test.dart';

// -- Test domain --------------------------------------------------------

/// Intent: the user asked to flip the switch. From the outside — this is
/// the only thing a "screen" sends.
class ToggleSwitch extends Intent {
  const ToggleSwitch();
}

/// Intent with no registered handler, for the fail-fast test.
class UnknownIntent extends Intent {
  const UnknownIntent();
}

/// Command: the exact, internal write instruction the ToggleSwitch
/// handler produces.
class SetSwitch extends Command<SwitchState> {
  final bool on;
  const SetSwitch(this.on);

  @override
  String get name => 'setSwitch';

  @override
  SwitchState reduce(SwitchState state) => state.copyWith(on: on);
}

/// Event: a declarative fact the ToggleSwitch handler broadcasts,
/// distinct from the automatic [EventCommitted].
class SwitchToggled extends Event {
  final bool on;
  const SwitchToggled(this.on);
}

/// An unrelated Event, used to prove that publishing one Event type never
/// reaches an Echo registered for a different one.
class OtherEvent extends Event {
  const OtherEvent();
}

/// Intent for the "a Ripple executes a Command after an await" test below.
class DelayedMarkDone extends Intent {
  const DelayedMarkDone();
}

/// Command produced from inside a Ripple, after it has awaited — proof
/// that a Ripple can capture its handler's `IntentContext` by closure and
/// call `execute` once its async work is done, not just while the
/// handler itself is still running synchronously.
class MarkDone extends Command<SwitchState> {
  const MarkDone();

  @override
  String get name => 'markDone';

  @override
  SwitchState reduce(SwitchState state) => state.copyWith(synced: true);
}

class SwitchState {
  final bool on;
  final bool synced;
  const SwitchState({this.on = false, this.synced = false});

  SwitchState copyWith({bool? on, bool? synced}) =>
      SwitchState(on: on ?? this.on, synced: synced ?? this.synced);

  @override
  bool operator ==(Object other) =>
      other is SwitchState && other.on == on && other.synced == synced;

  @override
  int get hashCode => Object.hash(on, synced);

  @override
  String toString() => 'SwitchState(on: $on, synced: $synced)';
}

/// A feature driven entirely by the Intent/Command/Event taxonomy: one
/// Intent handler that executes a Command, publishes a custom Event, and
/// launches a Ripple — all from a single `IntentContext`.
class SwitchFeature extends Feature<SwitchState> {
  @override
  SwitchState get initial => const SwitchState();

  @override
  void registerIntents(IntentRegistry<SwitchState> intents) {
    intents.on<ToggleSwitch>((intent, ctx) {
      final next = !ctx.state.on;
      ctx.execute(SetSwitch(next));
      ctx.publish(SwitchToggled(next));
      ctx.launch((event, emit) async {
        emit(ctx.state.copyWith(synced: true));
      }, source: 'sync');
    });

    intents.on<DelayedMarkDone>((intent, ctx) {
      ctx.launch((event, emit) async {
        await Future<void>.delayed(Duration.zero);
        // Executed after the await, through the IntentContext captured
        // when the handler ran — not through the unused `emit` above.
        ctx.execute(const MarkDone());
      }, source: 'delayed');
    });
  }

  @override
  void registerEchos(EchoRegistry<SwitchState> echos) {
    echos.echo<SwitchToggled>('toggled', (event, lens) {
      harness?.recordEcho('toggled', event.on);
    });
    echos.echo<EventCommitted>('committed', (event, lens) {
      harness?.recordEcho('committed', event.source);
    });
    echos.echo<OtherEvent>('other', (event, lens) {
      harness?.recordEcho('other', null);
    });
  }

  // Test back-reference (set by tests) so Echoes can record calls.
  static FeatureHarness<SwitchState>? harness;
}

void main() {
  test('Intent: routes to its handler, which executes a Command', () {
    final h = FeatureHarness<SwitchState>(SwitchFeature());
    SwitchFeature.harness = h;
    h.send(const ToggleSwitch());
    expect(h.state.on, isTrue);
    expect(h.transactions.first.source, 'setSwitch');
    SwitchFeature.harness = null;
    h.dispose();
  });

  test('Intent: sending an unregistered type fails fast', () {
    final h = FeatureHarness<SwitchState>(SwitchFeature());
    expect(() => h.send(const UnknownIntent()), throwsStateError);
    h.dispose();
  });

  test('Command: execute defaults source to command.name', () {
    final h = FeatureHarness<SwitchState>(SwitchFeature());
    h.execute(const SetSwitch(true));
    expect(h.lastTransaction!.source, 'setSwitch');
    h.dispose();
  });

  test('Command: execute accepts an explicit source override', () {
    final h = FeatureHarness<SwitchState>(SwitchFeature());
    h.execute(const SetSwitch(true), source: 'manualOverride');
    expect(h.lastTransaction!.source, 'manualOverride');
    h.dispose();
  });

  test('Command: execute is a no-op commit when reduce is idempotent', () {
    final h = FeatureHarness<SwitchState>(SwitchFeature());
    h.execute(const SetSwitch(false)); // already off — no change
    expect(h.transactions, isEmpty);
    h.dispose();
  });

  test(
    'Event: publish is routed by the published type, not by Event itself',
    () {
      final h = FeatureHarness<SwitchState>(SwitchFeature());
      SwitchFeature.harness = h;

      h.send(const ToggleSwitch());

      // The custom SwitchToggled Event reached its own Echo...
      expect(h.echoCalls('toggled'), [true]);
      // ...but never the Echo registered for a *different* Event type.
      expect(h.echoCalls('other'), isEmpty);

      SwitchFeature.harness = null;
      h.dispose();
    },
  );

  test(
    'Event: EventCommitted is published automatically for every commit',
    () async {
      final h = FeatureHarness<SwitchState>(SwitchFeature());
      SwitchFeature.harness = h;

      h.send(const ToggleSwitch());
      // The Intent handler's Ripple (launched fire-and-forget) still has
      // to land its own commit.
      await h.pump(const Duration(milliseconds: 20));

      // One EventCommitted for the executed Command, one for the Ripple's
      // emission — both automatic, neither hand-wired by the feature.
      expect(h.echoCalls('committed'), ['setSwitch', 'sync']);
      expect(h.state.synced, isTrue);

      SwitchFeature.harness = null;
      h.dispose();
    },
  );

  test('IntentContext.launch runs a Ripple that commits through emit',
      () async {
    final h = FeatureHarness<SwitchState>(SwitchFeature());
    h.send(const ToggleSwitch());
    await h.pump(const Duration(milliseconds: 20));
    expect(h.state.synced, isTrue);
    expect(h.transactions.map((t) => t.source), ['setSwitch', 'sync']);
    h.dispose();
  });

  test(
    'IntentContext captured by a Ripple can execute a Command after an '
    'await',
    () async {
      final h = FeatureHarness<SwitchState>(SwitchFeature());
      h.send(const DelayedMarkDone());
      await h.pump(const Duration(milliseconds: 20));
      expect(h.state.synced, isTrue);
      expect(h.lastTransaction!.source, 'markDone');
      h.dispose();
    },
  );
}
