import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_flutter/models/outbox_entry.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/outbox_repository.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_local_state_coordinator.dart';
import 'package:todo_flutter/services/task_sync_coordinator.dart';
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
    'sync coordinator gates anonymous-review sync and publishes blocked state',
    () async {
      final anonymousTask = buildTask(
        id: 'task-anon-blocked',
        title: 'Anonymous review task',
        beginsAt: DateTime(2026, 3, 1, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = InMemoryTasksRepository([anonymousTask]);
      final outboxRepository = InMemoryOutboxRepository();
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

      final service = TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
        localStateCoordinator: localStateCoordinator,
      );
      final coordinator = TaskSyncCoordinator.fromRepository(
        repository,
        service,
        outboxRepository: outboxRepository,
        localStateCoordinator: localStateCoordinator,
        runtimeDebug: runtimeDebug,
      );

      var reloadCount = 0;
      await coordinator.syncAllTasks(
        tasks: await repository.loadTasks(),
        userId: 'user-1',
        hasPendingAnonymousReview: true,
        isLoading: false,
        setLoading: (_) {},
        onTasksReloaded: (_) async {
          reloadCount++;
        },
      );

      expect(reloadCount, 0);
      expect(
        runtimeDebug.state.syncPhase,
        RuntimeSyncPhase.blockedAnonymousReview,
      );
    },
  );

  test(
    'sync coordinator reloads merged tasks around the remote sync engine',
    () async {
      final dirtyTask = buildTask(
        id: 'task-sync-coordinator',
        title: 'Sync me',
        beginsAt: DateTime(2026, 3, 2, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([dirtyTask]);
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
      await localStateCoordinator.saveState(
        TaskLocalState(
          tasks: [dirtyTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: dirtyTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.queued,
                ownerScope: OutboxOwnerScope.authenticated,
                firstQueuedAt: dirtyTask.lastModifiedAt?.toUtc(),
                taskPayload: dirtyTask.toJson(),
              ),
            ],
          ),
        ),
      );

      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
        localStateCoordinator: localStateCoordinator,
      );
      final coordinator = TaskSyncCoordinator.fromRepository(
        repository,
        service,
        outboxRepository: outboxRepository,
        localStateCoordinator: localStateCoordinator,
        runtimeDebug: runtimeDebug,
      );

      final loadingStates = <bool>[];
      List<SyncStatus> reloadedStatuses = const [];

      await coordinator.syncAllTasks(
        tasks: await repository.loadTasks(),
        userId: 'user-1',
        hasPendingAnonymousReview: false,
        isLoading: false,
        setLoading: loadingStates.add,
        onTasksReloaded: (tasks) async {
          reloadedStatuses = tasks.map((task) => task.syncStatus).toList();
        },
      );

      expect(remote.insertedTaskIds, ['task-sync-coordinator']);
      expect(reloadedStatuses, [SyncStatus.synced]);
      expect(loadingStates, [true, false]);
    },
  );
}
