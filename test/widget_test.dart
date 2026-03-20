import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'package:todo_flutter/services/user_session_service.dart';

void main() {
  test(
    'syncAllTasks keeps the fresher remote task when local state is stale',
    () async {
      final remoteTask = _buildTask(
        id: 'task-1',
        title: 'Remote truth',
        beginsAt: DateTime(2026, 1, 10, 9),
        estimatedDuration: const Duration(hours: 1),
        updatedAt: DateTime(2026, 1, 10, 12),
        userId: 'user-1',
      );

      final localTask = _buildTask(
        id: 'task-1',
        title: 'Stale local draft',
        beginsAt: DateTime(2026, 1, 10, 9),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 10, 10),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      );

      final repository = _InMemoryTasksRepository([localTask]);
      final remote = _FakeTaskRemoteDataSource([remoteTask]);
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
    'agenda syncAllTasks does not upload anonymous tasks before review',
    () async {
      final anonymousTask = _buildTask(
        id: 'task-anon',
        title: 'Anonymous draft',
        beginsAt: DateTime(2026, 2, 10, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = _InMemoryTasksRepository([anonymousTask]);
      final remote = _FakeTaskRemoteDataSource([]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
      );
      final agenda = AgendaProvider(repository, service, UserSessionService())
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
      final anonymousTask = _buildTask(
        id: 'task-adopt',
        title: 'Local draft',
        beginsAt: DateTime(2026, 2, 11, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = _InMemoryTasksRepository([anonymousTask]);
      final remote = _FakeTaskRemoteDataSource([]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
      );
      final agenda = AgendaProvider(repository, service, UserSessionService())
        ..userId = 'user-1';

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
      final anonymousTask = _buildTask(
        id: 'task-delete-anon',
        title: 'Throwaway local task',
        beginsAt: DateTime(2026, 2, 12, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = _InMemoryTasksRepository([anonymousTask]);
      final remote = _FakeTaskRemoteDataSource([]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
      );
      final agenda = AgendaProvider(repository, service, UserSessionService());

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
    final deletedAnonymousTask = _buildTask(
      id: 'task-legacy-tombstone',
      title: 'Legacy deleted local task',
      beginsAt: DateTime(2026, 2, 13, 9),
      estimatedDuration: const Duration(hours: 1),
      syncStatus: SyncStatus.deleted,
    );

    final repository = _InMemoryTasksRepository([deletedAnonymousTask]);
    final remote = _FakeTaskRemoteDataSource([]);
    final service = TaskSyncService.forTesting(
      repository,
      remote: remote,
      connectivityCheck: () async => [ConnectivityResult.wifi],
      hasActiveSession: () => false,
    );
    final agenda = AgendaProvider(repository, service, UserSessionService());

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
      final accountTask = _buildTask(
        id: 'task-delete-account',
        title: 'Cloud task',
        beginsAt: DateTime(2026, 2, 14, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.synced,
        userId: 'user-1',
      );

      final repository = _InMemoryTasksRepository([accountTask]);
      final remote = _FakeTaskRemoteDataSource([]);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
      );
      final agenda = AgendaProvider(repository, service, UserSessionService())
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
}

class _InMemoryTasksRepository implements TasksRepository {
  List<TaskModel> _tasks;

  _InMemoryTasksRepository(List<TaskModel> tasks)
    : _tasks = tasks.map(_cloneTask).toList();

  @override
  Future<void> clearTasks() async {
    _tasks = [];
  }

  @override
  Future<List<TaskModel>> loadTasks() async {
    return _tasks.map(_cloneTask).toList();
  }

  @override
  Future<void> saveTasks(List<TaskModel> tasks) async {
    _tasks = tasks.map(_cloneTask).toList();
  }
}

class _FakeTaskRemoteDataSource implements TaskRemoteDataSource {
  final Map<String, TaskModel> _tasksById;
  final List<String> insertedTaskIds = [];
  final List<String> updatedTaskIds = [];

  _FakeTaskRemoteDataSource(List<TaskModel> tasks)
    : _tasksById = {for (final task in tasks) task.id: _cloneTask(task)};

  @override
  Future<void> deleteTask(String taskId) async {
    _tasksById.remove(taskId);
  }

  @override
  Future<List<TaskModel>> fetchAllTasks() async {
    return _tasksById.values.map(_cloneTask).toList();
  }

  @override
  Future<TaskModel?> fetchTaskById(String taskId) async {
    final task = _tasksById[taskId];
    if (task == null) {
      return null;
    }

    return _cloneTask(task);
  }

  @override
  Future<void> insertTask(TaskModel task) async {
    insertedTaskIds.add(task.id);
    _tasksById[task.id] = _cloneTask(
      task,
      syncStatus: SyncStatus.synced,
      updatedAt: task.lastModifiedAt ?? DateTime.now(),
    );
  }

  @override
  Future<void> updateTask(TaskModel task) async {
    updatedTaskIds.add(task.id);
    _tasksById[task.id] = _cloneTask(
      task,
      syncStatus: SyncStatus.synced,
      updatedAt: task.lastModifiedAt ?? DateTime.now(),
    );
  }
}

TaskModel _buildTask({
  required String id,
  required String title,
  required DateTime beginsAt,
  required Duration estimatedDuration,
  SyncStatus syncStatus = SyncStatus.synced,
  DateTime? updatedAt,
  DateTime? lastModifiedAt,
  String? userId,
}) {
  return TaskModel(
    id: id,
    title: title,
    beginsAt: beginsAt,
    estimatedDuration: estimatedDuration,
    syncStatus: syncStatus,
    updatedAt: updatedAt,
    lastModifiedAt: lastModifiedAt,
    userId: userId,
  );
}

TaskModel _cloneTask(
  TaskModel task, {
  SyncStatus? syncStatus,
  DateTime? updatedAt,
}) {
  return TaskModel(
    id: task.id,
    title: task.title,
    beginsAt: task.beginsAt,
    estimatedDuration: task.estimatedDuration,
    isCompleted: task.isCompleted,
    completedAt: task.completedAt,
    description: task.description,
    priority: task.priority,
    tags: List<String>.from(task.tags),
    syncStatus: syncStatus ?? task.syncStatus,
    createdAt: task.createdAt,
    updatedAt: updatedAt ?? task.updatedAt,
    lastModifiedAt: task.lastModifiedAt,
    userId: task.userId,
  );
}
