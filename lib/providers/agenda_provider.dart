import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:todo_flutter/controllers/task_filter_controller.dart';
import 'package:todo_flutter/controllers/task_selection_controller.dart';
import 'package:todo_flutter/models/task.dart';
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

  // Filter controller for managing task filters
  final _filterController = TaskFilterController();
  // Selection controller for managing selected tasks
  final _selectionController = TaskSelectionController();

  final TasksRepository _repository;

  final List<TaskModel> _tasks = [];

  // User ID for cloud sync
  // This is used to identify the user for cloud sync operations.
  String? _userId;

  // Loading state
  bool _isLoading = false;

  // Constructor
  AgendaProvider(this._repository, this._taskSyncService, this._userSession);

  // Getters

  // This getter returns an unmodifiable list of tasks, filtering out those marked as deleted.
  // It ensures that the tasks list is read-only and cannot be modified directly.
  List<TaskModel> get tasks => List.unmodifiable(
    _tasks.where((task) {
      // Filter out tasks that are marked as deleted
      return task.syncStatus != SyncStatus.deleted;
    }),
  );

  // List<TaskModel> get anonymousTasks {
  //   // Return tasks that are not associated with any user
  //   return _tasks.where((task) => task.userId == null).toList();
  // }

  // Getters for filtered tasks, search query, and current filter
  // These getters provide access to the filtered tasks based on the current search query and filter.
  List<TaskModel> get filteredTasks => _filterController.apply(_tasks);
  String get searchQuery => _filterController.searchQuery;
  TaskFilter get currentFilter => _filterController.filter;
  bool get isLoading => _isLoading;
  String? get userId => _userId;

  // Getters for task selection
  TaskModel? get selectedTask => _selectionController.selected;
  bool get hasSelectedTask => selectedTask != null;
  bool get isTaskSelected => selectedTask != null;

  // Getters for task counts
  // These getters provide various counts of tasks based on their status.
  int get totalTasks => _tasks.length;
  int get completedTasksCount =>
      _tasks.where((task) => task.isCompleted).length;
  int get pendingTasksCount => _tasks.where((task) => !task.isCompleted).length;
  int get todayTasksCount => _tasks.where((task) => task.isToday).length;
  int get overdueTasksCount => _tasks.where((task) => task.isOverdue).length;

  // Setters

  // Sets the list of tasks and notifies listeners.
  set tasks(List<TaskModel> tasks) {
    _tasks.clear();
    _tasks.addAll(tasks);
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

  // Loading from repository
  Future<void> loadTasks() async {
    final storedTasks = await _repository.loadTasks();
    _tasks
      ..clear()
      ..addAll(storedTasks);
    notifyListeners();
  }

  // Task Management Methods
  Future<void> addTask(TaskModel task) async {
    task.userId = _userId; // Set user ID for the task
    task.dirty(); // Mark task as dirty for sync
    _tasks.add(task);
    await _repository.saveTasks(_tasks);
    notifyListeners();
    _triggerSync(task); // Trigger sync immediately
  }

  Future<void> updateTask(TaskModel updatedTask) async {
    updatedTask.dirty(); // Mark task as dirty for sync
    final index = _tasks.indexWhere((task) => task.id == updatedTask.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      await _repository.saveTasks(_tasks);
      notifyListeners();
      _triggerSync(updatedTask); // Trigger sync immediately
    }
  }

  Future<void> deleteTask(String taskId) async {
    // debugPrint('Marking task $taskId as deleted');
    // Mark the task as deleted instead of removing it
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) {
      // debugPrint('Task with ID $taskId not found');
      return;
    }
    _tasks[index].markAsDeleted();
    // Clear selection if deleted task was selected
    if (selectedTask?.id == taskId) {
      _selectionController.clear();
    }
    await _repository.saveTasks(_tasks);
    notifyListeners();
    _triggerSync(_tasks[index]); // Trigger sync immediately
  }

  Future<void> toggleTaskCompletion(String taskId) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index != -1) {
      _tasks[index].toggleCompletion();
      await _repository.saveTasks(_tasks);
      notifyListeners();
      _triggerSync(_tasks[index]); // Trigger sync immediately
    }
  }

  Future<void> clearAllTasks() async {
    _tasks.clear();
    await _repository.clearTasks();
    notifyListeners();
  }

  // Selected Task Management
  void selectTask(TaskModel task) {
    _selectionController.select(task);
    notifyListeners();
  }

  void clearSelection() {
    _selectionController.clear();
    notifyListeners();
  }

  // Filter Management

  void setFilter(TaskFilter filter) {
    _filterController.setFilter(filter);
    // Clear selection when changing filter
    _selectionController.clear();
    notifyListeners();
  }

  // Search and Filter Methods
  void updateSearchQuery(String query) {
    _filterController.updateSearch(query);
    // Clear selection when changing search query
    _selectionController.clear();
    notifyListeners();
  }

  void clearSearch() {
    _filterController.clearSearch();
    // Clear selection when clearing search
    _selectionController.clear();
    notifyListeners();
  }

  void clearFilter() {
    _filterController.clearFilter();
    // Clear selection when clearing filter
    _selectionController.clear();
    notifyListeners();
  }

  // Bulk Operations
  void markAllAsCompleted() {
    for (var task in _tasks) {
      if (!task.isCompleted) {
        task.toggleCompletion();
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
      debugPrint('No user ID found. Skipping sync for task: ${task.id}');
      return;
    }
    if (_isLoading) {
      debugPrint(
        'Sync already in progress. Skipping sync for task: ${task.id}',
      );
      return;
    }
    _isLoading = true;
    notifyListeners();
    // debugPrint('Triggering sync for task: ${task.id}');
    // debugPrint('Task sync status: ${task.syncStatus}');
    _taskSyncService.syncIfLoggedIn(
      task.copyWith(), // Use a copy to avoid modifying the original task
      (List<TaskModel> syncedTasks) async {
        // Optional: handle synced tasks here
        await loadTasks(); // Reload tasks after sync
        _isLoading = false;
        notifyListeners();
      },
    );
  }
}
