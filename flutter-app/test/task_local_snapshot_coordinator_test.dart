import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';

import 'test_support/app_test_support.dart';

void main() {
  test(
    'local snapshot coordinator prunes deleted anonymous tombstones on load',
    () async {
      final deletedAnonymousTask = buildTask(
        id: 'task-local-prune',
        title: 'Legacy local tombstone',
        beginsAt: DateTime(2026, 3, 5, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.deleted,
      );
      final accountTask = buildTask(
        id: 'task-local-account',
        title: 'Account task',
        beginsAt: DateTime(2026, 3, 5, 11),
        estimatedDuration: const Duration(hours: 1),
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([
        deletedAnonymousTask,
        accountTask,
      ]);
      final coordinator = TaskLocalSnapshotCoordinator.fromRepository(
        repository,
      );

      final loadedTasks = await coordinator.loadSnapshot();
      final savedTasks = await repository.loadTasks();

      expect(loadedTasks, hasLength(1));
      expect(loadedTasks.single.id, accountTask.id);
      expect(savedTasks, hasLength(1));
      expect(savedTasks.single.id, accountTask.id);
    },
  );

  test(
    'local snapshot coordinator removes target task ids and persists the remaining snapshot',
    () async {
      final alphaTask = buildTask(
        id: 'task-local-alpha',
        title: 'Alpha task',
        beginsAt: DateTime(2026, 3, 6, 9),
        estimatedDuration: const Duration(hours: 1),
      );
      final betaTask = buildTask(
        id: 'task-local-beta',
        title: 'Beta task',
        beginsAt: DateTime(2026, 3, 6, 11),
        estimatedDuration: const Duration(hours: 1),
      );

      final repository = InMemoryTasksRepository([alphaTask, betaTask]);
      final coordinator = TaskLocalSnapshotCoordinator.fromRepository(
        repository,
      );

      final nextTasks = await coordinator.removeTaskIds(
        [alphaTask, betaTask],
        [alphaTask.id],
      );

      expect(nextTasks.map((task) => task.id).toList(), [betaTask.id]);
      expect((await repository.loadTasks()).map((task) => task.id).toList(), [
        betaTask.id,
      ]);
    },
  );
}
