// Runnable example Flutter app for casus_flutter.
//
// Run it with:
//   cd example && flutter run

import 'package:casus_flutter/casus_flutter.dart';
import 'package:flutter/material.dart';

/// A repository that simulates a flaky network load.
class ProfileRepository {
  Future<Result<String>> load({required bool shouldFail}) =>
      Result.guardAsync(() async {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (shouldFail) throw Exception('network unreachable');
        return 'Ada Lovelace';
      });
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(body: Center(child: ProfilePage())),
      );
}

/// Loads a profile into a [Resource], and lets the next reload
/// deliberately fail to demonstrate stale-while-revalidate: the last
/// successfully-loaded name stays on screen, wrapped in an error banner,
/// instead of the whole page collapsing to a retry view.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _repository = ProfileRepository();
  Resource<String> _state = const Resource.loading();

  @override
  void initState() {
    super.initState();
    _load(shouldFail: false);
  }

  Future<void> _load({required bool shouldFail}) async {
    // Keep the current data on screen (if any) while a reload is in
    // flight — Loading itself doesn't carry previousData in this
    // version (see Resource.dataOrPrevious's doc comment), so this
    // example just leaves the last Resource in place until the new one
    // arrives, then reads its old data back into the Failure it builds.
    final previousData = _state.dataOrNull;
    final result = await _repository.load(shouldFail: shouldFail);
    setState(() {
      _state = result.fold(
        onSuccess: Resource<String>.ready,
        onFailure: (error, stackTrace) => Resource<String>.error(
          error,
          stackTrace: stackTrace,
          previousData: previousData,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ResourceBuilder<String>(
            resource: _state,
            loading: (_) => const CircularProgressIndicator(),
            ready: (_, name) =>
                Text('Hello, $name!', style: const TextStyle(fontSize: 24)),
            error: (_, error, previousData) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (previousData != null)
                  Text(
                    'Hello, $previousData! (stale)',
                    style: const TextStyle(fontSize: 24),
                  ),
                Text('Error: $error',
                    style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _load(shouldFail: false),
            child: const Text('Reload (succeeds)'),
          ),
          ElevatedButton(
            onPressed: () => _load(shouldFail: true),
            child: const Text('Reload (fails)'),
          ),
        ],
      );
}
