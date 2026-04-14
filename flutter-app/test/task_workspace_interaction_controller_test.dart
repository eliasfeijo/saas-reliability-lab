import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/controllers/task_workspace_interaction_controller.dart';
import 'package:todo_flutter/models/task.dart';

import 'test_support/app_test_support.dart';

void main() {
  test(
    'entering batch mode clears single selection and exiting clears batch selection',
    () {
      final controller = TaskWorkspaceInteractionController();
      final alphaTask = buildTask(
        id: 'task-alpha',
        title: 'Alpha',
        beginsAt: DateTime(2026, 2, 20, 9),
        estimatedDuration: const Duration(hours: 1),
      );
      final betaTask = buildTask(
        id: 'task-beta',
        title: 'Beta',
        beginsAt: DateTime(2026, 2, 20, 10),
        estimatedDuration: const Duration(hours: 1),
      );

      controller.selectTask(alphaTask);
      controller.enterBatchMode();
      controller.toggleTaskInBatchSelection(betaTask.id, [
        alphaTask.id,
        betaTask.id,
      ]);

      expect(controller.selectedTask, isNull);
      expect(controller.isBatchMode, isTrue);
      expect(controller.batchSelectedCount, 1);

      controller.exitBatchMode();

      expect(controller.isBatchMode, isFalse);
      expect(controller.batchSelectedCount, 0);
    },
  );

  test('search and filter changes clear selection and batch selection', () {
    final controller = TaskWorkspaceInteractionController();
    final alphaTask = buildTask(
      id: 'task-alpha',
      title: 'Alpha queue task',
      beginsAt: DateTime(2026, 2, 21, 9),
      estimatedDuration: const Duration(hours: 1),
    );

    controller.selectTask(alphaTask);
    controller.enterBatchMode();
    controller.toggleTaskInBatchSelection(alphaTask.id, [alphaTask.id]);

    controller.updateSearchQuery('Alpha');

    expect(controller.selectedTask, isNull);
    expect(controller.batchSelectedCount, 0);

    controller.toggleTaskInBatchSelection(alphaTask.id, [alphaTask.id]);
    controller.setFilter(TaskFilter.pending);

    expect(controller.batchSelectedCount, 0);
  });

  test('batch selection only accepts visible tasks', () {
    final controller = TaskWorkspaceInteractionController();

    controller.enterBatchMode();

    expect(
      controller.toggleTaskInBatchSelection('hidden-task', ['visible-task']),
      isFalse,
    );
    expect(controller.batchSelectedCount, 0);

    expect(
      controller.toggleTaskInBatchSelection('visible-task', ['visible-task']),
      isTrue,
    );
    expect(controller.batchSelectedCount, 1);
    expect(controller.isTaskBatchSelected('visible-task'), isTrue);
  });

  test(
    'pruneInteractionState drops hidden batch tasks and exits batch mode when empty',
    () {
      final controller = TaskWorkspaceInteractionController();
      final alphaTask = buildTask(
        id: 'task-alpha',
        title: 'Alpha',
        beginsAt: DateTime(2026, 2, 22, 9),
        estimatedDuration: const Duration(hours: 1),
      );
      final betaTask = buildTask(
        id: 'task-beta',
        title: 'Beta',
        beginsAt: DateTime(2026, 2, 22, 10),
        estimatedDuration: const Duration(hours: 1),
      );

      controller.selectTask(alphaTask);
      controller.enterBatchMode();
      controller.selectAllVisibleTasks([alphaTask.id, betaTask.id]);

      controller.pruneInteractionState(
        activeTaskIds: {alphaTask.id, betaTask.id},
        visibleTaskIds: {alphaTask.id},
      );

      expect(controller.batchSelectedCount, 1);
      expect(controller.isTaskBatchSelected(alphaTask.id), isTrue);
      expect(controller.isTaskBatchSelected(betaTask.id), isFalse);

      controller.pruneInteractionState(
        activeTaskIds: <String>{},
        visibleTaskIds: <String>{},
      );

      expect(controller.isBatchMode, isFalse);
      expect(controller.batchSelectedCount, 0);
      expect(controller.selectedTask, isNull);
    },
  );
}
