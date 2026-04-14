import 'package:todo_flutter/controllers/task_filter_controller.dart';
import 'package:todo_flutter/controllers/task_selection_controller.dart';
import 'package:todo_flutter/models/task.dart';

class TaskWorkspaceInteractionController {
  final TaskFilterController _filterController = TaskFilterController();
  final TaskSelectionController _selectionController =
      TaskSelectionController();
  final Set<String> _batchSelectedTaskIds = <String>{};

  bool _isBatchMode = false;

  String get searchQuery => _filterController.searchQuery;
  TaskFilter get filter => _filterController.filter;
  TaskSort get sort => _filterController.sort;

  TaskModel? get selectedTask => _selectionController.selected;
  bool get hasSelectedTask => _selectionController.hasSelected;

  bool get isBatchMode => _isBatchMode;
  bool get hasBatchSelection => _batchSelectedTaskIds.isNotEmpty;
  int get batchSelectedCount => _batchSelectedTaskIds.length;

  List<TaskModel> apply(List<TaskModel> tasks) {
    return _filterController.apply(tasks);
  }

  bool selectTask(TaskModel task) {
    if (_isBatchMode) {
      return false;
    }

    _selectionController.select(task);
    return true;
  }

  bool clearSelection() {
    if (!_selectionController.hasSelected) {
      return false;
    }

    _selectionController.clear();
    return true;
  }

  bool enterBatchMode() {
    if (_isBatchMode) {
      return false;
    }

    _isBatchMode = true;
    _selectionController.clear();
    _batchSelectedTaskIds.clear();
    return true;
  }

  bool exitBatchMode() {
    if (!_isBatchMode && _batchSelectedTaskIds.isEmpty) {
      return false;
    }

    _isBatchMode = false;
    _batchSelectedTaskIds.clear();
    return true;
  }

  bool toggleTaskInBatchSelection(
    String taskId,
    Iterable<String> visibleTaskIds,
  ) {
    if (!_isBatchMode) {
      return false;
    }

    final visibleIds = visibleTaskIds.toSet();
    if (_batchSelectedTaskIds.contains(taskId)) {
      _batchSelectedTaskIds.remove(taskId);
      return true;
    }

    if (!visibleIds.contains(taskId)) {
      return false;
    }

    _batchSelectedTaskIds.add(taskId);
    return true;
  }

  bool selectAllVisibleTasks(Iterable<String> visibleTaskIds) {
    if (!_isBatchMode) {
      return false;
    }

    final nextIds = visibleTaskIds.toSet();
    if (_batchSelectedTaskIds.length == nextIds.length &&
        _batchSelectedTaskIds.containsAll(nextIds)) {
      return false;
    }

    _batchSelectedTaskIds
      ..clear()
      ..addAll(nextIds);
    return true;
  }

  bool clearBatchSelection() {
    if (_batchSelectedTaskIds.isEmpty) {
      return false;
    }

    _batchSelectedTaskIds.clear();
    return true;
  }

  bool isTaskBatchSelected(String taskId) {
    return _batchSelectedTaskIds.contains(taskId);
  }

  bool setFilter(TaskFilter filter) {
    if (_filterController.filter == filter) {
      return false;
    }

    _filterController.setFilter(filter);
    resetForViewChange();
    return true;
  }

  bool updateSearchQuery(String query) {
    if (_filterController.searchQuery == query) {
      return false;
    }

    _filterController.updateSearch(query);
    resetForViewChange();
    return true;
  }

  bool clearSearch() {
    if (_filterController.searchQuery.isEmpty) {
      return false;
    }

    _filterController.clearSearch();
    resetForViewChange();
    return true;
  }

  bool clearFilter() {
    if (_filterController.filter == TaskFilter.all) {
      return false;
    }

    _filterController.clearFilter();
    resetForViewChange();
    return true;
  }

  bool setSort(TaskSort sort) {
    if (_filterController.sort == sort) {
      return false;
    }

    _filterController.setSort(sort);
    return true;
  }

  void resetForViewChange() {
    _selectionController.clear();
    if (_isBatchMode) {
      _batchSelectedTaskIds.clear();
    }
  }

  void pruneInteractionState({
    required Set<String> activeTaskIds,
    required Set<String> visibleTaskIds,
  }) {
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

    _batchSelectedTaskIds.removeWhere(
      (taskId) =>
          !activeTaskIds.contains(taskId) || !visibleTaskIds.contains(taskId),
    );

    if (activeTaskIds.isEmpty) {
      _isBatchMode = false;
    }
  }

  void removeTaskIds(Iterable<String> taskIds) {
    final targetIds = taskIds.toSet();
    _selectionController.clear();
    _batchSelectedTaskIds.removeWhere(targetIds.contains);
  }
}
