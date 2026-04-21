import 'package:todo_flutter/models/task.dart';

class TaskMutationResult {
  const TaskMutationResult({
    required this.tasks,
    this.syncTask,
    this.changedTaskIds = const <String>{},
    this.didChange = false,
  });

  final List<TaskModel> tasks;
  final TaskModel? syncTask;
  final Set<String> changedTaskIds;
  final bool didChange;
}

class TaskMutationCoordinator {
  const TaskMutationCoordinator();

  TaskMutationResult addTask(
    List<TaskModel> tasks,
    TaskModel task, {
    required String? userId,
  }) {
    task.userId = userId;
    task.dirty();
    task.hasRemoteBackingRecord = false;
    return TaskMutationResult(
      tasks: [...tasks, task],
      syncTask: task,
      changedTaskIds: {task.id},
      didChange: true,
    );
  }

  TaskMutationResult updateTask(List<TaskModel> tasks, TaskModel updatedTask) {
    final index = tasks.indexWhere((task) => task.id == updatedTask.id);
    if (index == -1) {
      return TaskMutationResult(tasks: List<TaskModel>.from(tasks));
    }

    updatedTask.dirty();
    final nextTasks = List<TaskModel>.from(tasks);
    nextTasks[index] = updatedTask;
    return TaskMutationResult(
      tasks: nextTasks,
      syncTask: updatedTask,
      changedTaskIds: {updatedTask.id},
      didChange: true,
    );
  }

  TaskMutationResult setCompletionState(
    List<TaskModel> tasks,
    Iterable<String> taskIds, {
    required bool isCompleted,
  }) {
    final targetIds = taskIds.toSet();
    if (targetIds.isEmpty) {
      return TaskMutationResult(tasks: List<TaskModel>.from(tasks));
    }

    final nextTasks = List<TaskModel>.from(tasks);
    TaskModel? syncTask;
    var didChange = false;

    for (final task in nextTasks) {
      if (!targetIds.contains(task.id)) {
        continue;
      }

      if (isCompleted) {
        if (task.isCompleted) {
          continue;
        }
        task.markAsCompleted();
      } else {
        if (!task.isCompleted) {
          continue;
        }
        task.markAsPending();
      }

      syncTask ??= task;
      didChange = true;
    }

    return TaskMutationResult(
      tasks: nextTasks,
      syncTask: syncTask,
      changedTaskIds: targetIds,
      didChange: didChange,
    );
  }

  TaskMutationResult deleteTasks(
    List<TaskModel> tasks,
    Iterable<String> taskIds,
  ) {
    final targetIds = taskIds.toSet();
    if (targetIds.isEmpty) {
      return TaskMutationResult(tasks: List<TaskModel>.from(tasks));
    }

    final nextTasks = <TaskModel>[];
    TaskModel? syncTask;
    var didChange = false;

    for (final task in tasks) {
      if (!targetIds.contains(task.id)) {
        nextTasks.add(task);
        continue;
      }

      if (task.userId == null) {
        didChange = true;
        continue;
      }

      if (!task.hasRemoteBackingRecord) {
        didChange = true;
        continue;
      }

      if (task.syncStatus == SyncStatus.deleted) {
        nextTasks.add(task);
        continue;
      }

      task.markAsDeleted();
      syncTask ??= task;
      didChange = true;
      nextTasks.add(task);
    }

    return TaskMutationResult(
      tasks: nextTasks,
      syncTask: syncTask,
      changedTaskIds: targetIds,
      didChange: didChange,
    );
  }

  TaskMutationResult adoptAnonymousTasks(
    List<TaskModel> tasks, {
    required String? userId,
  }) {
    if (userId == null || userId.isEmpty) {
      return TaskMutationResult(tasks: List<TaskModel>.from(tasks));
    }

    final nextTasks = List<TaskModel>.from(tasks);
    final changedTaskIds = <String>{};
    var didChange = false;

    for (final task in nextTasks.where((task) => task.userId == null)) {
      task.userId = userId;
      task.dirty();
      changedTaskIds.add(task.id);
      didChange = true;
    }

    return TaskMutationResult(
      tasks: nextTasks,
      changedTaskIds: changedTaskIds,
      didChange: didChange,
    );
  }

  TaskMutationResult markAllCompleted(List<TaskModel> tasks) {
    final nextTasks = List<TaskModel>.from(tasks);
    var didChange = false;

    for (final task in nextTasks) {
      if (task.isCompleted) {
        continue;
      }
      task.markAsCompleted();
      didChange = true;
    }

    return TaskMutationResult(tasks: nextTasks, didChange: didChange);
  }

  TaskMutationResult clearCompletedTasks(List<TaskModel> tasks) {
    final nextTasks = tasks
        .where((task) => !task.isCompleted)
        .toList(growable: false);
    return TaskMutationResult(
      tasks: nextTasks,
      didChange: nextTasks.length != tasks.length,
    );
  }
}
