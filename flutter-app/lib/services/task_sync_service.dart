import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/controllers/debounce_controller.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/services/fault_injection_policy.dart';

import '../models/task.dart';
import '../repositories/tasks_repository.dart';

typedef ConnectivityCheck = Future<List<ConnectivityResult>> Function();
typedef SessionCheck = bool Function();
typedef DelayExecution = Future<void> Function(Duration duration);

class TaskSyncRunResult {
  const TaskSyncRunResult({
    this.acknowledgedTasks = const <TaskModel>[],
    this.hadRecoverableErrors = false,
  });

  final List<TaskModel> acknowledgedTasks;
  final bool hadRecoverableErrors;
}

abstract class TaskSyncGateway {
  Future<TaskSyncRunResult> syncTasks(List<TaskModel> tasks);

  void syncIfLoggedIn(
    TaskModel task,
    Function()? beforeSync,
    Function(TaskSyncRunResult result) callback,
  );
}

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

class TaskSyncService implements TaskSyncGateway {
  final TasksRepository repository;
  final TaskRemoteDataSource _remote;
  final ConnectivityCheck _checkConnectivity;
  final SessionCheck _hasActiveSession;
  final DebounceController _debouncedSync;
  final RuntimeDebugProvider? _runtimeDebug;
  final FaultInjectionPolicy _faultInjectionPolicy;
  final DelayExecution _delayExecution;

