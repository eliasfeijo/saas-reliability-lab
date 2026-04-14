import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'test_support/app_test_support.dart';

void main() {
  test('syncAllTasks keeps the fresher remote task when local state is stale', () async {
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

    final syncedTasks = await service.syncAllTasks(await repository.loadTasks());
    final savedTasks = await repository.loadTasks();

    expect(syncedTasks, isEmpty);
    expect(remote.updatedTaskIds, isEmpty);
    expect(savedTasks, hasLength(1));
    expect(savedTasks.single.title, 'Remote truth');
    expect(savedTasks.single.syncStatus, SyncStatus.synced);
    expect(savedTasks.single.updatedAt, DateTime(2026, 1, 10, 12));
  });
}
