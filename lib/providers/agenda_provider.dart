import 'package:flutter/foundation.dart';
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

  bool _isLoading = false;

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

  // Methods

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
    task.dirty(); // Mark task as dirty for sync
    _tasks.add(task);
    await _repository.saveTasks(_tasks);
    notifyListeners();
  }

  Future<void> updateTask(TaskModel updatedTask) async {
    updatedTask.dirty(); // Mark task as dirty for sync
    final index = _tasks.indexWhere((task) => task.id == updatedTask.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      await _repository.saveTasks(_tasks);
      notifyListeners();
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

  Future<void> syncWithCloudOnLogin() async {
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
}
