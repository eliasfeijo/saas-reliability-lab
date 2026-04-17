import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/services/task_list_state_coordinator.dart';

import 'test_support/app_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityPlatform originalConnectivityPlatform;
  late TestConnectivityPlatform connectivityPlatform;

  setUpAll(() async {
    originalConnectivityPlatform = ConnectivityPlatform.instance;
    connectivityPlatform = TestConnectivityPlatform(
      initialResults: const [ConnectivityResult.wifi],
    );
    ConnectivityPlatform.instance = connectivityPlatform;
  });

  tearDownAll(() async {
    ConnectivityPlatform.instance = originalConnectivityPlatform;
    await connectivityPlatform.dispose();
  });

  setUp(() {
    connectivityPlatform.emit(const [ConnectivityResult.wifi]);
  });

  test(
    'loadTasks prunes legacy anonymous tombstones and updates task counts',
    () async {
      final deletedAnonymousTask = buildTask(
        id: 'legacy-anon-deleted',
        title: 'Legacy anonymous tombstone',
        beginsAt: DateTime(2026, 3, 1, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.deleted,
      );
      final dirtyAccountTask = buildTask(
        id: 'dirty-account-task',
        title: 'Dirty account task',
        beginsAt: DateTime(2026, 3, 1, 11),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([
        deletedAnonymousTask,
        dirtyAccountTask,
      ]);
      final runtimeDebug = RuntimeDebugProvider();
      final coordinator = TaskListStateCoordinator.fromRepository(
        repository,
        runtimeDebug: runtimeDebug,
      );

      final loadedTasks = await coordinator.loadTasks();
      final savedTasks = await repository.loadTasks();

      expect(loadedTasks, hasLength(1));
      expect(loadedTasks.single.id, dirtyAccountTask.id);
      expect(savedTasks, hasLength(1));
      expect(savedTasks.single.id, dirtyAccountTask.id);
      expect(runtimeDebug.state.dirtyTaskCount, 1);
      expect(runtimeDebug.state.deletedTaskCount, 0);
      expect(runtimeDebug.state.anonymousTaskCount, 0);

      runtimeDebug.dispose();
    },
  );

  test('saveTasks publishes dirty deleted and anonymous counts', () async {
    final dirtyAnonymousTask = buildTask(
      id: 'dirty-anonymous-task',
      title: 'Dirty anonymous task',
      beginsAt: DateTime(2026, 3, 2, 9),
      estimatedDuration: const Duration(hours: 1),
      syncStatus: SyncStatus.dirty,
    );
    final deletedAccountTask = buildTask(
      id: 'deleted-account-task',
      title: 'Deleted account task',
      beginsAt: DateTime(2026, 3, 2, 11),
      estimatedDuration: const Duration(hours: 1),
      syncStatus: SyncStatus.deleted,
      userId: 'user-1',
    );

    final repository = InMemoryTasksRepository(const []);
    final runtimeDebug = RuntimeDebugProvider();
    final coordinator = TaskListStateCoordinator.fromRepository(
      repository,
      runtimeDebug: runtimeDebug,
    );

    await coordinator.saveTasks([dirtyAnonymousTask, deletedAccountTask]);

    expect(runtimeDebug.state.dirtyTaskCount, 1);
    expect(runtimeDebug.state.deletedTaskCount, 1);
    expect(runtimeDebug.state.anonymousTaskCount, 1);

    runtimeDebug.dispose();
  });
}