  TaskSyncService(
    this.repository,
    SupabaseClient supabase, {
    TaskRemoteDataSource? remote,
    ConnectivityCheck? connectivityCheck,
    SessionCheck? hasActiveSession,
    DebounceController? debounceController,
    RuntimeDebugProvider? runtimeDebug,
    FaultInjectionPolicy? faultInjectionPolicy,
    DelayExecution? delayExecution,
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
           DebounceController(debounceDuration: const Duration(seconds: 3)),
       _runtimeDebug = runtimeDebug,
       _faultInjectionPolicy = faultInjectionPolicy ?? FaultInjectionPolicy(),
       _delayExecution = delayExecution ?? Future<void>.delayed;

  TaskSyncService.forTesting(
    this.repository, {
    required TaskRemoteDataSource remote,
    required ConnectivityCheck connectivityCheck,
    required SessionCheck hasActiveSession,
    DebounceController? debounceController,
    RuntimeDebugProvider? runtimeDebug,
    FaultInjectionPolicy? faultInjectionPolicy,
    DelayExecution? delayExecution,
  }) : _remote = remote,
       _checkConnectivity = connectivityCheck,
       _hasActiveSession = hasActiveSession,
       _debouncedSync =
           debounceController ??
           DebounceController(debounceDuration: const Duration(seconds: 3)),
       _runtimeDebug = runtimeDebug,
       _faultInjectionPolicy = faultInjectionPolicy ?? FaultInjectionPolicy(),
       _delayExecution = delayExecution ?? Future<void>.delayed;

  @override
  Future<TaskSyncRunResult> syncTasks(List<TaskModel> tasks) async {
    final connectivityResult = _faultInjectionPolicy.applyConnectivityResults(
      await _checkConnectivity(),
    );
    _runtimeDebug?.setConnectivityResults(connectivityResult, logEvent: false);
    _runtimeDebug?.updateTaskCounts(tasks);

    if (_hasNoConnectivity(connectivityResult)) {
      final message = _faultInjectionPolicy.isConnectivityLossActive
          ? 'Connectivity loss scenario is active. Cloud sync is being forced offline.'
          : 'No internet connection. Skipping sync.';
      _runtimeDebug?.markSyncSkipped(
        phase: RuntimeSyncPhase.offline,
        message: message,
        payload: _buildSyncPayload(
          stage: 'Replay skipped',
          summary:
              'The sync pass did not start because the cloud boundary is offline.',
          tasks: tasks,
          notes: [
            if (_faultInjectionPolicy.isConnectivityLossActive)
              'A controlled connectivity-loss scenario is currently forcing the sync boundary offline.',
          ],
        ),
      );
      debugPrint(message);
      return const TaskSyncRunResult();
    }

    if (!_hasActiveSession()) {
      _runtimeDebug?.markSyncSkipped(
        phase: RuntimeSyncPhase.blockedNoSession,
        message: 'No authenticated session. Skipping sync.',
        payload: _buildSyncPayload(
          stage: 'Replay blocked',
          summary:
              'The sync pass is waiting for an authenticated session before any cloud replay can start.',
          tasks: tasks,
        ),
      );
      debugPrint('No user session. Skipping sync.');
      return const TaskSyncRunResult();
    }

    final delayedSyncLabel = _faultInjectionPolicy.delayedSyncDurationLabel;
    final startMessage = delayedSyncLabel == null
        ? 'Synchronizing ${tasks.length} local task(s).'
        : 'Delayed sync scenario is active. Holding remote replay for $delayedSyncLabel before synchronizing ${tasks.length} local task(s).';

    _runtimeDebug?.markSyncStarted(
      startMessage,
      payload: _buildSyncPayload(
        stage: 'Replay started',
        summary:
            'The runtime is preparing local task mutations for cloud replay.',
        tasks: tasks,
        notes: [
          if (delayedSyncLabel != null)
            'A deterministic delay is active before remote replay begins.',
        ],
      ),
    );
    await _applyInjectedPreSyncDelay(tasks);

    try {
      final syncedTasks = <TaskModel>[];
      final acknowledgedTaskDetails = <RuntimeEventTaskDetail>[];
      final adoptedRemoteTaskDetails = <RuntimeEventTaskDetail>[];
      final remotelyConfirmedTaskIds = <String>{};
      final workingTasks = [...tasks];
      var hadRecoverableErrors = false;

      final toDelete = workingTasks
          .where((t) => t.syncStatus == SyncStatus.deleted)
          .toList();
      for (final task in toDelete) {
        try {
          await _remote.deleteTask(task.id);
          workingTasks.removeWhere((t) => t.id == task.id);
          task.syncStatus = SyncStatus.synced;
          syncedTasks.add(task);
          acknowledgedTaskDetails.add(
            _buildTaskDetail(
              task,
              outcome: 'Deleted remotely',
              description:
                  'A locally deleted task was confirmed and removed from the cloud record.',
            ),
          );
        } catch (e) {
          hadRecoverableErrors = true;
          _runtimeDebug?.addEvent(
            category: RuntimeEventCategory.sync,
            message: 'Failed to delete task ${task.title}.',
            level: RuntimeEventLevel.warning,
            detail: e.toString(),
            payload: _buildSyncPayload(
              stage: 'Delete failed',
              summary:
                  'The runtime could not remove this task from the remote store during replay.',
              tasks: tasks,
              highlightedTasks: [
                _buildTaskDetail(
                  task,
                  outcome: 'Delete failed',
                  description:
                      'The task remains in local review state until a later sync pass succeeds.',
                ),
              ],
              notes: [e.toString()],
            ),
          );
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
            acknowledgedTaskDetails.add(
              _buildTaskDetail(
                task,
                outcome: 'Created remotely',
                description:
                    'A local-only task was inserted into the remote task set.',
              ),
            );
            continue;
          }

          if (_isLocalTaskNewer(task, remoteTask)) {
            await _remote.updateTask(task);
            task.syncStatus = SyncStatus.synced;
            remotelyConfirmedTaskIds.add(task.id);
            syncedTasks.add(task);
            acknowledgedTaskDetails.add(
              _buildTaskDetail(
                task,
                outcome: 'Updated remotely',
                description:
                    'The local task version was newer and replaced the remote copy.',
                fieldDiffs: _buildTaskFieldDiffs(remoteTask, task),
              ),
            );
            continue;
          }

          _replaceTask(workingTasks, remoteTask);
          _runtimeDebug?.addEvent(
            category: RuntimeEventCategory.sync,
            message: 'Remote task ${task.title} replaced stale local state.',
            payload: _buildSyncPayload(
              stage: 'Remote truth adopted',
              summary:
                  'The remote task version was newer, so the local draft was replaced to preserve canonical state.',
              tasks: tasks,
              highlightedTasks: [
                _buildTaskDetail(
                  remoteTask,
                  outcome: 'Remote truth kept',
                  description:
                      'The local draft was stale and has been replaced by the fresher remote state.',
                  fieldDiffs: _buildTaskFieldDiffs(task, remoteTask),
                ),
              ],
            ),
          );
          adoptedRemoteTaskDetails.add(
            _buildTaskDetail(
              remoteTask,
              outcome: 'Remote truth kept',
              description:
                  'The local draft was stale and the remote version became the retained record.',
              fieldDiffs: _buildTaskFieldDiffs(task, remoteTask),
            ),
          );
          debugPrint(
            'Remote task ${task.id} is newer or equal. Keeping remote version.',
          );
        } catch (e) {
          hadRecoverableErrors = true;
          _runtimeDebug?.addEvent(
            category: RuntimeEventCategory.sync,
            message: 'Failed to sync task ${task.title}.',
            level: RuntimeEventLevel.warning,
            detail: e.toString(),
            payload: _buildSyncPayload(
              stage: 'Task replay failed',
              summary:
                  'The runtime could not replay this task mutation to the remote store.',
              tasks: tasks,
              highlightedTasks: [
                _buildTaskDetail(
                  task,
                  outcome: 'Replay failed',
                  description:
                      'The task remains locally available and will need another sync pass.',
                ),
              ],
              notes: [e.toString()],
            ),
          );
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
      _runtimeDebug?.updateTaskCounts(mergedTasks);

      final summary =
          'Sync completed. ${syncedTasks.length} task(s) acknowledged.';
      if (hadRecoverableErrors) {
        _runtimeDebug?.markSyncPartial(
          '$summary Some operations need review.',
          payload: _buildSyncPayload(
            stage: 'Replay completed with review needed',
            summary:
                'The sync pass finished, but one or more operations emitted warning events that still need operator review.',
            tasks: mergedTasks,
            highlightedTasks: [
              ...acknowledgedTaskDetails,
              ...adoptedRemoteTaskDetails,
            ],
            extraMetrics: [
              RuntimeEventMetric(
                label: 'Acknowledged',
                value: syncedTasks.length.toString(),
              ),
              RuntimeEventMetric(
                label: 'Remote truth kept',
                value: adoptedRemoteTaskDetails.length.toString(),
              ),
            ],
            notes: const [
              'Review the warning events in the timeline for the specific tasks that still need attention.',
            ],
          ),
        );
      } else {
        _runtimeDebug?.markSyncSuccess(
          summary,
          payload: _buildSyncPayload(
            stage: 'Replay completed',
            summary:
                'All local mutations in this pass were reconciled without warning-level issues.',
            tasks: mergedTasks,
            highlightedTasks: [
              ...acknowledgedTaskDetails,
              ...adoptedRemoteTaskDetails,
            ],
            extraMetrics: [
              RuntimeEventMetric(
                label: 'Acknowledged',
                value: syncedTasks.length.toString(),
              ),
              RuntimeEventMetric(
                label: 'Remote truth kept',
                value: adoptedRemoteTaskDetails.length.toString(),
              ),
            ],
          ),
        );
      }

      debugPrint('Sync completed. Synced ${syncedTasks.length} tasks.');

      return TaskSyncRunResult(
        acknowledgedTasks: syncedTasks,
        hadRecoverableErrors: hadRecoverableErrors,
      );
    } catch (e) {
      _runtimeDebug?.markSyncFailure(
        'Sync failed: $e',
        payload: _buildSyncPayload(
          stage: 'Replay failed',
          summary:
              'The sync pass stopped before completion because an unrecoverable error escaped the replay loop.',
          tasks: tasks,
          notes: [e.toString()],
        ),
      );
      rethrow;
    }
  }

  Future<List<TaskModel>> syncAllTasks(List<TaskModel> tasks) async {
    final result = await syncTasks(tasks);
    return result.acknowledgedTasks;
  }

  void debouncedSync(
    TaskModel task,
    Function()? beforeSync,
    Function(TaskSyncRunResult result) callback,
  ) {
    _debouncedSync.trigger(() async {
      if (beforeSync != null) {
        beforeSync();
      }
      final tasks = await repository.loadTasks();
      final result = await syncTasks(tasks);
      callback(result);
    });
  }

  @override
  void syncIfLoggedIn(
    TaskModel task,
    Function()? beforeSync,
    Function(TaskSyncRunResult result) callback,
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

  Future<void> _applyInjectedPreSyncDelay(List<TaskModel> tasks) async {
    final delay = _faultInjectionPolicy.delayedSyncDuration;
    final delayLabel = _faultInjectionPolicy.delayedSyncDurationLabel;
    if (delay == null || delayLabel == null) {
      return;
    }

    final message =
        'Delayed sync scenario is holding the sync pass for $delayLabel before remote replay begins.';
    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.sync,
      message: message,
      level: RuntimeEventLevel.warning,
      payload: _buildSyncPayload(
        stage: 'Deterministic hold',
        summary:
            'The sync pass is intentionally paused before remote replay to make the delayed-sync scenario visible.',
        tasks: tasks,
        extraMetrics: [
          RuntimeEventMetric(label: 'Injected delay', value: delayLabel),
        ],
      ),
    );
    debugPrint(message);
    await _delayExecution(delay);
  }

  RuntimeEventPayload _buildSyncPayload({
    required String stage,
    required String summary,
    required List<TaskModel> tasks,
    List<RuntimeEventTaskDetail> highlightedTasks = const [],
    List<RuntimeEventMetric> extraMetrics = const [],
    List<String> notes = const [],
  }) {
    return RuntimeEventPayload(
      stage: stage,
      summary: summary,
      metrics: [..._buildTaskMetrics(tasks), ...extraMetrics],
      tasks: highlightedTasks.isEmpty
          ? tasks.map(_buildTaskDetail).toList(growable: false)
          : highlightedTasks,
      notes: notes,
    );
  }

  List<RuntimeEventMetric> _buildTaskMetrics(List<TaskModel> tasks) {
    final dirtyCount = tasks
        .where((task) => task.syncStatus == SyncStatus.dirty)
        .length;
    final deletedCount = tasks
        .where((task) => task.syncStatus == SyncStatus.deleted)
        .length;
    final localOnlyCount = tasks
        .where(
          (task) =>
              task.userId == null && task.syncStatus != SyncStatus.deleted,
        )
        .length;

    return [
      RuntimeEventMetric(
        label: 'Tasks in pass',
        value: tasks.length.toString(),
      ),
      RuntimeEventMetric(label: 'Dirty', value: dirtyCount.toString()),
      RuntimeEventMetric(label: 'Deleted', value: deletedCount.toString()),
      RuntimeEventMetric(label: 'Local only', value: localOnlyCount.toString()),
    ];
  }

  RuntimeEventTaskDetail _buildTaskDetail(
    TaskModel task, {
    String? outcome,
    String? description,
    List<RuntimeEventFieldDiff> fieldDiffs = const [],
  }) {
    return RuntimeEventTaskDetail(
      title: task.title.isEmpty ? 'Untitled task' : task.title,
      taskId: task.id,
      syncStatus: _syncStatusLabel(task.syncStatus),
      outcome: outcome,
      description: description ?? _buildTaskSnapshot(task),
      tags: [
        _priorityLabel(task.priority),
        if (task.userId == null) 'No user linked',
        if (task.isCompleted) 'Completed' else 'Open',
      ],
      fieldDiffs: fieldDiffs,
    );
  }

  List<RuntimeEventFieldDiff> _buildTaskFieldDiffs(
    TaskModel before,
    TaskModel after,
  ) {
    final fieldDiffs = <RuntimeEventFieldDiff>[];

    void addField(String label, String previous, String next) {
      if (previous == next) {
        return;
      }
      fieldDiffs.add(
        RuntimeEventFieldDiff(label: label, before: previous, after: next),
      );
    }

    addField('Title', before.title, after.title);
    addField(
      'Start',
      _formatDateTime(before.beginsAt),
      _formatDateTime(after.beginsAt),
    );
    addField(
      'Duration',
      _formatDuration(before.estimatedDuration),
      _formatDuration(after.estimatedDuration),
    );
    addField(
      'Completion',
      before.isCompleted ? 'Completed' : 'Open',
      after.isCompleted ? 'Completed' : 'Open',
    );
    addField(
      'Priority',
      _priorityLabel(before.priority),
      _priorityLabel(after.priority),
    );
    addField(
      'Description',
      (before.description == null || before.description!.isEmpty)
          ? 'Not provided'
          : before.description!,
      (after.description == null || after.description!.isEmpty)
          ? 'Not provided'
          : after.description!,
    );

    return fieldDiffs;
  }

  String _buildTaskSnapshot(TaskModel task) {
    return '${_formatDateTime(task.beginsAt)} for ${_formatDuration(task.estimatedDuration)}.';
  }

  String _syncStatusLabel(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return 'Synced';
      case SyncStatus.dirty:
        return 'Dirty';
      case SyncStatus.deleted:
        return 'Deleted';
    }
  }

  String _priorityLabel(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return 'Low priority';
      case TaskPriority.medium:
        return 'Medium priority';
      case TaskPriority.high:
        return 'High priority';
      case TaskPriority.urgent:
        return 'Urgent';
    }
  }

  String _formatDateTime(DateTime value) {
    final localValue = value.toLocal();
    final hour = localValue.hour.toString().padLeft(2, '0');
    final minute = localValue.minute.toString().padLeft(2, '0');
    return '${localValue.year}-${localValue.month.toString().padLeft(2, '0')}-${localValue.day.toString().padLeft(2, '0')} $hour:$minute';
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    if (hours == 0) {
      return '${value.inMinutes} min';
    }
    if (minutes == 0) {
      return '$hours h';
    }
    return '$hours h $minutes min';
  }
}
