import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';
import 'package:todo_flutter/models/outbox_entry.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/fault_injection_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/services/workspace_session_coordinator.dart';
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
  late final ScrollController _queueScrollController;
  late final ScrollController _inspectorScrollController;

  final TextEditingController _searchController = TextEditingController();
  bool _isCompactPanelMinimized = false;

  bool get _hasAuthenticatedSession {
    final auth = Supabase.instance.client.auth;
    return auth.currentUser != null && auth.currentSession != null;
  }

  @override
  void initState() {
    super.initState();
    _queueScrollController = ScrollController();
    _inspectorScrollController = ScrollController();
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
            await _handleAuthStateChange(event.event);
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
    _queueScrollController.dispose();
    _inspectorScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleAuthStateChange(AuthChangeEvent event) async {
    if (!mounted) return;

    final agenda = context.read<AgendaProvider>();
    final runtimeDebug = context.read<RuntimeDebugProvider>();
    final sessionCoordinator = context.read<WorkspaceSessionCoordinator>();

    final result = await sessionCoordinator.handleAuthStateChange(
      event,
      agenda: agenda,
      runtimeDebug: runtimeDebug,
    );

    if (result.shouldClearSearch) {
      _searchController.clear();
    }

    if (result.shouldShowAnonymousTaskReview) {
      if (!mounted) {
        return;
      }
      _showAnonymousTaskReviewDialog();
    }
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
                                  : _buildCompactTaskWorkspace(
                                      agenda: agenda,
                                      selectedTask: selectedTask,
                                      dense: isDenseLayout,
                                      viewportHeight: constraints.maxHeight,
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
    final sessionCoordinator = context.read<WorkspaceSessionCoordinator>();

    try {
      final result = await sessionCoordinator.initialize(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
      );
      if (result.shouldShowAnonymousTaskReview) {
        if (!mounted) {
          return;
        }
        _showAnonymousTaskReviewDialog();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to initialize the workspace.')),
      );
    }
  }

  Widget _buildLoadingIndicator() {
    return Consumer3<
      AgendaProvider,
      RuntimeDebugProvider,
      FaultInjectionProvider
    >(
      builder: (context, agenda, runtimeDebug, faultInjection, child) {
        if (!agenda.isLoading) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final faultState = faultInjection.state;
        final statusMessage = runtimeDebug.state.lastSyncMessage;
        final helperMessage = statusMessage != null && statusMessage.isNotEmpty
            ? statusMessage
            : 'Sync is in progress. The workspace stays interactive while remote replay continues.';
        final showDeterministicDelay =
            faultState.isActive &&
            faultState.activeScenario == FaultInjectionScenario.delayedSync &&
            runtimeDebug.state.syncPhase == RuntimeSyncPhase.syncing &&
            runtimeDebug.state.lastSyncStartedAt != null &&
            faultState.effectiveDelayMs != null;

        return IgnorePointer(
          ignoring: true,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Container(
                  key: const ValueKey('task-workspace-sync-activity'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Sync in progress',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(helperMessage, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 10),
                      if (showDeterministicDelay)
                        _DeterministicSyncDelayIndicator(
                          startAt: runtimeDebug.state.lastSyncStartedAt!,
                          totalDelayMs: faultState.effectiveDelayMs!,
                        )
                      else
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: const LinearProgressIndicator(minHeight: 4),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
                    const SizedBox(height: 8),
                    Consumer<RuntimeDebugProvider>(
                      builder: (context, runtimeDebug, child) {
                        final debugState = runtimeDebug.state;
                        if (debugState.failedEntryCount == 0 &&
                            debugState.blockedAnonymousReviewEntryCount == 0) {
                          return const SizedBox.shrink();
                        }

                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (debugState.failedEntryCount > 0)
                              _buildOperationNoticeChip(
                                theme,
                                label:
                                    '${debugState.failedEntryCount} failed operation(s)',
                                color: theme.colorScheme.tertiary,
                              ),
                            if (debugState.blockedAnonymousReviewEntryCount > 0)
                              _buildOperationNoticeChip(
                                theme,
                                label:
                                    '${debugState.blockedAnonymousReviewEntryCount} waiting for review',
                                color: theme.colorScheme.secondary,
                              ),
                          ],
                        );
                      },
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

  Widget _buildOperationNoticeChip(
    ThemeData theme, {
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(label, style: theme.textTheme.labelMedium),
    );
  }

  String _buildWorkspaceSubtitle(
    AgendaProvider agenda,
    TaskModel? selectedTask,
  ) {
    final countLabel = _formatTaskCount(agenda.filteredTasks.length);

    if (agenda.isBatchMode) {
      if (agenda.hasBatchSelection) {
        return '$countLabel in view. ${agenda.batchSelectedCount} selected for batch actions.';
      }

      return '$countLabel in view. Batch mode is active for multi-task actions.';
    }

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
        SizedBox(height: spacing),
        Expanded(
          child: _buildTaskListPane(
            agenda: agenda,
            selectedTask: selectedTask,
            compact: compact,
            dense: dense,
            scrollInternally: true,
            scrollController: compact ? null : _queueScrollController,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactTaskWorkspace({
    required AgendaProvider agenda,
    required TaskModel? selectedTask,
    required bool dense,
    required double viewportHeight,
  }) {
    final spacing = dense ? 12.0 : 16.0;
    final hasAttachedPanel = _hasCompactAttachedPanel(agenda, selectedTask);
    final queueMinHeight = viewportHeight < 780 ? 340.0 : 420.0;

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: viewportHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildControlDeck(agenda: agenda, compact: true, dense: dense),
            if (hasAttachedPanel) ...[
              SizedBox(height: spacing),
              _isCompactPanelMinimized
                  ? _buildCompactPanelHandle(
                      agenda: agenda,
                      selectedTask: selectedTask,
                    )
                  : ConstrainedBox(
                      constraints: BoxConstraints(minHeight: dense ? 220 : 260),
                      child: _buildInspectorPane(
                        agenda: agenda,
                        selectedTask: selectedTask,
                        compact: true,
                        dense: dense,
                        onMinimize: _minimizeCompactPanel,
                        onClose: () => _dismissAttachedPanel(agenda),
                      ),
                    ),
            ],
            SizedBox(height: spacing),
            _buildTaskListPane(
              agenda: agenda,
              selectedTask: selectedTask,
              compact: true,
              dense: dense,
              scrollInternally: false,
              minBodyHeight: queueMinHeight,
            ),
          ],
        ),
      ),
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
          Consumer<RuntimeDebugProvider>(
            builder: (context, runtimeDebug, child) {
              final debugState = runtimeDebug.state;
              if (debugState.conflictEntryCount == 0) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: EdgeInsets.only(top: dense ? 12 : 14),
                child: _buildConflictAlertCard(
                  debugState: debugState,
                  compact: compact,
                  dense: dense,
                ),
              );
            },
          ),
          SizedBox(height: dense ? 12 : 16),
          _buildSearchBar(agenda),
          SizedBox(height: dense ? 10 : 14),
          _buildFilterStrip(agenda: agenda, compact: compact, dense: dense),
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

  Widget _buildConflictAlertCard({
    required RuntimeDebugState debugState,
    required bool compact,
    required bool dense,
  }) {
    final theme = Theme.of(context);
    final conflictCount = debugState.conflictEntryCount;
    final primaryEntry = debugState.conflictEntries.first;
    final primaryTitle = _taskTitleForConflictEntry(primaryEntry);
    final title = conflictCount == 1
        ? 'Sync conflict needs review'
        : '$conflictCount sync conflicts need review';
    final message = conflictCount == 1
        ? 'Your local changes and the remote version for "$primaryTitle" diverged. Review the diff before the next replay.'
        : 'Local changes and remote versions diverged for multiple tasks. Review each diff before the next replay.';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('task-workspace-conflict-alert'),
        borderRadius: BorderRadius.circular(dense ? 18 : 20),
        onTap: _showConflictReviewDialog,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(dense ? 14 : 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(dense ? 18 : 20),
            border: Border.all(
              color: theme.colorScheme.error.withValues(alpha: 0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.error.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNoticeHeader(
                      icon: Icons.warning_amber_rounded,
                      title: title,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      key: const ValueKey(
                        'task-workspace-conflict-review-button',
                      ),
                      onPressed: _showConflictReviewDialog,
                      icon: const Icon(Icons.compare_arrows_rounded),
                      label: const Text('Review conflicts'),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            message,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      key: const ValueKey(
                        'task-workspace-conflict-review-button',
                      ),
                      onPressed: _showConflictReviewDialog,
                      icon: const Icon(Icons.compare_arrows_rounded),
                      label: const Text('Review conflicts'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _showConflictReviewDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 760),
            child: Consumer2<AgendaProvider, RuntimeDebugProvider>(
              builder: (dialogContext, agenda, runtimeDebug, child) {
                final conflicts = runtimeDebug.state.conflictEntries;
                return Padding(
                  padding: const EdgeInsets.all(24),
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
                                  'Conflict review',
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  conflicts.isEmpty
                                      ? 'No sync conflicts are waiting for review now.'
                                      : 'Compare your local version with the current remote version, then decide which side should win the next sync pass.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close),
                            tooltip: 'Close conflict review',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: conflicts.isEmpty
                            ? Center(
                                child: Text(
                                  'The workspace no longer has unresolved sync conflicts.',
                                  style: theme.textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.separated(
                                itemCount: conflicts.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (context, index) {
                                  final entry = conflicts[index];
                                  return _buildConflictReviewCard(
                                    agenda,
                                    entry,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildConflictReviewCard(AgendaProvider agenda, OutboxEntry entry) {
    final theme = Theme.of(context);
    final localTask = _taskFromConflictJson(entry.taskPayload);
    final remoteTask = _taskFromConflictJson(entry.remoteSnapshot);
    final diffs = _buildConflictFieldDiffs(
      entry: entry,
      localTask: localTask,
      remoteTask: remoteTask,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _taskTitleForConflictEntry(entry),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _conflictSummary(entry, localTask, remoteTask),
            style: theme.textTheme.bodyMedium,
          ),
          if (entry.lastError != null &&
              entry.lastError!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              entry.lastError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 640;
              final localPane = _buildConflictVersionPane(
                title: 'Local version',
                accent: theme.colorScheme.primary,
                task: localTask,
                fallback: entry.operationType == OutboxOperationType.delete
                    ? 'Delete this task from the synced queue.'
                    : 'Local task details are no longer available.',
              );
              final remotePane = _buildConflictVersionPane(
                title: 'Remote version',
                accent: theme.colorScheme.secondary,
                task: remoteTask,
                fallback: 'The remote version no longer exists.',
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [localPane, const SizedBox(height: 12), remotePane],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: localPane),
                  const SizedBox(width: 12),
                  Expanded(child: remotePane),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text('What changed', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          if (diffs.isEmpty)
            Text(
              'This conflict is about replay order rather than obvious field-level differences. Review the local and remote summaries above before deciding.',
              style: theme.textTheme.bodyMedium,
            )
          else
            ...diffs.map(
              (diff) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildConflictDiffRow(diff),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await agenda.keepRemoteConflict(entry.taskId);
                  if (!mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Kept the remote version for ${_taskTitleForConflictEntry(entry)}.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.cloud_done_outlined),
                label: const Text('Keep remote version'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await agenda.reapplyLocalConflict(entry.taskId);
                  if (!mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Queued your local changes again for ${_taskTitleForConflictEntry(entry)}.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.upload_outlined),
                label: const Text('Keep my local changes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConflictVersionPane({
    required String title,
    required Color accent,
    required TaskModel? task,
    required String fallback,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (task == null)
            Text(fallback, style: theme.textTheme.bodyMedium)
          else ...[
            Text(
              task.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(_formatLongTaskWindow(task), style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              '${task.priority.displayName} priority • ${task.isCompleted ? 'Completed' : 'Open'} • ${_syncStatusLabel(task.syncStatus)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(_taskNotes(task), style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _buildConflictDiffRow(_ConflictFieldDiffData diff) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 560;
          final localBlock = _buildConflictDiffValueBlock(
            label: 'Local',
            value: diff.localValue,
            accent: theme.colorScheme.primary,
          );
          final remoteBlock = _buildConflictDiffValueBlock(
            label: 'Remote',
            value: diff.remoteValue,
            accent: theme.colorScheme.secondary,
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(diff.label, style: theme.textTheme.labelLarge),
                const SizedBox(height: 10),
                localBlock,
                const SizedBox(height: 10),
                remoteBlock,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(diff.label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: localBlock),
                  const SizedBox(width: 10),
                  Expanded(child: remoteBlock),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConflictDiffValueBlock({
    required String label,
    required String value,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  TaskModel? _taskFromConflictJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return null;
    }

    try {
      return TaskModel.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  String _taskTitleForConflictEntry(OutboxEntry entry) {
    final localTask = _taskFromConflictJson(entry.taskPayload);
    final remoteTask = _taskFromConflictJson(entry.remoteSnapshot);
    return localTask?.title ??
        remoteTask?.title ??
        (entry.taskPayload['title'] as String?) ??
        'Task ${entry.taskId}';
  }

  String _conflictSummary(
    OutboxEntry entry,
    TaskModel? localTask,
    TaskModel? remoteTask,
  ) {
    if (entry.operationType == OutboxOperationType.delete) {
      return remoteTask == null
          ? 'You tried to delete this task locally after the remote version had already moved. Decide whether to keep the remote state or finish the deletion.'
          : 'You deleted this task locally, but the remote version changed first. Decide whether the task should stay in cloud state or be removed.';
    }

    if (localTask == null || remoteTask == null) {
      return 'The local and remote copies no longer agree. Review the available state before choosing which version should win.';
    }

    return 'Your local edits to "${localTask.title}" no longer match the current remote version. Choose whether to keep the remote state or enforce your local changes.';
  }

  List<_ConflictFieldDiffData> _buildConflictFieldDiffs({
    required OutboxEntry entry,
    required TaskModel? localTask,
    required TaskModel? remoteTask,
  }) {
    final diffs = <_ConflictFieldDiffData>[];

    void addDiff(String label, String localValue, String remoteValue) {
      if (localValue == remoteValue) {
        return;
      }
      diffs.add(
        _ConflictFieldDiffData(
          label: label,
          localValue: localValue,
          remoteValue: remoteValue,
        ),
      );
    }

    final localIntent = entry.operationType == OutboxOperationType.delete
        ? 'Delete this task'
        : 'Keep and sync my edits';
    final remoteIntent = remoteTask == null
        ? 'Task no longer exists remotely'
        : 'Keep the current remote task';
    addDiff('Intent', localIntent, remoteIntent);

    addDiff(
      'Title',
      localTask?.title.trim().isNotEmpty == true
          ? localTask!.title.trim()
          : 'Untitled task',
      remoteTask?.title.trim().isNotEmpty == true
          ? remoteTask!.title.trim()
          : 'Untitled task',
    );
    addDiff(
      'Schedule',
      localTask == null ? 'Unavailable' : _formatLongTaskWindow(localTask),
      remoteTask == null ? 'Unavailable' : _formatLongTaskWindow(remoteTask),
    );
    addDiff(
      'Duration',
      localTask == null
          ? 'Unavailable'
          : _formatDurationLabel(localTask.estimatedDuration),
      remoteTask == null
          ? 'Unavailable'
          : _formatDurationLabel(remoteTask.estimatedDuration),
    );
    addDiff(
      'Completion',
      localTask == null
          ? 'Unavailable'
          : (localTask.isCompleted ? 'Completed' : 'Open'),
      remoteTask == null
          ? 'Unavailable'
          : (remoteTask.isCompleted ? 'Completed' : 'Open'),
    );
    addDiff(
      'Priority',
      localTask?.priority.displayName ?? 'Unavailable',
      remoteTask?.priority.displayName ?? 'Unavailable',
    );
    addDiff(
      'Notes',
      localTask == null ? 'Unavailable' : _taskNotes(localTask),
      remoteTask == null ? 'Unavailable' : _taskNotes(remoteTask),
    );
    addDiff(
      'Tags',
      localTask == null ? 'Unavailable' : _formatConflictTags(localTask.tags),
      remoteTask == null ? 'Unavailable' : _formatConflictTags(remoteTask.tags),
    );

    return diffs;
  }

  String _formatConflictTags(List<String> tags) {
    if (tags.isEmpty) {
      return 'No tags';
    }

    return tags.join(', ');
  }

  Widget _buildFilterStrip({
    required AgendaProvider agenda,
    required bool compact,
    required bool dense,
  }) {
    final filterChips = TaskFilter.values.map((filter) {
      final count = _taskCountForFilter(agenda.tasks, filter);
      return ChoiceChip(
        label: Text('${_shortFilterLabel(filter)} $count'),
        selected: agenda.currentFilter == filter,
        onSelected: (_) => agenda.setFilter(filter),
        visualDensity: dense ? VisualDensity.compact : null,
      );
    }).toList();

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSortMenuButton(agenda: agenda, dense: dense),
          SizedBox(height: dense ? 8 : 10),
          Wrap(
            spacing: dense ? 8 : 10,
            runSpacing: dense ? 8 : 10,
            children: filterChips,
          ),
        ],
      );
    }

    return Wrap(
      spacing: dense ? 8 : 10,
      runSpacing: dense ? 8 : 10,
      children: [
        _buildSortMenuButton(agenda: agenda, dense: dense),
        ...filterChips,
      ],
    );
  }

  Widget _buildSortMenuButton({
    required AgendaProvider agenda,
    required bool dense,
  }) {
    final theme = Theme.of(context);

    return PopupMenuButton<TaskSort>(
      initialValue: agenda.currentSort,
      tooltip: 'Sort queue',
      onSelected: agenda.setSort,
      itemBuilder: (context) => TaskSort.values
          .map(
            (sort) => PopupMenuItem<TaskSort>(
              value: sort,
              child: Row(
                children: [
                  if (sort == agenda.currentSort) ...[
                    const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                  ] else ...[
                    const SizedBox(width: 26),
                  ],
                  Expanded(child: Text(sort.label)),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 14,
          vertical: dense ? 9 : 10,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              dense
                  ? 'Sort: ${agenda.currentSort.shortLabel}'
                  : 'Sort: ${agenda.currentSort.label}',
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
      ),
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
        valueKey: const ValueKey('task-workspace-in-view-value'),
        dense: dense,
      ),
      _WorkspaceMetricChip(
        label: 'Pending',
        value: '${agenda.pendingTasksCount}',
        tone: theme.colorScheme.secondaryContainer,
        foreground: theme.colorScheme.onSecondaryContainer,
        valueKey: const ValueKey('task-workspace-pending-value'),
        dense: dense,
      ),
      _WorkspaceMetricChip(
        label: 'Overdue',
        value: '${agenda.overdueTasksCount}',
        tone: theme.colorScheme.errorContainer,
        foreground: theme.colorScheme.onErrorContainer,
        valueKey: const ValueKey('task-workspace-overdue-value'),
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
        valueKey: const ValueKey('task-workspace-review-value'),
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
    required bool scrollInternally,
    double? minBodyHeight,
    ScrollController? scrollController,
  }) {
    final theme = Theme.of(context);
    final tasks = agenda.filteredTasks;
    final isBatchMode = agenda.isBatchMode;
    final queueActions = tasks.isNotEmpty
        ? Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (isBatchMode) ...[
                TextButton.icon(
                  onPressed: () {
                    _expandCompactPanel();
                    agenda.selectAllVisibleTasks();
                  },
                  icon: const Icon(Icons.select_all),
                  label: const Text('Select all'),
                ),
                if (agenda.hasBatchSelection)
                  TextButton.icon(
                    onPressed: agenda.clearBatchSelection,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
                TextButton.icon(
                  onPressed: () => _dismissAttachedPanel(agenda),
                  icon: const Icon(Icons.done_all),
                  label: Text(compact ? 'Done' : 'Done selecting'),
                ),
              ] else ...[
                TextButton.icon(
                  onPressed: () {
                    _expandCompactPanel();
                    agenda.enterBatchMode();
                  },
                  icon: const Icon(Icons.checklist_outlined),
                  label: const Text('Select'),
                ),
                if (selectedTask != null)
                  TextButton.icon(
                    onPressed: () => _dismissAttachedPanel(agenda),
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear selection'),
                  ),
              ],
            ],
          )
        : null;

    return Container(
      decoration: _panelDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              dense ? 14 : 18,
              dense ? 14 : 18,
              dense ? 14 : 18,
              dense ? 10 : 12,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Task Queue', style: theme.textTheme.titleMedium),
                      SizedBox(height: dense ? 2 : 4),
                      Text(
                        tasks.isEmpty
                            ? 'Nothing is visible in the current scope.'
                            : isBatchMode
                            ? agenda.hasBatchSelection
                                  ? '${agenda.batchSelectedCount} task(s) selected for batch actions.'
                                  : 'Select tasks to mark done, reopen, or delete them together.'
                            : 'Select a row to review its details in the attached panel.',
                        style: theme.textTheme.bodySmall,
                        maxLines: dense ? 2 : null,
                        overflow: dense ? TextOverflow.ellipsis : null,
                      ),
                      if (queueActions != null) ...[
                        SizedBox(height: dense ? 10 : 12),
                        queueActions,
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Task Queue',
                              style: theme.textTheme.titleMedium,
                            ),
                            SizedBox(height: dense ? 2 : 4),
                            Text(
                              tasks.isEmpty
                                  ? 'Nothing is visible in the current scope.'
                                  : isBatchMode
                                  ? agenda.hasBatchSelection
                                        ? '${agenda.batchSelectedCount} task(s) selected for batch actions.'
                                        : 'Select tasks to mark done, reopen, or delete them together.'
                                  : 'Select a row to inspect and act without leaving the queue.',
                              style: theme.textTheme.bodySmall,
                              maxLines: dense ? 1 : null,
                              overflow: dense ? TextOverflow.ellipsis : null,
                            ),
                          ],
                        ),
                      ),
                      ?queueActions,
                    ],
                  ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          if (scrollInternally)
            Expanded(
              child: compact
                  ? _buildTaskQueueBody(
                      agenda,
                      selectedTask,
                      dense,
                      controller: scrollController,
                    )
                  : _buildDesktopPaneScrollbar(
                      controller: scrollController!,
                      child: _buildTaskQueueBody(
                        agenda,
                        selectedTask,
                        dense,
                        controller: scrollController,
                      ),
                    ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: minBodyHeight ?? 320),
              child: _buildTaskQueueBody(
                agenda,
                selectedTask,
                dense,
                controller: scrollController,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskQueueBody(
    AgendaProvider agenda,
    TaskModel? selectedTask,
    bool dense, {
    ScrollController? controller,
    bool shrinkWrap = false,
    ScrollPhysics? physics,
  }) {
    final tasks = agenda.filteredTasks;

    if (tasks.isEmpty) {
      return _buildEmptyState(agenda);
    }

    return ListView.separated(
      controller: controller,
      shrinkWrap: shrinkWrap,
      physics: physics,
      padding: EdgeInsets.fromLTRB(
        dense ? 14 : 18,
        dense ? 10 : 14,
        dense ? 14 : 18,
        dense ? 14 : 18,
      ),
      itemCount: tasks.length,
      separatorBuilder: (context, index) => SizedBox(height: dense ? 8 : 10),
      itemBuilder: (context, index) {
        final task = tasks[index];
        final isSelected = selectedTask?.id == task.id;
        return _WorkspaceTaskCard(
          task: task,
          isBatchMode: agenda.isBatchMode,
          isBatchSelected: agenda.isTaskBatchSelected(task.id),
          isSelected: isSelected,
          dense: dense,
          onTap: () => _handleTaskCardTap(agenda, task),
          onMarkDone: task.isCompleted
              ? null
              : () => agenda.markTaskCompleted(task.id),
          onToggleBatchSelection: agenda.isBatchMode
              ? () => _handleTaskCardTap(agenda, task)
              : null,
        );
      },
    );
  }

  bool _hasCompactAttachedPanel(
    AgendaProvider agenda,
    TaskModel? selectedTask,
  ) {
    return selectedTask != null ||
        (agenda.isBatchMode && agenda.hasBatchSelection);
  }

  void _handleTaskCardTap(AgendaProvider agenda, TaskModel task) {
    _expandCompactPanel();
    if (agenda.isBatchMode) {
      agenda.toggleTaskInBatchSelection(task.id);
      return;
    }

    agenda.selectTask(task);
  }

  void _expandCompactPanel() {
    if (!_isCompactPanelMinimized) {
      return;
    }

    setState(() {
      _isCompactPanelMinimized = false;
    });
  }

  void _minimizeCompactPanel() {
    if (_isCompactPanelMinimized) {
      return;
    }

    setState(() {
      _isCompactPanelMinimized = true;
    });
  }

  void _dismissAttachedPanel(AgendaProvider agenda) {
    if (_isCompactPanelMinimized) {
      setState(() {
        _isCompactPanelMinimized = false;
      });
    }

    if (agenda.isBatchMode) {
      agenda.exitBatchMode();
      return;
    }

    agenda.clearSelection();
  }

  Widget _buildCompactPanelHandle({
    required AgendaProvider agenda,
    required TaskModel? selectedTask,
  }) {
    final theme = Theme.of(context);
    final label = agenda.isBatchMode
        ? '${agenda.batchSelectedCount} selected for batch actions'
        : selectedTask?.title ?? 'Task details';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _panelDecoration(
        theme,
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          Icon(
            agenda.isBatchMode
                ? Icons.checklist_rtl_outlined
                : Icons.notes_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _expandCompactPanel,
            icon: const Icon(Icons.expand_less),
            label: const Text('Open'),
          ),
          IconButton(
            onPressed: () => _dismissAttachedPanel(agenda),
            icon: const Icon(Icons.close),
            tooltip: 'Close panel',
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
    VoidCallback? onMinimize,
    VoidCallback? onClose,
    bool translucentBackground = false,
  }) {
    final theme = Theme.of(context);
    final backgroundColor =
        (compact
                ? theme.colorScheme.surface
                : theme.colorScheme.surfaceContainerLowest)
            .withValues(alpha: translucentBackground ? 0.72 : 1);

    return Container(
      decoration: _panelDecoration(theme, color: backgroundColor),
      child: agenda.isBatchMode
          ? _buildBatchInspectorPane(
              agenda: agenda,
              compact: compact,
              dense: dense,
              onMinimize: onMinimize,
              onClose: onClose,
              scrollController: compact ? null : _inspectorScrollController,
            )
          : selectedTask == null
          ? _buildInspectorPlaceholder(compact: compact, dense: dense)
          : _buildInspectorScrollSurface(
              compact: compact,
              controller: compact ? null : _inspectorScrollController,
              child: SingleChildScrollView(
                controller: compact ? null : _inspectorScrollController,
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
                                compact ? 'Task details' : 'Task Inspector',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                compact
                                    ? 'Attached details for the active task.'
                                    : 'Desktop detail surface for the active task.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onMinimize != null)
                              IconButton(
                                onPressed: onMinimize,
                                icon: const Icon(Icons.expand_more),
                                tooltip: 'Minimize panel',
                              ),
                            IconButton(
                              onPressed: onClose ?? agenda.clearSelection,
                              icon: const Icon(Icons.close),
                              tooltip: 'Clear selection',
                            ),
                          ],
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
                          backgroundColor: selectedTask.priority.color
                              .withValues(alpha: 0.16),
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
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHigh,
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
                      value: _formatDurationLabel(
                        selectedTask.estimatedDuration,
                      ),
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
                          onPressed: () => selectedTask.isCompleted
                              ? agenda.reopenTask(selectedTask.id)
                              : agenda.markTaskCompleted(selectedTask.id),
                          icon: Icon(
                            selectedTask.isCompleted
                                ? Icons.undo_outlined
                                : Icons.check_circle_outline,
                          ),
                          label: Text(
                            selectedTask.isCompleted
                                ? 'Reopen task'
                                : 'Mark done',
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
            ),
    );
  }

  Widget _buildBatchInspectorPane({
    required AgendaProvider agenda,
    required bool compact,
    required bool dense,
    VoidCallback? onMinimize,
    VoidCallback? onClose,
    ScrollController? scrollController,
  }) {
    final theme = Theme.of(context);
    final selectedTasks = agenda.selectedBatchTasks;
    final completedCount = selectedTasks
        .where((task) => task.isCompleted)
        .length;
    final incompleteCount = selectedTasks.length - completedCount;

    if (selectedTasks.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(dense ? 18 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.checklist_rtl_outlined,
                size: 34,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                compact ? 'Batch mode is ready' : 'Batch actions are ready',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Select tasks in the queue to mark them done, reopen them, or delete them together.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return _buildInspectorScrollSurface(
      compact: compact,
      controller: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
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
                        compact ? 'Batch actions' : 'Batch Actions',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${agenda.batchSelectedCount} task(s) selected in the current view.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onMinimize != null)
                      IconButton(
                        onPressed: onMinimize,
                        icon: const Icon(Icons.expand_more),
                        tooltip: 'Minimize panel',
                      ),
                    IconButton(
                      onPressed: onClose ?? agenda.exitBatchMode,
                      icon: const Icon(Icons.close),
                      tooltip: 'Exit batch mode',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _WorkspaceBadge(
                  icon: Icons.playlist_add_check_circle_outlined,
                  label: '${agenda.batchSelectedCount} selected',
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                ),
                _WorkspaceBadge(
                  icon: Icons.check_circle_outline,
                  label: '$incompleteCount ready to mark done',
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                ),
                _WorkspaceBadge(
                  icon: Icons.undo_outlined,
                  label: '$completedCount ready to reopen',
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                  foregroundColor: theme.colorScheme.onSurface,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Apply the current queue-safe actions to the selected tasks in one local save and one sync pass.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: incompleteCount > 0
                      ? () => agenda.markSelectedTasksCompleted()
                      : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Mark done'),
                ),
                OutlinedButton.icon(
                  onPressed: completedCount > 0
                      ? () => agenda.reopenSelectedTasks()
                      : null,
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Reopen'),
                ),
                TextButton.icon(
                  onPressed: () => _confirmBatchDelete(context, agenda),
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

  Widget _buildDesktopPaneScrollbar({
    required ScrollController controller,
    required Widget child,
  }) {
    return _DesktopPaneScrollbar(controller: controller, child: child);
  }

  Widget _buildInspectorScrollSurface({
    required bool compact,
    required Widget child,
    ScrollController? controller,
  }) {
    if (compact || controller == null) {
      return child;
    }

    return _buildDesktopPaneScrollbar(controller: controller, child: child);
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

  Future<void> _confirmBatchDelete(
    BuildContext context,
    AgendaProvider agenda,
  ) {
    final count = agenda.batchSelectedCount;
    if (count == 0) {
      return Future.value();
    }

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tasks'),
        content: Text(
          count == 1
              ? 'Are you sure you want to delete the selected task?'
              : 'Are you sure you want to delete $count selected tasks?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              agenda.deleteSelectedTasks();
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

class _DeterministicSyncDelayIndicator extends StatelessWidget {
  const _DeterministicSyncDelayIndicator({
    required this.startAt,
    required this.totalDelayMs,
  });

  final DateTime startAt;
  final int totalDelayMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalDuration = Duration(milliseconds: totalDelayMs);
    final elapsed = DateTime.now().difference(startAt);
    final clampedElapsedMs = elapsed.inMilliseconds.clamp(0, totalDelayMs);
    final begin = totalDelayMs == 0 ? 1.0 : clampedElapsedMs / totalDelayMs;
    final remainingDuration = Duration(
      milliseconds: (totalDelayMs - clampedElapsedMs).clamp(0, totalDelayMs),
    );

    return TweenAnimationBuilder<double>(
      key: ValueKey(
        'deterministic-sync-delay-${startAt.millisecondsSinceEpoch}-$totalDelayMs',
      ),
      tween: Tween<double>(begin: begin, end: 1),
      duration: remainingDuration,
      builder: (context, progress, child) {
        final remainingMs = ((1 - progress) * totalDelayMs).ceil().clamp(
          0,
          totalDelayMs,
        );
        final remainingLabel = formatFaultInjectionDuration(remainingMs);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    remainingMs > 0
                        ? 'Delay remaining: $remainingLabel'
                        : 'Delay complete. Finishing remote replay...',
                    key: const ValueKey('task-workspace-sync-delay-label'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatFaultInjectionDuration(totalDuration.inMilliseconds),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                key: const ValueKey('task-workspace-sync-delay-progress'),
                minHeight: 4,
                value: progress,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceMetricChip extends StatelessWidget {
  const _WorkspaceMetricChip({
    required this.label,
    required this.value,
    required this.tone,
    required this.foreground,
    this.dense = false,
    this.valueKey,
  });

  final String label;
  final String value;
  final Color tone;
  final Color foreground;
  final bool dense;
  final Key? valueKey;

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
                  key: valueKey,
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
                  key: valueKey,
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

class _DesktopPaneScrollbar extends StatefulWidget {
  const _DesktopPaneScrollbar({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  State<_DesktopPaneScrollbar> createState() => _DesktopPaneScrollbarState();
}

class _DesktopPaneScrollbarState extends State<_DesktopPaneScrollbar> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _ready = widget.controller.hasClients;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _DesktopPaneScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _ready = widget.controller.hasClients;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: widget.controller,
        thumbVisibility: _ready,
        trackVisibility: _ready,
        interactive: _ready,
        thickness: 14,
        radius: const Radius.circular(999),
        child: widget.child,
      ),
    );
  }
}

class _WorkspaceTaskCard extends StatelessWidget {
  const _WorkspaceTaskCard({
    required this.task,
    required this.isBatchMode,
    required this.isBatchSelected,
    required this.isSelected,
    required this.dense,
    required this.onTap,
    required this.onMarkDone,
    required this.onToggleBatchSelection,
  });

  final TaskModel task;
  final bool isBatchMode;
  final bool isBatchSelected;
  final bool isSelected;
  final bool dense;
  final VoidCallback onTap;
  final VoidCallback? onMarkDone;
  final VoidCallback? onToggleBatchSelection;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useStackedHeader = constraints.maxWidth < 520;

          return InkWell(
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
                  if (useStackedHeader)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
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
                        SizedBox(height: dense ? 10 : 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _buildTaskCardActions(theme, statusColor),
                        ),
                      ],
                    )
                  else
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
                        const SizedBox(width: 12),
                        _buildTaskCardActions(theme, statusColor),
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
                    hasDescription
                        ? task.description!.trim()
                        : _taskSummary(task),
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
          );
        },
      ),
    );
  }

  Widget _buildTaskCardActions(ThemeData theme, Color statusColor) {
    if (isBatchMode) {
      return Checkbox(
        value: isBatchSelected,
        onChanged: (_) => onToggleBatchSelection?.call(),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isSelected ? Icons.check_circle : Icons.circle_outlined,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        const SizedBox(width: 8),
        if (task.isCompleted)
          _WorkspaceBadge(
            icon: Icons.task_alt_outlined,
            label: 'Completed',
            backgroundColor: _statusBackgroundColor(
              task.status,
              theme.colorScheme,
            ),
            foregroundColor: statusColor,
          )
        else
          OutlinedButton.icon(
            onPressed: onMarkDone,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Mark done'),
          ),
      ],
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
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
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

class _ConflictFieldDiffData {
  const _ConflictFieldDiffData({
    required this.label,
    required this.localValue,
    required this.remoteValue,
  });

  final String label;
  final String localValue;
  final String remoteValue;
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
