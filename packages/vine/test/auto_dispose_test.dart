import 'package:test/test.dart';
import 'package:vine/vine.dart';

void main() {
  group('autoDispose on computed', () {
    test('watcher count 0 -> dropped on next pump; re-tap re-runs', () async {
      var runs = 0;
      final cell = Vine.cell(1);
      final vine = Vine.computed((tap) {
        runs++;
        return tap(cell) * 2;
      }).autoDispose;
      final garden = Garden().grow();
      final stop = garden.watch(vine, (_) {});
      expect(garden.tap(vine), 2);
      expect(runs, 1);
      stop();
      await garden.pump();
      // Dropped: tapping again reruns create from scratch.
      expect(garden.tap(vine), 2);
      expect(runs, 2,
          reason: 'the cached value was dropped, so tapping reran it');
    });

    test('rapid unwatch + rewatch within a turn is NOT dropped (grace)',
        () async {
      var runs = 0;
      final vine = Vine.computed((tap) {
        runs++;
        return 1;
      }).autoDispose;
      final garden = Garden().grow();
      garden.tap(vine);
      expect(runs, 1);
      final stop = garden.watch(vine, (_) {});
      stop();
      final stop2 =
          garden.watch(vine, (_) {}); // re-watched before the grace check runs
      await garden.pump();
      garden.tap(vine);
      expect(runs, 1,
          reason:
              'still watched when the drop check ran, so it was not dropped');
      stop2();
    });

    test('a non-autoDispose computed is never dropped', () async {
      var runs = 0;
      final vine = Vine.computed((tap) {
        runs++;
        return 1;
      });
      final garden = Garden().grow();
      final stop = garden.watch(vine, (_) {});
      garden.tap(vine);
      stop();
      await garden.pump();
      garden.tap(vine);
      expect(runs, 1,
          reason: 'no autoDispose -> never dropped regardless of watchers');
    });
  });

  group('autoDispose on future', () {
    test('watcher count 0 -> dropped on next pump; re-tap re-runs', () async {
      var runs = 0;
      final vine = Vine.future<int>((tap) async {
        runs++;
        return runs;
      }).autoDispose;
      final garden = Garden().grow();
      final stop = garden.watch(vine, (_) {});
      expect(await garden.tapAsync(vine), 1);
      stop();
      await garden.pump();
      expect(await garden.tapAsync(vine), 2,
          reason: 'dropped and rebuilt from scratch');
    });
  });

  group('autoDispose on each', () {
    test('family keys are dropped individually', () async {
      final runsPerKey = <int, int>{};
      final family = Vine.each<int, int>((tap, key) {
        runsPerKey[key] = (runsPerKey[key] ?? 0) + 1;
        return key;
      }).autoDispose;
      final garden = Garden().grow();
      final stopA = garden.watch(family(1), (_) {});
      final stopB = garden.watch(family(2), (_) {});
      garden.tap(family(1));
      garden.tap(family(2));
      expect(runsPerKey, {1: 1, 2: 1});

      stopA(); // only key 1 loses its watcher
      await garden.pump();
      garden.tap(family(1));
      garden.tap(family(2));
      expect(runsPerKey[1], 2, reason: 'key 1 was dropped and rebuilt');
      expect(runsPerKey[2], 1, reason: 'key 2 still watched, never dropped');
      stopB();
    });
  });
}
