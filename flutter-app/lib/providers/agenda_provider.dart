import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:todo_flutter/controllers/task_filter_controller.dart';
import 'package:todo_flutter/controllers/task_selection_controller.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_mutation_coordinator.dart';
import 'package:todo_flutter/services/task_sync_coordinator.dart';
import 'package:todo_flutter/services/task_sync_service.dart';

class AgendaProvider extends ChangeNotifier {
  // Private fields

  // Task sync service for managing task synchronization
  // This service handles syncing tasks with the cloud and local storage.
  final TaskSyncCoordinator _taskSyncCoordinator;
  final RuntimeDebugProvider? _runtimeDebug;

  // Filter controller for managing task filters
  final _filterController = TaskFilterController();
  // Selection controller for managing selected tasks
  final _selectionController = TaskSelectionController();

  final TaskLocalSnapshotCoordinator _localSnapshotCoordinator;
  final TaskMutationCoordinator _taskMutationCoordinator;

  final List<TaskModel> _tasks = [];
  final Set<String> _batchSelectedTaskIds = <String>{};

  // User ID for cloud sync
  // This is used to identify the user for cloud sync operations.
  String? _userId;

  // Loading state
  bool _isLoading = false;
  bool _isBatchMode = false;

  // Constructor
  AgendaProvider(
    TasksRepository repository,
    TaskSyncService taskSyncService, {
    TaskSyncCoordinator? taskSyncCoordinator,
    TaskLocalSnapshotCoordinator? localSnapshotCoordinator,
    TaskMutationCoordinator? taskMutationCoordinator,
    RuntimeDebugProvider? runtimeDebug,
  }) : _taskSyncCoordinator =
            taskSyncCoordinator ??
            TaskSyncCoordinator(
              repository,
              taskSyncService,
              runtimeDebug: runtimeDebug,
            ),
        _localSnapshotCoordinator =
            localSnapshotCoordinator ?? TaskLocalSnapshotCoordinator(repository),
        _taskMutationCoordinator =
            taskMutationCoordinator ?? const TaskMutationCoordinator(),
        _runtimeDebug = runtimeDebug;

  // Getters

  List<TaskModel> get _activeTasks => _tasks
      .where((task) => task.syncStatus != SyncStatus.deleted)
      .toList(growable: false);

  List<TaskModel> get _storedAnonymousTasks =>
      _tasks.where((task) => task.userId == null).toList(growable: false);

  // This getter returns an unmodifiable list of tasks, filtering out those marked as deleted.
  // It ensures that the tasks list is read-only and cannot be modified directly.
  List<TaskModel> get tasks => List.unmodifiable(_activeTasks);

  /// Return tasks that are not associated with any user
  List<TaskModel> get anonymousTasks =>
      _activeTasks.where((task) => task.userId == null).toList(growable: false);

  // Getters for filtered tasks, search query, and current filter
  // These getters provide access to the filtered tasks based on the current search query and filter.
  List<TaskModel> get filteredTasks => _filterController.apply(_activeTasks);
  String get searchQuery => _filterController.searchQuery;
  TaskFilter get currentFilter => _filterController.filter;
  TaskSort get currentSort => _filterController.sort;
  bool get isLoading => _isLoading;
  String? get userId => _userId;
  bool get hasPendingAnonymousReview =>
      _userId != null && _userId!.isNotEmpty && anonymousTasks.isNotEmpty;

  // Getters for task selection
  TaskModel? get selectedTask => _selectionController.selected;
  bool get hasSelectedTask => selectedTask != null;
  bool get isTaskSelected => selectedTask != null;
  bool get isBatchMode => _isBatchMode;
  bool get hasBatchSelection => batchSelectedCount > 0;
  int get batchSelectedCount => selectedBatchTasks.length;
  List<TaskModel> get selectedBatchTasks => _activeTasks
      .where((task) => _batchSelectedTaskIds.contains(task.id))
      .toList(growable: false);

