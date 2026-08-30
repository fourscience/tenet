import 'package:test/test.dart';
import 'package:vine/vine.dart';

void main() {
  group('pump()', () {
    test('flushes batched sets into a single watcher notification', () async {
      final cell = Vine.cell(0);
      final doubled = Vine.computed((tap) => tap(cell) * 2);
      final garden = Garden().grow();
      final seen = <int>[];
      garden.watch(doubled, seen.add);
      garden.set(cell, 1);
      garden.set(cell, 2);
      garden.set(cell, 3);
      expect(seen, isEmpty, reason: 'not flushed yet');
      await garden.pump();
      expect(seen, [6], reason: 'one notification, reflecting the final value');
    });

    test('flushes a chain of scheduled reactive runs', () async {
      final cell = Vine.cell(1);
      final a = Vine.computed((tap) => tap(cell) + 1);
      final b = Vine.computed((tap) => tap(a) + 1);
      final c = Vine.computed((tap) => tap(b) + 1);
      final garden = Garden().grow();
      final seen = <int>[];
      garden.watch(c, seen.add);
      garden.tap(c); // establish the initial value/edges
      garden.set(cell, 10);
      await garden.pump();
      expect(seen, [13]);
    });

    test('is bounded: a self-stabilizing feedback loop terminates', () async {
      // A cell an effect both reads and clamps-writes: converges to a
      // fixed point (10) instead of looping forever, thanks to the
      // equality gate cutting off propagation once nothing changes.
      final cell = Vine.cell(50);
      final garden = Garden().grow();
      garden.effect((tap) async {
        final value = tap(cell);
        if (value > 10) garden.set(cell, 10);
      });
      await garden.pump().timeout(const Duration(seconds: 5));
      expect(garden.tap(cell), 10);
    });
  });
}
