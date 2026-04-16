import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';

class TaskLocalSnapshotCoordinator {
  TaskLocalSnapshotCoordinator(this._snapshotStore);

  factory TaskLocalSnapshotCoordinator.fromRepository(
    TasksRepository repository,
  ) {
    return TaskLocalSnapshotCoordinator(
      TasksRepositorySnapshotStore(repository),
    );
  }

  final TaskSnapshotStore _snapshotStore;

  Future<List<TaskModel>> loadSnapshot() async {
    final tasks = await _snapshotStore.loadSnapshot();
    final prunedTasks = _pruneDeletedAnonymousTasks(tasks);
    if (prunedTasks.length != tasks.length) {
      await _snapshotStore.saveSnapshot(prunedTasks);
    }
    return prunedTasks;
  }

  Future<List<TaskModel>> saveSnapshot(List<TaskModel> tasks) async {
    final prunedTasks = _pruneDeletedAnonymousTasks(tasks);
    await _snapshotStore.saveSnapshot(prunedTasks);
    return prunedTasks;
  }

  Future<List<TaskModel>> removeTaskIds(
    List<TaskModel> tasks,
    Iterable<String> taskIds,
  ) async {
    final targetIds = taskIds.toSet();
    final nextTasks = tasks
        .where((task) => !targetIds.contains(task.id))
        .toList(growable: false);
    return saveSnapshot(nextTasks);
  }

  Future<List<TaskModel>> clearSnapshot() async {
    await _snapshotStore.clearSnapshot();
    return const <TaskModel>[];
  }

  List<TaskModel> _pruneDeletedAnonymousTasks(List<TaskModel> tasks) {
    return tasks
        .where(
          (task) =>
              !(task.userId == null && task.syncStatus == SyncStatus.deleted),
        )
        .toList(growable: false);
  }
}
