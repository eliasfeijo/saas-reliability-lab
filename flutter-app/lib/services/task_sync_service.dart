import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/controllers/debounce_controller.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';
import 'package:todo_flutter/models/outbox_entry.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/outbox_repository.dart';
import 'package:todo_flutter/services/fault_injection_policy.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_local_state_coordinator.dart';

import '../models/task.dart';
import '../repositories/tasks_repository.dart';

typedef ConnectivityCheck = Future<List<ConnectivityResult>> Function();
typedef SessionCheck = bool Function();
typedef DelayExecution = Future<void> Function(Duration duration);

class _VolatileOutboxRepository implements OutboxRepository {
  OutboxStorageState _state = const OutboxStorageState(isInitialized: true);

  @override
  Future<void> clearState() async {
    _state = const OutboxStorageState(isInitialized: true);
  }

  @override
  Future<OutboxStorageState> loadState() async {
    return _state.copyWith(
      activeEntries: List<OutboxEntry>.from(_state.activeEntries),
      recentAcknowledgements: List<OutboxEntry>.from(
        _state.recentAcknowledgements,
      ),
    );
  }

  @override
  Future<void> saveState(OutboxStorageState state) async {
    _state = state.copyWith(
      activeEntries: List<OutboxEntry>.from(state.activeEntries),
      recentAcknowledgements: List<OutboxEntry>.from(
        state.recentAcknowledgements,
      ),
    );
  }
}

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

    return TaskModel.fromJson(
      existing,
    ).copyWith(syncStatus: SyncStatus.synced, hasRemoteBackingRecord: true);
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
        .map(
          (json) => TaskModel.fromJson(json).copyWith(
            syncStatus: SyncStatus.synced,
            hasRemoteBackingRecord: true,
          ),
        )
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
  final TaskLocalStateCoordinator _localStateCoordinator;

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
    required TaskLocalStateCoordinator localStateCoordinator,
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
       _delayExecution = delayExecution ?? Future<void>.delayed,
       _localStateCoordinator = localStateCoordinator;

  TaskSyncService.forTesting(
    this.repository, {
    required TaskRemoteDataSource remote,
    required ConnectivityCheck connectivityCheck,
    required SessionCheck hasActiveSession,
    DebounceController? debounceController,
    RuntimeDebugProvider? runtimeDebug,
    FaultInjectionPolicy? faultInjectionPolicy,
    DelayExecution? delayExecution,
    TaskLocalStateCoordinator? localStateCoordinator,
  }) : _remote = remote,
       _checkConnectivity = connectivityCheck,
       _hasActiveSession = hasActiveSession,
       _debouncedSync =
           debounceController ??
           DebounceController(debounceDuration: const Duration(seconds: 3)),
       _runtimeDebug = runtimeDebug,
       _faultInjectionPolicy = faultInjectionPolicy ?? FaultInjectionPolicy(),
       _delayExecution = delayExecution ?? Future<void>.delayed,
       _localStateCoordinator =
           localStateCoordinator ??
           TaskLocalStateCoordinator(
             TaskLocalSnapshotCoordinator.fromRepository(repository),
             _VolatileOutboxRepository(),
             runtimeDebug: runtimeDebug,
           );

  @override
  Future<TaskSyncRunResult> syncTasks(List<TaskModel> tasks) async {
    final localState = await _localStateCoordinator.loadState();
    final effectiveTasks = localState.tasks;

    final connectivityResult = _faultInjectionPolicy.applyConnectivityResults(
      await _checkConnectivity(),
    );
    _runtimeDebug?.setConnectivityResults(connectivityResult, logEvent: false);
    _runtimeDebug?.updateTaskCounts(effectiveTasks);
    _runtimeDebug?.updateOutboxState(localState.outboxState);

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
          tasks: effectiveTasks,
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
      await _persistLocalState(
        TaskLocalState(
          tasks: localState.tasks,
          outboxState: _updateEntriesForBlockedNoSession(
            localState.outboxState,
          ),
        ),
      );
      _runtimeDebug?.markSyncSkipped(
        phase: RuntimeSyncPhase.blockedNoSession,
        message: 'No authenticated session. Skipping sync.',
        payload: _buildSyncPayload(
          stage: 'Replay blocked',
          summary:
              'The sync pass is waiting for an authenticated session before any cloud replay can start.',
          tasks: effectiveTasks,
        ),
      );
      debugPrint('No user session. Skipping sync.');
      return const TaskSyncRunResult();
    }

    final plannedDelayDescription =
        _faultInjectionPolicy.plannedDelayDescription;
    final startMessage = plannedDelayDescription == null
        ? 'Synchronizing ${effectiveTasks.length} local task(s).'
        : 'Delayed sync scenario is active. $plannedDelayDescription Synchronizing ${effectiveTasks.length} local task(s).';

    _runtimeDebug?.markSyncStarted(
      startMessage,
      payload: _buildSyncPayload(
        stage: 'Replay started',
        summary:
            'The runtime is preparing local task mutations for cloud replay.',
        tasks: effectiveTasks,
        notes: [if (plannedDelayDescription != null) plannedDelayDescription],
      ),
    );
    await _applyInjectedPreSyncDelay(effectiveTasks);
    return _syncTasksWithOutbox(localState);
  }

  Future<TaskSyncRunResult> _syncTasksWithOutbox(
    TaskLocalState localState,
  ) async {
    try {
      final workingTasks = localState.tasks
          .map((task) => task.copyWith())
          .toList();
      var outboxState = _resetBlockedEntriesForReplay(localState.outboxState);
      final acknowledgedTasks = <TaskModel>[];
      final acknowledgedTaskDetails = <RuntimeEventTaskDetail>[];
      var hadRecoverableErrors = false;

      final orderedEntries = [...outboxState.activeEntries]
        ..sort((left, right) {
          final leftTime = left.firstQueuedAt ?? left.createdAt;
          final rightTime = right.firstQueuedAt ?? right.createdAt;
          return leftTime.compareTo(rightTime);
        });

      for (final entry in orderedEntries) {
        if (!_isReplayableEntry(entry)) {
          continue;
        }

        final sendingEntry = entry.copyWith(
          state: OutboxEntryState.sending,
          updatedAt: DateTime.now().toUtc(),
          lastAttemptAt: DateTime.now().toUtc(),
          attemptCount: entry.attemptCount + 1,
          lastError: null,
        );
        outboxState = _replaceActiveEntry(outboxState, sendingEntry);
        await _persistLocalState(
          TaskLocalState(tasks: workingTasks, outboxState: outboxState),
        );

        try {
          if (entry.operationType == OutboxOperationType.delete) {
            await _applyInjectedDelay(
              DelayedSyncTarget.deleteOperation,
              tasks: workingTasks,
              entry: sendingEntry,
            );
            await _remote.deleteTask(entry.taskId);
            workingTasks.removeWhere((task) => task.id == entry.taskId);
            await _applyInjectedDelay(
              DelayedSyncTarget.acknowledgement,
              tasks: workingTasks,
              entry: sendingEntry,
            );
            outboxState = _acknowledgeEntry(outboxState, sendingEntry);
            acknowledgedTaskDetails.add(
              RuntimeEventTaskDetail(
                title: _taskTitleForEntry(entry),
                taskId: entry.taskId,
                syncStatus: 'Deleted',
                outcome: 'Deleted remotely',
                description:
                    'A locally deleted task was confirmed and removed from the cloud record.',
              ),
            );
            continue;
          }

          final localTask = _taskFromEntry(entry, workingTasks);
          await _applyInjectedDelay(
            DelayedSyncTarget.fetchById,
            tasks: workingTasks,
            entry: sendingEntry,
            task: localTask,
          );
          final remoteTask = await _remote.fetchTaskById(entry.taskId);

          if (remoteTask == null) {
            await _applyInjectedDelay(
              DelayedSyncTarget.insert,
              tasks: workingTasks,
              entry: sendingEntry,
              task: localTask,
            );
            await _remote.insertTask(localTask);
            final acknowledgedTask = localTask.copyWith(
              syncStatus: SyncStatus.synced,
              hasRemoteBackingRecord: true,
            );
            _replaceTask(workingTasks, acknowledgedTask);
            acknowledgedTasks.add(acknowledgedTask);
            await _applyInjectedDelay(
              DelayedSyncTarget.acknowledgement,
              tasks: workingTasks,
              entry: sendingEntry,
              task: acknowledgedTask,
            );
            acknowledgedTaskDetails.add(
              _buildTaskDetail(
                acknowledgedTask,
                outcome: 'Created remotely',
                description:
                    'A local-only task was inserted into the remote task set.',
              ),
            );
            outboxState = _acknowledgeEntry(outboxState, sendingEntry);
            continue;
          }

          if (_isEntrySafeToApply(localTask, remoteTask, sendingEntry)) {
            await _applyInjectedDelay(
              DelayedSyncTarget.update,
              tasks: workingTasks,
              entry: sendingEntry,
              task: localTask,
            );
            await _remote.updateTask(localTask);
            final acknowledgedTask = localTask.copyWith(
              syncStatus: SyncStatus.synced,
              hasRemoteBackingRecord: true,
            );
            _replaceTask(workingTasks, acknowledgedTask);
            acknowledgedTasks.add(acknowledgedTask);
            await _applyInjectedDelay(
              DelayedSyncTarget.acknowledgement,
              tasks: workingTasks,
              entry: sendingEntry,
              task: acknowledgedTask,
            );
            acknowledgedTaskDetails.add(
              _buildTaskDetail(
                acknowledgedTask,
                outcome: 'Updated remotely',
                description:
                    'The local task version was newer and replaced the remote copy.',
                fieldDiffs: _buildTaskFieldDiffs(remoteTask, acknowledgedTask),
              ),
            );
            outboxState = _acknowledgeEntry(outboxState, sendingEntry);
            continue;
          }

          final conflictEntry = sendingEntry.copyWith(
            state: OutboxEntryState.conflict,
            updatedAt: DateTime.now().toUtc(),
            lastError:
                'Remote task changed since this outbox entry was queued.',
            remoteSnapshot: remoteTask.toJson(),
          );
          outboxState = _replaceActiveEntry(outboxState, conflictEntry);
          hadRecoverableErrors = true;
          _runtimeDebug?.addEvent(
            category: RuntimeEventCategory.sync,
            message: 'Task ${localTask.title} requires conflict review.',
            level: RuntimeEventLevel.warning,
            payload: _buildSyncPayload(
              stage: 'Conflict detected',
              summary:
                  'The remote task changed after this local outbox entry was queued, so the runtime blocked replay for review.',
              tasks: workingTasks,
              highlightedTasks: [
                _buildTaskDetail(
                  localTask,
                  outcome: 'Conflict',
                  description:
                      'Local replay stopped because the remote version is newer than the queued base snapshot.',
                  fieldDiffs: _buildTaskFieldDiffs(localTask, remoteTask),
                ),
              ],
            ),
          );
        } catch (error) {
          hadRecoverableErrors = true;
          final failedEntry = sendingEntry.copyWith(
            state: OutboxEntryState.failed,
            updatedAt: DateTime.now().toUtc(),
            lastError: error.toString(),
          );
          outboxState = _replaceActiveEntry(outboxState, failedEntry);
          _runtimeDebug?.addEvent(
            category: RuntimeEventCategory.sync,
            message:
                'Failed to replay ${entry.operationType.name} for ${_taskTitleForEntry(entry)}.',
            level: RuntimeEventLevel.warning,
            detail: error.toString(),
            payload: _buildSyncPayload(
              stage: 'Task replay failed',
              summary:
                  'The runtime could not replay this outbox entry to the remote store.',
              tasks: workingTasks,
              highlightedTasks: [
                RuntimeEventTaskDetail(
                  title: _taskTitleForEntry(entry),
                  taskId: entry.taskId,
                  syncStatus: sendingEntry.state.name,
                  outcome: 'Replay failed',
                  description:
                      'The entry remains queued for later review or retry.',
                ),
              ],
              notes: [error.toString()],
            ),
          );
        }

        await _persistLocalState(
          TaskLocalState(tasks: workingTasks, outboxState: outboxState),
        );
      }

      await _applyInjectedDelay(
        DelayedSyncTarget.fetchAllMerge,
        tasks: workingTasks,
      );
      final remoteTasks = await _remote.fetchAllTasks();
      final mergedTasks = _mergeRemoteTasksWithLocalState(
        workingTasks,
        remoteTasks,
      );
      await _persistLocalState(
        TaskLocalState(tasks: mergedTasks, outboxState: outboxState),
      );
      _runtimeDebug?.updateTaskCounts(mergedTasks);

      final summary =
          'Sync completed. ${acknowledgedTasks.length} task(s) acknowledged.';
      if (hadRecoverableErrors ||
          outboxState.activeEntries.any(_isBlockingEntry)) {
        _runtimeDebug?.markSyncPartial(
          '$summary Some operations need review.',
          payload: _buildSyncPayload(
            stage: 'Replay completed with review needed',
            summary:
                'The outbox replay pass finished, but one or more operations still need operator review.',
            tasks: mergedTasks,
            highlightedTasks: acknowledgedTaskDetails,
            extraMetrics: [
              RuntimeEventMetric(
                label: 'Acknowledged',
                value: acknowledgedTasks.length.toString(),
              ),
              RuntimeEventMetric(
                label: 'Remaining entries',
                value: outboxState.activeEntries.length.toString(),
              ),
            ],
          ),
        );
      } else {
        _runtimeDebug?.markSyncSuccess(
          summary,
          payload: _buildSyncPayload(
            stage: 'Replay completed',
            summary:
                'All replayable outbox entries in this pass were reconciled without warning-level issues.',
            tasks: mergedTasks,
            highlightedTasks: acknowledgedTaskDetails,
            extraMetrics: [
              RuntimeEventMetric(
                label: 'Acknowledged',
                value: acknowledgedTasks.length.toString(),
              ),
            ],
          ),
        );
      }

      return TaskSyncRunResult(
        acknowledgedTasks: acknowledgedTasks,
        hadRecoverableErrors: hadRecoverableErrors,
      );
    } catch (error) {
      _runtimeDebug?.markSyncFailure(
        'Sync failed: $error',
        payload: _buildSyncPayload(
          stage: 'Replay failed',
          summary:
              'The outbox replay pass stopped before completion because an unrecoverable error escaped the replay loop.',
          tasks: localState.tasks,
          notes: [error.toString()],
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
      final tasks = await _loadTasksLocally();
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

  Future<List<TaskModel>> _loadTasksLocally() {
    return _localStateCoordinator.loadTaskSnapshot();
  }

  Future<void> _persistLocalState(TaskLocalState state) async {
    await _localStateCoordinator.saveState(state);
  }

  OutboxStorageState _updateEntriesForBlockedNoSession(
    OutboxStorageState state,
  ) {
    return state.copyWith(
      activeEntries: state.activeEntries
          .map((entry) {
            if (entry.ownerScope == OutboxOwnerScope.anonymous ||
                entry.state == OutboxEntryState.conflict ||
                entry.state == OutboxEntryState.blockedAnonymousReview) {
              return entry;
            }

            return entry.copyWith(
              state: OutboxEntryState.blockedNoSession,
              updatedAt: DateTime.now().toUtc(),
            );
          })
          .toList(growable: false),
    );
  }

  OutboxStorageState _resetBlockedEntriesForReplay(OutboxStorageState state) {
    return state.copyWith(
      activeEntries: state.activeEntries
          .map((entry) {
            if (entry.state != OutboxEntryState.blockedNoSession &&
                entry.state != OutboxEntryState.failed &&
                entry.state != OutboxEntryState.sending) {
              return entry;
            }

            return entry.copyWith(
              state: OutboxEntryState.queued,
              updatedAt: DateTime.now().toUtc(),
              lastError: null,
            );
          })
          .toList(growable: false),
    );
  }

  bool _isReplayableEntry(OutboxEntry entry) {
    return entry.state == OutboxEntryState.queued ||
        entry.state == OutboxEntryState.failed ||
        entry.state == OutboxEntryState.blockedNoSession ||
        entry.state == OutboxEntryState.sending;
  }

  bool _isBlockingEntry(OutboxEntry entry) {
    return entry.state == OutboxEntryState.failed ||
        entry.state == OutboxEntryState.conflict ||
        entry.state == OutboxEntryState.blockedAnonymousReview ||
        entry.state == OutboxEntryState.blockedNoSession;
  }

  TaskModel _taskFromEntry(OutboxEntry entry, List<TaskModel> workingTasks) {
    final existingTask = workingTasks
        .where((task) => task.id == entry.taskId)
        .firstOrNull;
    if (existingTask != null) {
      return existingTask;
    }

    return TaskModel.fromJson(entry.taskPayload);
  }

  String _taskTitleForEntry(OutboxEntry entry) {
    return (entry.taskPayload['title'] as String?)?.trim().isNotEmpty == true
        ? entry.taskPayload['title'] as String
        : 'Untitled task';
  }

  bool _isEntrySafeToApply(
    TaskModel localTask,
    TaskModel remoteTask,
    OutboxEntry entry,
  ) {
    final baseRemoteUpdatedAt = entry.baseRemoteUpdatedAt;
    final remoteUpdatedAt = remoteTask.updatedAt ?? remoteTask.lastModifiedAt;
    if (baseRemoteUpdatedAt != null && remoteUpdatedAt != null) {
      return !remoteUpdatedAt.toUtc().isAfter(baseRemoteUpdatedAt.toUtc());
    }

    return _isLocalTaskNewer(localTask, remoteTask);
  }

  OutboxStorageState _replaceActiveEntry(
    OutboxStorageState state,
    OutboxEntry replacement,
  ) {
    return state.copyWith(
      activeEntries: state.activeEntries
          .map((entry) => entry.id == replacement.id ? replacement : entry)
          .toList(growable: false),
    );
  }

  OutboxStorageState _acknowledgeEntry(
    OutboxStorageState state,
    OutboxEntry entry,
  ) {
    final acknowledgedEntry = entry.copyWith(
      state: OutboxEntryState.acknowledged,
      updatedAt: DateTime.now().toUtc(),
      lastError: null,
    );

    return state.copyWith(
      activeEntries: state.activeEntries
          .where((candidate) => candidate.id != entry.id)
          .toList(growable: false),
      recentAcknowledgements: [
        acknowledgedEntry,
        ...state.recentAcknowledgements.where(
          (candidate) => candidate.id != acknowledgedEntry.id,
        ),
      ].take(10).toList(growable: false),
    );
  }

  List<TaskModel> _mergeRemoteTasksWithLocalState(
    List<TaskModel> workingTasks,
    List<TaskModel> remoteTasks,
  ) {
    final merged = <String, TaskModel>{
      for (final task in remoteTasks) task.id: task,
    };

    for (final task in workingTasks) {
      if (task.syncStatus != SyncStatus.synced) {
        merged[task.id] = task;
      }
    }

    final mergedTasks = merged.values.toList(growable: false)
      ..sort((left, right) => left.beginsAt.compareTo(right.beginsAt));
    return mergedTasks;
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
    await _applyInjectedDelay(DelayedSyncTarget.fullPass, tasks: tasks);
  }

  Future<void> _applyInjectedDelay(
    DelayedSyncTarget target, {
    required List<TaskModel> tasks,
    OutboxEntry? entry,
    TaskModel? task,
  }) async {
    final injection = _faultInjectionPolicy.injectionFor(target);
    if (injection == null) {
      return;
    }

    final message = _delayMessageForInjection(injection);
    final notes = <String>[_delaySummaryForInjection(injection)];
    if (injection.behavior == DelayedSyncBehavior.oneShot) {
      notes.add(
        'This one-shot delay will clear itself after the selected seam is exercised.',
      );
    }

    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.sync,
      message: message,
      level: RuntimeEventLevel.warning,
      payload: _buildSyncPayload(
        stage: 'Delayed sync at ${injection.target.label}',
        summary: _delaySummaryForInjection(injection),
        tasks: tasks,
        highlightedTasks: task == null
            ? const []
            : [
                _buildTaskDetail(
                  task,
                  outcome: 'Delay injected',
                  description:
                      'Replay is intentionally paused at ${injection.target.label.toLowerCase()} in ${injection.mode.label.toLowerCase()} mode.',
                ),
              ],
        extraMetrics: [
          RuntimeEventMetric(
            label: 'Injected delay',
            value: injection.durationLabel,
          ),
          RuntimeEventMetric(label: 'Mode', value: injection.mode.label),
          RuntimeEventMetric(label: 'Target', value: injection.target.label),
          RuntimeEventMetric(
            label: 'Behavior',
            value: injection.behavior.label,
          ),
          if (entry != null)
            RuntimeEventMetric(label: 'Outbox entry', value: entry.id),
          if (task != null)
            RuntimeEventMetric(label: 'Task id', value: task.id),
        ],
        notes: notes,
      ),
    );
    debugPrint(message);
    await _delayExecution(injection.duration);
    await _faultInjectionPolicy.consumeDelayedSyncIfNeeded(target);
  }

  String _delayMessageForInjection(DelayedSyncInjection injection) {
    switch (injection.mode) {
      case DelayedSyncMode.local:
        return 'Delayed sync scenario is holding the sync pass for ${injection.durationLabel} before remote replay begins.';
      case DelayedSyncMode.transport:
        return 'Delayed sync scenario is holding the ${injection.target.label.toLowerCase()} transport seam for ${injection.durationLabel} before replay continues.';
      case DelayedSyncMode.backend:
        return 'Delayed sync scenario is holding acknowledgement for ${injection.durationLabel} after remote success and before the outbox entry is acknowledged.';
    }
  }

  String _delaySummaryForInjection(DelayedSyncInjection injection) {
    switch (injection.mode) {
      case DelayedSyncMode.local:
        return 'The sync pass is intentionally paused before remote replay to make delayed convergence visible.';
      case DelayedSyncMode.transport:
        return 'A transport-shaped delay is intentionally pausing a named outbound replay seam so the outbox stays visibly in flight.';
      case DelayedSyncMode.backend:
        return 'A backend-shaped acknowledgement delay is intentionally pausing the replay pass after remote success so the outbox remains in sending longer.';
    }
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
