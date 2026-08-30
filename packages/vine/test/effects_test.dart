import 'dart:async';

import 'package:test/test.dart';
import 'package:vine/vine.dart';

void main() {
  group('effect', () {
    test('runs once immediately, then again on a tracked change', () async {
      final cell = Vine.cell(1);
      final seen = <int>[];
      final garden = Garden().grow();
      garden.effect((tap) async {
        seen.add(tap(cell));
      });
      await garden.pump();
      expect(seen, [1]);
      garden.set(cell, 2);
      await garden.pump();
      expect(seen, [1, 2]);
    });

    test('dynamic re-tracking: switching branches changes what it reacts to',
        () async {
      final useLeft = Vine.cell(true);
      final left = Vine.cell(10);
      final right = Vine.cell(20);
      final seen = <int>[];
      final garden = Garden().grow();
      garden.effect((tap) async {
        seen.add(tap(useLeft) ? tap(left) : tap(right));
      });
      await garden.pump();
      expect(seen, [10]);

      garden.set(right, 999); // not tracked yet (still on the left branch)
      await garden.pump();
      expect(seen, [10], reason: 'right was never tapped, so no rerun');

      garden.set(useLeft, false);
      await garden.pump();
      expect(seen, [10, 999]);

      garden.set(left, 1); // left dropped out of the dependency set now
      await garden.pump();
      expect(seen, [10, 999], reason: 'left is no longer tracked');
    });

    test('runs are serialized: a change mid-run coalesces into one rerun',
        () async {
      final cell = Vine.cell(1);
      final started = <int>[];
      final finished = <int>[];
      final garden = Garden().grow();
      garden.effect((tap) async {
        final value = tap(cell);
        started.add(value);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        finished.add(value);
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(started, [1]);
      garden.set(cell, 2);
      garden.set(cell, 3);
      // A real (non-zero) delay inside the effect body needs to actually
      // elapse — pump() can't fast-forward it (see Scheduler.pump's doc
      // comment), so await it directly here instead.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(finished.last, 3, reason: 'runs coalesce onto the latest value');
      expect(started.length, lessThan(4),
          reason: 'no overlapping/queued-per-set runs');
    });

    test('disposer stops future runs', () async {
      final cell = Vine.cell(1);
      final seen = <int>[];
      final garden = Garden().grow();
      final stop = garden.effect((tap) async => seen.add(tap(cell)));
      await garden.pump();
      expect(seen, [1]);
      stop();
      garden.set(cell, 2);
      await garden.pump();
      expect(seen, [1], reason: 'disposed effect must not rerun');
    });

    test('an error is reported to onError, not thrown to the caller', () async {
      final errors = <Object>[];
      final garden =
          Garden(onError: (vine, error, stack) => errors.add(error)).grow();
      garden.effect((tap) async => throw StateError('boom'));
      await garden.pump();
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });
  });
}
