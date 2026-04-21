import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/outbox_entry.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/outbox_repository.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_local_state_coordinator.dart';

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
    'local state coordinator initializes empty outbox storage without deriving legacy entries',
    () async {
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

      final dirtyAccountTask = buildTask(
        id: 'task-state-dirty',
        title: 'Dirty account task',
        beginsAt: DateTime(2026, 4, 10, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        lastModifiedAt: DateTime(2026, 4, 10, 10),
        updatedAt: DateTime(2026, 4, 10, 8),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );
      final deletedAccountTask = buildTask(
        id: 'task-state-deleted',
        title: 'Deleted account task',
        beginsAt: DateTime(2026, 4, 10, 11),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.deleted,
        lastModifiedAt: DateTime(2026, 4, 10, 12),
        updatedAt: DateTime(2026, 4, 10, 7),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );
      final anonymousTask = buildTask(
        id: 'task-state-anonymous',
        title: 'Anonymous local task',
        beginsAt: DateTime(2026, 4, 10, 13),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        lastModifiedAt: DateTime(2026, 4, 10, 14),
      );
      final deletedAnonymousTask = buildTask(
        id: 'task-state-pruned',
        title: 'Pruned anonymous tombstone',
        beginsAt: DateTime(2026, 4, 10, 15),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.deleted,
      );

      final repository = InMemoryTasksRepository([
        dirtyAccountTask,
        deletedAccountTask,
        anonymousTask,
        deletedAnonymousTask,
      ]);
      final outboxRepository = InMemoryOutboxRepository();
      final coordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );

      final state = await coordinator.loadState();
      final persistedState = await outboxRepository.loadState();

      expect(state.tasks.map((task) => task.id), [
        'task-state-dirty',
        'task-state-deleted',
        'task-state-anonymous',
      ]);
      expect(persistedState.isInitialized, isTrue);
      expect(persistedState.activeEntries, isEmpty);
      expect(runtimeDebug.state.recentEvents, isEmpty);
    },
  );

  test(
    'local state coordinator keeps the derived outbox in sync when task snapshot changes',
    () async {
      final repository = InMemoryTasksRepository([
        buildTask(
          id: 'task-state-save',
          title: 'Save me',
          beginsAt: DateTime(2026, 4, 11, 9),
          estimatedDuration: const Duration(hours: 1),
          syncStatus: SyncStatus.dirty,
          userId: 'user-1',
        ),
      ]);
      final outboxRepository = InMemoryOutboxRepository();
      final coordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
      );

      await coordinator.loadState();
      await coordinator.saveTaskSnapshot([
        buildTask(
          id: 'task-state-save',
          title: 'Now synced',
          beginsAt: DateTime(2026, 4, 11, 9),
          estimatedDuration: const Duration(hours: 1),
          syncStatus: SyncStatus.synced,
          userId: 'user-1',
          hasRemoteBackingRecord: true,
        ),
      ]);

      final persistedState = await outboxRepository.loadState();

      expect(persistedState.isInitialized, isTrue);
      expect(persistedState.activeEntries, isEmpty);
    },
  );

  test(
    'local state coordinator prunes orphaned deleted account tombstones with no active replay entry on load',
    () async {
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final deletedAccountTask = buildTask(
        id: 'task-orphaned-deleted',
        title: 'Poisoned deleted tombstone',
        beginsAt: DateTime(2026, 4, 11, 11),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.deleted,
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );

      final repository = InMemoryTasksRepository([deletedAccountTask]);
      final outboxRepository = InMemoryOutboxRepository();
      await outboxRepository.saveState(
        const OutboxStorageState(isInitialized: true),
      );
      final coordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );

      final state = await coordinator.loadState();
      final savedTasks = await repository.loadTasks();

      expect(state.tasks, isEmpty);
      expect(savedTasks, isEmpty);
      expect(
        runtimeDebug.state.recentEvents.any(
          (event) =>
              event.category == RuntimeEventCategory.storage &&
              event.payload?.stage == 'Local snapshot repaired',
        ),
        isTrue,
      );
      expect(runtimeDebug.state.deletedTaskCount, 0);
    },
  );

  test(
    'local state coordinator clears outbox storage when local state is cleared',
    () async {
      final repository = InMemoryTasksRepository([
        buildTask(
          id: 'task-state-clear',
          title: 'Clear me',
          beginsAt: DateTime(2026, 4, 12, 9),
          estimatedDuration: const Duration(hours: 1),
          syncStatus: SyncStatus.dirty,
          userId: 'user-1',
        ),
      ]);
      final outboxRepository = InMemoryOutboxRepository();
      final coordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
      );

      await coordinator.loadState();
      await coordinator.clearLocalState();

      expect(await repository.loadTasks(), isEmpty);

      final persistedState = await outboxRepository.loadState();
      expect(persistedState.isInitialized, isTrue);
      expect(persistedState.activeEntries, isEmpty);
    },
  );

  test(
    'local state coordinator can clear retained acknowledgements without removing active entries',
    () async {
      final repository = InMemoryTasksRepository([]);
      final outboxRepository = InMemoryOutboxRepository();
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final coordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );

      await coordinator.saveOutboxState(
        OutboxStorageState(
          isInitialized: true,
          activeEntries: [
            OutboxEntry(
              taskId: 'task-active-entry',
              operationType: OutboxOperationType.upsert,
              state: OutboxEntryState.queued,
              ownerScope: OutboxOwnerScope.authenticated,
              taskPayload: const {'id': 'task-active-entry'},
            ),
          ],
          recentAcknowledgements: [
            OutboxEntry(
              taskId: 'task-ack-entry',
              operationType: OutboxOperationType.upsert,
              state: OutboxEntryState.acknowledged,
              ownerScope: OutboxOwnerScope.authenticated,
              taskPayload: const {'id': 'task-ack-entry'},
            ),
          ],
        ),
      );

      await coordinator.clearRecentAcknowledgements();

      final persistedState = await outboxRepository.loadState();
      expect(persistedState.activeEntries, hasLength(1));
      expect(persistedState.recentAcknowledgements, isEmpty);
      expect(runtimeDebug.state.acknowledgedEntryCount, 0);
      expect(runtimeDebug.state.queuedEntryCount, 1);
    },
  );

  test(
    'local state coordinator can keep remote state when resolving a conflict',
    () async {
      final localTask = buildTask(
        id: 'task-conflict-keep-remote',
        title: 'Local conflicting title',
        beginsAt: DateTime(2026, 4, 14, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );
      final remoteTask = buildTask(
        id: localTask.id,
        title: 'Remote canonical title',
        beginsAt: localTask.beginsAt,
        estimatedDuration: localTask.estimatedDuration,
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 4, 14, 12),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );
      final repository = InMemoryTasksRepository([localTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final coordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
      );

      await coordinator.saveState(
        TaskLocalState(
          tasks: [localTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: localTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.conflict,
                ownerScope: OutboxOwnerScope.authenticated,
                taskPayload: localTask.toJson(),
                remoteSnapshot: remoteTask.toJson(),
              ),
            ],
          ),
        ),
      );

      final resolvedTasks = await coordinator.resolveConflictKeepingRemote(
        localTask.id,
      );
      final outboxState = await outboxRepository.loadState();

      expect(resolvedTasks.single.title, 'Remote canonical title');
      expect(resolvedTasks.single.syncStatus, SyncStatus.synced);
      expect(outboxState.activeEntries, isEmpty);
    },
  );

  test(
    'local state coordinator can reapply local intent from a conflict using the latest remote base',
    () async {
      final localTask = buildTask(
        id: 'task-conflict-reapply',
        title: 'Local intent',
        beginsAt: DateTime(2026, 4, 15, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );
      final remoteTask = buildTask(
        id: localTask.id,
        title: 'Remote changed title',
        beginsAt: localTask.beginsAt,
        estimatedDuration: localTask.estimatedDuration,
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 4, 15, 12),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );
      final repository = InMemoryTasksRepository([localTask]);
      final outboxRepository = InMemoryOutboxRepository();
      final coordinator = TaskLocalStateCoordinator(
        TaskLocalSnapshotCoordinator.fromRepository(repository),
        outboxRepository,
      );

      await coordinator.saveState(
        TaskLocalState(
          tasks: [localTask],
          outboxState: OutboxStorageState(
            isInitialized: true,
            activeEntries: [
              OutboxEntry(
                taskId: localTask.id,
                operationType: OutboxOperationType.upsert,
                state: OutboxEntryState.conflict,
                ownerScope: OutboxOwnerScope.authenticated,
                taskPayload: localTask.toJson(),
                remoteSnapshot: remoteTask.toJson(),
              ),
            ],
          ),
        ),
      );

      final resolvedTasks = await coordinator.reapplyConflictAsQueued(
        localTask.id,
      );
      final outboxState = await outboxRepository.loadState();

      expect(resolvedTasks.single.title, 'Local intent');
      expect(resolvedTasks.single.syncStatus, SyncStatus.dirty);
      expect(outboxState.activeEntries.single.state, OutboxEntryState.queued);
      expect(
        outboxState.activeEntries.single.baseRemoteUpdatedAt,
        DateTime(2026, 4, 15, 12).toUtc(),
      );
      expect(outboxState.activeEntries.single.remoteSnapshot, isNull);
    },
  );
}
