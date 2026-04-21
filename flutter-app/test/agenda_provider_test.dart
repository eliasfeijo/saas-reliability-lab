import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/outbox_repository.dart';
import 'package:todo_flutter/services/fault_injection_policy.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_local_state_coordinator.dart';
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
    'agenda syncAllTasks does not upload anonymous tasks before review',
    () async {
      final anonymousTask = buildTask(
        id: 'task-anon',
        title: 'Anonymous draft',
        beginsAt: DateTime(2026, 2, 10, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = InMemoryTasksRepository([anonymousTask]);
      final remote = FakeTaskRemoteDataSource([]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
      );
      final agenda = buildAgendaProviderForTesting(repository, service)
        ..userId = 'user-1';

      agenda.tasks = [anonymousTask];
      await agenda.syncAllTasks();

      final savedTasks = await repository.loadTasks();

      expect(remote.insertedTaskIds, isEmpty);
      expect(savedTasks, hasLength(1));
      expect(savedTasks.single.userId, isNull);
      expect(savedTasks.single.syncStatus, SyncStatus.dirty);
    },
  );

  test(
    'takeOwnershipOfAnonymousTasks syncs only after explicit keep',
    () async {
      final anonymousTask = buildTask(
        id: 'task-adopt',
        title: 'Local draft',
        beginsAt: DateTime(2026, 2, 11, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = InMemoryTasksRepository([anonymousTask]);
      final remote = FakeTaskRemoteDataSource([]);
      final outboxRepository = InMemoryOutboxRepository();
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
      );
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        localStateCoordinator: localStateCoordinator,
      );
      final agenda = buildAgendaProviderForTesting(
        repository,
        service,
        localStateCoordinator: localStateCoordinator,
        outboxRepository: outboxRepository,
      )..userId = 'user-1';

      agenda.tasks = [anonymousTask];
      await agenda.takeOwnershipOfAnonymousTasks();

      final savedTasks = await repository.loadTasks();

      expect(remote.insertedTaskIds, ['task-adopt']);
      expect(savedTasks, hasLength(1));
      expect(savedTasks.single.userId, 'user-1');
      expect(savedTasks.single.syncStatus, SyncStatus.synced);
    },
  );

  test(
    'deleteTask removes anonymous tasks from storage and clears active counts',
    () async {
      final anonymousTask = buildTask(
        id: 'task-delete-anon',
        title: 'Throwaway local task',
        beginsAt: DateTime(2026, 2, 12, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = InMemoryTasksRepository([anonymousTask]);
      final remote = FakeTaskRemoteDataSource([]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
      );
      final agenda = buildAgendaProviderForTesting(repository, service);

      agenda.tasks = [anonymousTask];
      await agenda.deleteTask(anonymousTask.id);

      final savedTasks = await repository.loadTasks();

      expect(savedTasks, isEmpty);
      expect(agenda.tasks, isEmpty);
      expect(agenda.filteredTasks, isEmpty);
      expect(agenda.totalTasks, 0);
      expect(agenda.pendingTasksCount, 0);
      expect(agenda.anonymousTasks, isEmpty);
    },
  );

  test('loadTasks prunes legacy deleted anonymous tombstones', () async {
    final deletedAnonymousTask = buildTask(
      id: 'task-legacy-tombstone',
      title: 'Legacy deleted local task',
      beginsAt: DateTime(2026, 2, 13, 9),
      estimatedDuration: const Duration(hours: 1),
      syncStatus: SyncStatus.deleted,
    );

    final repository = InMemoryTasksRepository([deletedAnonymousTask]);
    final remote = FakeTaskRemoteDataSource([]);
    final service = TaskSyncService.forTesting(
      repository,
      remote: remote,
      connectivityCheck: () async => [ConnectivityResult.wifi],
      hasActiveSession: () => false,
    );
    final agenda = buildAgendaProviderForTesting(repository, service);

    await agenda.loadTasks();

    final savedTasks = await repository.loadTasks();

    expect(savedTasks, isEmpty);
    expect(agenda.tasks, isEmpty);
    expect(agenda.totalTasks, 0);
    expect(agenda.anonymousTasks, isEmpty);
    expect(agenda.pendingTasksCount, 0);
  });

  test(
    'deleteTask keeps authenticated tombstones for sync while hiding them from active counts',
    () async {
      final accountTask = buildTask(
        id: 'task-delete-account',
        title: 'Cloud task',
        beginsAt: DateTime(2026, 2, 14, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.synced,
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );

      final repository = InMemoryTasksRepository([accountTask]);
      final remote = FakeTaskRemoteDataSource([]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
      );
      final agenda = buildAgendaProviderForTesting(repository, service)
        ..userId = 'user-1';

      agenda.tasks = [accountTask];
      await agenda.deleteTask(accountTask.id);

      final savedTasks = await repository.loadTasks();

      expect(savedTasks, hasLength(1));
      expect(savedTasks.single.syncStatus, SyncStatus.deleted);
      expect(agenda.tasks, isEmpty);
      expect(agenda.filteredTasks, isEmpty);
      expect(agenda.totalTasks, 0);
      expect(agenda.pendingTasksCount, 0);
      expect(agenda.anonymousTasks, isEmpty);
    },
  );

  test(
    'hardResetWorkspace deletes remote-backed account tasks before wiping local state',
    () async {
      final remoteTask = buildTask(
        id: 'task-remote',
        title: 'Remote-backed task',
        beginsAt: DateTime(2026, 2, 17, 9),
        estimatedDuration: const Duration(hours: 1),
        userId: 'user-1',
        syncStatus: SyncStatus.synced,
        hasRemoteBackingRecord: true,
      );
      final alreadyDeletedRemoteTask = buildTask(
        id: 'task-remote-deleted',
        title: 'Already deleted remotely-backed task',
        beginsAt: DateTime(2026, 2, 17, 11),
        estimatedDuration: const Duration(hours: 1),
        userId: 'user-1',
        syncStatus: SyncStatus.deleted,
        hasRemoteBackingRecord: true,
      );
      final localOnlyTask = buildTask(
        id: 'task-local-only',
        title: 'Local-only account task',
        beginsAt: DateTime(2026, 2, 17, 13),
        estimatedDuration: const Duration(hours: 1),
        userId: 'user-1',
        syncStatus: SyncStatus.dirty,
        hasRemoteBackingRecord: false,
      );
      final anonymousTask = buildTask(
        id: 'task-anonymous',
        title: 'Anonymous local task',
        beginsAt: DateTime(2026, 2, 17, 15),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = InMemoryTasksRepository([
        remoteTask,
        alreadyDeletedRemoteTask,
        localOnlyTask,
        anonymousTask,
      ]);
      final remote = FakeTaskRemoteDataSource([
        remoteTask,
        alreadyDeletedRemoteTask,
      ]);
      final outboxRepository = InMemoryOutboxRepository();
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
      );
      await localStateCoordinator.saveState(
        TaskLocalState(
          tasks: [
            remoteTask,
            alreadyDeletedRemoteTask,
            localOnlyTask,
            anonymousTask,
          ],
          outboxState: const OutboxStorageState(isInitialized: true),
        ),
      );
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        localStateCoordinator: localStateCoordinator,
      );
      final agenda =
          buildAgendaProviderForTesting(
              repository,
              service,
              localStateCoordinator: localStateCoordinator,
              outboxRepository: outboxRepository,
            )
            ..userId = 'user-1'
            ..tasks = [
              remoteTask,
              alreadyDeletedRemoteTask,
              localOnlyTask,
              anonymousTask,
            ];

      final preview = agenda.hardResetPreview;

      expect(preview.remoteDeleteCount, 2);
      expect(preview.authenticatedLocalOnlyRemovalCount, 1);
      expect(preview.anonymousRemovalCount, 1);

      await agenda.hardResetWorkspace();

      expect(await repository.loadTasks(), isEmpty);
      expect(await remote.fetchAllTasks(), isEmpty);
      expect(agenda.tasks, isEmpty);
      expect(agenda.filteredTasks, isEmpty);
      expect(agenda.totalTasks, 0);
    },
  );

  test(
    'agenda provider clears a queued delete on the follow-up sync after an in-flight update race',
    () async {
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final updatedTask = buildTask(
        id: 'task-race-update',
        title: 'Updated locally before sync',
        beginsAt: DateTime(2026, 2, 18, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        lastModifiedAt: DateTime(2026, 2, 18, 10),
        updatedAt: DateTime(2026, 2, 18, 8),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );
      final deleteCandidate = buildTask(
        id: 'task-race-delete',
        title: 'Delete during in-flight sync',
        beginsAt: DateTime(2026, 2, 18, 11),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 2, 18, 8, 30),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );
      final remoteUpdatedBase = buildTask(
        id: updatedTask.id,
        title: 'Remote older title',
        beginsAt: updatedTask.beginsAt,
        estimatedDuration: updatedTask.estimatedDuration,
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 2, 18, 8),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );

      final repository = InMemoryTasksRepository([updatedTask, deleteCandidate]);
      final remote = FakeTaskRemoteDataSource([
        remoteUpdatedBase,
        deleteCandidate,
      ]);
      final outboxRepository = InMemoryOutboxRepository();
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );
      await localStateCoordinator.saveTaskSnapshot(
        [updatedTask, deleteCandidate],
        changedTaskIds: {updatedTask.id},
      );

      final delayCompleter = Completer<void>();
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
        faultInjectionPolicy: FaultInjectionPolicy(
          readState: () => const FaultInjectionState(
            activeScenario: FaultInjectionScenario.delayedSync,
            isEnabled: true,
            delayMs: 500,
            delayedSyncMode: DelayedSyncMode.backend,
            delayedSyncTarget: DelayedSyncTarget.acknowledgement,
            delayedSyncBehavior: DelayedSyncBehavior.oneShot,
          ),
        ),
        localStateCoordinator: localStateCoordinator,
        delayExecution: (_) => delayCompleter.future,
      );
      final agenda =
          buildAgendaProviderForTesting(
              repository,
              service,
              runtimeDebug: runtimeDebug,
              localStateCoordinator: localStateCoordinator,
              outboxRepository: outboxRepository,
            )
            ..userId = 'user-1'
            ..tasks = [updatedTask, deleteCandidate];

      final firstSyncFuture = agenda.syncAllTasks();
      await Future<void>.delayed(Duration.zero);

      await agenda.deleteTask(deleteCandidate.id);
      delayCompleter.complete();
      await firstSyncFuture;

      final afterFirstSyncState = await localStateCoordinator.loadState();
      expect(
        afterFirstSyncState.tasks.where((task) => task.id == updatedTask.id).single.syncStatus,
        SyncStatus.synced,
      );
      expect(
        afterFirstSyncState.tasks.where((task) => task.id == deleteCandidate.id).single.syncStatus,
        SyncStatus.deleted,
      );
      expect(afterFirstSyncState.outboxState.activeEntries, hasLength(1));
      expect(
        afterFirstSyncState.outboxState.activeEntries.single.taskId,
        deleteCandidate.id,
      );
      expect(
        runtimeDebug.state.lastSyncMessage,
        'Sync completed. 1 task(s) acknowledged. 1 newer local change(s) remain queued for a follow-up sync.',
      );

      await agenda.syncAllTasks();

      final reloadedAgenda =
          buildAgendaProviderForTesting(
              repository,
              service,
              runtimeDebug: runtimeDebug,
              localStateCoordinator: localStateCoordinator,
              outboxRepository: outboxRepository,
            )
            ..userId = 'user-1';
      await reloadedAgenda.loadTasks();

      final savedTasks = await repository.loadTasks();
      final finalOutboxState = await outboxRepository.loadState();
      final remoteTasks = await remote.fetchAllTasks();

      expect(savedTasks, hasLength(1));
      expect(savedTasks.single.id, updatedTask.id);
      expect(savedTasks.single.syncStatus, SyncStatus.synced);
      expect(finalOutboxState.activeEntries, isEmpty);
      expect(remoteTasks, hasLength(1));
      expect(remoteTasks.single.id, updatedTask.id);
      expect(reloadedAgenda.tasks, hasLength(1));
      expect(reloadedAgenda.totalTasks, 1);
      expect(runtimeDebug.state.deletedTaskCount, 0);
      expect(
        runtimeDebug.state.recentEvents.any(
          (event) =>
              event.payload?.stage == 'Concurrent local mutations preserved' &&
              event.message.contains('preserved while replay was already in progress'),
        ),
        isTrue,
      );
    },
  );

  test('batch mode selects only visible tasks in the current view', () async {
    final alphaTask = buildTask(
      id: 'task-alpha',
      title: 'Alpha queue task',
      beginsAt: DateTime(2026, 2, 15, 9),
      estimatedDuration: const Duration(hours: 1),
    );
    final betaTask = buildTask(
      id: 'task-beta',
      title: 'Beta queue task',
      beginsAt: DateTime(2026, 2, 15, 11),
      estimatedDuration: const Duration(hours: 1),
    );

    final repository = InMemoryTasksRepository([alphaTask, betaTask]);
    final remote = FakeTaskRemoteDataSource([]);
    final service = TaskSyncService.forTesting(
      repository,
      remote: remote,
      connectivityCheck: () async => [ConnectivityResult.wifi],
      hasActiveSession: () => false,
    );
    final agenda = buildAgendaProviderForTesting(repository, service);

    agenda.tasks = [alphaTask, betaTask];
    agenda.selectTask(alphaTask);
    agenda.enterBatchMode();
    agenda.updateSearchQuery('Alpha');
    agenda.selectAllVisibleTasks();

    expect(agenda.selectedTask, isNull);
    expect(agenda.isBatchMode, isTrue);
    expect(agenda.batchSelectedCount, 1);
    expect(agenda.selectedBatchTasks.single.id, alphaTask.id);
    expect(agenda.isTaskBatchSelected(alphaTask.id), isTrue);
    expect(agenda.isTaskBatchSelected(betaTask.id), isFalse);
  });

  test(
    'deleteSelectedTasks removes anonymous tasks and tombstones account tasks',
    () async {
      final anonymousTask = buildTask(
        id: 'task-batch-anon',
        title: 'Local batch task',
        beginsAt: DateTime(2026, 2, 16, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );
      final accountTask = buildTask(
        id: 'task-batch-account',
        title: 'Account batch task',
        beginsAt: DateTime(2026, 2, 16, 11),
        estimatedDuration: const Duration(hours: 1),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );

      final repository = InMemoryTasksRepository([anonymousTask, accountTask]);
      final remote = FakeTaskRemoteDataSource([]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
      );
      final agenda = buildAgendaProviderForTesting(repository, service)
        ..userId = 'user-1';

      agenda.tasks = [anonymousTask, accountTask];
      agenda.enterBatchMode();
      agenda.toggleTaskInBatchSelection(anonymousTask.id);
      agenda.toggleTaskInBatchSelection(accountTask.id);

      await agenda.deleteSelectedTasks();

      final savedTasks = await repository.loadTasks();

      expect(savedTasks, hasLength(1));
      expect(savedTasks.single.id, accountTask.id);
      expect(savedTasks.single.syncStatus, SyncStatus.deleted);
      expect(agenda.tasks, isEmpty);
      expect(agenda.batchSelectedCount, 0);
      expect(agenda.isBatchMode, isFalse);
    },
  );

  test('setSort reorders filtered tasks by the selected queue sort', () async {
    final now = DateTime.now();
    final urgentTask = buildTask(
      id: 'task-urgent',
      title: 'Urgent task',
      beginsAt: now.add(const Duration(hours: 4)),
      estimatedDuration: const Duration(hours: 1),
    )..priority = TaskPriority.urgent;
    final laterTask = buildTask(
      id: 'task-later',
      title: 'Later task',
      beginsAt: now.add(const Duration(days: 2)),
      estimatedDuration: const Duration(hours: 1),
    );
    final earlierTask = buildTask(
      id: 'task-earlier',
      title: 'Earlier task',
      beginsAt: now.subtract(const Duration(hours: 1)),
      estimatedDuration: const Duration(hours: 1),
      updatedAt: now.subtract(const Duration(hours: 2)),
    )..lastModifiedAt = now.subtract(const Duration(hours: 2));
    laterTask.lastModifiedAt = now.add(const Duration(hours: 6));

    final repository = InMemoryTasksRepository([
      urgentTask,
      laterTask,
      earlierTask,
    ]);
    final remote = FakeTaskRemoteDataSource([]);
    final service = TaskSyncService.forTesting(
      repository,
      remote: remote,
      connectivityCheck: () async => [ConnectivityResult.wifi],
      hasActiveSession: () => false,
    );
    final agenda = buildAgendaProviderForTesting(repository, service);

    agenda.tasks = [urgentTask, laterTask, earlierTask];
    expect(agenda.filteredTasks.map((task) => task.id).toList(), [
      'task-earlier',
      'task-urgent',
      'task-later',
    ]);

    agenda.setSort(TaskSort.earliestFirst);
    expect(agenda.filteredTasks.map((task) => task.id).toList(), [
      'task-earlier',
      'task-urgent',
      'task-later',
    ]);

    agenda.setSort(TaskSort.latestFirst);
    expect(agenda.filteredTasks.map((task) => task.id).toList(), [
      'task-later',
      'task-urgent',
      'task-earlier',
    ]);

    agenda.setSort(TaskSort.priorityHighToLow);
    expect(agenda.filteredTasks.first.id, 'task-urgent');

    agenda.setSort(TaskSort.recentlyUpdated);
    expect(agenda.filteredTasks.first.id, 'task-later');
  });
}
