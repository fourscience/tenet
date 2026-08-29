// Regression test: a provider changing while another widget's build is
// still in progress must not crash with "setState() or markNeedsBuild()
// called during build."
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tenet_di_flutter/tenet_di_flutter.dart';

final counter = StateProvider<int>((ref) => 0);

class Watcher extends ConsumerWidget {
  const Watcher({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${ref.observe(counter).state}', textDirection: TextDirection.ltr);
}

/// Writes to [counter] from inside its own build — the write's
/// notification reaches [Watcher] while the framework is still building
/// this frame's widgets.
class MutatesDuringBuild extends ConsumerWidget {
  const MutatesDuringBuild({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.resolve(counter).state = 42;
    return const SizedBox();
  }
}

void main() {
  testWidgets(
    'a provider write during build does not crash, and the observer '
    'still updates by the next frame',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: Column(children: [Watcher(), MutatesDuringBuild()]),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('0'), findsOneWidget,
          reason: 'the deferred rebuild has not run yet');

      // The deferred setState runs in a post-frame callback; pump once
      // more to let it land.
      await tester.pump();
      expect(find.text('42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
