import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';

class AgendaProvider extends ChangeNotifier {
  // Private fields
  final TasksRepository _repository;

  final List<TaskModel> _tasks = [];
  TaskModel? _selectedTask;
  String _searchQuery = '';
  TaskFilter _currentFilter = TaskFilter.all;

  // User ID for cloud sync
  // This is used to identify the user for cloud sync operations.
  String? _userId;

  // Loading state
  bool _isLoading = false;

  // Timer for debouncing sync operations
  // This is used to prevent multiple sync operations from being triggered in quick succession.
  Timer? _syncDebounceTimer;

  // Constructor
  AgendaProvider(this._repository);

  // Getters
  List<TaskModel> get tasks => List.unmodifiable(
    _tasks.where((task) {
      // Filter out tasks that are marked as deleted
      return task.syncStatus != SyncStatus.deleted;
    }),
  );
  TaskModel? get selectedTask => _selectedTask;
  String get searchQuery => _searchQuery;
  TaskFilter get currentFilter => _currentFilter;
  bool get isLoading => _isLoading;
  String? get userId => _userId;

  // Computed getters
  List<TaskModel> get filteredTasks {
    var filtered = _tasks.where((task) {
      // Exclude tasks that are marked as deleted
      if (task.syncStatus == SyncStatus.deleted) return false;

      // Apply search filter
      if (_searchQuery.isNotEmpty) {
        if (!task.title.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }

      // Apply status filter
      switch (_currentFilter) {
        case TaskFilter.completed:
          return task.isCompleted;
        case TaskFilter.pending:
          return !task.isCompleted;
        case TaskFilter.today:
          return task.isToday;
        case TaskFilter.upcoming:
          return task.isUpcoming && !task.isToday;
        case TaskFilter.overdue:
          return task.isOverdue;
        case TaskFilter.all:
          return true;
      }
    }).toList();

    // Sort by beginDate (earliest first)
    filtered.sort((a, b) => a.beginsAt.compareTo(b.beginsAt));
    return filtered;
  }

  // List<TaskModel> get anonymousTasks {
  //   // Return tasks that are not associated with any user
  //   return _tasks.where((task) => task.userId == null).toList();
  // }

  bool get hasSelectedTask => _selectedTask != null;
  bool get isTaskSelected => _selectedTask != null;

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
    final prefs = await SharedPreferences.getInstance();
    final String? lastLocalUserId = prefs.getString('userId');
    // Check if the user is logged in
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // If the user is logged in, use their ID
      _userId = user.id;
      debugPrint('Using logged in user ID: $_userId');
    } else if (lastLocalUserId != null) {
      // If not logged in, use the last saved local user ID
      // This is useful for offline mode or when the user was previously logged in
      debugPrint('Using last local user ID: $lastLocalUserId');
      _userId = lastLocalUserId;
    } else {
      // No user ID available
      _userId = null;
      debugPrint('No user ID found in SharedPreferences or Supabase auth.');
    }
    _isLoading = false;
    notifyListeners();
  }

  // Save user ID to SharedPreferences
  Future<void> saveUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
    return loadUser(); // Reload user to update state
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
    await _debouncedSync(task); // Debounced sync
  }

  Future<void> updateTask(TaskModel updatedTask) async {
    updatedTask.dirty(); // Mark task as dirty for sync
    final index = _tasks.indexWhere((task) => task.id == updatedTask.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      await _repository.saveTasks(_tasks);
      notifyListeners();
      await _debouncedSync(updatedTask); // Debounced sync
    }
  }

  Future<void> deleteTask(String taskId) async {
    // _tasks.removeWhere((task) => task.id == taskId);
    _tasks.firstWhere((task) => task.id == taskId).markAsDeleted();
    // Clear selection if deleted task was selected
    if (_selectedTask?.id == taskId) {
      _selectedTask = null;
    }
    await _repository.saveTasks(_tasks);
    notifyListeners();
    await _debouncedSync(_tasks.firstWhere((task) => task.id == taskId));
  }

  Future<void> toggleTaskCompletion(String taskId) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index != -1) {
      _tasks[index].toggleCompletion();
      await _repository.saveTasks(_tasks);
      notifyListeners();
    }
  }

  Future<void> clearAllTasks() async {
    _tasks.clear();
    await _repository.clearTasks();
    notifyListeners();
  }

  // Selected Task Management
  void selectTask(TaskModel task) {
    _selectedTask = task;
    notifyListeners();
  }

  void selectTaskById(String taskId) {
    final task = _tasks.firstWhere(
      (task) => task.id == taskId,
      orElse: () => throw ArgumentError('Task with id $taskId not found'),
    );
    selectTask(task);
  }

  void clearSelection() {
    _selectedTask = null;
    notifyListeners();
  }

  void selectNextTask() {
    if (_selectedTask == null || _tasks.isEmpty) return;

    final currentIndex = _tasks.indexWhere(
      (task) => task.id == _selectedTask!.id,
    );
    if (currentIndex != -1 && currentIndex < _tasks.length - 1) {
      _selectedTask = _tasks[currentIndex + 1];
      notifyListeners();
    }
  }

  void selectPreviousTask() {
    if (_selectedTask == null || _tasks.isEmpty) return;

    final currentIndex = _tasks.indexWhere(
      (task) => task.id == _selectedTask!.id,
    );
    if (currentIndex > 0) {
      _selectedTask = _tasks[currentIndex - 1];
      notifyListeners();
    }
  }

  // Search and Filter Methods
  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  void setFilter(TaskFilter filter) {
    _currentFilter = filter;
    notifyListeners();
  }

  void clearFilter() {
    _currentFilter = TaskFilter.all;
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
    // final completedTaskIds = _tasks
    //     .where((task) => task.isCompleted)
    //     .map((task) => task.id)
    //     .toList();

    // Clear selection if selected task is completed
    if (_selectedTask?.isCompleted == true) {
      _selectedTask = null;
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
    debugPrint('Selected task: ${_selectedTask?.title ?? 'None'}');
    debugPrint('Current filter: $_currentFilter');
    debugPrint('Search query: "$_searchQuery"');
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

  // Sync with Cloud on Login
  Future<void> syncWithCloudOnLogin() async {
    final connectivityResult = await (Connectivity().checkConnectivity());
    if (!connectivityResult.contains(ConnectivityResult.none)) {
      debugPrint('Internet connection available. Starting sync...');
    } else {
      debugPrint('No internet connection. Skipping sync.');
      return;
    }

    _isLoading = true;
    notifyListeners();
    final supabase = Supabase.instance.client;

    // Skip if not logged in
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('No user logged in. Skipping sync.');
      _isLoading = false;
      notifyListeners();
      return;
    }

    // Check if there is an active session
    if (supabase.auth.currentSession == null) {
      debugPrint('No active session found. Skipping sync.');
      _isLoading = false;
      notifyListeners();
      return;
    }

    debugPrint('Syncing tasks with cloud for user: ${user.id}');

    final markedAsDeleted = _tasks
        .where((task) => task.syncStatus == SyncStatus.deleted)
        .toList();

    // 1. Delete tasks marked as deleted
    for (final task in markedAsDeleted) {
      try {
        debugPrint('Deleting task "${task.title}" from cloud');
        // Delete from Supabase
        await supabase.from('tasks').delete().eq('id', task.id);
        // Remove from local list
        _tasks.removeWhere((t) => t.id == task.id);
        // Clear selection if deleted task was selected
        if (_selectedTask?.id == task.id) {
          _selectedTask = null;
        }
      } catch (e) {
        debugPrint('Error deleting task "${task.title}": $e');
      }
    }
    // Save updated local tasks after deletion
    await _repository.saveTasks(_tasks);

    // 2. Upload unsynced tasks (e.g. no `synced` flag? unique `id` already in Supabase?)
    final dirtyTasks = _tasks
        .where((task) => task.syncStatus == SyncStatus.dirty)
        .toList();
    for (final task in dirtyTasks) {
      try {
        final existing = await supabase
            .from('tasks')
            .select()
            .eq('id', task.id)
            .maybeSingle();

        if (existing == null) {
          // Task does not exist, insert it
          debugPrint('Inserting new task "${task.title}" to cloud');
          await supabase.from('tasks').insert(task.toJson());
        } else if (task.lastModifiedAt != null) {
          // Task exists, check if local version is newer
          if (task.lastModifiedAt!.isAfter(
            DateTime.parse(existing['updated_at']),
          )) {
            // Update existing task if local version is newer
            debugPrint('Updating task "${task.title}" in cloud');
            await supabase
                .from('tasks')
                .update(task.toJson())
                .eq('id', task.id);
            // Update local task
            task.syncStatus = SyncStatus.synced;
          } else {
            // If remote version is newer, update local task
            task.syncStatus = SyncStatus.synced;
            task.lastModifiedAt = DateTime.parse(existing['updated_at']);
            _tasks[_tasks.indexWhere((t) => t.id == task.id)] = task;
          }
        }
      } catch (e) {
        debugPrint('Error syncing task "${task.title}": $e');
      }
    }

    // Reload local tasks to ensure we have the latest state
    // This is necessary to ensure we have the latest local tasks after deletions and updates
    await loadTasks();

    // 3. Pull cloud tasks
    final remoteTasksRaw = await supabase
        .from('tasks')
        .select()
        .order('start_date');

    final remoteTasks = (remoteTasksRaw as List)
        .map((json) => TaskModel.fromJson(json))
        .toList();

    // 4. Merge local and remote tasks
    final localTasks = List<TaskModel>.from(_tasks);
    final merged = <String, TaskModel>{};
    for (final task in [...remoteTasks, ...localTasks]) {
      merged[task.id] = task;
    }

    _tasks
      ..clear()
      ..addAll(merged.values);
    await _repository.saveTasks(_tasks);

    _isLoading = false;
    notifyListeners();
  }

  /// Attempts to auto-sync a single task with the cloud.
  Future<void> _tryAutoSync(TaskModel task) async {
    // Attempt to sync with cloud if user is logged in
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      debugPrint('Auto-syncing tasks for user: ${user.id}');
      // TODO: Refactor this to sync only the specific task
      // For now, we will call the full sync method
      await syncWithCloudOnLogin();
    } else {
      debugPrint('No user logged in. Skipping auto-sync.');
    }
  }

  /// Debounced sync method to prevent multiple sync operations in quick succession.
  Future<void> _debouncedSync(TaskModel task) async {
    // Cancel any existing timer
    _syncDebounceTimer?.cancel();
    // Start a new timer
    _syncDebounceTimer = Timer(
      const Duration(seconds: 3),
      () => _tryAutoSync(task),
    );
  }
}
