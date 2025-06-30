import 'package:todo_flutter/models/task.dart';

class TaskSelectionController {
  TaskModel? _selected;

  TaskModel? get selected => _selected;
  bool get hasSelected => _selected != null;

  void select(TaskModel task) {
    _selected = task;
  }

  void clear() {
    _selected = null;
  }

  void selectNext(List<TaskModel> tasks) {
    if (_selected == null || tasks.isEmpty) return;
    final index = tasks.indexWhere((t) => t.id == _selected!.id);
    if (index != -1 && index < tasks.length - 1) {
      _selected = tasks[index + 1];
    }
  }

  void selectPrevious(List<TaskModel> tasks) {
    if (_selected == null || tasks.isEmpty) return;
    final index = tasks.indexWhere((t) => t.id == _selected!.id);
    if (index > 0) {
      _selected = tasks[index - 1];
    }
  }

  bool isSelected(String taskId) {
    return _selected?.id == taskId;
  }
}
