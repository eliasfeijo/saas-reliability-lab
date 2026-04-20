import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/services/fault_injection_policy.dart';
import 'package:todo_flutter/services/task_sync_service.dart';

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

  test(
    'syncAllTasks keeps the fresher remote task when local state is stale',
    () async {
      final remoteTask = buildTask(
        id: 'task-1',
        title: 'Remote truth',
        beginsAt: DateTime(2026, 1, 10, 9),
        estimatedDuration: const Duration(hours: 1),
        updatedAt: DateTime(2026, 1, 10, 12),
        userId: 'user-1',
      );

      final localTask = buildTask(
        id: 'task-1',
        title: 'Stale local draft',
        beginsAt: DateTime(2026, 1, 10, 9),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 10, 10),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([localTask]);
      final remote = FakeTaskRemoteDataSource([remoteTask]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
      );

      final syncedTasks = await service.syncAllTasks(
        await repository.loadTasks(),
      );
      final savedTasks = await repository.loadTasks();

      expect(syncedTasks, isEmpty);
      expect(remote.updatedTaskIds, isEmpty);
      expect(savedTasks, hasLength(1));
      expect(savedTasks.single.title, 'Remote truth');
      expect(savedTasks.single.syncStatus, SyncStatus.synced);
      expect(savedTasks.single.updatedAt, DateTime(2026, 1, 10, 12));
    },
  );

  test(
    'syncTasks skips cloud replay when connectivity loss is injected',
    () async {
      final localTask = buildTask(
        id: 'task-connectivity-loss',
        title: 'Will stay local',
        beginsAt: DateTime(2026, 1, 11, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([localTask]);
      final remote = FakeTaskRemoteDataSource([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
        faultInjectionPolicy: FaultInjectionPolicy(
          readState: () => const FaultInjectionState(
            activeScenario: FaultInjectionScenario.connectivityLoss,
            isEnabled: true,
          ),
        ),
      );

      final result = await service.syncTasks(await repository.loadTasks());
      final savedTasks = await repository.loadTasks();

      expect(result.acknowledgedTasks, isEmpty);
      expect(remote.insertedTaskIds, isEmpty);
      expect(remote.updatedTaskIds, isEmpty);
      expect(savedTasks.single.syncStatus, SyncStatus.dirty);
      expect(runtimeDebug.state.syncPhase, RuntimeSyncPhase.offline);
      expect(runtimeDebug.state.lastSyncResult, RuntimeSyncResult.skipped);
      expect(
        runtimeDebug.state.lastSyncMessage,
        'Connectivity loss scenario is active. Cloud sync is being forced offline.',
      );
    },
  );
}
