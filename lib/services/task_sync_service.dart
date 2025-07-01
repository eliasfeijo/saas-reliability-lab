import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/controllers/debounce_controller.dart';

import '../models/task.dart';
import '../repositories/tasks_repository.dart';

class TaskSyncService {
  final TasksRepository repository;
  final SupabaseClient supabase;

  final DebounceController _debouncedSync = DebounceController(
    debounceDuration: const Duration(seconds: 3),
  );

  TaskSyncService(this.repository, this.supabase);

  Future<List<TaskModel>> syncAllTasks(List<TaskModel> tasks) async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      debugPrint('No internet connection. Skipping sync.');
      return [];
    }

    final user = supabase.auth.currentUser;
    if (user == null || supabase.auth.currentSession == null) {
      debugPrint('No user session. Skipping sync.');
      return [];
    }

    // debugPrint('Starting sync for user ${user.id}');
    List<TaskModel> syncedTasks = [];
    final updatedTasks = [...tasks];

    final toDelete = updatedTasks
        .where((t) => t.syncStatus == SyncStatus.deleted)
        .toList();
    for (final task in toDelete) {
      try {
        await supabase.from('tasks').delete().eq('id', task.id);
        updatedTasks.removeWhere((t) => t.id == task.id);
        task.syncStatus = SyncStatus.synced;
        syncedTasks.add(task);
      } catch (e) {
        debugPrint('Delete error: $e');
      }
    }
    await repository.saveTasks(updatedTasks);

    final dirty = updatedTasks
        .where((t) => t.syncStatus == SyncStatus.dirty)
        .toList();
    for (final task in dirty) {
      try {
        final existing = await supabase
            .from('tasks')
            .select()
            .eq('id', task.id)
            .maybeSingle();

        if (existing == null) {
          await supabase.from('tasks').insert(task.toCloudJson());
          // debugPrint('Inserted new task: ${task.id}');
        } else if (task.lastModifiedAt != null &&
            task.lastModifiedAt!.isAfter(
              DateTime.parse(existing['updated_at']),
            )) {
          await supabase
              .from('tasks')
              .update(task.toCloudJson())
              .eq('id', task.id);
          // debugPrint('Updated existing task: ${task.id}');
        }
        // Update local task status
        task.syncStatus = SyncStatus.synced;
        syncedTasks.add(task);
      } catch (e) {
        debugPrint('Sync error: $e');
      }
    }
    await repository.saveTasks(updatedTasks);

    final remoteTasksRaw = await supabase
        .from('tasks')
        .select()
        .order('start_date');
    final remoteTasks = (remoteTasksRaw as List)
        .map((json) => TaskModel.fromJson(json))
        .toList();

    // Check for tasks that might have been deleted by another device
    // Compare remote tasks with local tasks
    final remoteTaskIds = remoteTasks.map((t) => t.id).toSet();
    final localTaskIds = updatedTasks.map((t) => t.id).toSet();
    final remainingTaskIds = localTaskIds.difference(remoteTaskIds).toList();
    // Remove deleted tasks from updatedTasks so they are not saved again
    updatedTasks.removeWhere((task) => remainingTaskIds.contains(task.id));

    final merged = <String, TaskModel>{};
    for (final task in [...remoteTasks, ...updatedTasks]) {
      merged[task.id] = task;
    }

    await repository.saveTasks(merged.values.toList());
    debugPrint('Sync completed. Synced ${syncedTasks.length} tasks.');

    return syncedTasks;
  }

  void debouncedSync(
    TaskModel task,
    Function(List<TaskModel> syncedTasks) callback,
  ) {
    _debouncedSync.trigger(() async {
      final tasks = await repository.loadTasks();
      final syncedTasks = await syncAllTasks(tasks);
      callback(syncedTasks);
    });
  }

  void syncIfLoggedIn(
    TaskModel task,
    Function(List<TaskModel> syncedTasks) callback,
  ) async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      debouncedSync(task, callback);
    } else {
      debugPrint('User not logged in. Skipping sync.');
    }
  }
}
