import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'test_support/app_test_support.dart';

void main() {
  test('agenda syncAllTasks does not upload anonymous tasks before review', () async {
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
    final agenda = AgendaProvider(repository, service)..userId = 'user-1';

    agenda.tasks = [anonymousTask];
    await agenda.syncAllTasks();

    final savedTasks = await repository.loadTasks();

    expect(remote.insertedTaskIds, isEmpty);
    expect(savedTasks, hasLength(1));
    expect(savedTasks.single.userId, isNull);
    expect(savedTasks.single.syncStatus, SyncStatus.dirty);
  });

  test('takeOwnershipOfAnonymousTasks syncs only after explicit keep', () async {
    final anonymousTask = buildTask(
      id: 'task-adopt',
      title: 'Local draft',
      beginsAt: DateTime(2026, 2, 11, 9),
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
    final agenda = AgendaProvider(repository, service)..userId = 'user-1';

    agenda.tasks = [anonymousTask];
    await agenda.takeOwnershipOfAnonymousTasks();

    final savedTasks = await repository.loadTasks();

    expect(remote.insertedTaskIds, ['task-adopt']);
    expect(savedTasks, hasLength(1));
    expect(savedTasks.single.userId, 'user-1');
    expect(savedTasks.single.syncStatus, SyncStatus.synced);
  });

  test('deleteTask removes anonymous tasks from storage and clears active counts', () async {
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
    final agenda = AgendaProvider(repository, service);

    agenda.tasks = [anonymousTask];
    await agenda.deleteTask(anonymousTask.id);

    final savedTasks = await repository.loadTasks();

    expect(savedTasks, isEmpty);
    expect(agenda.tasks, isEmpty);
    expect(agenda.filteredTasks, isEmpty);
    expect(agenda.totalTasks, 0);
    expect(agenda.pendingTasksCount, 0);
    expect(agenda.anonymousTasks, isEmpty);
  });

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
    final agenda = AgendaProvider(repository, service);

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
      );

      final repository = InMemoryTasksRepository([accountTask]);
      final remote = FakeTaskRemoteDataSource([]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
      );
      final agenda = AgendaProvider(repository, service)..userId = 'user-1';

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
    final agenda = AgendaProvider(repository, service);

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

  test('deleteSelectedTasks removes anonymous tasks and tombstones account tasks', () async {
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
    );

    final repository = InMemoryTasksRepository([anonymousTask, accountTask]);
    final remote = FakeTaskRemoteDataSource([]);
    final service = TaskSyncService.forTesting(
      repository,
      remote: remote,
      connectivityCheck: () async => [ConnectivityResult.wifi],
      hasActiveSession: () => false,
    );
    final agenda = AgendaProvider(repository, service)..userId = 'user-1';

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
  });

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

    final repository = InMemoryTasksRepository([urgentTask, laterTask, earlierTask]);
    final remote = FakeTaskRemoteDataSource([]);
    final service = TaskSyncService.forTesting(
      repository,
      remote: remote,
      connectivityCheck: () async => [ConnectivityResult.wifi],
      hasActiveSession: () => false,
    );
    final agenda = AgendaProvider(repository, service);

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
