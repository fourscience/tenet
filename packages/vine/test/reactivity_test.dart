import 'package:test/test.dart';
import 'package:vine/vine.dart';

void main() {
  group('cell', () {
    test('reads its initial value', () {
      final cell = Vine.cell(10);
      final garden = Garden().grow();
      expect(garden.tap(cell), 10);
    });

    test('set updates the value read afterward', () {
      final cell = Vine.cell(10);
      final garden = Garden().grow();
      garden.set(cell, 20);
      expect(garden.tap(cell), 20);
    });

    test('an equal-value set is a no-op: watcher not notified', () async {
      final cell = Vine.cell(10);
      final garden = Garden().grow();
      var notifications = 0;
      garden.watch(cell, (_) => notifications++);
      garden.set(cell, 10); // same value
      await garden.pump();
      expect(notifications, 0);
    });

    test('a changing set does notify a watcher', () async {
      final cell = Vine.cell(10);
      final garden = Garden().grow();
      final seen = <int>[];
      garden.watch(cell, seen.add);
      garden.set(cell, 20);
      await garden.pump();
      expect(seen, [20]);
    });
  });

  group('computed', () {
    test('derives from a cell', () {
      final cell = Vine.cell(2);
      final doubled = Vine.computed((tap) => tap(cell) * 2);
      final garden = Garden().grow();
      expect(garden.tap(doubled), 4);
    });

    test('recomputes lazily after its input changes', () {
      final cell = Vine.cell(2);
      final doubled = Vine.computed((tap) => tap(cell) * 2);
      final garden = Garden().grow();
      expect(garden.tap(doubled), 4);
      garden.set(cell, 5);
      expect(garden.tap(doubled), 10);
    });

    test('body runs once per wave, not once per tap (memoized)', () {
      var runs = 0;
      final cell = Vine.cell(1);
      final doubled = Vine.computed((tap) {
        runs++;
        return tap(cell) * 2;
      });
      final garden = Garden().grow();
      garden.tap(doubled);
      garden.tap(doubled);
      garden.tap(doubled);
      expect(runs, 1);
      garden.set(cell, 2);
      garden.tap(doubled);
      garden.tap(doubled);
      expect(runs, 2);
    });

    test('chains through another computed', () {
      final cell = Vine.cell(1);
      final doubled = Vine.computed((tap) => tap(cell) * 2);
      final quadrupled = Vine.computed((tap) => tap(doubled) * 2);
      final garden = Garden().grow();
      expect(garden.tap(quadrupled), 4);
      garden.set(cell, 2);
      expect(garden.tap(quadrupled), 8);
    });

    test('equality gate: unchanged result does not renotify a watcher',
        () async {
      final cell = Vine.cell(4);
      // Always parity 'even' for any even cell value -> result never
      // actually changes when the cell moves between even numbers.
      final parity = Vine.computed((tap) => tap(cell).isEven ? 'even' : 'odd');
      final garden = Garden().grow();
      final seen = <String>[];
      garden.watch(parity, seen.add);
      expect(garden.tap(parity), 'even');
      garden.set(cell, 6); // still even
      await garden.pump();
      expect(seen, isEmpty, reason: 'parity result did not change');
      garden.set(cell, 7); // now odd
      await garden.pump();
      expect(seen, ['odd']);
    });

    test('diamond graph: shared dependency recomputes each node once per wave',
        () {
      var leftRuns = 0;
      var rightRuns = 0;
      var bottomRuns = 0;
      final top = Vine.cell(1);
      final left = Vine.computed((tap) {
        leftRuns++;
        return tap(top) + 1;
      });
      final right = Vine.computed((tap) {
        rightRuns++;
        return tap(top) + 2;
      });
      final bottom = Vine.computed((tap) {
        bottomRuns++;
        return tap(left) + tap(right);
      });
      final garden = Garden().grow();
      expect(garden.tap(bottom), 1 + 1 + 1 + 2);
      expect((leftRuns, rightRuns, bottomRuns), (1, 1, 1));

      garden.set(top, 10);
      expect(garden.tap(bottom), 11 + 12);
      expect((leftRuns, rightRuns, bottomRuns), (2, 2, 2));
    });

    test('dynamic re-tracking drops a branch no longer read', () {
      var runs = 0;
      final useLeft = Vine.cell(true);
      final left = Vine.cell(1);
      final right = Vine.cell(100);
      final picked = Vine.computed((tap) {
        runs++;
        return tap(useLeft) ? tap(left) : tap(right);
      });
      final garden = Garden().grow();
      expect(garden.tap(picked), 1);
      garden.set(useLeft, false);
      expect(garden.tap(picked), 100);
      expect(runs, 2);

      // `left` is no longer read by `picked` -> changing it must not
      // dirty (let alone recompute) `picked` anymore.
      garden.set(left, 999);
      expect(garden.tap(picked), 100);
      expect(runs, 2, reason: 'left was dropped from the dependency set');

      garden.set(right, 200);
      expect(garden.tap(picked), 200);
      expect(runs, 3);
    });

    test('tapping a pending future throws AsyncInSyncContextError', () {
      final future = Vine.future<int>((tap) async => 1);
      final bad = Vine.computed((tap) => tap(future).value ?? -1);
      final garden = Garden().grow();
      expect(() => garden.tap(bad), throwsA(isA<AsyncInSyncContextError>()));
    });

    test('single tapping computed is frozen — never re-runs', () {
      var computedRuns = 0;
      final cell = Vine.cell(1);
      final computed = Vine.computed((tap) {
        computedRuns++;
        return tap(cell);
      });
      final frozen = Vine.single((tap) => tap(computed));
      final garden = Garden().grow();
      expect(garden.tap(frozen), 1);
      expect(computedRuns, 1);
      garden.set(cell, 2);
      expect(garden.tap(computed), 2, reason: 'computed itself still reacts');
      expect(computedRuns, 2);
      expect(garden.tap(frozen), 1, reason: 'single never re-runs once built');
    });
  });
}
