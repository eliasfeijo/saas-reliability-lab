import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/widgets/forms/task_form.dart';
import 'package:todo_flutter/widgets/tiles/task_tile.dart';

class TaskList extends StatefulWidget {
  const TaskList({super.key});

  @override
  State<TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<TaskList> {
  late Timer _refreshTimer;

  // Controller for the search bar
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Refresh the task list every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      setState(() {
        // Trigger a rebuild to refresh the task list
        // This will call the build method again
        // We do this to recalculate the elapsed time for tasks
        // and update any dynamic properties that depend on time
        // TODO: Consider optimizing this if performance becomes an issue
      });
    });

    // Load initial tasks
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final agenda = Provider.of<AgendaProvider>(context, listen: false);
      agenda.loadTasks();
    });
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Consumer<AgendaProvider>(
          builder: (context, agenda, child) {
            return Text(agenda.currentFilter.title);
          },
        ),
        actions: [
          Consumer<AgendaProvider>(
            builder: (context, agenda, child) {
              return IconButton(
                icon: Icon(
                  agenda.hasSelectedTask ? Icons.clear : Icons.filter_list,
                ),
                onPressed: () {
                  if (agenda.hasSelectedTask) {
                    agenda.clearSelection();
                  } else {
                    _showFilterDialog(context);
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                constraints: BoxConstraints(maxWidth: 500),
                // color: Colors.red,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selected task banner
                    Consumer<AgendaProvider>(
                      builder: (context, agenda, child) {
                        if (!agenda.hasSelectedTask) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            child: SearchBar(
                              controller: _searchController,
                              elevation: WidgetStatePropertyAll(1),
                              hintText: 'Search tasks...',
                              onChanged: (value) {
                                Provider.of<AgendaProvider>(
                                  context,
                                  listen: false,
                                ).updateSearchQuery(value);
                              },
                              leading: const Icon(Icons.search),
                              trailing: [
                                Consumer<AgendaProvider>(
                                  builder: (context, agenda, child) {
                                    if (agenda.searchQuery.isNotEmpty) {
                                      return IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          Provider.of<AgendaProvider>(
                                            context,
                                            listen: false,
                                          ).clearSearch();
                                          _searchController.clear();
                                        },
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ],
                            ),
                          );
                        }

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          color: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.1),
                          child: Row(
                            children: [
                              // Display selected task details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Selected: ${agenda.selectedTask!.title}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      'Status: ${agenda.selectedTask!.status.displayName}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              // Action buttons for selected task
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editSelectedTask(context),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () =>
                                        _deleteSelectedTask(context),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => agenda.clearSelection(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    SizedBox(height: 8),

                    // Task list
                    Expanded(
                      child: Consumer<AgendaProvider>(
                        builder: (context, agenda, child) {
                          final tasks = agenda.filteredTasks;

                          if (tasks.isEmpty) {
                            return const Center(child: Text('No tasks found'));
                          }

                          return ListView.builder(
                            itemCount: tasks.length,
                            itemBuilder: (context, index) {
                              final task = tasks[index];
                              final isSelected =
                                  agenda.selectedTask?.id == task.id;

                              return TaskTile(
                                task: task,
                                isSelected: isSelected,
                                onTap: () => agenda.selectTask(task),
                                onToggleComplete: () =>
                                    agenda.toggleTaskCompletion(task.id),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateTaskDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Tasks'),
        content: Consumer<AgendaProvider>(
          builder: (context, agenda, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: TaskFilter.values.map((filter) {
                return RadioListTile<TaskFilter>(
                  title: Text(filter.displayName),
                  subtitle: Text(filter.description),
                  value: filter,
                  groupValue: agenda.currentFilter,
                  onChanged: (value) {
                    agenda.setFilter(value!);
                    Navigator.of(context).pop();
                  },
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  void _editSelectedTask(BuildContext context) {
    final agenda = Provider.of<AgendaProvider>(context, listen: false);
    if (agenda.selectedTask == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Task'),
        content: TaskForm(
          task: agenda.selectedTask,
          onSaved: () {
            Navigator.of(context).pop();
            agenda.clearSelection();
          },
        ),
      ),
    );
  }

  void _deleteSelectedTask(BuildContext context) {
    final agenda = Provider.of<AgendaProvider>(context, listen: false);
    if (agenda.selectedTask == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text(
          'Are you sure you want to delete "${agenda.selectedTask!.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              agenda.deleteTask(agenda.selectedTask!.id);
              Navigator.of(context).pop();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCreateTaskDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Task'),
        content: TaskForm(onSaved: () => Navigator.of(context).pop()),
      ),
    );
  }
}
