import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/services/task_list_state_coordinator.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_local_state_coordinator.dart';
import 'package:todo_flutter/services/task_mutation_coordinator.dart';
import 'package:todo_flutter/services/task_sync_coordinator.dart';
import 'package:todo_flutter/services/task_sync_flow_coordinator.dart';
import 'package:todo_flutter/services/task_sync_service.dart';

import 'test_support/app_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityPlatform originalConnectivityPlatform;
  late TestConnectivityPlatform connectivityPlatform;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
    'takeOwnershipOfAnonymousTasks saves adopted tasks and syncs the reloaded list',
    () async {
      final anonymousTask = buildTask(
        id: 'flow-adopt-task',
        title: 'Anonymous flow task',
        beginsAt: DateTime(2026, 4, 1, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = InMemoryTasksRepository([anonymousTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final remote = FakeTaskRemoteDataSource([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final snapshotCoordinator = TaskLocalSnapshotCoordinator.fromRepository(
        repository,
      );
      final localStateCoordinator = TaskLocalStateCoordinator(
        snapshotCoordinator,
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );

      final syncCoordinator = TaskSyncCoordinator.fromRepository(
        repository,
        TaskSyncService.forTesting(
          repository,
          remote: remote,
          connectivityCheck: () async => [ConnectivityResult.wifi],
          hasActiveSession: () => true,
          runtimeDebug: runtimeDebug,
          localStateCoordinator: localStateCoordinator,
        ),
        outboxRepository: outboxRepository,
        localStateCoordinator: localStateCoordinator,
        runtimeDebug: runtimeDebug,
      );
      final flowCoordinator = TaskSyncFlowCoordinator(
        TaskListStateCoordinator.fromRepository(
          repository,
          outboxRepository: outboxRepository,
          localStateCoordinator: localStateCoordinator,
          runtimeDebug: runtimeDebug,
        ),
        syncCoordinator,
      );
      final mutationResult = const TaskMutationCoordinator()
          .adoptAnonymousTasks([anonymousTask], userId: 'user-1');

      final loadingStates = <bool>[];
      List<TaskModel> appliedTasks = const <TaskModel>[];

      await flowCoordinator.takeOwnershipOfAnonymousTasks(
        mutationResult,
        userId: 'user-1',
        hasPendingAnonymousReview: false,
        isLoading: false,
        setLoading: loadingStates.add,
        applyTasks: (tasks) {
          appliedTasks = tasks.map(cloneTask).toList(growable: false);
        },
      );

      final savedTasks = await repository.loadTasks();

      expect(remote.insertedTaskIds, ['flow-adopt-task']);
      expect(savedTasks.single.userId, 'user-1');
      expect(savedTasks.single.syncStatus, SyncStatus.synced);
      expect(appliedTasks.single.syncStatus, SyncStatus.synced);
      expect(loadingStates, [true, false]);
    },
  );

  test(
    'discardAnonymousTasks removes local anonymous tasks before syncing remaining account tasks',
    () async {
      final anonymousTask = buildTask(
        id: 'flow-discard-anon',
        title: 'Discard me',
        beginsAt: DateTime(2026, 4, 2, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );
      final accountTask = buildTask(
        id: 'flow-discard-account',
        title: 'Keep syncing me',
        beginsAt: DateTime(2026, 4, 2, 11),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([anonymousTask, accountTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final remote = FakeTaskRemoteDataSource([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final snapshotCoordinator = TaskLocalSnapshotCoordinator.fromRepository(
        repository,
      );
      final localStateCoordinator = TaskLocalStateCoordinator(
        snapshotCoordinator,
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );

      final syncCoordinator = TaskSyncCoordinator.fromRepository(
        repository,
        TaskSyncService.forTesting(
          repository,
          remote: remote,
          connectivityCheck: () async => [ConnectivityResult.wifi],
          hasActiveSession: () => true,
          runtimeDebug: runtimeDebug,
          localStateCoordinator: localStateCoordinator,
        ),
        outboxRepository: outboxRepository,
        localStateCoordinator: localStateCoordinator,
        runtimeDebug: runtimeDebug,
      );
      final flowCoordinator = TaskSyncFlowCoordinator(
        TaskListStateCoordinator.fromRepository(
          repository,
          outboxRepository: outboxRepository,
          localStateCoordinator: localStateCoordinator,
          runtimeDebug: runtimeDebug,
        ),
        syncCoordinator,
      );

      List<TaskModel> appliedTasks = const <TaskModel>[];

      await flowCoordinator.discardAnonymousTasks(
        tasks: [anonymousTask, accountTask],
        taskIds: [anonymousTask.id],
        userId: 'user-1',
        hasPendingAnonymousReview: false,
        isLoading: false,
        setLoading: (_) {},
        applyTasks: (tasks) {
          appliedTasks = tasks.map(cloneTask).toList(growable: false);
        },
      );

      final savedTasks = await repository.loadTasks();

      expect(remote.insertedTaskIds, ['flow-discard-account']);
      expect(savedTasks, hasLength(1));
      expect(savedTasks.single.id, 'flow-discard-account');
      expect(savedTasks.single.syncStatus, SyncStatus.synced);
      expect(appliedTasks, hasLength(1));
      expect(appliedTasks.single.id, 'flow-discard-account');
    },
  );
}
