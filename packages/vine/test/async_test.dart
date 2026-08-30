import 'package:test/test.dart';
import 'package:vine/vine.dart';

void main() {
  group('Vine.future basics', () {
    test('tap is AsyncLoading before settling, AsyncData after', () async {
      final vine = Vine.future<int>((tap) async => 42);
      final garden = Garden().grow();
      expect(garden.tap(vine), isA<AsyncLoading<int>>());
      await garden.pump();
      expect(garden.tap(vine), AsyncData<int>(42));
    });

    test('tapAsync awaits the resolved value', () async {
      final vine = Vine.future<int>((tap) async => 42);
      final garden = Garden().grow();
      expect(await garden.tapAsync(vine), 42);
    });

    test('concurrent tapAsync calls dedupe onto one run', () async {
      var runs = 0;
      final vine = Vine.future<int>((tap) async {
        runs++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return runs;
      });
      final garden = Garden().grow();
      final results = await Future.wait([
        garden.tapAsync(vine),
        garden.tapAsync(vine),
        garden.tapAsync(vine),
      ]);
      expect(results, [1, 1, 1]);
      expect(runs, 1);
    });

    test('a failing run surfaces as AsyncError and tapAsync rethrows',
        () async {
      final vine = Vine.future<int>((tap) async => throw StateError('boom'));
      final garden = Garden().grow();
      await expectLater(garden.tapAsync(vine), throwsA(isA<StateError>()));
      await garden.pump();
      final snapshot = garden.tap(vine);
      expect(snapshot, isA<AsyncError<int>>());
      expect((snapshot as AsyncError<int>).error, isA<StateError>());
    });

    test('the garden stays healthy after a future vine fails', () async {
      final vine = Vine.future<int>((tap) async => throw StateError('boom'));
      final other = Vine.single((tap) => 'still fine');
      final garden = Garden().grow();
      await expectLater(garden.tapAsync(vine), throwsA(isA<StateError>()));
      expect(garden.tap(other), 'still fine');
    });

    test('an error preserves previous data (stale-while-revalidate)', () async {
      var succeed = true;
      final cell = Vine.cell(0);
      final vine = Vine.future<int>((tap) async {
        tap(cell);
        if (!succeed) throw StateError('boom');
        return 7;
      });
      final garden = Garden().grow();
      expect(await garden.tapAsync(vine), 7);
      await garden.pump();
      succeed = false;
      await garden.refresh(vine);
      final snapshot = garden.tap(vine) as AsyncError<int>;
      expect(snapshot.value, 7,
          reason: 'previous data preserved through the error');
    });

    test('AsyncLoading during a refresh carries the previous value', () async {
      var n = 1;
      final vine = Vine.future<int>((tap) async => n);
      final garden = Garden().grow();
      expect(await garden.tapAsync(vine), 1);
      n = 2;
      final refreshFuture = garden.refresh(vine);
      final duringRefresh = garden.tap(vine);
      expect(duringRefresh, isA<AsyncLoading<int>>());
      expect((duringRefresh as AsyncLoading<int>).previous, 1);
      await refreshFuture;
      expect(garden.tap(vine), AsyncData<int>(2));
    });
  });

  group('Vine.future dual mode: derived (reacts to a tracked cell)', () {
    test('re-runs when a tapped-before-first-await cell changes', () async {
      final cell = Vine.cell(1);
      var runs = 0;
      final vine = Vine.future<int>((tap) async {
        runs++;
        final value = tap(cell);
        await Future<void>.delayed(Duration.zero);
        return value * 10;
      });
      final garden = Garden().grow();
      expect(await garden.tapAsync(vine), 10);
      garden.set(cell, 2);
      await garden.pump();
      expect(garden.tap(vine), AsyncData<int>(20));
      expect(runs, 2);
    });

    test('never re-runs on its own if it taps nothing reactive', () async {
      var runs = 0;
      final vine = Vine.future<int>((tap) async {
        runs++;
        return 5;
      });
      final garden = Garden().grow();
      await garden.tapAsync(vine);
      await garden.pump();
      await garden.pump();
      expect(runs, 1);
    });
  });

  group('race safety', () {
    test('a superseded run is discarded even if it finishes last', () async {
      var call = 0;
      final vine = Vine.future<int>((tap) async {
        final myCall = ++call;
        // call 1 is slow; every call after it is fast — so if there
        // were no generation guard, call 1 would land last and clobber
        // whatever a later call already settled.
        await Future<void>.delayed(
            Duration(milliseconds: myCall == 1 ? 30 : 5));
        return myCall;
      });
      final garden = Garden().grow();
      garden.tap(vine); // starts call 1 (slow), not awaited
      await garden
          .refresh(vine); // discards call 1, starts+awaits call 2 (fast)
      expect((garden.tap(vine) as AsyncData<int>).value, 2);

      // Give call 1's slow timer time to fire too, to prove it can't
      // clobber the fresher result once it (eventually) completes.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect((garden.tap(vine) as AsyncData<int>).value, 2,
          reason: 'the stale, slow run must not overwrite the fresher one');
    });
  });

  group('Vine.eachAsync', () {
    test('memoizes per key and dedupes concurrent taps of the same key',
        () async {
      final calls = <int>[];
      final family = Vine.eachAsync<int, String>((tap, key) async {
        calls.add(key);
        return 'value-$key';
      });
      final garden = Garden().grow();
      expect(await garden.tapAsync(family(1)), 'value-1');
      expect(await garden.tapAsync(family(1)), 'value-1');
      expect(await garden.tapAsync(family(2)), 'value-2');
      expect(calls, [1, 2]);
    });
  });
}