  // Getters for task counts
  // These getters provide various counts of tasks based on their status.
  int get totalTasks => _activeTasks.length;
  int get completedTasksCount =>
      _activeTasks.where((task) => task.isCompleted).length;
  int get pendingTasksCount =>
      _activeTasks.where((task) => !task.isCompleted).length;
  int get todayTasksCount => _activeTasks.where((task) => task.isToday).length;
  int get overdueTasksCount =>
      _activeTasks.where((task) => task.isOverdue).length;

  // Setters

  // Sets the list of tasks and notifies listeners.
  set tasks(List<TaskModel> tasks) {
    _tasks.clear();
    _tasks.addAll(tasks);
    _pruneInteractionState();
    _publishTaskDebugState();
    notifyListeners();
  }

  set userId(String? userId) {
    _userId = userId;
    notifyListeners();
  }

  // Methods

  // Loading from repository
  Future<void> loadTasks() async {
    final storedTasks = await _localSnapshotCoordinator.loadSnapshot();
    _tasks
      ..clear()
      ..addAll(storedTasks);
    _pruneInteractionState();
    _publishTaskDebugState();
    notifyListeners();
  }

  // Task Management Methods
  Future<void> addTask(TaskModel task) async {
    final result = _taskMutationCoordinator.addTask(
      _tasks,
      task,
      userId: _userId,
    );
    await _persistMutationResult(result);
  }

  Future<void> updateTask(TaskModel updatedTask) async {
    final result = _taskMutationCoordinator.updateTask(_tasks, updatedTask);
    await _persistMutationResult(result);
  }

  Future<void> deleteTask(String taskId) async {
    await _deleteTasksById([taskId]);
  }

  Future<void> toggleTaskCompletion(String taskId) async {
    final task = getTaskById(taskId);
    if (task == null) {
      return;
    }

    if (task.isCompleted) {
      await reopenTask(taskId);
      return;
    }

    await markTaskCompleted(taskId);
  }

  Future<void> markTaskCompleted(String taskId) async {
    await _persistMutationResult(
      _taskMutationCoordinator.setCompletionState(
        _tasks,
        [taskId],
        isCompleted: true,
      ),
    );
  }

  Future<void> reopenTask(String taskId) async {
    await _persistMutationResult(
      _taskMutationCoordinator.setCompletionState(
        _tasks,
        [taskId],
        isCompleted: false,
      ),
    );
  }

  Future<void> markSelectedTasksCompleted() async {
    await _persistMutationResult(
      _taskMutationCoordinator.setCompletionState(
        _tasks,
        _batchSelectedTaskIds,
        isCompleted: true,
      ),
    );
  }

  Future<void> reopenSelectedTasks() async {
    await _persistMutationResult(
      _taskMutationCoordinator.setCompletionState(
        _tasks,
        _batchSelectedTaskIds,
        isCompleted: false,
      ),
    );
  }

  Future<void> deleteSelectedTasks() async {
    await _deleteTasksById(_batchSelectedTaskIds);
  }

  Future<void> clearAllTasks() async {
    final clearedTasks = await _localSnapshotCoordinator.clearSnapshot();
    _tasks
      ..clear()
      ..addAll(clearedTasks);
    _publishTaskDebugState();
    notifyListeners();
  }

  // Selected Task Management
  void selectTask(TaskModel task) {
    if (_isBatchMode) {
      return;
    }
    _selectionController.select(task);
    notifyListeners();
  }

  void clearSelection() {
    _selectionController.clear();
    notifyListeners();
  }

  void enterBatchMode() {
    if (_isBatchMode) {
      return;
    }
    _isBatchMode = true;
    _selectionController.clear();
    _batchSelectedTaskIds.clear();
    notifyListeners();
  }

  void exitBatchMode() {
    if (!_isBatchMode && _batchSelectedTaskIds.isEmpty) {
      return;
    }
    _isBatchMode = false;
    _batchSelectedTaskIds.clear();
    notifyListeners();
  }

  void toggleTaskInBatchSelection(String taskId) {
    if (!_isBatchMode) {
      return;
    }
    if (_batchSelectedTaskIds.contains(taskId)) {
      _batchSelectedTaskIds.remove(taskId);
    } else if (isTaskInFiltered(taskId)) {
      _batchSelectedTaskIds.add(taskId);
    }
    notifyListeners();
  }

