import 'package:todo_flutter/models/task.dart';

class TaskFilterController {
  String _searchQuery = '';
  TaskFilter _filter = TaskFilter.all;
  TaskSort _sort = TaskSort.closestToNow;

  String get searchQuery => _searchQuery;
  TaskFilter get filter => _filter;
  TaskSort get sort => _sort;

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

  void setSort(TaskSort newSort) {
    _sort = newSort;
  }

  List<TaskModel> apply(List<TaskModel> tasks) {
    final filteredTasks = tasks.where((task) {
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
    }).toList();

    final referenceNow = DateTime.now();
    filteredTasks.sort((a, b) => _compareTasks(a, b, referenceNow));
    return filteredTasks;
  }

  int _compareTasks(TaskModel a, TaskModel b, DateTime referenceNow) {
    switch (_sort) {
      case TaskSort.closestToNow:
        return _compareByClosestToNow(a, b, referenceNow);
      case TaskSort.earliestFirst:
        return _compareWithTieBreaker(a.beginsAt.compareTo(b.beginsAt), a, b);
      case TaskSort.latestFirst:
        return _compareWithTieBreaker(b.beginsAt.compareTo(a.beginsAt), a, b);
      case TaskSort.recentlyUpdated:
        return _compareWithTieBreaker(
          _taskSortTimestamp(b).compareTo(_taskSortTimestamp(a)),
          a,
          b,
        );
      case TaskSort.priorityHighToLow:
        return _compareWithTieBreaker(
          b.priority.value.compareTo(a.priority.value),
          a,
          b,
        );
    }
  }

  int _compareByClosestToNow(TaskModel a, TaskModel b, DateTime referenceNow) {
    final aDistance = a.beginsAt.difference(referenceNow).inMilliseconds.abs();
    final bDistance = b.beginsAt.difference(referenceNow).inMilliseconds.abs();
    final distanceCompare = aDistance.compareTo(bDistance);
    if (distanceCompare != 0) {
      return distanceCompare;
    }

    final aIsUpcoming = !a.beginsAt.isBefore(referenceNow);
    final bIsUpcoming = !b.beginsAt.isBefore(referenceNow);
    if (aIsUpcoming != bIsUpcoming) {
      return aIsUpcoming ? -1 : 1;
    }

    return _compareWithTieBreaker(a.beginsAt.compareTo(b.beginsAt), a, b);
  }

  int _compareWithTieBreaker(int primary, TaskModel a, TaskModel b) {
    if (primary != 0) {
      return primary;
    }

    final scheduleCompare = a.beginsAt.compareTo(b.beginsAt);
    if (scheduleCompare != 0) {
      return scheduleCompare;
    }

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  DateTime _taskSortTimestamp(TaskModel task) {
    return task.lastModifiedAt ??
        task.updatedAt ??
        task.createdAt ??
        task.beginsAt;
  }
}
