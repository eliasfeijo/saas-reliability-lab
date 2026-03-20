import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/helpers/web_push_helper.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/widgets/bottomsheets/login.dart';
import 'package:todo_flutter/widgets/common/transition_switcher.dart';
import 'package:todo_flutter/widgets/forms/task_form.dart';
import 'package:todo_flutter/widgets/tiles/task_tile.dart';

class TaskWorkspace extends StatefulWidget {
  const TaskWorkspace({super.key});

  @override
  State<TaskWorkspace> createState() => _TaskWorkspaceState();
}

class _TaskWorkspaceState extends State<TaskWorkspace> {
  TaskModel? _selectedTask;
  late Timer _refreshTimer;
  late final StreamSubscription<AuthState> _authStateSubscription;

  final TextEditingController _searchController = TextEditingController();
  final TransitionSwitcherController _topBarTransitionController =
      TransitionSwitcherController();

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        setState(() {});
      }
    });

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
    final runtimeDebug = context.read<RuntimeDebugProvider>();

    runtimeDebug.setUserState(
      cachedUserId: provider.userId,
      activeUserId: Supabase.instance.client.auth.currentUser?.id,
      hasAuthenticatedSession: _hasAuthenticatedSession,
      logEvent: true,
      message: 'Auth event: ${authState.event.name}',
    );

    if (authState.event == AuthChangeEvent.signedIn) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await provider.saveUser(user.id);
      await _completeAuthenticatedSetup(provider);
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

  Future<void> _completeAuthenticatedSetup(AgendaProvider agenda) async {
    final runtimeDebug = context.read<RuntimeDebugProvider>();

    if (agenda.hasPendingAnonymousReview) {
      runtimeDebug.addEvent(
        category: RuntimeEventCategory.storage,
        message:
            'Anonymous local tasks are waiting for review before cloud sync can continue.',
        level: RuntimeEventLevel.warning,
      );

      await registerWebPushSubscription(runtimeDebug: runtimeDebug);

      if (!mounted) return;
      _showAnonymousTaskReviewDialog();
      return;
    }

    await agenda.syncAllTasks();
    await registerWebPushSubscription(runtimeDebug: runtimeDebug);
  }

  void _showLoginBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const LoginBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          children: [
            _buildWorkspaceHeader(),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    color: theme.colorScheme.surfaceContainerLow,
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                            _buildAnonymousNotificationHint(),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Consumer<AgendaProvider>(
                                builder: (context, agenda, child) {
                                  final tasks = agenda.filteredTasks;
                                  if (tasks.isEmpty) {
                                    return _buildEmptyState(agenda);
                                  }

                                  return ListView.builder(
                                    padding: const EdgeInsets.only(
                                      bottom: 84,
                                      top: 4,
                                    ),
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
                          right: 20,
                          bottom: 20,
                          child: FloatingActionButton.extended(
                            onPressed: () => _showCreateTaskDialog(context),
                            icon: const Icon(Icons.add),
                            label: const Text('New Task'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildLoadingIndicator(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initAgenda() async {
    final agenda = context.read<AgendaProvider>();
    final runtimeDebug = context.read<RuntimeDebugProvider>();

    runtimeDebug.startInitialLoad('Loading local session and task snapshot.');

    try {
      await agenda.loadUser();
      await agenda.loadTasks();
      runtimeDebug.finishInitialLoad(
        message: 'Loaded local session and task snapshot.',
      );

      if (_hasAuthenticatedSession &&
          agenda.userId != null &&
          agenda.userId!.isNotEmpty) {
        await _completeAuthenticatedSetup(agenda);
      }
    } catch (error) {
      runtimeDebug.failInitialLoad(
        'Failed to initialize the workspace: $error',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to initialize the workspace.')),
      );
    }
  }

  Widget _buildLoadingIndicator() {
    return Consumer<AgendaProvider>(
      builder: (context, agenda, child) {
        if (!agenda.isLoading) {
          return const SizedBox.shrink();
        }

        return Container(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _buildWorkspaceHeader() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Consumer<AgendaProvider>(
              builder: (context, agenda, child) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Task Workspace', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      agenda.hasSelectedTask
                          ? 'Selection controls stay in the workspace; durable controls live in the operator rail.'
                          : agenda.currentFilter.title,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Consumer<AgendaProvider>(
            builder: (context, agenda, child) {
              if (!agenda.hasSelectedTask) {
                return const SizedBox.shrink();
              }

              return OutlinedButton.icon(
                onPressed: () async {
                  agenda.clearSelection();
                  await _topBarTransitionController.switchChild(
                    _buildSearchBar(),
                  );
                  setState(() {
                    _selectedTask = null;
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear selection'),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editSelectedTask(BuildContext context) {
    final agenda = context.read<AgendaProvider>();
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
    final agenda = context.read<AgendaProvider>();
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SearchBar(
        controller: _searchController,
        hintText: 'Search tasks...',
        onChanged: (value) {
          context.read<AgendaProvider>().updateSearchQuery(value);
        },
        leading: const Icon(Icons.search),
        trailing: [
          Consumer<AgendaProvider>(
            builder: (context, agenda, child) {
              if (agenda.searchQuery.isNotEmpty) {
                return IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    context.read<AgendaProvider>().clearSearch();
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

  void _showAnonymousTaskReviewDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review Local Tasks Before Sync'),
        content: const Text(
          'This device still has anonymous local tasks from before sign-in. Keep them to attach and sync them to this account, discard them to load cloud state only, or review them later from the operator rail. Cloud sync will stay paused until you decide.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Review later'),
          ),
          TextButton(
            onPressed: () async {
              final agenda = context.read<AgendaProvider>();
              Navigator.of(dialogContext).pop();
              await agenda.takeOwnershipOfAnonymousTasks();

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Anonymous tasks kept and queued for sync.'),
                ),
              );
            },
            child: const Text('Keep local tasks'),
          ),
          TextButton(
            onPressed: () async {
              final agenda = context.read<AgendaProvider>();
              Navigator.of(dialogContext).pop();
              await agenda.discardAnonymousTasks();

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Anonymous tasks discarded. Cloud sync resumed.',
                  ),
                ),
              );
            },
            child: const Text(
              'Discard local tasks',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnonymousNotificationHint() {
    return Consumer<AgendaProvider>(
      builder: (context, agenda, child) {
        final isLoggedIn = agenda.userId != null && agenda.userId!.isNotEmpty;
        final theme = Theme.of(context);

        if (isLoggedIn && agenda.hasPendingAnonymousReview) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.sync_problem_outlined,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cloud sync is paused until local tasks are reviewed.',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Keep the anonymous tasks to attach them to this account, or discard them to load cloud state only.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: _showAnonymousTaskReviewDialog,
                          icon: const Icon(Icons.person_search_outlined),
                          label: const Text('Review now'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (isLoggedIn) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notifications are available on signed-in devices.',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in to register web push on this browser profile.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: _showLoginBottomSheet,
                        icon: const Icon(Icons.login),
                        label: const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(AgendaProvider agenda) {
    final isLoggedIn = agenda.userId != null && agenda.userId!.isNotEmpty;
    if (isLoggedIn) {
      return const Center(child: Text('No tasks found'));
    }

    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active_outlined,
              size: 36,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks found',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to receive notifications on this device.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _showLoginBottomSheet,
              icon: const Icon(Icons.login),
              label: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTaskBanner() {
    if (_selectedTask == null) {
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
  const SelectedTaskBanner({
    super.key,
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  final TaskModel task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
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
                const SizedBox(height: 4),
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
