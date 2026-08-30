import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vine_flutter/vine_flutter.dart';

/// Wraps [child] in a minimal app shell so plain `Text` widgets have the
/// `Directionality`/`MediaQuery` ancestors they need.
Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('Trellis / context.tap', () {
    testWidgets('context.tap reads without subscribing', (tester) async {
      final cell = Vine.cell(1);
      final garden = Garden().grow();
      late BuildContext capturedContext;
      await tester.pumpWidget(_app(Trellis(
        garden: garden,
        child: Builder(builder: (context) {
          capturedContext = context;
          return Text('${context.tap(cell)}');
        }),
      )));
      expect(find.text('1'), findsOneWidget);
      garden.set(cell, 2);
      await tester.pump();
      // context.tap does not subscribe, so this Builder never rebuilds
      // on its own — still showing the stale value is expected/correct.
      expect(find.text('1'), findsOneWidget);
      expect(capturedContext.tap(cell), 2);
    });

    testWidgets('Trellis.of throws NoTrellisError with no ancestor',
        (tester) async {
      await tester.pumpWidget(_app(Builder(builder: (context) {
        expect(() => Trellis.of(context), throwsA(isA<NoTrellisError>()));
        return const SizedBox();
      })));
    });
  });

  group('context.watch', () {
    testWidgets('rebuilds the watching element on change', (tester) async {
      final cell = Vine.cell(0);
      final garden = Garden().grow();
      var buildCount = 0;
      await tester.pumpWidget(_app(Trellis(
        garden: garden,
        child: VineBuilder(builder: (context, _) {
          buildCount++;
          return Text('${context.watch(cell)}');
        }),
      )));
      expect(find.text('0'), findsOneWidget);
      expect(buildCount, 1);

      garden.set(cell, 1);
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(buildCount, 2);
    });

    testWidgets('an equal-value set does not trigger a rebuild',
        (tester) async {
      final cell = Vine.cell(0);
      final garden = Garden().grow();
      var buildCount = 0;
      await tester.pumpWidget(_app(Trellis(
        garden: garden,
        child: VineBuilder(builder: (context, _) {
          buildCount++;
          return Text('${context.watch(cell)}');
        }),
      )));
      expect(buildCount, 1);
      garden.set(cell, 0); // same value
      await tester.pump();
      expect(buildCount, 1,
          reason: 'equality gate suppresses the notification');
    });

    testWidgets('only the watching widget rebuilds, not its siblings',
        (tester) async {
      final cell = Vine.cell(0);
      final garden = Garden().grow();
      var siblingBuilds = 0;
      await tester.pumpWidget(_app(Trellis(
        garden: garden,
        child: Column(
          children: [
            VineBuilder(
                builder: (context, _) => Text('${context.watch(cell)}')),
            Builder(builder: (context) {
              siblingBuilds++;
              return const SizedBox();
            }),
          ],
        ),
      )));
      expect(siblingBuilds, 1);
      garden.set(cell, 1);
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(siblingBuilds, 1, reason: 'the sibling never watched the cell');
    });

    testWidgets('throws NoVineWatchSupportError from a plain context',
        (tester) async {
      final cell = Vine.cell(0);
      final garden = Garden().grow();
      await tester.pumpWidget(_app(Trellis(
        garden: garden,
        child: Builder(builder: (context) {
          expect(() => context.watch(cell),
              throwsA(isA<NoVineWatchSupportError>()));
          return const SizedBox();
        }),
      )));
    });
  });

  group('TrellisScope', () {
    testWidgets('shadows the parent for its subtree only', (tester) async {
      final greeting = Vine.single((tap) => 'root');
      final garden = Garden().grow();
      await tester.pumpWidget(_app(Trellis(
        garden: garden,
        child: Column(
          children: [
            VineBuilder(
                builder: (context, _) =>
                    Text('outer:${context.tap(greeting)}')),
            TrellisScope(
              overrides: [greeting.override((tap) => 'scoped')],
              child: VineBuilder(
                builder: (context, _) => Text('inner:${context.tap(greeting)}'),
              ),
            ),
          ],
        ),
      )));
      expect(find.text('outer:root'), findsOneWidget);
      expect(find.text('inner:scoped'), findsOneWidget);
    });

    testWidgets('disposes its scope on unmount', (tester) async {
      final disposed = <String>[];
      final vine = Vine.single((tap) => 'x', dispose: (_) => disposed.add('x'));
      final garden = Garden().grow();
      await tester.pumpWidget(_app(Trellis(
        garden: garden,
        child: TrellisScope(
          child: VineBuilder(builder: (c, _) => Text(c.tap(vine))),
        ),
      )));
      expect(find.text('x'), findsOneWidget);
      expect(disposed, isEmpty);

      await tester
          .pumpWidget(_app(Trellis(garden: garden, child: const SizedBox())));
      expect(disposed, ['x']);
    });
  });

  group('SuspendedVine', () {
    testWidgets('loading -> data', (tester) async {
      final vine = Vine.future<String>((tap) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'ready';
      });
      final garden = Garden().grow();
      await tester.pumpWidget(_app(Trellis(
        garden: garden,
        child: SuspendedVine<String>(
          vine: vine,
          builder: (context, data) => Text(data),
          loading: () => const Text('loading'),
        ),
      )));
      expect(find.text('loading'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('ready'), findsOneWidget);
    });

    testWidgets('a refresh keeps showing previous data instead of loading',
        (tester) async {
      var n = 1;
      final vine = Vine.future<int>((tap) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return n;
      });
      final garden = Garden().grow();
      await tester.pumpWidget(_app(Trellis(
        garden: garden,
        child: SuspendedVine<int>(
          vine: vine,
          builder: (context, data) => Text('$data'),
          loading: () => const Text('loading'),
        ),
      )));
      await tester.pump();
      expect(find.text('loading'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('1'), findsOneWidget);

      n = 2;
      final refreshFuture = garden.refresh(vine);
      await tester.pump();
      expect(find.text('1'), findsOneWidget,
          reason: 'stale-while-revalidate: keeps showing 1, not "loading"');
      await tester.pump(const Duration(milliseconds: 20));
      await refreshFuture;
      expect(find.text('2'), findsOneWidget);
    });
  });
}
