import 'package:casus_flutter/casus_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pumps the loading builder for Loading', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ResourceBuilder<int>(
          resource: const Resource.loading(),
          loading: (_) => const Text('loading'),
          ready: (_, data) => Text('data: $data'),
          error: (_, error, previous) => Text('error: $error'),
        ),
      ),
    );
    expect(find.text('loading'), findsOneWidget);
  });

  testWidgets('pumps the ready builder with the data for Ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ResourceBuilder<int>(
          resource: const Resource.ready(7),
          loading: (_) => const Text('loading'),
          ready: (_, data) => Text('data: $data'),
          error: (_, error, previous) => Text('error: $error'),
        ),
      ),
    );
    expect(find.text('data: 7'), findsOneWidget);
  });

  group('error state', () {
    testWidgets('passes previousData through for a stale-while-revalidate UI', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ResourceBuilder<int>(
            resource: Resource.error('offline', previousData: 5),
            loading: (_) => const Text('loading'),
            ready: (_, data) => Text('data: $data'),
            error: (_, error, previous) =>
                Text('error: $error, prev: $previous'),
          ),
        ),
      );
      expect(find.text('error: offline, prev: 5'), findsOneWidget);
    });

    testWidgets('passes null previousData when none was retained', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ResourceBuilder<int>(
            resource: Resource.error('offline'),
            loading: (_) => const Text('loading'),
            ready: (_, data) => Text('data: $data'),
            error: (_, error, previous) =>
                Text('error: $error, prev: $previous'),
          ),
        ),
      );
      expect(find.text('error: offline, prev: null'), findsOneWidget);
    });
  });

  testWidgets('rebuilds when the resource changes', (tester) async {
    Widget build(Resource<int> resource) => Directionality(
          textDirection: TextDirection.ltr,
          child: ResourceBuilder<int>(
            resource: resource,
            loading: (_) => const Text('loading'),
            ready: (_, data) => Text('data: $data'),
            error: (_, error, previous) => Text('error: $error'),
          ),
        );

    await tester.pumpWidget(build(const Resource.loading()));
    expect(find.text('loading'), findsOneWidget);

    await tester.pumpWidget(build(const Resource.ready(3)));
    expect(find.text('data: 3'), findsOneWidget);
    expect(find.text('loading'), findsNothing);

    await tester.pumpWidget(build(Resource.error('bad')));
    expect(find.text('error: bad'), findsOneWidget);
    expect(find.text('data: 3'), findsNothing);
  });
}
