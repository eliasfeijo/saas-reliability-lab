import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/outbox_repository.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_local_state_coordinator.dart';
import 'package:todo_flutter/services/task_sync_service.dart';

typedef SyncLoadingCallback = void Function(bool isLoading);
typedef SyncedTasksCallback = FutureOr<void> Function(List<TaskModel> tasks);

class TaskSyncCoordinator {
  TaskSyncCoordinator(
    TaskLocalSnapshotCoordinator _,
    this._taskSyncGateway, {
    RuntimeDebugProvider? runtimeDebug,
    required TaskLocalStateCoordinator localStateCoordinator,
  }) : _runtimeDebug = runtimeDebug,
       _localStateCoordinator = localStateCoordinator;

  factory TaskSyncCoordinator.fromRepository(
    TasksRepository repository,
    TaskSyncGateway taskSyncGateway, {
    RuntimeDebugProvider? runtimeDebug,
    OutboxRepository? outboxRepository,
    TaskLocalStateCoordinator? localStateCoordinator,
  }) {
    final snapshotCoordinator = TaskLocalSnapshotCoordinator.fromRepository(
      repository,
    );
    final resolvedLocalStateCoordinator =
        localStateCoordinator ??
        TaskLocalStateCoordinator(
          snapshotCoordinator,
          outboxRepository ?? SharedPreferencesOutboxRepository(),
          runtimeDebug: runtimeDebug,
        );

    return TaskSyncCoordinator(
      snapshotCoordinator,
      taskSyncGateway,
      runtimeDebug: runtimeDebug,
      localStateCoordinator: resolvedLocalStateCoordinator,
    );
  }

  final TaskSyncGateway _taskSyncGateway;
  final RuntimeDebugProvider? _runtimeDebug;
  final TaskLocalStateCoordinator _localStateCoordinator;

  Future<TaskSyncRunResult> syncAllTasks({
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
      return const TaskSyncRunResult();
    }

    setLoading(true);

    try {
      debugPrint('Syncing all tasks...');
      final result = await _taskSyncGateway.syncTasks(tasks);
      await _reloadTasks(onTasksReloaded);
      debugPrint('All tasks synced.');
      return result;
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

    _taskSyncGateway.syncIfLoggedIn(
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
        payload: const RuntimeEventPayload(
          stage: 'Replay blocked',
          summary:
              'Cloud replay is paused until the operator keeps or discards anonymous local tasks.',
        ),
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
    final reloadedTasks = await _localStateCoordinator.loadTaskSnapshot();
    await onTasksReloaded(reloadedTasks);
  }
}
