import 'package:todo_flutter/models/outbox_entry.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/outbox_repository.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';

class TaskLocalState {
  const TaskLocalState({
    required this.tasks,
    required this.outboxState,
    this.didMigrateLegacySyncState = false,
  });

  final List<TaskModel> tasks;
  final OutboxStorageState outboxState;
  final bool didMigrateLegacySyncState;
}

class TaskLocalStateCoordinator {
  TaskLocalStateCoordinator(
    this._snapshotCoordinator,
    this._outboxRepository, {
    RuntimeDebugProvider? runtimeDebug,
  }) : _runtimeDebug = runtimeDebug;

  factory TaskLocalStateCoordinator.fromRepository(
    TasksRepository repository, {
    OutboxRepository? outboxRepository,
    RuntimeDebugProvider? runtimeDebug,
  }) {
    final snapshotCoordinator = TaskLocalSnapshotCoordinator.fromRepository(
      repository,
    );

    return TaskLocalStateCoordinator(
      snapshotCoordinator,
      outboxRepository ?? SharedPreferencesOutboxRepository(),
      runtimeDebug: runtimeDebug,
    );
  }

  final TaskLocalSnapshotCoordinator _snapshotCoordinator;
  final OutboxRepository _outboxRepository;
  final RuntimeDebugProvider? _runtimeDebug;

  Future<List<TaskModel>> clearLocalState() async {
    final clearedTasks = await _snapshotCoordinator.clearSnapshot();
    const clearedOutboxState = OutboxStorageState(isInitialized: true);
    await _outboxRepository.saveState(clearedOutboxState);
    _runtimeDebug?.updateOutboxState(clearedOutboxState);
    return clearedTasks;
  }

  Future<TaskLocalState> loadState() async {
    final tasks = await _snapshotCoordinator.loadSnapshot();

    final currentState = await _outboxRepository.loadState();
    if (currentState.isInitialized) {
      _runtimeDebug?.updateOutboxState(currentState);
      return TaskLocalState(tasks: tasks, outboxState: currentState);
    }

    return _persistDerivedLegacyOutbox(tasks, logMigrationEvent: true);
  }

  Future<OutboxStorageState> loadOutboxState() async {
    return (await loadState()).outboxState;
  }

  Future<List<TaskModel>> loadTaskSnapshot() async {
    return (await loadState()).tasks;
  }

  Future<List<TaskModel>> removeTaskIds(
    List<TaskModel> tasks,
    Iterable<String> taskIds,
  ) async {
    final nextTasks = await _snapshotCoordinator.removeTaskIds(tasks, taskIds);
    await _rebuildOutboxStateForTasks(nextTasks, changedTaskIds: taskIds);
    return nextTasks;
  }

  Future<List<TaskModel>> saveTaskSnapshot(
    List<TaskModel> tasks, {
    Iterable<String> changedTaskIds = const <String>[],
  }) async {
    final storedTasks = await _snapshotCoordinator.saveSnapshot(tasks);
    await _rebuildOutboxStateForTasks(
      storedTasks,
      changedTaskIds: changedTaskIds,
    );
    return storedTasks;
  }

  Future<void> saveState(TaskLocalState state) async {
    await _snapshotCoordinator.saveSnapshot(state.tasks);
    await _outboxRepository.saveState(state.outboxState);
    _runtimeDebug?.updateOutboxState(state.outboxState);
  }

  Future<void> saveOutboxState(OutboxStorageState state) {
    _runtimeDebug?.updateOutboxState(state);
    return _outboxRepository.saveState(state);
  }

  Future<void> clearRecentAcknowledgements() async {
    final currentState = await _outboxRepository.loadState();
    final nextState = currentState.copyWith(
      recentAcknowledgements: const <OutboxEntry>[],
    );
    await _outboxRepository.saveState(nextState);
    _runtimeDebug?.updateOutboxState(nextState);
  }