  void selectAllVisibleTasks() {
    if (!_isBatchMode) {
      return;
    }
    _batchSelectedTaskIds
      ..clear()
      ..addAll(filteredTasks.map((task) => task.id));
    notifyListeners();
  }

  void clearBatchSelection() {
    if (_batchSelectedTaskIds.isEmpty) {
      return;
    }
    _batchSelectedTaskIds.clear();
    notifyListeners();
  }

  bool isTaskBatchSelected(String taskId) {
    return _batchSelectedTaskIds.contains(taskId);
  }

  // Filter Management

  void setFilter(TaskFilter filter) {
    _filterController.setFilter(filter);
    _resetInteractionForViewChange();
    notifyListeners();
  }

  // Search and Filter Methods
  void updateSearchQuery(String query) {
    _filterController.updateSearch(query);
    _resetInteractionForViewChange();
    notifyListeners();
  }

  void clearSearch() {
    _filterController.clearSearch();
    _resetInteractionForViewChange();
    notifyListeners();
  }

  void clearFilter() {
    _filterController.clearFilter();
    _resetInteractionForViewChange();
    notifyListeners();
  }

  void setSort(TaskSort sort) {
    if (_filterController.sort == sort) {
      return;
    }

    _filterController.setSort(sort);
    _pruneInteractionState();
    notifyListeners();
  }

  // Bulk Operations
  void markAllAsCompleted() {
    final result = _taskMutationCoordinator.markAllCompleted(_tasks);
    _replaceTasks(result.tasks);
    notifyListeners();
  }

  void clearCompletedTasks() {
    // Clear selection if selected task is completed
    if (selectedTask?.isCompleted == true) {
      _selectionController.clear();
    }

    final result = _taskMutationCoordinator.clearCompletedTasks(_tasks);
    _replaceTasks(result.tasks);
    _publishTaskDebugState();
    notifyListeners();
  }

  // Utility Methods
  TaskModel? getTaskById(String id) {
    try {
      return _tasks.firstWhere((task) => task.id == id);
    } catch (e) {
      return null;
    }
  }

  bool isTaskInFiltered(String taskId) {
    return filteredTasks.any((task) => task.id == taskId);
  }

  // Debug helper
  void printTasks() {
    debugPrint('=== AGENDA DEBUG ===');
    debugPrint('Total tasks: ${_tasks.length}');
    debugPrint('Selected task: ${selectedTask?.title ?? 'None'}');
    debugPrint('Current filter: $currentFilter');
    debugPrint('Current sort: $currentSort');
    debugPrint('Search query: "$searchQuery"');
    debugPrint('Filtered tasks: ${filteredTasks.length}');
    for (var task in _tasks) {
      debugPrint('- ${task.title} (${task.isCompleted ? 'Done' : 'Pending'})');
    }
    debugPrint('==================');
  }

  // Refresh method
  void refresh() {
    // This method can be used to trigger a UI refresh if needed
    notifyListeners();
  }

  // Sync Methods

  // Sync all tasks (e.g.: on user login)
  Future<void> syncAllTasks() async {
    await _taskSyncCoordinator.syncAllTasks(
      tasks: _tasks,
      userId: _userId,
      hasPendingAnonymousReview: hasPendingAnonymousReview,
      isLoading: _isLoading,
      setLoading: _setLoading,
      onTasksReloaded: _replaceTasksAfterSync,
    );
  }

  // Trigger sync for a specific task
  void _triggerSync(TaskModel task) {
    _taskSyncCoordinator.triggerTaskSync(
      task: task,
      userId: _userId,
      hasPendingAnonymousReview: hasPendingAnonymousReview,
      isLoading: _isLoading,
      setLoading: _setLoading,
      onTasksReloaded: _replaceTasksAfterSync,
    );
  }

