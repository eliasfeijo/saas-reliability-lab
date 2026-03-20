import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/controllers/debounce_controller.dart';

import '../models/task.dart';
import '../repositories/tasks_repository.dart';

typedef ConnectivityCheck = Future<List<ConnectivityResult>> Function();
typedef SessionCheck = bool Function();

abstract class TaskRemoteDataSource {
  Future<void> deleteTask(String taskId);
  Future<TaskModel?> fetchTaskById(String taskId);
  Future<void> insertTask(TaskModel task);
  Future<void> updateTask(TaskModel task);
  Future<List<TaskModel>> fetchAllTasks();
}

class SupabaseTaskRemoteDataSource implements TaskRemoteDataSource {
  final SupabaseClient supabase;

  SupabaseTaskRemoteDataSource(this.supabase);

  @override
  Future<void> deleteTask(String taskId) async {
    await supabase.from('tasks').delete().eq('id', taskId);
  }

  @override
  Future<TaskModel?> fetchTaskById(String taskId) async {
    final existing = await supabase
        .from('tasks')
        .select()
        .eq('id', taskId)
        .maybeSingle();

    if (existing == null) {
      return null;
    }

    return TaskModel.fromJson(existing);
  }

  @override
  Future<void> insertTask(TaskModel task) async {
    await supabase.from('tasks').insert(task.toCloudJson());
  }

  @override
  Future<void> updateTask(TaskModel task) async {
    await supabase.from('tasks').update(task.toCloudJson()).eq('id', task.id);
  }

  @override
  Future<List<TaskModel>> fetchAllTasks() async {
    final remoteTasksRaw = await supabase
        .from('tasks')
        .select()
        .order('start_date');

    return (remoteTasksRaw as List)
        .map((json) => TaskModel.fromJson(json))
        .toList();
  }
}

class TaskSyncService {
  final TasksRepository repository;
  final TaskRemoteDataSource _remote;
  final ConnectivityCheck _checkConnectivity;
  final SessionCheck _hasActiveSession;
  final DebounceController _debouncedSync;

  TaskSyncService(
    this.repository,
    SupabaseClient supabase, {
    TaskRemoteDataSource? remote,
    ConnectivityCheck? connectivityCheck,
    SessionCheck? hasActiveSession,
    DebounceController? debounceController,
  }) : _remote = remote ?? SupabaseTaskRemoteDataSource(supabase),
       _checkConnectivity =
           connectivityCheck ?? Connectivity().checkConnectivity,
       _hasActiveSession =
           hasActiveSession ??
           (() {
             final auth = supabase.auth;
             return auth.currentUser != null && auth.currentSession != null;
           }),
       _debouncedSync =
           debounceController ??
           DebounceController(debounceDuration: const Duration(seconds: 3));

  TaskSyncService.forTesting(
    this.repository, {
    required TaskRemoteDataSource remote,
    required ConnectivityCheck connectivityCheck,
    required SessionCheck hasActiveSession,
    DebounceController? debounceController,
  }) : _remote = remote,
       _checkConnectivity = connectivityCheck,
       _hasActiveSession = hasActiveSession,
       _debouncedSync =
           debounceController ??
           DebounceController(debounceDuration: const Duration(seconds: 3));