  Future<List<TaskModel>> resolveConflictKeepingRemote(String taskId) async {
    final currentState = await loadState();
    final conflictEntry = currentState.outboxState.activeEntries
        .where(
          (entry) =>
              entry.taskId == taskId &&
              entry.state == OutboxEntryState.conflict,
        )
        .firstOrNull;
    if (conflictEntry == null) {
      return currentState.tasks;
    }

    final remoteTask = _taskFromRemoteSnapshot(conflictEntry.remoteSnapshot);
    final nextTasks = [...currentState.tasks];

    if (remoteTask != null) {
      _replaceTask(nextTasks, remoteTask);
    } else {
      nextTasks.removeWhere((task) => task.id == taskId);
    }

    final nextOutboxState = currentState.outboxState.copyWith(
      activeEntries: currentState.outboxState.activeEntries
          .where((entry) => entry.id != conflictEntry.id)
          .toList(growable: false),
    );

    await saveState(
      TaskLocalState(tasks: nextTasks, outboxState: nextOutboxState),
    );
    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.sync,
      message:
          'Conflict for ${_taskTitleForEntry(conflictEntry)} was resolved by keeping remote state.',
      payload: const RuntimeEventPayload(
        stage: 'Conflict resolved',
        summary:
            'The operator discarded the local conflicting intent and retained the remote task state.',
      ),
    );
    return nextTasks;
  }

  Future<List<TaskModel>> reapplyConflictAsQueued(String taskId) async {
    final currentState = await loadState();
    final conflictEntry = currentState.outboxState.activeEntries
        .where(
          (entry) =>
              entry.taskId == taskId &&
              entry.state == OutboxEntryState.conflict,
        )
        .firstOrNull;
    if (conflictEntry == null) {
      return currentState.tasks;
    }

    final remoteTask = _taskFromRemoteSnapshot(conflictEntry.remoteSnapshot);
    final baseRemoteUpdatedAt =
        remoteTask?.updatedAt?.toUtc() ?? remoteTask?.lastModifiedAt?.toUtc();
    final nextTasks = [...currentState.tasks];
    final localTask =
        nextTasks.where((task) => task.id == taskId).firstOrNull ??
        TaskModel.fromJson(conflictEntry.taskPayload);
    final nextTask = localTask.copyWith(
      syncStatus: SyncStatus.dirty,
      updatedAt: baseRemoteUpdatedAt?.toLocal(),
      hasRemoteBackingRecord: true,
      userId: remoteTask?.userId ?? localTask.userId,
    );
    _replaceTask(nextTasks, nextTask);

    final nextOutboxState = currentState.outboxState.copyWith(
      activeEntries: currentState.outboxState.activeEntries
          .map((entry) {
            if (entry.id != conflictEntry.id) {
              return entry;
            }

            return entry.copyWith(
              state: OutboxEntryState.queued,
              updatedAt: DateTime.now().toUtc(),
              firstQueuedAt: DateTime.now().toUtc(),
              lastAttemptAt: null,
              attemptCount: 0,
              lastError: null,
              baseRemoteUpdatedAt: baseRemoteUpdatedAt,
              taskPayload: nextTask.toJson(),
              remoteSnapshot: null,
            );
          })
          .toList(growable: false),
    );

    await saveState(
      TaskLocalState(tasks: nextTasks, outboxState: nextOutboxState),
    );
    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.sync,
      message:
          'Conflict for ${_taskTitleForEntry(conflictEntry)} was re-queued with the latest remote base.',
      payload: const RuntimeEventPayload(
        stage: 'Conflict re-queued',
        summary:
            'The operator kept the local intent, refreshed its remote base, and queued it for another replay attempt.',
      ),
    );
    return nextTasks;
  }

  List<OutboxEntry> _buildLegacyEntries(List<TaskModel> tasks) {
    final entries = <OutboxEntry>[];

    for (final task in tasks) {
      if (task.userId == null) {
        entries.add(
          OutboxEntry(
            taskId: task.id,
            operationType: OutboxOperationType.upsert,
            state: OutboxEntryState.blockedAnonymousReview,
            ownerScope: OutboxOwnerScope.anonymous,
            firstQueuedAt: task.lastModifiedAt?.toUtc(),
            baseRemoteUpdatedAt: task.updatedAt?.toUtc(),
            taskPayload: task.toJson(),
          ),
        );
        continue;
      }

      if (task.syncStatus == SyncStatus.dirty) {
        entries.add(
          OutboxEntry(
            taskId: task.id,
            operationType: OutboxOperationType.upsert,
            state: OutboxEntryState.queued,
            ownerScope: OutboxOwnerScope.authenticated,
            firstQueuedAt: task.lastModifiedAt?.toUtc(),
            baseRemoteUpdatedAt: task.updatedAt?.toUtc(),
            taskPayload: task.toJson(),
          ),
        );
        continue;
      }

      if (task.syncStatus == SyncStatus.deleted) {
        entries.add(
          OutboxEntry(
            taskId: task.id,
            operationType: OutboxOperationType.delete,
            state: OutboxEntryState.queued,
            ownerScope: OutboxOwnerScope.authenticated,
            firstQueuedAt: task.lastModifiedAt?.toUtc(),
            baseRemoteUpdatedAt: task.updatedAt?.toUtc(),
            taskPayload: task.toJson(),
          ),
        );
      }
    }

    return entries;
  }

  void _logLegacyMigration(List<TaskModel> tasks, List<OutboxEntry> entries) {
    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.storage,
      message:
          'Initialized explicit outbox storage from legacy local sync markers.',
      payload: RuntimeEventPayload(
        stage: 'Legacy sync migration',
        summary:
            'The runtime derived an initial explicit outbox from the existing locally persisted task snapshot.',
        metrics: [
          RuntimeEventMetric(
            label: 'Visible tasks',
            value: tasks.length.toString(),
          ),
          RuntimeEventMetric(
            label: 'Derived outbox entries',
            value: entries.length.toString(),
          ),
        ],
      ),
    );
  }

  Future<TaskLocalState> _persistDerivedLegacyOutbox(
    List<TaskModel> tasks, {
    bool logMigrationEvent = false,
  }) async {
    final currentState = await _outboxRepository.loadState();
    final nextEntries = _buildLegacyEntries(tasks);
    final didMigrate = !currentState.isInitialized;
    final nextState = currentState.copyWith(
      isInitialized: true,
      activeEntries: nextEntries,
    );

    await _outboxRepository.saveState(nextState);
    _runtimeDebug?.updateOutboxState(nextState);

    if (logMigrationEvent && didMigrate) {
      _logLegacyMigration(tasks, nextEntries);
    }

    return TaskLocalState(
      tasks: tasks,
      outboxState: nextState,
      didMigrateLegacySyncState: didMigrate,
    );
  }

  Future<OutboxStorageState> _rebuildOutboxStateForTasks(
    List<TaskModel> tasks, {
    Iterable<String> changedTaskIds = const <String>[],
  }) async {
    final currentState = await _outboxRepository.loadState();
    final changedIds = changedTaskIds.toSet();
    final currentEntriesByTaskId = {
      for (final entry in currentState.activeEntries) entry.taskId: entry,
    };
    final nextEntries = <OutboxEntry>[];

    for (final task in tasks) {
      final nextEntry = _buildActiveEntryForTask(
        task,
        existingEntry: currentEntriesByTaskId[task.id],
        resetState: changedIds.contains(task.id),
      );

      if (nextEntry != null) {
        nextEntries.add(nextEntry);
      }
    }

    final nextState = currentState.copyWith(
      isInitialized: true,
      activeEntries: nextEntries,
    );
    await _outboxRepository.saveState(nextState);
    _runtimeDebug?.updateOutboxState(nextState);
    return nextState;
  }

  OutboxEntry? _buildActiveEntryForTask(
    TaskModel task, {
    OutboxEntry? existingEntry,
    required bool resetState,
  }) {
    final now = DateTime.now().toUtc();

    if (task.userId == null) {
      return _buildEntry(
        task,
        existingEntry: existingEntry,
        resetState: resetState,
        operationType: OutboxOperationType.upsert,
        state: OutboxEntryState.blockedAnonymousReview,
        ownerScope: OutboxOwnerScope.anonymous,
      );
    }

    if (task.syncStatus == SyncStatus.synced) {
      return null;
    }

    if (task.syncStatus == SyncStatus.deleted && !task.hasRemoteBackingRecord) {
      return null;
    }

    final operationType = task.syncStatus == SyncStatus.deleted
        ? OutboxOperationType.delete
        : OutboxOperationType.upsert;

    if (existingEntry != null &&
        !resetState &&
        existingEntry.operationType == operationType) {
      return existingEntry.copyWith(
        updatedAt: now,
        ownerScope: OutboxOwnerScope.authenticated,
        taskPayload: task.toJson(),
        baseRemoteUpdatedAt: task.updatedAt?.toUtc(),
      );
    }

    return _buildEntry(
      task,
      existingEntry: existingEntry,
      resetState: true,
      operationType: operationType,
      state: OutboxEntryState.queued,
      ownerScope: OutboxOwnerScope.authenticated,
    );
  }

  OutboxEntry _buildEntry(
    TaskModel task, {
    OutboxEntry? existingEntry,
    required bool resetState,
    required OutboxOperationType operationType,
    required OutboxEntryState state,
    required OutboxOwnerScope ownerScope,
  }) {
    final now = DateTime.now().toUtc();
    if (existingEntry != null && !resetState) {
      return existingEntry.copyWith(
        state: state,
        ownerScope: ownerScope,
        updatedAt: now,
        taskPayload: task.toJson(),
        baseRemoteUpdatedAt: task.updatedAt?.toUtc(),
      );
    }

    return OutboxEntry(
      id: existingEntry?.id,
      taskId: task.id,
      operationType: operationType,
      state: state,
      ownerScope: ownerScope,
      createdAt: existingEntry?.createdAt,
      updatedAt: now,
      firstQueuedAt: task.lastModifiedAt?.toUtc() ?? now,
      attemptCount: 0,
      lastError: null,
      baseRemoteUpdatedAt: task.updatedAt?.toUtc(),
      taskPayload: task.toJson(),
      remoteSnapshot: null,
    );
  }

  TaskModel? _taskFromRemoteSnapshot(Map<String, dynamic>? snapshot) {
    if (snapshot == null) {
      return null;
    }

    return TaskModel.fromJson(
      snapshot,
    ).copyWith(syncStatus: SyncStatus.synced, hasRemoteBackingRecord: true);
  }

  String _taskTitleForEntry(OutboxEntry entry) {
    return (entry.taskPayload['title'] as String?)?.trim().isNotEmpty == true
        ? entry.taskPayload['title'] as String
        : 'Untitled task';
  }

  void _replaceTask(List<TaskModel> tasks, TaskModel task) {
    final index = tasks.indexWhere((candidate) => candidate.id == task.id);
    if (index == -1) {
      tasks.add(task);
      return;
    }

    tasks[index] = task;
  }
}
