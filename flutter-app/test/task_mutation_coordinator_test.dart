import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/services/task_mutation_coordinator.dart';

import 'test_support/app_test_support.dart';

void main() {
  const coordinator = TaskMutationCoordinator();

  test(
    'task mutation coordinator tombstones account tasks and removes anonymous tasks on delete',
    () {
      final anonymousTask = buildTask(
        id: 'task-mutation-anon',
        title: 'Anonymous task',
        beginsAt: DateTime(2026, 3, 7, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );
      final accountTask = buildTask(
        id: 'task-mutation-account',
        title: 'Account task',
        beginsAt: DateTime(2026, 3, 7, 11),
        estimatedDuration: const Duration(hours: 1),
        userId: 'user-1',
        syncStatus: SyncStatus.synced,
        hasRemoteBackingRecord: true,
      );

      final result = coordinator.deleteTasks(
        [anonymousTask, accountTask],
        [anonymousTask.id, accountTask.id],
      );

      expect(result.didChange, isTrue);
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.id, accountTask.id);
      expect(result.tasks.single.syncStatus, SyncStatus.deleted);
      expect(result.syncTask?.id, accountTask.id);
      expect(
        result.changedTaskIds,
        containsAll([anonymousTask.id, accountTask.id]),
      );
    },
  );

  test(
    'task mutation coordinator removes unsynced account tasks completely on delete',
    () {
      final localOnlyAccountTask = buildTask(
        id: 'task-mutation-local-only-account',
        title: 'Never synced account task',
        beginsAt: DateTime(2026, 3, 7, 13),
        estimatedDuration: const Duration(hours: 1),
        userId: 'user-1',
        syncStatus: SyncStatus.dirty,
        hasRemoteBackingRecord: false,
      );

      final result = coordinator.deleteTasks(
        [localOnlyAccountTask],
        [localOnlyAccountTask.id],
      );

      expect(result.didChange, isTrue);
      expect(result.tasks, isEmpty);
      expect(result.syncTask, isNull);
    },
  );

  test(
    'task mutation coordinator adopts anonymous tasks into the authenticated account',
    () {
      final anonymousTask = buildTask(
        id: 'task-mutation-adopt',
        title: 'Local draft',
        beginsAt: DateTime(2026, 3, 8, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final result = coordinator.adoptAnonymousTasks([
        anonymousTask,
      ], userId: 'user-1');

      expect(result.didChange, isTrue);
      expect(result.tasks.single.userId, 'user-1');
      expect(result.tasks.single.syncStatus, SyncStatus.dirty);
      expect(result.changedTaskIds, contains(anonymousTask.id));
    },
  );

  test(
    'task mutation coordinator returns the first changed task for completion sync',
    () {
      final alphaTask = buildTask(
        id: 'task-mutation-alpha',
        title: 'Alpha task',
        beginsAt: DateTime(2026, 3, 9, 9),
        estimatedDuration: const Duration(hours: 1),
        userId: 'user-1',
      );
      final betaTask = buildTask(
        id: 'task-mutation-beta',
        title: 'Beta task',
        beginsAt: DateTime(2026, 3, 9, 11),
        estimatedDuration: const Duration(hours: 1),
        userId: 'user-1',
      );

      final result = coordinator.setCompletionState(
        [alphaTask, betaTask],
        [alphaTask.id, betaTask.id],
        isCompleted: true,
      );

      expect(result.didChange, isTrue);
      expect(result.tasks.every((task) => task.isCompleted), isTrue);
      expect(result.syncTask?.id, alphaTask.id);
    },
  );
}
