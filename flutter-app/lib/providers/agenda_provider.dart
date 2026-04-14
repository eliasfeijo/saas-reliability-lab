import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:todo_flutter/controllers/task_filter_controller.dart';
import 'package:todo_flutter/controllers/task_selection_controller.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'package:todo_flutter/services/user_session_service.dart';

class AgendaProvider extends ChangeNotifier {
  // Private fields

  // Task sync service for managing task synchronization
  // This service handles syncing tasks with the cloud and local storage.
  final TaskSyncService _taskSyncService;

  // User session service for managing user sessions
  final UserSessionService _userSession;
  final RuntimeDebugProvider? _runtimeDebug;

  // Filter controller for managing task filters
  final _filterController = TaskFilterController();
  // Selection controller for managing selected tasks
  final _selectionController = TaskSelectionController();

  final TasksRepository _repository;

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
    this._repository,
    this._taskSyncService,
    this._userSession, {
    RuntimeDebugProvider? runtimeDebug,
  }) : _runtimeDebug = runtimeDebug;

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
    _pruneLocallyDeletedAnonymousTasks();
    _pruneInteractionState();
    _publishTaskDebugState();
    notifyListeners();
  }

  set userId(String? userId) {
    _userId = userId;
    notifyListeners();
  }

  // Methods

  // Load user ID from SharedPreferences
  Future<void> loadUser() async {
    _isLoading = true;
    notifyListeners();

    _userId = await _userSession.loadUserId();
    // debugPrint('Loaded user ID: $_userId');

    _isLoading = false;
    notifyListeners();
  }

  // Save user ID to SharedPreferences
  Future<void> saveUser(String userId) async {
    await _userSession.saveUserId(userId);
    await loadUser(); // Reload user after saving
  }

  // Clear user ID from SharedPreferences
  Future<void> clearUser() async {
    await _userSession.clearUserId();
    _userId = null; // Clear the user ID in the provider
    notifyListeners();
  }

  // Loading from repository
  Future<void> loadTasks() async {
    final storedTasks = await _repository.loadTasks();
    _tasks
      ..clear()
      ..addAll(storedTasks);
    final didPrune = _pruneLocallyDeletedAnonymousTasks();
    _pruneInteractionState();
    if (didPrune) {
      await _repository.saveTasks(_tasks);
    }
    _publishTaskDebugState();
    notifyListeners();
  }

  // Task Management Methods
  Future<void> addTask(TaskModel task) async {
    task.userId = _userId; // Set user ID for the task
    task.dirty(); // Mark task as dirty for sync
    _tasks.add(task);
    await _saveTasks();
    _triggerSync(task); // Trigger sync immediately
  }

  Future<void> updateTask(TaskModel updatedTask) async {
    updatedTask.dirty(); // Mark task as dirty for sync
    final index = _tasks.indexWhere((task) => task.id == updatedTask.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      await _saveTasks();
      _triggerSync(updatedTask); // Trigger sync immediately
    }
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
    await _applyTaskUpdate([taskId], (task) {
      if (task.isCompleted) {
        return false;
      }
      task.markAsCompleted();
      return true;
    });
  }

  Future<void> reopenTask(String taskId) async {
    await _applyTaskUpdate([taskId], (task) {
      if (!task.isCompleted) {
        return false;
      }
      task.markAsPending();
      return true;
    });
  }

  Future<void> markSelectedTasksCompleted() async {
    await _applyTaskUpdate(_batchSelectedTaskIds, (task) {
      if (task.isCompleted) {
        return false;
      }
      task.markAsCompleted();
      return true;
    });
  }

  Future<void> reopenSelectedTasks() async {
    await _applyTaskUpdate(_batchSelectedTaskIds, (task) {
      if (!task.isCompleted) {
        return false;
      }
      task.markAsPending();
      return true;
    });
  }

  Future<void> deleteSelectedTasks() async {
    await _deleteTasksById(_batchSelectedTaskIds);
  }

  Future<void> clearAllTasks() async {
    _tasks.clear();
    await _repository.clearTasks();
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
    for (var task in _tasks) {
      if (!task.isCompleted) {
        task.markAsCompleted();
      }
    }
    notifyListeners();
  }

  void clearCompletedTasks() {
    // Clear selection if selected task is completed
    if (selectedTask?.isCompleted == true) {
      _selectionController.clear();
    }

    _tasks.removeWhere((task) => task.isCompleted);
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
    if (_userId == null) {
      debugPrint('No user ID found. Skipping task sync on login.');
      return;
    }
    if (hasPendingAnonymousReview) {
      _markSyncBlockedForAnonymousReview();
      debugPrint('Anonymous tasks pending review. Pausing cloud sync.');
      return;
    }
    if (_isLoading) {
      debugPrint('Sync already in progress. Skipping task sync.');
      return;
    }
    _isLoading = true;
    notifyListeners();
    debugPrint('Syncing all tasks...');
    await _taskSyncService.syncAllTasks(_tasks);
    await loadTasks(); // Reload tasks after sync
    debugPrint('All tasks synced.');
    _isLoading = false;
    notifyListeners();
  }

  // Trigger sync for a specific task
  void _triggerSync(TaskModel task) {
    if (_userId == null) {
      debugPrint('No user ID found. Skipping sync for task');
      return;
    }
    if (hasPendingAnonymousReview) {
      _markSyncBlockedForAnonymousReview();
      debugPrint('Anonymous tasks pending review. Skipping sync for task.');
      return;
    }
    if (_isLoading) {
      debugPrint('Sync already in progress. Skipping sync for task');
      return;
    }
    // debugPrint('Triggering sync for task: ${task.id}');
    // debugPrint('Task sync status: ${task.syncStatus}');
    _taskSyncService.syncIfLoggedIn(
      task.copyWith(), // Use a copy to avoid modifying the original task
      () {
        // Optional: handle before sync logic here
        _isLoading = true; // Set loading state before sync
        notifyListeners();
      },
      (List<TaskModel> syncedTasks) async {
        // Optional: handle synced tasks here
        await loadTasks(); // Reload tasks after sync
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> removeFromLocalStorage(List<TaskModel> tasks) async {
    // Remove tasks from the local storage
    for (var task in tasks) {
      _tasks.removeWhere((t) => t.id == task.id);
    }
    await _saveTasks();
  }

  Future<void> clearAllTasksFromLocalStorage() async {
    // Clear all tasks from local storage
    _tasks.clear();
    await _repository.clearTasks();
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
    // Take ownership of anonymous tasks by assigning the current user ID
    for (final task in anonymousTasks) {
      task.userId = _userId;
      task.dirty(); // Mark as dirty for sync
    }
    await _saveTasks();
    // Trigger sync for all tasks after taking ownership
    await syncAllTasks();
  }

  Future<void> _saveTasks() async {
    _pruneLocallyDeletedAnonymousTasks();
    _pruneInteractionState();
    await _repository.saveTasks(_tasks);
    _publishTaskDebugState();
    notifyListeners();
  }

  bool _pruneLocallyDeletedAnonymousTasks() {
    final initialCount = _tasks.length;
    _tasks.removeWhere(
      (task) => task.userId == null && task.syncStatus == SyncStatus.deleted,
    );
    return _tasks.length != initialCount;
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

  Future<void> _applyTaskUpdate(
    Iterable<String> taskIds,
    bool Function(TaskModel task) mutate,
  ) async {
    final targetIds = taskIds.toSet();
    if (targetIds.isEmpty) {
      return;
    }

    TaskModel? syncTask;
    var didChange = false;

    for (final task in _tasks) {
      if (!targetIds.contains(task.id)) {
        continue;
      }
      final changed = mutate(task);
      if (!changed) {
        continue;
      }
      syncTask ??= task;
      didChange = true;
    }

    if (!didChange || syncTask == null) {
      return;
    }

    await _saveTasks();
    _triggerSync(syncTask);
  }

  Future<void> _deleteTasksById(Iterable<String> taskIds) async {
    final targetIds = taskIds.toSet();
    if (targetIds.isEmpty) {
      return;
    }

    _selectionController.clear();
    TaskModel? syncTask;
    var didChange = false;

    _tasks.removeWhere((task) {
      if (!targetIds.contains(task.id)) {
        return false;
      }

      _batchSelectedTaskIds.remove(task.id);

      if (task.userId == null) {
        didChange = true;
        return true;
      }

      if (task.syncStatus == SyncStatus.deleted) {
        return false;
      }

      task.markAsDeleted();
      syncTask ??= task;
      didChange = true;
      return false;
    });

    if (!didChange) {
      return;
    }

    final syncTaskToTrigger = syncTask;
    await _saveTasks();

    if (syncTaskToTrigger != null) {
      _triggerSync(syncTaskToTrigger);
    }
  }

  void _publishTaskDebugState() {
    _runtimeDebug?.updateTaskCounts(_tasks);
  }

  void _markSyncBlockedForAnonymousReview() {
    _runtimeDebug?.markSyncSkipped(
      phase: RuntimeSyncPhase.blockedAnonymousReview,
      message:
          'Anonymous local tasks are waiting for review. Keep or discard them before cloud sync.',
    );
  }
}
