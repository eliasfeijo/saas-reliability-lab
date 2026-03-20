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
import 'package:todo_flutter/widgets/forms/task_form.dart';

class TaskWorkspace extends StatefulWidget {
  const TaskWorkspace({super.key});

  @override
  State<TaskWorkspace> createState() => _TaskWorkspaceState();
}

class _TaskWorkspaceState extends State<TaskWorkspace> {
  late Timer _refreshTimer;
  late final StreamSubscription<AuthState> _authStateSubscription;

  final TextEditingController _searchController = TextEditingController();

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
      _searchController.clear();
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
                  ColoredBox(
                    color: theme.colorScheme.surfaceContainerLow,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Consumer<AgendaProvider>(
                          builder: (context, agenda, child) {
                            final selectedTask = _resolveSelectedTask(agenda);
                            _syncSearchController(agenda.searchQuery);

                            final isSplitLayout = constraints.maxWidth >= 920;
                            final isDenseLayout = constraints.maxHeight < 820;
                            final contentPadding = isDenseLayout ? 14.0 : 18.0;
                            return Padding(
                              padding: EdgeInsets.all(contentPadding),
                              child: isSplitLayout
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: _buildTaskFlowPane(
                                            agenda: agenda,
                                            selectedTask: selectedTask,
                                            compact: false,
                                            dense: isDenseLayout,
                                          ),
                                        ),
                                        SizedBox(
                                          width: isDenseLayout ? 14 : 18,
                                        ),
                                        SizedBox(
                                          width: isDenseLayout ? 300 : 320,
                                          child: _buildInspectorPane(
                                            agenda: agenda,
                                            selectedTask: selectedTask,
                                            compact: false,
                                            dense: isDenseLayout,
                                          ),
                                        ),
                                      ],
                                    )
                                  : _buildTaskFlowPane(
                                      agenda: agenda,
                                      selectedTask: selectedTask,
                                      compact: true,
                                      dense: isDenseLayout,
                                    ),
                            );
                          },
                        );
                      },
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

        return ColoredBox(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _buildWorkspaceHeader() {
    final theme = Theme.of(context);
    final isTightScreen = MediaQuery.sizeOf(context).height < 820;

    return Container(
      padding: isTightScreen
          ? const EdgeInsets.fromLTRB(20, 14, 20, 12)
          : const EdgeInsets.fromLTRB(24, 18, 24, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Consumer<AgendaProvider>(
        builder: (context, agenda, child) {
          final selectedTask = _resolveSelectedTask(agenda);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Task Workspace',
                      style: isTightScreen
                          ? theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            )
                          : theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buildWorkspaceSubtitle(agenda, selectedTask),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: () => _showCreateTaskDialog(context),
                style: isTightScreen
                    ? FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.add_task_outlined),
                label: Text(isTightScreen ? 'New' : 'New task'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _buildWorkspaceSubtitle(
    AgendaProvider agenda,
    TaskModel? selectedTask,
  ) {
    final countLabel = _formatTaskCount(agenda.filteredTasks.length);

    if (selectedTask != null) {
      return '$countLabel in view. ${selectedTask.title} is open in the inspector.';
    }

    if (agenda.searchQuery.isNotEmpty) {
      return '$countLabel matching "${agenda.searchQuery}".';
    }

    return '$countLabel in the current view. Browse, inspect, and act without stretching the canvas.';
  }

  Widget _buildTaskFlowPane({
    required AgendaProvider agenda,
    required TaskModel? selectedTask,
    required bool compact,
    required bool dense,
  }) {
    final spacing = dense ? 12.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildControlDeck(agenda: agenda, compact: compact, dense: dense),
        if (compact && selectedTask != null) ...[
          SizedBox(height: spacing),
          SizedBox(
            height: dense ? 220 : 280,
            child: _buildInspectorPane(
              agenda: agenda,
              selectedTask: selectedTask,
              compact: true,
              dense: dense,
            ),
          ),
        ],
        SizedBox(height: spacing),
        Expanded(
          child: _buildTaskListPane(
            agenda: agenda,
            selectedTask: selectedTask,
            compact: compact,
            dense: dense,
          ),
        ),
      ],
    );
  }

  Widget _buildControlDeck({
    required AgendaProvider agenda,
    required bool compact,
    required bool dense,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(dense ? 14 : 18),
      decoration: _panelDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Queue Controls', style: theme.textTheme.titleMedium),
                    if (!dense) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Search, scope, and local session context stay attached to the task queue.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (agenda.searchQuery.isNotEmpty ||
                  agenda.currentFilter != TaskFilter.all)
                TextButton.icon(
                  onPressed: () => _resetView(agenda),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset view'),
                ),
            ],
          ),
          SizedBox(height: dense ? 12 : 16),
          _buildSearchBar(agenda),
          SizedBox(height: dense ? 10 : 14),
          _buildFilterStrip(agenda: agenda, dense: dense),
          SizedBox(height: dense ? 10 : 14),
          _buildMetricStrip(agenda: agenda, dense: dense),
          if (agenda.hasPendingAnonymousReview ||
              !_hasAuthenticatedSession) ...[
            SizedBox(height: dense ? 10 : 14),
            _buildSessionNotice(agenda: agenda, compact: compact, dense: dense),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterStrip({
    required AgendaProvider agenda,
    required bool dense,
  }) {
    final chips = TaskFilter.values.map((filter) {
      final count = _taskCountForFilter(agenda.tasks, filter);
      return ChoiceChip(
        label: Text('${_shortFilterLabel(filter)} $count'),
        selected: agenda.currentFilter == filter,
        onSelected: (_) => agenda.setFilter(filter),
        visualDensity: dense ? VisualDensity.compact : null,
      );
    }).toList();

    if (!dense) {
      return Wrap(spacing: 10, runSpacing: 10, children: chips);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: _withHorizontalSpacing(chips, 10)),
    );
  }

  Widget _buildMetricStrip({
    required AgendaProvider agenda,
    required bool dense,
  }) {
    final theme = Theme.of(context);
    final metrics = [
      _WorkspaceMetricChip(
        label: 'In view',
        value: '${agenda.filteredTasks.length}',
        tone: theme.colorScheme.primaryContainer,
        foreground: theme.colorScheme.onPrimaryContainer,
        dense: dense,
      ),
      _WorkspaceMetricChip(
        label: 'Pending',
        value: '${agenda.pendingTasksCount}',
        tone: theme.colorScheme.secondaryContainer,
        foreground: theme.colorScheme.onSecondaryContainer,
        dense: dense,
      ),
      _WorkspaceMetricChip(
        label: 'Overdue',
        value: '${agenda.overdueTasksCount}',
        tone: theme.colorScheme.errorContainer,
        foreground: theme.colorScheme.onErrorContainer,
        dense: dense,
      ),
      _WorkspaceMetricChip(
        label: agenda.hasPendingAnonymousReview ? 'Needs review' : 'Completed',
        value: agenda.hasPendingAnonymousReview
            ? '${agenda.anonymousTasks.length}'
            : '${agenda.completedTasksCount}',
        tone: agenda.hasPendingAnonymousReview
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        foreground: agenda.hasPendingAnonymousReview
            ? theme.colorScheme.onTertiaryContainer
            : theme.colorScheme.onSurface,
        dense: dense,
      ),
    ];

    if (!dense) {
      return Wrap(spacing: 10, runSpacing: 10, children: metrics);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: _withHorizontalSpacing(metrics, 10)),
    );
  }

  Widget _buildSearchBar(AgendaProvider agenda) {
    return SearchBar(
      controller: _searchController,
      hintText: 'Search task titles',
      leading: const Icon(Icons.search),
      onChanged: agenda.updateSearchQuery,
      trailing: [
        if (agenda.searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              agenda.clearSearch();
              _searchController.clear();
            },
          ),
      ],
    );
  }

  Widget _buildSessionNotice({
    required AgendaProvider agenda,
    required bool compact,
    required bool dense,
  }) {
    final theme = Theme.of(context);

    if (agenda.hasPendingAnonymousReview) {
      if (dense) {
        return _buildDenseSessionNotice(
          icon: Icons.sync_problem_outlined,
          title: 'Local review required',
          message: 'Sync is paused until local tasks are reviewed.',
          actionLabel: 'Review',
          onAction: _showAnonymousTaskReviewDialog,
          backgroundColor: theme.colorScheme.tertiaryContainer,
          foregroundColor: theme.colorScheme.onTertiaryContainer,
        );
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNoticeHeader(
                    icon: Icons.sync_problem_outlined,
                    title: 'Local review required',
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cloud sync is paused until you keep or discard the anonymous local tasks.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _showAnonymousTaskReviewDialog,
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('Review now'),
                  ),
                ],
              )
            : Row(
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
                          'Local review required',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cloud sync is paused until you keep or discard the anonymous local tasks.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _showAnonymousTaskReviewDialog,
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('Review now'),
                  ),
                ],
              ),
      );
    }

    if (dense) {
      return _buildDenseSessionNotice(
        icon: Icons.cloud_off_outlined,
        title: 'Anonymous mode',
        message: 'Local tasks stay on this device until you sign in.',
        actionLabel: 'Sign in',
        onAction: _showLoginBottomSheet,
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNoticeHeader(
                  icon: Icons.cloud_off_outlined,
                  title: 'Anonymous mode',
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tasks stay on this device until you sign in. Web push is available only on authenticated sessions.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _showLoginBottomSheet,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in'),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Anonymous mode',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tasks stay on this device until you sign in. Web push is available only on authenticated sessions.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: _showLoginBottomSheet,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in'),
                ),
              ],
            ),
    );
  }

  Widget _buildDenseSessionNotice({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foregroundColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$title • $message',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: foregroundColor,
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskListPane({
    required AgendaProvider agenda,
    required TaskModel? selectedTask,
    required bool compact,
    required bool dense,
  }) {
    final theme = Theme.of(context);
    final tasks = agenda.filteredTasks;

    return Container(
      decoration: _panelDecoration(theme),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              dense ? 14 : 18,
              dense ? 14 : 18,
              dense ? 14 : 18,
              dense ? 10 : 12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Task Queue', style: theme.textTheme.titleMedium),
                      SizedBox(height: dense ? 2 : 4),
                      Text(
                        tasks.isEmpty
                            ? 'Nothing is visible in the current scope.'
                            : compact
                            ? 'Select a row to open the inline inspector.'
                            : 'Select a row to inspect and act without leaving the queue.',
                        style: theme.textTheme.bodySmall,
                        maxLines: dense ? 1 : null,
                        overflow: dense ? TextOverflow.ellipsis : null,
                      ),
                    ],
                  ),
                ),
                if (selectedTask != null)
                  TextButton.icon(
                    onPressed: agenda.clearSelection,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear selection'),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: tasks.isEmpty
                ? _buildEmptyState(agenda)
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      dense ? 14 : 18,
                      dense ? 10 : 14,
                      dense ? 14 : 18,
                      dense ? 14 : 18,
                    ),
                    itemCount: tasks.length,
                    separatorBuilder: (context, index) =>
                        SizedBox(height: dense ? 8 : 10),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      final isSelected = selectedTask?.id == task.id;
                      return _WorkspaceTaskCard(
                        task: task,
                        isSelected: isSelected,
                        dense: dense,
                        onTap: () => agenda.selectTask(task),
                        onToggleComplete: () =>
                            agenda.toggleTaskCompletion(task.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AgendaProvider agenda) {
    final theme = Theme.of(context);
    final hasViewModifiers =
        agenda.searchQuery.isNotEmpty || agenda.currentFilter != TaskFilter.all;

    if (hasViewModifiers && agenda.tasks.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_alt_off_outlined,
                size: 36,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'No tasks match this view',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Clear the search or change the scope to bring the rest of the queue back into view.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _resetView(agenda),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset view'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt_outlined,
              size: 36,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks scheduled yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _hasAuthenticatedSession
                  ? 'Create the first task for this account.'
                  : 'Create a local task now, or sign in when you want to sync and enable push.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _showCreateTaskDialog(context),
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('Create task'),
                ),
                if (!_hasAuthenticatedSession)
                  OutlinedButton.icon(
                    onPressed: _showLoginBottomSheet,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorPane({
    required AgendaProvider agenda,
    required TaskModel? selectedTask,
    required bool compact,
    required bool dense,
  }) {
    final theme = Theme.of(context);

    return Container(
      decoration: _panelDecoration(
        theme,
        color: compact
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerLowest,
      ),
      child: selectedTask == null
          ? _buildInspectorPlaceholder(compact: compact, dense: dense)
          : SingleChildScrollView(
              padding: EdgeInsets.all(dense ? 14 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              compact ? 'Inline Inspector' : 'Task Inspector',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              compact
                                  ? 'Selection details stay available above the queue on narrow widths.'
                                  : 'Desktop detail surface for the active task.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: agenda.clearSelection,
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear selection',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    selectedTask.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _WorkspaceBadge(
                        icon: Icons.flag_rounded,
                        label: selectedTask.priority.displayName,
                        backgroundColor: selectedTask.priority.color.withValues(
                          alpha: 0.16,
                        ),
                        foregroundColor: selectedTask.priority.color,
                      ),
                      _WorkspaceBadge(
                        icon: _statusIcon(selectedTask.status),
                        label: selectedTask.status.displayName,
                        backgroundColor: _statusBackgroundColor(
                          selectedTask.status,
                          theme.colorScheme,
                        ),
                        foregroundColor: _statusForegroundColor(
                          selectedTask.status,
                          theme.colorScheme,
                        ),
                      ),
                      _WorkspaceBadge(
                        icon: selectedTask.userId == null
                            ? Icons.phone_iphone_outlined
                            : Icons.cloud_done_outlined,
                        label: selectedTask.userId == null
                            ? 'Local only'
                            : 'Account task',
                        backgroundColor: theme.colorScheme.surfaceContainerHigh,
                        foregroundColor: theme.colorScheme.onSurface,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _InspectorField(
                    label: 'Schedule',
                    value: _formatLongTaskWindow(selectedTask),
                  ),
                  _InspectorField(
                    label: 'Duration',
                    value: _formatDurationLabel(selectedTask.estimatedDuration),
                  ),
                  _InspectorField(
                    label: 'Sync state',
                    value: _syncStatusLabel(selectedTask.syncStatus),
                  ),
                  _InspectorField(
                    label: 'Notes',
                    value: _taskNotes(selectedTask),
                  ),
                  if (selectedTask.tags.isNotEmpty) ...[
                    Text('Tags', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selectedTask.tags
                          .map((tag) => Chip(label: Text(tag)))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _editTask(context, selectedTask),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            agenda.toggleTaskCompletion(selectedTask.id),
                        icon: Icon(
                          selectedTask.isCompleted
                              ? Icons.undo_outlined
                              : Icons.check_circle_outline,
                        ),
                        label: Text(
                          selectedTask.isCompleted
                              ? 'Reopen task'
                              : 'Mark complete',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _deleteTask(context, selectedTask),
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                        label: Text(
                          'Delete',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInspectorPlaceholder({
    required bool compact,
    required bool dense,
  }) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(dense ? 18 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              compact ? Icons.touch_app_outlined : Icons.dashboard_customize,
              size: 34,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              compact ? 'No task selected' : 'Inspector is standing by',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              compact
                  ? 'Tap a task in the queue to open its details above the list.'
                  : 'Select a task to inspect its schedule, sync state, and actions without displacing the queue.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTask(BuildContext context, TaskModel task) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Task'),
        content: TaskForm(
          task: task,
          onSaved: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _deleteTask(BuildContext context, TaskModel task) {
    final agenda = context.read<AgendaProvider>();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              agenda.deleteTask(task.id);
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

  void _syncSearchController(String query) {
    if (_searchController.text == query) {
      return;
    }

    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _resetView(AgendaProvider agenda) {
    agenda.clearFilter();
    agenda.clearSearch();
    _searchController.clear();
  }

  TaskModel? _resolveSelectedTask(AgendaProvider agenda) {
    final selectedTask = agenda.selectedTask;
    if (selectedTask == null) {
      return null;
    }

    return agenda.getTaskById(selectedTask.id) ?? selectedTask;
  }

  BoxDecoration _panelDecoration(ThemeData theme, {Color? color}) {
    return BoxDecoration(
      color: color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: theme.colorScheme.outlineVariant),
    );
  }

  List<Widget> _withHorizontalSpacing(List<Widget> children, double spacing) {
    if (children.isEmpty) {
      return const [];
    }

    final spacedChildren = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        spacedChildren.add(SizedBox(width: spacing));
      }
      spacedChildren.add(children[index]);
    }
    return spacedChildren;
  }
}

class _WorkspaceMetricChip extends StatelessWidget {
  const _WorkspaceMetricChip({
    required this.label,
    required this.value,
    required this.tone,
    required this.foreground,
    this.dense = false,
  });

  final String label;
  final String value;
  final Color tone;
  final Color foreground;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 12 : 14,
        vertical: dense ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(18),
      ),
      child: dense
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.84),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.84),
                  ),
                ),
              ],
            ),
    );
  }
}

class _WorkspaceTaskCard extends StatelessWidget {
  const _WorkspaceTaskCard({
    required this.task,
    required this.isSelected,
    required this.dense,
    required this.onTap,
    required this.onToggleComplete,
  });

  final TaskModel task;
  final bool isSelected;
  final bool dense;
  final VoidCallback onTap;
  final VoidCallback onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDescription = task.description?.trim().isNotEmpty ?? false;
    final statusColor = _statusForegroundColor(task.status, theme.colorScheme);

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.56)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(dense ? 18 : 22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(dense ? 18 : 22),
        child: Container(
          padding: EdgeInsets.all(dense ? 14 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(dense ? 18 : 22),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _WorkspaceBadge(
                          icon: Icons.flag_rounded,
                          label: task.priority.displayName,
                          backgroundColor: task.priority.color.withValues(
                            alpha: 0.16,
                          ),
                          foregroundColor: task.priority.color,
                        ),
                        _WorkspaceBadge(
                          icon: _statusIcon(task.status),
                          label: task.status.displayName,
                          backgroundColor: _statusBackgroundColor(
                            task.status,
                            theme.colorScheme,
                          ),
                          foregroundColor: statusColor,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Checkbox(
                        value: task.isCompleted,
                        onChanged: (_) => onToggleComplete(),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: dense ? 10 : 12),
              Text(
                task.title,
                style:
                    (dense
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.titleMedium)
                        ?.copyWith(
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.isCompleted
                              ? theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                )
                              : theme.colorScheme.onSurface,
                        ),
              ),
              SizedBox(height: dense ? 4 : 6),
              Text(
                hasDescription ? task.description!.trim() : _taskSummary(task),
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: dense ? 10 : 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _WorkspaceBadge(
                    icon: Icons.schedule_outlined,
                    label: _formatShortTaskWindow(task),
                    backgroundColor: theme.colorScheme.surfaceContainerLow,
                    foregroundColor: theme.colorScheme.onSurface,
                  ),
                  _WorkspaceBadge(
                    icon: Icons.timelapse_outlined,
                    label: _formatDurationLabel(task.estimatedDuration),
                    backgroundColor: theme.colorScheme.surfaceContainerLow,
                    foregroundColor: theme.colorScheme.onSurface,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceBadge extends StatelessWidget {
  const _WorkspaceBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.icon,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foregroundColor),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorField extends StatelessWidget {
  const _InspectorField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

String _shortFilterLabel(TaskFilter filter) {
  switch (filter) {
    case TaskFilter.all:
      return 'All';
    case TaskFilter.completed:
      return 'Done';
    case TaskFilter.pending:
      return 'Pending';
    case TaskFilter.today:
      return 'Today';
    case TaskFilter.upcoming:
      return 'Upcoming';
    case TaskFilter.overdue:
      return 'Overdue';
  }
}

int _taskCountForFilter(List<TaskModel> tasks, TaskFilter filter) {
  switch (filter) {
    case TaskFilter.all:
      return tasks.length;
    case TaskFilter.completed:
      return tasks.where((task) => task.isCompleted).length;
    case TaskFilter.pending:
      return tasks.where((task) => !task.isCompleted).length;
    case TaskFilter.today:
      return tasks.where((task) => task.isToday).length;
    case TaskFilter.upcoming:
      return tasks.where((task) => task.isUpcoming).length;
    case TaskFilter.overdue:
      return tasks.where((task) => task.isOverdue).length;
  }
}

String _formatTaskCount(int count) {
  return count == 1 ? '1 task' : '$count tasks';
}

String _formatShortTaskWindow(TaskModel task) {
  return '${_formatDayLabel(task.beginsAt)} • ${_formatTimeLabel(task.beginsAt)}-${_formatTimeLabel(task.endsAt)}';
}

String _formatLongTaskWindow(TaskModel task) {
  if (_isSameDay(task.beginsAt, task.endsAt)) {
    return '${_formatLongDateLabel(task.beginsAt)} • ${_formatTimeLabel(task.beginsAt)} to ${_formatTimeLabel(task.endsAt)}';
  }

  return '${_formatLongDateLabel(task.beginsAt)} ${_formatTimeLabel(task.beginsAt)} to ${_formatLongDateLabel(task.endsAt)} ${_formatTimeLabel(task.endsAt)}';
}

String _formatLongDateLabel(DateTime dateTime) {
  const monthLabels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return '${dateTime.day} ${monthLabels[dateTime.month - 1]} ${dateTime.year}';
}

String _formatDayLabel(DateTime dateTime) {
  final now = DateTime.now();
  final tomorrow = now.add(const Duration(days: 1));
  final yesterday = now.subtract(const Duration(days: 1));

  if (_isSameDay(dateTime, now)) {
    return 'Today';
  }
  if (_isSameDay(dateTime, tomorrow)) {
    return 'Tomorrow';
  }
  if (_isSameDay(dateTime, yesterday)) {
    return 'Yesterday';
  }

  return _formatLongDateLabel(dateTime);
}

String _formatTimeLabel(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDurationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final parts = <String>[];

  if (hours > 0) {
    parts.add('$hours h');
  }
  if (minutes > 0) {
    parts.add('$minutes min');
  }

  return parts.isEmpty ? '< 1 min' : parts.join(' ');
}

String _taskNotes(TaskModel task) {
  final notes = task.description?.trim();
  if (notes == null || notes.isEmpty) {
    return 'No notes captured for this task yet.';
  }

  return notes;
}

String _taskSummary(TaskModel task) {
  if (task.isCompleted) {
    return 'Completed and ready to remain in the historical record.';
  }
  if (task.isOverdue) {
    return 'Overdue by ${_formatDurationLabel(task.overdueDuration)}.';
  }
  if (task.isInProgress) {
    return 'In progress with ${_formatDurationLabel(task.timeUntilEnd)} remaining.';
  }
  if (task.isUpcoming) {
    return 'Starts in ${_formatDurationLabel(task.timeUntilStart)}.';
  }
  return 'Pending scheduling follow-through.';
}

String _syncStatusLabel(SyncStatus status) {
  switch (status) {
    case SyncStatus.synced:
      return 'Synced';
    case SyncStatus.dirty:
      return 'Pending sync';
    case SyncStatus.deleted:
      return 'Marked for deletion';
  }
}

Color _statusBackgroundColor(TaskStatus status, ColorScheme colorScheme) {
  switch (status) {
    case TaskStatus.completed:
      return Color.alphaBlend(
        Colors.green.withValues(alpha: 0.14),
        colorScheme.surface,
      );
    case TaskStatus.overdue:
      return colorScheme.errorContainer;
    case TaskStatus.inProgress:
      return Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.12),
        colorScheme.surface,
      );
    case TaskStatus.upcoming:
      return Color.alphaBlend(
        colorScheme.secondary.withValues(alpha: 0.12),
        colorScheme.surface,
      );
    case TaskStatus.pending:
      return colorScheme.surfaceContainerHighest;
  }
}

Color _statusForegroundColor(TaskStatus status, ColorScheme colorScheme) {
  switch (status) {
    case TaskStatus.completed:
      return Colors.green.shade800;
    case TaskStatus.overdue:
      return colorScheme.onErrorContainer;
    case TaskStatus.inProgress:
      return colorScheme.primary;
    case TaskStatus.upcoming:
      return colorScheme.secondary;
    case TaskStatus.pending:
      return colorScheme.onSurface;
  }
}

IconData _statusIcon(TaskStatus status) {
  switch (status) {
    case TaskStatus.completed:
      return Icons.task_alt_outlined;
    case TaskStatus.overdue:
      return Icons.warning_amber_rounded;
    case TaskStatus.inProgress:
      return Icons.play_circle_outline;
    case TaskStatus.upcoming:
      return Icons.schedule_send_outlined;
    case TaskStatus.pending:
      return Icons.hourglass_bottom_outlined;
  }
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
