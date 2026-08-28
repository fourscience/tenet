// Runnable example for the Intent/Command/Event taxonomy.
//
// Where example/tenet_example.dart shows the original Flow/Ripple/Echo
// model, this one shows the same four concepts through an explicit
// Intent -> Command -> Event pipeline for a small "session" feature:
//   * Intent  — LogIn, the only thing a screen sends.
//   * Command — SetSessionStatus, the exact write instruction the
//     handler produces, both immediately and after its async work.
//   * Ripple  — launched by the handler to "authenticate" asynchronously,
//     via IntentContext.launch.
//   * Event   — SessionStarted, a custom broadcast once sign-in
//     succeeds, plus the automatic EventCommitted every commit publishes
//     for free — no hand-wiring required.
//
// Run it with:
//   dart run example/intent_command_event_example.dart

import 'dart:async';

import 'package:tenet/tenet.dart';

/// Sent by a screen when the user submits the login form.
class LogIn extends Intent {
  final String username;
  const LogIn(this.username);
}

/// The exact write instruction the LogIn handler produces — both right
/// away (to show "authenticating") and again once the async sign-in
/// finishes.
class SetSessionStatus extends Command<SessionState> {
  final String? username;
  final String status;
  const SetSessionStatus({this.username, required this.status});

  @override
  String get name => 'setSessionStatus';

  @override
  SessionState reduce(SessionState state) => SessionState(
        username: username ?? state.username,
        status: status,
      );
}

/// Broadcast once sign-in actually succeeds — distinct from the generic,
/// automatic [EventCommitted] every commit already publishes.
class SessionStarted extends Event {
  final String username;
  const SessionStarted(this.username);
}

/// State for the session feature.
class SessionState {
  final String? username;

  /// 'signedOut' | 'authenticating' | 'signedIn'
  final String status;

  const SessionState({this.username, this.status = 'signedOut'});

  @override
  String toString() => 'SessionState(username: $username, status: $status)';
}

/// Simulates a remote auth call.
Future<void> authenticate(String username) =>
    Future<void>.delayed(const Duration(milliseconds: 100));

/// A feature driven entirely by Intents: the LogIn handler executes a
/// Command synchronously, launches a Ripple for the async part, and that
/// Ripple executes a second Command — captured via closure over the same
/// IntentContext — once it's done.
class SessionFeature extends Feature<SessionState> {
  @override
  SessionState get initial => const SessionState();

  @override
  void registerIntents(IntentRegistry<SessionState> intents) {
    intents.on<LogIn>((intent, ctx) {
      ctx.execute(const SetSessionStatus(status: 'authenticating'));

      ctx.launch((event, emit) async {
        await authenticate(intent.username);
        // Executed after the await, through the IntentContext captured
        // when the handler ran — the Ripple's own `emit` goes unused
        // here since every write in this feature goes through a Command.
        ctx.execute(
          SetSessionStatus(username: intent.username, status: 'signedIn'),
        );
        ctx.publish(SessionStarted(intent.username));
      }, source: 'authenticate');
    });
  }

  @override
  void registerEchos(EchoRegistry<SessionState> echos) {
    echos.echo<SessionStarted>('audit', (event, lens) {
      print('[audit] ${event.username} signed in -> ${lens.state}');
    });
    echos.echo<EventCommitted>('audit', (event, lens) {
      print('[audit] commit from "${event.source}" -> ${lens.state}');
    });
  }
}

Future<void> main() async {
  final store = Store<SessionState>(SessionFeature());

  print('Before: ${store.state}');

  // The only thing a screen calls: send an Intent.
  store.send(const LogIn('ada'));
  print('Immediately after send: ${store.state}'); // still authenticating

  // The handler's Ripple is fire-and-forget by design (IntentContext.launch
  // mirrors Store.runRipple); give it time to finish its simulated auth
  // call and execute its own Command.
  await Future<void>.delayed(const Duration(milliseconds: 150));
  print('After sign-in completes: ${store.state}');

  print('\nLedger:');
  for (final txn in store.ledger) {
    print('  $txn');
  }

  store.close();
}