  Future<void> removeFromLocalStorage(List<TaskModel> tasks) async {
    final nextTasks = await _localSnapshotCoordinator.removeTaskIds(
      _tasks,
      tasks.map((task) => task.id),
    );
    _tasks
      ..clear()
      ..addAll(nextTasks);
    _pruneInteractionState();
    _publishTaskDebugState();
    notifyListeners();
  }

  Future<void> clearAllTasksFromLocalStorage() async {
    final clearedTasks = await _localSnapshotCoordinator.clearSnapshot();
    _tasks
      ..clear()
      ..addAll(clearedTasks);
    _publishTaskDebugState();
    notifyListeners();
  }

  Future<void> discardAnonymousTasks() async {
    final tasksToDiscard = List<TaskModel>.from(_storedAnonymousTasks);
    if (tasksToDiscard.isEmpty) {
      return;
    }

    await removeFromLocalStorage(tasksToDiscard);

    if (_userId != null && _userId!.isNotEmpty) {
      await syncAllTasks();
    }
  }

  Future<void> takeOwnershipOfAnonymousTasks() async {
    if (_userId == null || _userId!.isEmpty) {
      debugPrint('No authenticated user available to adopt anonymous tasks.');
      return;
    }
    final result = _taskMutationCoordinator.adoptAnonymousTasks(
      _tasks,
      userId: _userId,
    );
    if (!result.didChange) {
      return;
    }
    _replaceTasks(result.tasks);
    await _saveTasks();
    // Trigger sync for all tasks after taking ownership
    await syncAllTasks();
  }

  Future<void> _saveTasks() async {
    final storedTasks = await _localSnapshotCoordinator.saveSnapshot(_tasks);
    _tasks
      ..clear()
      ..addAll(storedTasks);
    _pruneInteractionState();
    _publishTaskDebugState();
    notifyListeners();
  }

  void _setLoading(bool isLoading) {
    if (_isLoading == isLoading) {
      return;
    }

    _isLoading = isLoading;
    notifyListeners();
  }

  Future<void> _replaceTasksAfterSync(List<TaskModel> tasks) async {
    _replaceTasks(tasks);
    _pruneInteractionState();
    _publishTaskDebugState();
    notifyListeners();
  }

  void _replaceTasks(List<TaskModel> tasks) {
    _tasks
      ..clear()
      ..addAll(tasks);
  }

  Future<void> _persistMutationResult(TaskMutationResult result) async {
    if (!result.didChange) {
      return;
    }

    _replaceTasks(result.tasks);
    await _saveTasks();

    if (result.syncTask != null) {
      _triggerSync(result.syncTask!);
    }
  }

  void _resetInteractionForViewChange() {
    _selectionController.clear();
    if (_isBatchMode) {
      _batchSelectedTaskIds.clear();
    }
  }

  void _pruneInteractionState() {
    final activeTaskIds = _activeTasks.map((task) => task.id).toSet();
    if (selectedTask != null && !activeTaskIds.contains(selectedTask!.id)) {
      _selectionController.clear();
    }

    if (!_isBatchMode) {
      _batchSelectedTaskIds.clear();
      return;
    }

    if (_batchSelectedTaskIds.isEmpty) {
      if (activeTaskIds.isEmpty) {
        _isBatchMode = false;
      }
      return;
    }

    final visibleTaskIds = filteredTasks.map((task) => task.id).toSet();
    _batchSelectedTaskIds.removeWhere(
      (taskId) =>
          !activeTaskIds.contains(taskId) || !visibleTaskIds.contains(taskId),
    );

    if (activeTaskIds.isEmpty) {
      _isBatchMode = false;
    }
  }

  Future<void> _deleteTasksById(Iterable<String> taskIds) async {
    final targetIds = taskIds.toSet();
    if (targetIds.isEmpty) {
      return;
    }

    _selectionController.clear();
    _batchSelectedTaskIds.removeWhere(targetIds.contains);
    await _persistMutationResult(
      _taskMutationCoordinator.deleteTasks(_tasks, targetIds),
    );
  }

  void _publishTaskDebugState() {
    _runtimeDebug?.updateTaskCounts(_tasks);
  }
}
