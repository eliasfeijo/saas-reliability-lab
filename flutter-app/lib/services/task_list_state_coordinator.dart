import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';

class TaskListStateCoordinator {
  TaskListStateCoordinator(
    this._localSnapshotCoordinator, {
    RuntimeDebugProvider? runtimeDebug,
  }) : _runtimeDebug = runtimeDebug;

  factory TaskListStateCoordinator.fromRepository(
    TasksRepository repository, {
    RuntimeDebugProvider? runtimeDebug,
  }) {
    return TaskListStateCoordinator(
      TaskLocalSnapshotCoordinator.fromRepository(repository),
      runtimeDebug: runtimeDebug,
    );
  }

  final TaskLocalSnapshotCoordinator _localSnapshotCoordinator;
  final RuntimeDebugProvider? _runtimeDebug;

  Future<List<TaskModel>> loadTasks() async {
    final tasks = await _localSnapshotCoordinator.loadSnapshot();
    publishTaskCounts(tasks);
    return tasks;
  }

  Future<List<TaskModel>> saveTasks(List<TaskModel> tasks) async {
    final storedTasks = await _localSnapshotCoordinator.saveSnapshot(tasks);
    publishTaskCounts(storedTasks);
    return storedTasks;
  }

  Future<List<TaskModel>> removeTaskIds(
    List<TaskModel> tasks,
    Iterable<String> taskIds,
  ) async {
    final nextTasks = await _localSnapshotCoordinator.removeTaskIds(
      tasks,
      taskIds,
    );
    publishTaskCounts(nextTasks);
    return nextTasks;
  }

  Future<List<TaskModel>> clearTasks() async {
    final clearedTasks = await _localSnapshotCoordinator.clearSnapshot();
    publishTaskCounts(clearedTasks);
    return clearedTasks;
  }

  void publishTaskCounts(List<TaskModel> tasks) {
    _runtimeDebug?.updateTaskCounts(tasks);
  }
}
