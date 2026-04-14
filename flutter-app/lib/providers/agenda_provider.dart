import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:todo_flutter/controllers/task_workspace_interaction_controller.dart';
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

  final TaskLocalSnapshotCoordinator _localSnapshotCoordinator;
  final TaskMutationCoordinator _taskMutationCoordinator;
  final TaskWorkspaceInteractionController _interactionController;

  final List<TaskModel> _tasks = [];

  // User ID for cloud sync
  // This is used to identify the user for cloud sync operations.
  String? _userId;

  // Loading state
  bool _isLoading = false;

  // Constructor
  AgendaProvider(
    TasksRepository repository,
    TaskSyncService taskSyncService, {
    TaskSyncCoordinator? taskSyncCoordinator,
    TaskLocalSnapshotCoordinator? localSnapshotCoordinator,
    TaskMutationCoordinator? taskMutationCoordinator,
    TaskWorkspaceInteractionController? interactionController,
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
       _interactionController =
           interactionController ?? TaskWorkspaceInteractionController(),
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
  List<TaskModel> get filteredTasks =>
      _interactionController.apply(_activeTasks);
  String get searchQuery => _interactionController.searchQuery;
  TaskFilter get currentFilter => _interactionController.filter;
  TaskSort get currentSort => _interactionController.sort;
  bool get isLoading => _isLoading;
  String? get userId => _userId;
  bool get hasPendingAnonymousReview =>
      _userId != null && _userId!.isNotEmpty && anonymousTasks.isNotEmpty;

  // Getters for task selection
  TaskModel? get selectedTask => _interactionController.selectedTask;
  bool get hasSelectedTask => _interactionController.hasSelectedTask;
  bool get isTaskSelected => hasSelectedTask;
  bool get isBatchMode => _interactionController.isBatchMode;
  bool get hasBatchSelection => batchSelectedCount > 0;
  int get batchSelectedCount => _interactionController.batchSelectedCount;
  List<TaskModel> get selectedBatchTasks => _activeTasks
      .where((task) => _interactionController.isTaskBatchSelected(task.id))
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
      _taskMutationCoordinator.setCompletionState(_tasks, [
        taskId,
      ], isCompleted: true),
    );
  }

  Future<void> reopenTask(String taskId) async {
    await _persistMutationResult(
      _taskMutationCoordinator.setCompletionState(_tasks, [
        taskId,
      ], isCompleted: false),
    );
  }

  Future<void> markSelectedTasksCompleted() async {
    await _persistMutationResult(
      _taskMutationCoordinator.setCompletionState(
        _tasks,
        selectedBatchTasks.map((task) => task.id),
        isCompleted: true,
      ),
    );
  }

  Future<void> reopenSelectedTasks() async {
    await _persistMutationResult(
      _taskMutationCoordinator.setCompletionState(
        _tasks,
        selectedBatchTasks.map((task) => task.id),
        isCompleted: false,
      ),
    );
  }

  Future<void> deleteSelectedTasks() async {
    await _deleteTasksById(selectedBatchTasks.map((task) => task.id));
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
    if (!_interactionController.selectTask(task)) {
      return;
    }
    notifyListeners();
  }

  void clearSelection() {
    if (!_interactionController.clearSelection()) {
      return;
    }
    notifyListeners();
  }

  void enterBatchMode() {
    if (!_interactionController.enterBatchMode()) {
      return;
    }
    notifyListeners();
  }

  void exitBatchMode() {
    if (!_interactionController.exitBatchMode()) {
      return;
    }
    notifyListeners();
  }

  void toggleTaskInBatchSelection(String taskId) {
    if (!_interactionController.toggleTaskInBatchSelection(
      taskId,
      filteredTasks.map((task) => task.id),
    )) {
      return;
    }
    notifyListeners();
  }

  void selectAllVisibleTasks() {
    if (!_interactionController.selectAllVisibleTasks(
      filteredTasks.map((task) => task.id),
    )) {
      return;
    }
    notifyListeners();
  }

  void clearBatchSelection() {
    if (!_interactionController.clearBatchSelection()) {
      return;
    }
    notifyListeners();
  }

  bool isTaskBatchSelected(String taskId) {
    return _interactionController.isTaskBatchSelected(taskId);
  }

  // Filter Management

  void setFilter(TaskFilter filter) {
    if (!_interactionController.setFilter(filter)) {
      return;
    }
    notifyListeners();
  }

  // Search and Filter Methods
  void updateSearchQuery(String query) {
    if (!_interactionController.updateSearchQuery(query)) {
      return;
    }
    notifyListeners();
  }

  void clearSearch() {
    if (!_interactionController.clearSearch()) {
      return;
    }
    notifyListeners();
  }

  void clearFilter() {
    if (!_interactionController.clearFilter()) {
      return;
    }
    notifyListeners();
  }

  void setSort(TaskSort sort) {
    if (!_interactionController.setSort(sort)) {
      return;
    }

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
      _interactionController.clearSelection();
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

  void _pruneInteractionState() {
    final activeTaskIds = _activeTasks.map((task) => task.id).toSet();
    final visibleTaskIds = filteredTasks.map((task) => task.id).toSet();
    _interactionController.pruneInteractionState(
      activeTaskIds: activeTaskIds,
      visibleTaskIds: visibleTaskIds,
    );
  }

  Future<void> _deleteTasksById(Iterable<String> taskIds) async {
    final targetIds = taskIds.toSet();
    if (targetIds.isEmpty) {
      return;
    }

    _interactionController.removeTaskIds(targetIds);
    await _persistMutationResult(
      _taskMutationCoordinator.deleteTasks(_tasks, targetIds),
    );
  }

  void _publishTaskDebugState() {
    _runtimeDebug?.updateTaskCounts(_tasks);
  }
}