  Future<List<TaskModel>> syncAllTasks(List<TaskModel> tasks) async {
    final connectivityResult = await _checkConnectivity();
    if (_hasNoConnectivity(connectivityResult)) {
      debugPrint('No internet connection. Skipping sync.');
      return [];
    }

    if (!_hasActiveSession()) {
      debugPrint('No user session. Skipping sync.');
      return [];
    }

    final syncedTasks = <TaskModel>[];
    final remotelyConfirmedTaskIds = <String>{};
    final workingTasks = [...tasks];

    final toDelete = workingTasks
        .where((t) => t.syncStatus == SyncStatus.deleted)
        .toList();
    for (final task in toDelete) {
      try {
        await _remote.deleteTask(task.id);
        workingTasks.removeWhere((t) => t.id == task.id);
        task.syncStatus = SyncStatus.synced;
        syncedTasks.add(task);
      } catch (e) {
        debugPrint('Delete error: $e');
      }
    }
    await repository.saveTasks(workingTasks);

    final dirty = workingTasks
        .where((t) => t.syncStatus == SyncStatus.dirty)
        .toList();
    for (final task in dirty) {
      try {
        final remoteTask = await _remote.fetchTaskById(task.id);

        if (remoteTask == null) {
          await _remote.insertTask(task);
          task.syncStatus = SyncStatus.synced;
          remotelyConfirmedTaskIds.add(task.id);
          syncedTasks.add(task);
          continue;
        }

        if (_isLocalTaskNewer(task, remoteTask)) {
          await _remote.updateTask(task);
          task.syncStatus = SyncStatus.synced;
          remotelyConfirmedTaskIds.add(task.id);
          syncedTasks.add(task);
          continue;
        }

        _replaceTask(workingTasks, remoteTask);
        debugPrint(
          'Remote task ${task.id} is newer or equal. Keeping remote version.',
        );
      } catch (e) {
        debugPrint('Sync error: $e');
      }
    }
    await repository.saveTasks(workingTasks);

    final remoteTasks = await _remote.fetchAllTasks();
    final remoteTaskIds = remoteTasks.map((t) => t.id).toSet();
    final merged = <String, TaskModel>{
      for (final task in remoteTasks) task.id: task,
    };

    for (final task in workingTasks) {
      final shouldKeepLocalTask =
          task.syncStatus != SyncStatus.synced ||
          remotelyConfirmedTaskIds.contains(task.id) &&
              !remoteTaskIds.contains(task.id);

      if (shouldKeepLocalTask) {
        merged[task.id] = task;
      }
    }

    final mergedTasks = merged.values.toList()
      ..sort((a, b) => a.beginsAt.compareTo(b.beginsAt));

    await repository.saveTasks(mergedTasks);
    debugPrint('Sync completed. Synced ${syncedTasks.length} tasks.');

    return syncedTasks;
  }

  void debouncedSync(
    TaskModel task,
    Function()? beforeSync,
    Function(List<TaskModel> syncedTasks) callback,
  ) {
    _debouncedSync.trigger(() async {
      if (beforeSync != null) {
        beforeSync();
      }
      final tasks = await repository.loadTasks();
      final syncedTasks = await syncAllTasks(tasks);
      callback(syncedTasks);
    });
  }

  void syncIfLoggedIn(
    TaskModel task,
    Function()? beforeSync,
    Function(List<TaskModel> syncedTasks) callback,
  ) async {
    if (_hasActiveSession()) {
      debouncedSync(task, beforeSync, callback);
    } else {
      debugPrint('User not logged in. Skipping sync.');
    }
  }

  bool _hasNoConnectivity(List<ConnectivityResult> connectivityResult) {
    return connectivityResult.isEmpty ||
        connectivityResult.every((result) => result == ConnectivityResult.none);
  }

  bool _isLocalTaskNewer(TaskModel localTask, TaskModel remoteTask) {
    final localModifiedAt = localTask.lastModifiedAt;
    if (localModifiedAt == null) {
      return false;
    }

    final remoteUpdatedAt = remoteTask.updatedAt ?? remoteTask.lastModifiedAt;
    if (remoteUpdatedAt == null) {
      return true;
    }

    return localModifiedAt.isAfter(remoteUpdatedAt.toLocal());
  }

  void _replaceTask(List<TaskModel> tasks, TaskModel replacement) {
    final index = tasks.indexWhere((task) => task.id == replacement.id);
    if (index == -1) {
      tasks.add(replacement);
      return;
    }

    tasks[index] = replacement;
  }
}
