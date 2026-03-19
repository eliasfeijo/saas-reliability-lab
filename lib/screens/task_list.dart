import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/helpers/web_push_helper.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/widgets/bottomsheets/login.dart';
import 'package:todo_flutter/widgets/common/transition_switcher.dart';
import 'package:todo_flutter/widgets/forms/task_form.dart';
import 'package:todo_flutter/widgets/tiles/task_tile.dart';

class TaskList extends StatefulWidget {
  const TaskList({super.key});

  @override
  State<TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<TaskList> {
  // This will hold the currently selected task
  TaskModel? _selectedTask;

  // Timer to refresh the task list every 5 seconds
  late Timer _refreshTimer;
  late final StreamSubscription<AuthState> _authStateSubscription;
  bool _isLoggingOut = false;

  // Controller for the search bar
  final TextEditingController _searchController = TextEditingController();
  // Transition controller for the search bar
  final TransitionSwitcherController _topBarTransitionController =
      TransitionSwitcherController();

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
      _initAgenda();
    });

    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange
        .listen(
          (event) async {
            await _handleAuthStateChange(event);
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Auth state listener error: $error');
          },
        );
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    _refreshTimer.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasAuthenticatedSession {
    final auth = Supabase.instance.client.auth;
    return auth.currentUser != null && auth.currentSession != null;
  }

  Future<void> _handleAuthStateChange(AuthState authState) async {
    if (!mounted) return;

    final provider = context.read<AgendaProvider>();

    if (authState.event == AuthChangeEvent.signedIn) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await provider.saveUser(user.id);
      await _syncAuthenticatedAgenda(provider);
      return;
    }

    if (authState.event == AuthChangeEvent.signedOut) {
      provider.clearSelection();
      provider.clearSearch();
      await provider.clearUser();
      await provider.clearAllTasksFromLocalStorage();

      if (!mounted) return;

      _searchController.clear();
      await _topBarTransitionController.switchChild(_buildSearchBar());
      setState(() {
        _selectedTask = null;
      });
    }
  }

  Future<void> _syncAuthenticatedAgenda(AgendaProvider agenda) async {
    await agenda.syncAllTasks();
    await registerWebPushSubscription();

    if (!mounted) return;

    if (agenda.anonymousTasks.isNotEmpty) {
      _showDiscardAnonymousTasksDialog(context);
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;

    setState(() {
      _isLoggingOut = true;
    });

    String failureMessage = 'Logout failed. Please try again.';
    var loggedOut = false;

    try {
      try {
        await unregisterWebPushSubscription();
      } catch (error) {
        debugPrint(
          '[Auth] Failed to unregister web push during logout: $error',
        );
      }

      try {
        await Supabase.instance.client.auth.signOut();
        loggedOut = !_hasAuthenticatedSession;
      } on AuthException catch (error) {
        loggedOut = !_hasAuthenticatedSession;
        if (loggedOut) {
          debugPrint(
            '[Auth] Remote logout cleanup failed after local sign-out: ${error.message}',
          );
        } else {
          failureMessage = error.message;
        }
      } catch (error) {
        loggedOut = !_hasAuthenticatedSession;
        if (loggedOut) {
          debugPrint(
            '[Auth] Remote logout cleanup failed after local sign-out: $error',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loggedOut ? 'Logged out' : failureMessage)),
    );
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
                onPressed: () async {
                  if (agenda.hasSelectedTask) {
                    agenda.clearSelection();
                    await _topBarTransitionController.switchChild(
                      _buildSearchBar(),
                    );
                    setState(() {
                      _selectedTask = null;
                    });
                  } else {
                    _showFilterDialog(context);
                  }
                },
              );
            },
          ),
          Consumer<AgendaProvider>(
            builder: (context, agenda, child) {
              final isLoggedIn =
                  agenda.userId != null && agenda.userId!.isNotEmpty;

              if (!isLoggedIn) {
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: TextButton(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const LoginBottomSheet(),
                    ),
                    child: Text(
                      'Login',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              } else {
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: TextButton(
                    onPressed: _isLoggingOut ? null : _logout,
                    child: Text(
                      _isLoggingOut ? 'Logging out...' : 'Logout',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Row(
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
                    child: Stack(
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Transition Switcher: Search Bar and Selected Task Banner
                            TransitionSwitcher(
                              controller: _topBarTransitionController,
                              transitionOut: (child, animation) =>
                                  fadeThroughTransition(
                                    child,
                                    animation,
                                    reverse: true,
                                  ),
                              transitionIn: (child, animation) =>
                                  fadeThroughTransition(
                                    child,
                                    animation,
                                    reverse: false,
                                  ),
                              outDuration: const Duration(milliseconds: 200),
                              inDuration: const Duration(milliseconds: 500),
                              inDelay: const Duration(milliseconds: 100),
                              child: _buildSearchBar(),
                            ),

                            // Selected task banner
                            SizedBox(height: 8),

                            // Task list
                            Expanded(
                              child: Consumer<AgendaProvider>(
                                builder: (context, agenda, child) {
                                  final tasks = agenda.filteredTasks;
                                  if (tasks.isEmpty) {
                                    return const Center(
                                      child: Text('No tasks found'),
                                    );
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
                                        onTap: () => {
                                          agenda.selectTask(task),
                                          setState(() {
                                            _selectedTask = task;
                                          }),
                                          _topBarTransitionController
                                              .switchChild(
                                                _buildSelectedTaskBanner(),
                                              ),
                                        },
                                        onToggleComplete: () => agenda
                                            .toggleTaskCompletion(task.id),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),

                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: FloatingActionButton(
                            onPressed: () => _showCreateTaskDialog(context),
                            child: const Icon(Icons.add),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          _buildLoadingIndicator(),
        ],
      ),
    );
  }

  Future<void> _initAgenda() async {
    final agenda = Provider.of<AgendaProvider>(context, listen: false);
    // Load user and tasks when the widget is first built
    // This ensures that the user is loaded before tasks are fetched
    // and that the UI is ready to display them
    await agenda.loadUser();
    await agenda.loadTasks();
    if (_hasAuthenticatedSession &&
        agenda.userId != null &&
        agenda.userId!.isNotEmpty) {
      await _syncAuthenticatedAgenda(agenda);
    }
  }

  Widget _buildLoadingIndicator() {
    if (Provider.of<AgendaProvider>(context, listen: false).isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return const SizedBox.shrink();
  }

  void _showDiscardAnonymousTasksDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Anonymous Tasks'),
        content: const Text(
          'Do you want to discard the anonymous tasks that were created before you logged in? This will remove them permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final agenda = Provider.of<AgendaProvider>(
                context,
                listen: false,
              );
              agenda.takeOwnershipOfAnonymousTasks();
              Navigator.of(context).pop();
            },
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () async {
              final agenda = Provider.of<AgendaProvider>(
                context,
                listen: false,
              );
              await agenda.removeFromLocalStorage(agenda.anonymousTasks);
              // ignore: use_build_context_synchronously
              Navigator.of(context).pop();
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
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

  Future<void> _editSelectedTask(BuildContext context) {
    final agenda = Provider.of<AgendaProvider>(context, listen: false);
    if (agenda.selectedTask == null) return Future.value();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Task'),
        content: TaskForm(
          task: agenda.selectedTask,
          onSaved: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _deleteSelectedTask(BuildContext context) {
    final agenda = Provider.of<AgendaProvider>(context, listen: false);
    if (agenda.selectedTask == null) return Future.value();

    return showDialog(
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

  Widget _buildSearchBar() {
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

  Widget _buildSelectedTaskBanner() {
    if (_selectedTask == null) {
      // If no task is selected, return an empty container
      return const SizedBox.shrink();
    }
    return Consumer<AgendaProvider>(
      builder: (context, agenda, child) {
        return SelectedTaskBanner(
          task: _selectedTask!,
          onEdit: () async {
            await _editSelectedTask(context);
          },
          onDelete: () async {
            await _deleteSelectedTask(context);
            if (agenda.selectedTask == null) {
              // If the selected task was deleted, switch back to the search bar
              await _topBarTransitionController.switchChild(_buildSearchBar());
              setState(() {
                _selectedTask = null;
              });
            }
          },
          onClose: () async {
            agenda.clearSelection();
            await _topBarTransitionController.switchChild(_buildSearchBar());
            setState(() {
              _selectedTask = null;
            });
          },
        );
      },
    );
  }

  Widget fadeThroughTransition(
    Widget child,
    Animation<double> animation, {
    bool reverse = false,
  }) {
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
    final slide = Tween<Offset>(
      begin: Offset(0, reverse ? 0 : -1),
      end: Offset(0, reverse ? -1 : 0),
    ).animate(fade);

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

class SelectedTaskBanner extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const SelectedTaskBanner({
    super.key,
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 88,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Selected: ${task.title}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Status: ${task.status.displayName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
              IconButton(icon: const Icon(Icons.delete), onPressed: onDelete),
              IconButton(icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
        ],
      ),
    );
  }
}
