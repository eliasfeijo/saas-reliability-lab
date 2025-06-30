import 'package:todo_flutter/models/task.dart';

class TaskFilterController {
  String _searchQuery = '';
  TaskFilter _filter = TaskFilter.all;

  String get searchQuery => _searchQuery;
  TaskFilter get filter => _filter;

  void updateSearch(String query) {
    _searchQuery = query;
  }

  void clearSearch() {
    _searchQuery = '';
  }

  void setFilter(TaskFilter newFilter) {
    _filter = newFilter;
  }

  void clearFilter() {
    _filter = TaskFilter.all;
  }

  List<TaskModel> apply(List<TaskModel> tasks) {
    return tasks.where((task) {
      if (task.syncStatus == SyncStatus.deleted) return false;

      if (_searchQuery.isNotEmpty &&
          !task.title.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }

      switch (_filter) {
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
    }).toList()..sort((a, b) => a.beginsAt.compareTo(b.beginsAt));
  }
}
