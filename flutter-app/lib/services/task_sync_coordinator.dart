import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_sync_service.dart';

typedef SyncLoadingCallback = void Function(bool isLoading);
typedef SyncedTasksCallback = FutureOr<void> Function(List<TaskModel> tasks);

class TaskSyncCoordinator {
  TaskSyncCoordinator(
    this._repository,
    this._taskSyncService, {
    RuntimeDebugProvider? runtimeDebug,
  }) : _runtimeDebug = runtimeDebug;

  final TasksRepository _repository;
  final TaskSyncService _taskSyncService;
  final RuntimeDebugProvider? _runtimeDebug;

  Future<void> syncAllTasks({
    required List<TaskModel> tasks,
    required String? userId,
    required bool hasPendingAnonymousReview,
    required bool isLoading,
    required SyncLoadingCallback setLoading,
    required SyncedTasksCallback onTasksReloaded,
  }) async {
    if (!_canStartSync(
      userId: userId,
      hasPendingAnonymousReview: hasPendingAnonymousReview,
      isLoading: isLoading,
    )) {
      return;
    }

    setLoading(true);

    try {
      debugPrint('Syncing all tasks...');
      await _taskSyncService.syncAllTasks(tasks);
      await _reloadTasks(onTasksReloaded);
      debugPrint('All tasks synced.');
    } finally {
      setLoading(false);
    }
  }

  void triggerTaskSync({
    required TaskModel task,
    required String? userId,
    required bool hasPendingAnonymousReview,
    required bool isLoading,
    required SyncLoadingCallback setLoading,
    required SyncedTasksCallback onTasksReloaded,
  }) {
    if (!_canStartSync(
      userId: userId,
      hasPendingAnonymousReview: hasPendingAnonymousReview,
      isLoading: isLoading,
    )) {
      return;
    }

    _taskSyncService.syncIfLoggedIn(
      task.copyWith(),
      () {
        setLoading(true);
      },
      (_) async {
        try {
          await _reloadTasks(onTasksReloaded);
        } finally {
          setLoading(false);
        }
      },
    );
  }

  bool _canStartSync({
    required String? userId,
    required bool hasPendingAnonymousReview,
    required bool isLoading,
  }) {
    if (userId == null || userId.isEmpty) {
      debugPrint('No user ID found. Skipping sync.');
      return false;
    }

    if (hasPendingAnonymousReview) {
      _runtimeDebug?.markSyncSkipped(
        phase: RuntimeSyncPhase.blockedAnonymousReview,
        message:
            'Anonymous local tasks are waiting for review. Keep or discard them before cloud sync.',
      );
      debugPrint('Anonymous tasks pending review. Pausing cloud sync.');
      return false;
    }

    if (isLoading) {
      debugPrint('Sync already in progress. Skipping sync.');
      return false;
    }

    return true;
  }

  Future<void> _reloadTasks(SyncedTasksCallback onTasksReloaded) async {
    final reloadedTasks = await _repository.loadTasks();
    await onTasksReloaded(reloadedTasks);
  }
}
