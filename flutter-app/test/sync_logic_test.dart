import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';
import 'package:todo_flutter/models/outbox_entry.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
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
    'syncTasks replays queued outbox entries and retains recent acknowledgements',
    () async {
      final localTask = buildTask(
        id: 'task-outbox-replay',
        title: 'Queued outbox task',
        beginsAt: DateTime(2026, 1, 9, 9),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 9, 10),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: false,
      );

      final repository = InMemoryTasksRepository([localTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );

      await localStateCoordinator.saveState(
        TaskLocalState(
          tasks: [localTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: localTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.queued,
                ownerScope: OutboxOwnerScope.authenticated,
                firstQueuedAt: localTask.lastModifiedAt?.toUtc(),
                taskPayload: localTask.toJson(),
              ),
            ],
          ),
        ),
      );

      final remote = FakeTaskRemoteDataSource([]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
        localStateCoordinator: localStateCoordinator,
      );

      final result = await service.syncTasks(await repository.loadTasks());
      final savedTasks = await repository.loadTasks();
      final outboxState = await outboxRepository.loadState();

      expect(result.acknowledgedTasks, hasLength(1));
      expect(remote.insertedTaskIds, ['task-outbox-replay']);
      expect(savedTasks.single.syncStatus, SyncStatus.synced);
      expect(savedTasks.single.hasRemoteBackingRecord, isTrue);
      expect(outboxState.activeEntries, isEmpty);
      expect(outboxState.recentAcknowledgements, hasLength(1));
      expect(outboxState.recentAcknowledgements.single.taskId, localTask.id);
      expect(
        runtimeDebug.state.recentEvents.any(
          (event) =>
              event.payload?.stage == 'Concurrent local mutations preserved',
        ),
        isFalse,
      );
      expect(
        runtimeDebug.state.lastSyncMessage,
        'Sync completed. 1 task(s) acknowledged.',
      );
    },
  );

  test(
    'syncTasks marks queued outbox entries as conflict when remote changed after the base snapshot',
    () async {
      final localTask = buildTask(
        id: 'task-outbox-conflict',
        title: 'Conflict candidate',
        beginsAt: DateTime(2026, 1, 13, 9),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 13, 10),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );
      final remoteTask = buildTask(
        id: localTask.id,
        title: 'Remote changed later',
        beginsAt: localTask.beginsAt,
        estimatedDuration: localTask.estimatedDuration,
        updatedAt: DateTime(2026, 1, 13, 12),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );

      final repository = InMemoryTasksRepository([localTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );

      await localStateCoordinator.saveState(
        TaskLocalState(
          tasks: [localTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: localTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.queued,
                ownerScope: OutboxOwnerScope.authenticated,
                firstQueuedAt: localTask.lastModifiedAt?.toUtc(),
                baseRemoteUpdatedAt: DateTime(2026, 1, 13, 11).toUtc(),
                taskPayload: localTask.toJson(),
              ),
            ],
          ),
        ),
      );

      final remote = FakeTaskRemoteDataSource([remoteTask]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
        localStateCoordinator: localStateCoordinator,
      );

      final result = await service.syncTasks(await repository.loadTasks());
      final outboxState = await outboxRepository.loadState();

      expect(result.acknowledgedTasks, isEmpty);
      expect(remote.updatedTaskIds, isEmpty);
      expect(outboxState.activeEntries, hasLength(1));
      expect(outboxState.activeEntries.single.state, OutboxEntryState.conflict);
      expect(outboxState.activeEntries.single.remoteSnapshot, isNotNull);
      expect(runtimeDebug.state.lastSyncResult, RuntimeSyncResult.partial);
      expect(runtimeDebug.state.conflictEntryCount, 1);
      expect(runtimeDebug.state.conflictEntries, hasLength(1));
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

  test(
    'syncTasks holds the sync phase open when delayed sync is injected',
    () async {
      final localTask = buildTask(
        id: 'task-delayed-sync',
        title: 'Delayed convergence',
        beginsAt: DateTime(2026, 1, 12, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([localTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final remote = FakeTaskRemoteDataSource([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );
      await localStateCoordinator.saveState(
        TaskLocalState(
          tasks: [localTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: localTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.queued,
                ownerScope: OutboxOwnerScope.authenticated,
                firstQueuedAt: localTask.lastModifiedAt?.toUtc(),
                taskPayload: localTask.toJson(),
              ),
            ],
          ),
        ),
      );
      final delayCompleter = Completer<void>();
      Duration? delayedBy;

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
            delayMs: 5000,
          ),
        ),
        localStateCoordinator: localStateCoordinator,
        delayExecution: (duration) {
          delayedBy = duration;
          return delayCompleter.future;
        },
      );

      final syncFuture = service.syncTasks(await repository.loadTasks());
      await Future<void>.delayed(Duration.zero);

      expect(delayedBy, const Duration(seconds: 5));
      expect(runtimeDebug.state.syncPhase, RuntimeSyncPhase.syncing);
      expect(runtimeDebug.state.lastSyncResult, RuntimeSyncResult.none);
      expect(
        runtimeDebug.state.lastSyncMessage,
        'Delayed sync scenario is active. Holding the full replay pass for 5 s before remote work begins. Synchronizing 1 local task(s).',
      );
      expect(
        runtimeDebug.state.recentEvents.first.message,
        'Delayed sync scenario is holding the sync pass for 5 s before remote replay begins.',
      );
      expect(runtimeDebug.state.recentEvents.first.payload, isNotNull);
      expect(
        runtimeDebug.state.recentEvents.first.payload!.stage,
        'Delayed sync at Full pass',
      );
      expect(
        runtimeDebug.state.recentEvents.first.payload!.metrics
            .where((metric) => metric.label == 'Injected delay')
            .single
            .value,
        '5 s',
      );

      delayCompleter.complete();
      final result = await syncFuture;

      expect(result.acknowledgedTasks, hasLength(1));
      expect(remote.insertedTaskIds, ['task-delayed-sync']);
      expect(runtimeDebug.state.lastSyncResult, RuntimeSyncResult.success);
      expect(runtimeDebug.state.recentEvents.first.payload, isNotNull);
      expect(
        runtimeDebug.state.recentEvents.first.payload!.stage,
        'Replay completed',
      );
      expect(
        runtimeDebug.state.recentEvents.first.payload!.tasks.single.outcome,
        'Created remotely',
      );
    },
  );

  test(
    'syncTasks refreshes local replay input after a full-pass delay so newer mutations are not discarded',
    () async {
      final initialTask = buildTask(
        id: 'task-delayed-initial',
        title: 'Initial queued task',
        beginsAt: DateTime(2026, 1, 16, 9),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 16, 10),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: false,
      );
      final followUpTask = buildTask(
        id: 'task-delayed-follow-up',
        title: 'Added during hold',
        beginsAt: DateTime(2026, 1, 16, 11),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 16, 10, 30),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: false,
      );

      final repository = InMemoryTasksRepository([initialTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final remote = FakeTaskRemoteDataSource([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );
      await localStateCoordinator.saveState(
        TaskLocalState(
          tasks: [initialTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: initialTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.queued,
                ownerScope: OutboxOwnerScope.authenticated,
                firstQueuedAt: initialTask.lastModifiedAt?.toUtc(),
                taskPayload: initialTask.toJson(),
              ),
            ],
          ),
        ),
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
            delayMs: 5000,
          ),
        ),
        localStateCoordinator: localStateCoordinator,
        delayExecution: (_) => delayCompleter.future,
      );

      final syncFuture = service.syncTasks(await repository.loadTasks());
      await Future<void>.delayed(Duration.zero);

      await localStateCoordinator.saveTaskSnapshot(
        [initialTask, followUpTask],
        changedTaskIds: {followUpTask.id},
      );

      delayCompleter.complete();
      final result = await syncFuture;
      final savedTasks = await repository.loadTasks();

      expect(result.acknowledgedTasks, hasLength(2));
      expect(
        remote.insertedTaskIds,
        containsAll(['task-delayed-initial', 'task-delayed-follow-up']),
      );
      expect(remote.insertedTaskIds, hasLength(2));
      expect(savedTasks, hasLength(2));
      expect(
        savedTasks.every((task) => task.syncStatus == SyncStatus.synced),
        isTrue,
      );
      expect(
        runtimeDebug.state.recentEvents.any(
          (event) =>
              event.payload?.stage == 'Replay input refreshed' &&
              event.message.contains('refreshed before remote work began'),
        ),
        isTrue,
      );
    },
  );

  test(
    'syncTasks preserves newer local mutations staged during acknowledgement delay and leaves follow-up replay evidence',
    () async {
      final initialTask = buildTask(
        id: 'task-ack-initial',
        title: 'Initial in-flight task',
        beginsAt: DateTime(2026, 1, 17, 9),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 17, 10),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: false,
      );
      final followUpTask = buildTask(
        id: 'task-ack-follow-up',
        title: 'Created mid-replay',
        beginsAt: DateTime(2026, 1, 17, 11),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 17, 10, 15),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: false,
      );

      final repository = InMemoryTasksRepository([initialTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final remote = FakeTaskRemoteDataSource([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );
      await localStateCoordinator.saveState(
        TaskLocalState(
          tasks: [initialTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: initialTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.queued,
                ownerScope: OutboxOwnerScope.authenticated,
                firstQueuedAt: initialTask.lastModifiedAt?.toUtc(),
                taskPayload: initialTask.toJson(),
              ),
            ],
          ),
        ),
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
          ),
        ),
        localStateCoordinator: localStateCoordinator,
        delayExecution: (_) => delayCompleter.future,
      );

      final syncFuture = service.syncTasks(await repository.loadTasks());
      await Future<void>.delayed(Duration.zero);

      final inFlightState = await localStateCoordinator.loadState();
      await localStateCoordinator.saveTaskSnapshot(
        [...inFlightState.tasks, followUpTask],
        changedTaskIds: {followUpTask.id},
      );

      delayCompleter.complete();
      final result = await syncFuture;
      final finalState = await localStateCoordinator.loadState();

      expect(result.acknowledgedTasks, hasLength(1));
      expect(remote.insertedTaskIds, ['task-ack-initial']);
      expect(finalState.tasks, hasLength(2));
      final syncedTask = finalState.tasks
          .where((task) => task.id == initialTask.id)
          .single;
      final queuedTask = finalState.tasks
          .where((task) => task.id == followUpTask.id)
          .single;
      expect(syncedTask.syncStatus, SyncStatus.synced);
      expect(queuedTask.syncStatus, SyncStatus.dirty);
      expect(finalState.outboxState.activeEntries, hasLength(1));
      expect(
        finalState.outboxState.activeEntries.single.taskId,
        followUpTask.id,
      );
      expect(
        finalState.outboxState.activeEntries.single.state,
        OutboxEntryState.queued,
      );
      expect(finalState.outboxState.recentAcknowledgements, hasLength(1));
      expect(
        runtimeDebug.state.recentEvents.any(
          (event) =>
              event.payload?.stage == 'Concurrent local mutations preserved' &&
              event.message.contains(
                'preserved while replay was already in progress',
              ),
        ),
        isTrue,
      );
      expect(
        runtimeDebug.state.lastSyncMessage,
        'Sync completed. 1 task(s) acknowledged. 1 newer local change(s) remain queued for a follow-up sync.',
      );
    },
  );

  test(
    'syncTasks does not warn when an in-flight task is re-saved locally without a newer intent',
    () async {
      final localTask = buildTask(
        id: 'task-noop-resave',
        title: 'No-op resave task',
        beginsAt: DateTime(2026, 1, 18, 9),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 18, 10),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: false,
      );

      final repository = InMemoryTasksRepository([localTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final remote = FakeTaskRemoteDataSource([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );
      await localStateCoordinator.saveState(
        TaskLocalState(
          tasks: [localTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: localTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.queued,
                ownerScope: OutboxOwnerScope.authenticated,
                firstQueuedAt: localTask.lastModifiedAt?.toUtc(),
                taskPayload: localTask.toJson(),
              ),
            ],
          ),
        ),
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
          ),
        ),
        localStateCoordinator: localStateCoordinator,
        delayExecution: (_) => delayCompleter.future,
      );

      final syncFuture = service.syncTasks(await repository.loadTasks());
      await Future<void>.delayed(Duration.zero);

      await localStateCoordinator.saveTaskSnapshot(
        [localTask.copyWith()],
        changedTaskIds: {localTask.id},
      );

      delayCompleter.complete();
      final result = await syncFuture;
      final finalState = await localStateCoordinator.loadState();

      expect(result.acknowledgedTasks, hasLength(1));
      expect(remote.insertedTaskIds, ['task-noop-resave']);
      expect(finalState.tasks, hasLength(1));
      expect(finalState.tasks.single.syncStatus, SyncStatus.synced);
      expect(finalState.outboxState.activeEntries, isEmpty);
      expect(
        runtimeDebug.state.recentEvents.any(
          (event) =>
              event.payload?.stage == 'Concurrent local mutations preserved',
        ),
        isFalse,
      );
      expect(
        runtimeDebug.state.lastSyncMessage,
        'Sync completed. 1 task(s) acknowledged.',
      );
    },
  );

  test(
    'syncTasks can delay a transport update seam without delaying fetch-by-id first',
    () async {
      final localTask = buildTask(
        id: 'task-transport-update',
        title: 'Transport update',
        beginsAt: DateTime(2026, 1, 14, 9),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 14, 11),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );
      final remoteTask = buildTask(
        id: localTask.id,
        title: 'Transport update old',
        beginsAt: localTask.beginsAt,
        estimatedDuration: localTask.estimatedDuration,
        updatedAt: DateTime(2026, 1, 14, 10),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );

      final repository = InMemoryTasksRepository([localTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final remote = FakeTaskRemoteDataSource([remoteTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );
      await localStateCoordinator.saveState(
        TaskLocalState(
          tasks: [localTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: localTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.queued,
                ownerScope: OutboxOwnerScope.authenticated,
                firstQueuedAt: localTask.lastModifiedAt?.toUtc(),
                taskPayload: localTask.toJson(),
              ),
            ],
          ),
        ),
      );
      final delayCompleter = Completer<void>();
      Duration? delayedBy;

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
            delayMs: 2000,
            delayedSyncMode: DelayedSyncMode.transport,
            delayedSyncTarget: DelayedSyncTarget.update,
          ),
        ),
        localStateCoordinator: localStateCoordinator,
        delayExecution: (duration) {
          delayedBy = duration;
          return delayCompleter.future;
        },
      );

      final syncFuture = service.syncTasks(await repository.loadTasks());
      await Future<void>.delayed(Duration.zero);

      expect(delayedBy, const Duration(seconds: 2));
      expect(remote.updatedTaskIds, isEmpty);
      expect(
        runtimeDebug.state.recentEvents.first.message,
        'Delayed sync scenario is holding the update transport seam for 2 s before replay continues.',
      );
      expect(
        runtimeDebug.state.recentEvents.first.payload?.stage,
        'Delayed sync at Update',
      );

      delayCompleter.complete();
      final result = await syncFuture;

      expect(result.acknowledgedTasks, hasLength(1));
      expect(remote.updatedTaskIds, ['task-transport-update']);
      expect(runtimeDebug.state.lastSyncResult, RuntimeSyncResult.success);
    },
  );

  test(
    'syncTasks can delay backend acknowledgement after a successful insert',
    () async {
      final localTask = buildTask(
        id: 'task-backend-ack',
        title: 'Backend ack hold',
        beginsAt: DateTime(2026, 1, 15, 9),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 15, 10),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: false,
      );

      final repository = InMemoryTasksRepository([localTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final remote = FakeTaskRemoteDataSource([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final localStateCoordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );
      await localStateCoordinator.saveState(
        TaskLocalState(
          tasks: [localTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: localTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.queued,
                ownerScope: OutboxOwnerScope.authenticated,
                firstQueuedAt: localTask.lastModifiedAt?.toUtc(),
                taskPayload: localTask.toJson(),
              ),
            ],
          ),
        ),
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
          ),
        ),
        localStateCoordinator: localStateCoordinator,
        delayExecution: (_) => delayCompleter.future,
      );

      final syncFuture = service.syncTasks(await repository.loadTasks());
      await Future<void>.delayed(Duration.zero);

      final midReplayState = await outboxRepository.loadState();
      expect(remote.insertedTaskIds, ['task-backend-ack']);
      expect(
        midReplayState.activeEntries.single.state,
        OutboxEntryState.sending,
      );
      expect(
        runtimeDebug.state.recentEvents.first.message,
        'Delayed sync scenario is holding acknowledgement for 500 ms after remote success and before the outbox entry is acknowledged.',
      );

      delayCompleter.complete();
      final result = await syncFuture;
      final finalOutboxState = await outboxRepository.loadState();

      expect(result.acknowledgedTasks, hasLength(1));
      expect(finalOutboxState.activeEntries, isEmpty);
      expect(finalOutboxState.recentAcknowledgements, hasLength(1));
    },
  );
}
