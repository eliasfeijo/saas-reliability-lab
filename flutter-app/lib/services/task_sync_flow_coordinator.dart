import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/services/task_list_state_coordinator.dart';
import 'package:todo_flutter/services/task_mutation_coordinator.dart';
import 'package:todo_flutter/services/task_sync_coordinator.dart';

typedef TaskListApplyCallback = void Function(List<TaskModel> tasks);

class TaskSyncFlowCoordinator {
  TaskSyncFlowCoordinator(
    this._taskListStateCoordinator,
    this._taskSyncCoordinator,
  );

  final TaskListStateCoordinator _taskListStateCoordinator;
  final TaskSyncCoordinator _taskSyncCoordinator;

  Future<void> syncAllTasks({
    required List<TaskModel> tasks,
    required String? userId,
    required bool hasPendingAnonymousReview,
    required bool isLoading,
    required SyncLoadingCallback setLoading,
    required TaskListApplyCallback applyTasks,
  }) async {
    await _taskSyncCoordinator.syncAllTasks(
      tasks: tasks,
      userId: userId,
      hasPendingAnonymousReview: hasPendingAnonymousReview,
      isLoading: isLoading,
      setLoading: setLoading,
      onTasksReloaded: (reloadedTasks) => applyTasks(reloadedTasks),
    );
  }

  Future<void> persistMutationResult(
    TaskMutationResult result, {
    required String? userId,
    required bool hasPendingAnonymousReview,
    required bool isLoading,
    required SyncLoadingCallback setLoading,
    required TaskListApplyCallback applyTasks,
  }) async {
    if (!result.didChange) {
      return;
    }

    final storedTasks = await _taskListStateCoordinator.saveTasks(result.tasks);
    applyTasks(storedTasks);

    final syncTask = result.syncTask;
    if (syncTask == null) {
      return;
    }

    _taskSyncCoordinator.triggerTaskSync(
      task: _findTaskById(storedTasks, syncTask.id) ?? syncTask,
      userId: userId,
      hasPendingAnonymousReview: hasPendingAnonymousReview,
      isLoading: isLoading,
      setLoading: setLoading,
      onTasksReloaded: (reloadedTasks) => applyTasks(reloadedTasks),
    );
  }

  Future<void> discardAnonymousTasks({
    required List<TaskModel> tasks,
    required Iterable<String> taskIds,
    required String? userId,
    required bool hasPendingAnonymousReview,
    required bool isLoading,
    required SyncLoadingCallback setLoading,
    required TaskListApplyCallback applyTasks,
  }) async {
    final remainingTasks = await _taskListStateCoordinator.removeTaskIds(
      tasks,
      taskIds,
    );
    applyTasks(remainingTasks);

    if (userId == null || userId.isEmpty) {
      return;
    }

    await syncAllTasks(
      tasks: remainingTasks,
      userId: userId,
      hasPendingAnonymousReview: hasPendingAnonymousReview,
      isLoading: isLoading,
      setLoading: setLoading,
      applyTasks: applyTasks,
    );
  }

  Future<void> takeOwnershipOfAnonymousTasks(
    TaskMutationResult result, {
    required String? userId,
    required bool hasPendingAnonymousReview,
    required bool isLoading,
    required SyncLoadingCallback setLoading,
    required TaskListApplyCallback applyTasks,
  }) async {
    if (!result.didChange) {
      return;
    }

    final storedTasks = await _taskListStateCoordinator.saveTasks(result.tasks);
    applyTasks(storedTasks);

    await syncAllTasks(
      tasks: storedTasks,
      userId: userId,
      hasPendingAnonymousReview: hasPendingAnonymousReview,
      isLoading: isLoading,
      setLoading: setLoading,
      applyTasks: applyTasks,
    );
  }

  TaskModel? _findTaskById(List<TaskModel> tasks, String taskId) {
    for (final task in tasks) {
      if (task.id == taskId) {
        return task;
      }
    }

    return null;
  }
}
