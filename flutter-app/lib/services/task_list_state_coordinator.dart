import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/outbox_repository.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_local_state_coordinator.dart';

class TaskListStateCoordinator {
  TaskListStateCoordinator(
    this._localSnapshotCoordinator, {
    RuntimeDebugProvider? runtimeDebug,
    TaskLocalStateCoordinator? localStateCoordinator,
  }) : _runtimeDebug = runtimeDebug,
       _localStateCoordinator = localStateCoordinator;

  factory TaskListStateCoordinator.fromRepository(
    TasksRepository repository, {
    RuntimeDebugProvider? runtimeDebug,
    OutboxRepository? outboxRepository,
    TaskLocalStateCoordinator? localStateCoordinator,
  }) {
    final snapshotCoordinator = TaskLocalSnapshotCoordinator.fromRepository(
      repository,
    );

    return TaskListStateCoordinator(
      snapshotCoordinator,
      runtimeDebug: runtimeDebug,
      localStateCoordinator:
          localStateCoordinator ??
          (outboxRepository == null
              ? null
              : TaskLocalStateCoordinator(
                  snapshotCoordinator,
                  outboxRepository,
                  runtimeDebug: runtimeDebug,
                )),
    );
  }

  final TaskLocalSnapshotCoordinator _localSnapshotCoordinator;
  final TaskLocalStateCoordinator? _localStateCoordinator;
  final RuntimeDebugProvider? _runtimeDebug;

  Future<List<TaskModel>> loadTasks() async {
    final tasks =
        await (_localStateCoordinator?.loadTaskSnapshot() ??
            _localSnapshotCoordinator.loadSnapshot());
    publishTaskCounts(tasks);
    return tasks;
  }

  Future<List<TaskModel>> saveTasks(
    List<TaskModel> tasks, {
    Iterable<String> changedTaskIds = const <String>[],
  }) async {
    final storedTasks =
        await (_localStateCoordinator?.saveTaskSnapshot(
              tasks,
              changedTaskIds: changedTaskIds,
            ) ??
            _localSnapshotCoordinator.saveSnapshot(tasks));
    publishTaskCounts(storedTasks);
    return storedTasks;
  }

  Future<List<TaskModel>> removeTaskIds(
    List<TaskModel> tasks,
    Iterable<String> taskIds,
  ) async {
    final nextTasks =
        await (_localStateCoordinator?.removeTaskIds(tasks, taskIds) ??
            _localSnapshotCoordinator.removeTaskIds(tasks, taskIds));
    publishTaskCounts(nextTasks);
    return nextTasks;
  }

  Future<List<TaskModel>> clearTasks() async {
    final clearedTasks =
        await (_localStateCoordinator?.clearLocalState() ??
            _localSnapshotCoordinator.clearSnapshot());
    publishTaskCounts(clearedTasks);
    return clearedTasks;
  }

  Future<void> clearRecentAcknowledgements() {
    return _localStateCoordinator?.clearRecentAcknowledgements() ??
        Future<void>.value();
  }

  Future<List<TaskModel>> resolveConflictKeepingRemote(String taskId) async {
    final nextTasks =
        await (_localStateCoordinator?.resolveConflictKeepingRemote(taskId) ??
            loadTasks());
    publishTaskCounts(nextTasks);
    return nextTasks;
  }

  Future<List<TaskModel>> reapplyConflictAsQueued(String taskId) async {
    final nextTasks =
        await (_localStateCoordinator?.reapplyConflictAsQueued(taskId) ??
            loadTasks());
    publishTaskCounts(nextTasks);
    return nextTasks;
  }

  void publishTaskCounts(List<TaskModel> tasks) {
    _runtimeDebug?.updateTaskCounts(tasks);
  }
}
