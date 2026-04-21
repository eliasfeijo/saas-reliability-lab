import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/outbox_entry.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/fault_injection_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/widgets/debug/debug_status_card.dart';

class SyncDebugPanel extends StatelessWidget {
  const SyncDebugPanel({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer2<RuntimeDebugProvider, FaultInjectionProvider>(
      builder: (context, runtimeDebug, faultInjection, child) {
        final agenda = context.watch<AgendaProvider>();
        final state = runtimeDebug.state;

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(compact ? 0 : 28),
            border: compact
                ? null
                : Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Runtime Diagnostics',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Live evidence for auth, sync, local state, and push behavior.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              DebugStatusCard(
                title: 'Reset Controls',
                subtitle:
                    'Operator-friendly cleanup paths for recording and destructive reset workflows.',
                leading: const Icon(Icons.video_settings_outlined),
                accentColor: theme.colorScheme.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use these controls when you need a cleaner diagnostics surface for demos or a confirmed full workspace reset without explaining the mechanics on-screen.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _confirmSoftReset(
                            context,
                            agenda: agenda,
                            runtimeDebug: runtimeDebug,
                            faultInjection: faultInjection,
                          ),
                          icon: const Icon(Icons.auto_fix_high_outlined),
                          label: const Text('Soft demo reset'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.errorContainer,
                            foregroundColor: theme.colorScheme.onErrorContainer,
                          ),
                          onPressed: () => _confirmHardReset(
                            context,
                            agenda: agenda,
                            runtimeDebug: runtimeDebug,
                            faultInjection: faultInjection,
                            hasAuthenticatedSession:
                                state.hasAuthenticatedSession,
                            preview: agenda.hardResetPreview,
                          ),
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: const Text('Hard reset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Sync State',
                subtitle: 'Current connectivity and synchronization lifecycle.',
                leading: const Icon(Icons.sync),
                accentColor: _syncAccent(state.syncPhase, theme),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusBadge(
                          context,
                          state.connectivityStatus.label,
                          _connectivityColor(state.connectivityStatus, theme),
                        ),
                        _statusBadge(
                          context,
                          state.syncPhase.label,
                          _syncAccent(state.syncPhase, theme),
                        ),
                        _statusBadge(
                          context,
                          state.lastSyncResult.label,
                          _resultColor(state.lastSyncResult, theme),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _statusRow(
                      context,
                      label: 'Connectivity',
                      value: state.connectivityStatus.label,
                    ),
                    _statusRow(
                      context,
                      label: 'Phase',
                      value: state.syncPhase.label,
                    ),
                    _statusRow(
                      context,
                      label: 'Last result',
                      value: state.lastSyncResult.label,
                    ),
                    _statusRow(
                      context,
                      label: 'Last message',
                      value:
                          state.lastSyncMessage ??
                          'No sync event recorded yet.',
                    ),
                    _statusRow(
                      context,
                      label: 'Started',
                      value: _formatTimestamp(state.lastSyncStartedAt),
                    ),
                    _statusRow(
                      context,
                      label: 'Completed',
                      value: _formatTimestamp(state.lastSyncCompletedAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Sync Outcomes',
                subtitle: 'Most recent outcome recorded for each sync path.',
                leading: const Icon(Icons.fact_check_outlined),
                accentColor: _resultColor(state.lastSyncResult, theme),
                child: Column(
                  children: [
                    _outcomeTile(
                      context,
                      title: 'Successful sync',
                      timestamp: state.lastSuccessfulSyncAt,
                      message: state.lastSuccessfulSyncMessage,
                      accent: theme.colorScheme.primary,
                    ),
                    _outcomeTile(
                      context,
                      title: 'Skipped sync',
                      timestamp: state.lastSkippedSyncAt,
                      message: state.lastSkippedSyncMessage,
                      accent: theme.colorScheme.secondary,
                    ),
                    _outcomeTile(
                      context,
                      title: 'Partial sync',
                      timestamp: state.lastPartialSyncAt,
                      message: state.lastPartialSyncMessage,
                      accent: theme.colorScheme.tertiary,
                    ),
                    _outcomeTile(
                      context,
                      title: 'Failed sync',
                      timestamp: state.lastFailedSyncAt,
                      message: state.lastFailedSyncMessage,
                      accent: theme.colorScheme.error,
                      isLast: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Fault Injection',
                subtitle: state.activeFaultInjectionLabel == null
                    ? 'No controlled failure scenario is active right now.'
                    : 'The current runtime state is being influenced by an active controlled scenario.',
                leading: const Icon(Icons.science_outlined),
                accentColor: state.activeFaultInjectionLabel == null
                    ? theme.colorScheme.outline
                    : theme.colorScheme.error,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.activeFaultInjectionLabel == null)
                      Text(
                        'Use Scenario Controls in the operator rail to activate a controlled failure and observe its evidence here.',
                        style: theme.textTheme.bodyMedium,
                      )
                    else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          InputChip(
                            avatar: Icon(
                              Icons.science_outlined,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            label: Text(state.activeFaultInjectionLabel!),
                            selected: true,
                            showCheckmark: false,
                            deleteIcon: Icon(
                              Icons.close,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            onDeleted: () async {
                              await faultInjection.clearScenario();
                            },
                            selectedColor: theme.colorScheme.error.withValues(
                              alpha: 0.14,
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.28,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _statusRow(
                        context,
                        label: 'Scenario',
                        value: state.activeFaultInjectionLabel!,
                      ),
                      _statusRow(
                        context,
                        label: 'Summary',
                        value:
                            state.activeFaultInjectionMessage ??
                            'No summary recorded.',
                      ),
                      if (faultInjection.state.activeScenario ==
                              FaultInjectionScenario.delayedSync &&
                          faultInjection.state.delayLabel != null)
                        _statusRow(
                          context,
                          label: 'Injected delay',
                          value: faultInjection.state.delayLabel!,
                        ),
                      const SizedBox(height: 8),
                      Text('How to operate', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(
                        state.activeFaultInjectionInstruction ??
                            'No operator instruction recorded.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              await faultInjection.clearScenario();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reset failure scenario'),
                          ),
                          Text(
                            'Use this rail when you want to narrate the evidence and clear the scenario without jumping back to the operator controls.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Session Truth',
                subtitle:
                    'Supabase auth state compared with cached local identity.',
                leading: const Icon(Icons.person_outline),
                accentColor: state.hasAuthenticatedSession
                    ? theme.colorScheme.primary
                    : theme.colorScheme.secondary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statusRow(
                      context,
                      label: 'Authenticated session',
                      value: state.hasAuthenticatedSession ? 'Active' : 'None',
                    ),
                    _statusRow(
                      context,
                      label: 'Active user',
                      value: _summarizeId(state.activeUserId),
                    ),
                    _statusRow(
                      context,
                      label: 'Cached user',
                      value: _summarizeId(state.cachedUserId),
                    ),
                    _statusRow(
                      context,
                      label: 'Identity check',
                      value: _identityAlignment(state),
                    ),
                    _statusRow(
                      context,
                      label: 'Initial load',
                      value: state.isInitialLoadRunning ? 'Running' : 'Settled',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Operation States',
                subtitle:
                    'Current outbox state across queued, blocked, in-flight, and reviewed work.',
                leading: const Icon(Icons.account_tree_outlined),
                accentColor: state.conflictEntryCount > 0
                    ? theme.colorScheme.error
                    : state.failedEntryCount > 0
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _stateCountChip(
                          context,
                          'Queued',
                          state.queuedEntryCount,
                          theme.colorScheme.primary,
                        ),
                        _stateCountChip(
                          context,
                          'Sending',
                          state.sendingEntryCount,
                          theme.colorScheme.secondary,
                        ),
                        _stateCountChip(
                          context,
                          'Acknowledged',
                          state.acknowledgedEntryCount,
                          theme.colorScheme.tertiary,
                        ),
                        _stateCountChip(
                          context,
                          'Failed',
                          state.failedEntryCount,
                          theme.colorScheme.error,
                        ),
                        _stateCountChip(
                          context,
                          'Conflict',
                          state.conflictEntryCount,
                          theme.colorScheme.error,
                        ),
                        _stateCountChip(
                          context,
                          'Blocked Review',
                          state.blockedAnonymousReviewEntryCount,
                          theme.colorScheme.secondary,
                        ),
                        _stateCountChip(
                          context,
                          'Blocked Session',
                          state.blockedNoSessionEntryCount,
                          theme.colorScheme.secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _statusRow(
                      context,
                      label: 'Queued',
                      value: state.queuedEntryCount.toString(),
                    ),
                    _statusRow(
                      context,
                      label: 'Sending',
                      value: state.sendingEntryCount.toString(),
                    ),
                    _statusRow(
                      context,
                      label: 'Failed',
                      value: state.failedEntryCount.toString(),
                    ),
                    _statusRow(
                      context,
                      label: 'Conflict',
                      value: state.conflictEntryCount.toString(),
                    ),
                    _statusRow(
                      context,
                      label: 'Blocked review',
                      value: state.blockedAnonymousReviewEntryCount.toString(),
                    ),
                    _statusRow(
                      context,
                      label: 'Blocked session',
                      value: state.blockedNoSessionEntryCount.toString(),
                    ),
                    if (state.conflictEntries.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Conflict review',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      ...state.conflictEntries
                          .take(3)
                          .map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.errorContainer
                                      .withValues(alpha: 0.24),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: theme.colorScheme.error.withValues(
                                      alpha: 0.22,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _taskTitleForEntry(entry),
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      entry.lastError ??
                                          'Remote state changed after this operation was queued.',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    if (_remoteSnapshotTitle(entry) !=
                                        null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Remote version: ${_remoteSnapshotTitle(entry)}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        OutlinedButton(
                                          onPressed: () async {
                                            await context
                                                .read<AgendaProvider>()
                                                .keepRemoteConflict(
                                                  entry.taskId,
                                                );
                                            if (!context.mounted) {
                                              return;
                                            }
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Kept remote state for ${_taskTitleForEntry(entry)}.',
                                                ),
                                              ),
                                            );
                                          },
                                          child: const Text(
                                            'Keep remote version',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        FilledButton(
                                          onPressed: () async {
                                            await context
                                                .read<AgendaProvider>()
                                                .reapplyLocalConflict(
                                                  entry.taskId,
                                                );
                                            if (!context.mounted) {
                                              return;
                                            }
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Re-queued local intent for ${_taskTitleForEntry(entry)}.',
                                                ),
                                              ),
                                            );
                                          },
                                          child: const Text(
                                            'Reapply local intent',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                    ],
                    if (state.recentAcknowledgements.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Recent acknowledgements',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      ...state.recentAcknowledgements
                          .take(3)
                          .map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${entry.operationType.name} ${entry.taskId}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ),
                    ],
                    if (state.recentAcknowledgements.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Retained acknowledgements stay in local outbox storage until they are displaced by newer acknowledgements or explicitly cleared here.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (state.recentAcknowledgements.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () async {
                              await context
                                  .read<AgendaProvider>()
                                  .clearRetainedAcknowledgements();
                            },
                            icon: const Icon(Icons.cleaning_services_outlined),
                            label: const Text('Clear retained history'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Local State',
                subtitle:
                    'Task counts that affect replay, adoption, and cleanup.',
                leading: const Icon(Icons.storage_outlined),
                accentColor: theme.colorScheme.tertiary,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _metricPill(
                      context,
                      'Dirty',
                      state.dirtyTaskCount.toString(),
                    ),
                    _metricPill(
                      context,
                      'Deleted',
                      state.deletedTaskCount.toString(),
                    ),
                    _metricPill(
                      context,
                      'Anonymous',
                      state.anonymousTaskCount.toString(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Push State',
                subtitle: 'Browser permission and subscription lifecycle.',
                leading: const Icon(Icons.notifications_active_outlined),
                accentColor: theme.colorScheme.secondary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statusRow(
                      context,
                      label: 'Permission',
                      value: state.pushPermissionState.label,
                    ),
                    _statusRow(
                      context,
                      label: 'Subscription',
                      value: state.pushSubscriptionState.label,
                    ),
                    _statusRow(
                      context,
                      label: 'Last push message',
                      value:
                          state.lastPushMessage ??
                          'No push registration activity yet.',
                    ),
                    _statusRow(
                      context,
                      label: 'Updated',
                      value: _formatTimestamp(state.lastPushUpdatedAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Event Timeline',
                subtitle:
                    'Recent runtime evidence retained in memory for inspection.',
                leading: const Icon(Icons.history),
                accentColor: theme.colorScheme.primary,
                child: state.recentEvents.isEmpty
                    ? Text(
                        'Events will appear here as the app loads, authenticates, syncs, and registers push.',
                        style: theme.textTheme.bodySmall,
                      )
                    : Column(
                        children: state.recentEvents
                            .map(
                              (event) => _RuntimeEventTile(
                                key: ValueKey(event.id),
                                event: event,
                                compact: compact,
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmSoftReset(
    BuildContext context, {
    required AgendaProvider agenda,
    required RuntimeDebugProvider runtimeDebug,
    required FaultInjectionProvider faultInjection,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Soft demo reset?'),
          content: const Text(
            'This clears retained acknowledgements, sync outcome history, the in-memory event timeline, and active fault-injection evidence. It keeps live auth state, push state, local tasks, and active outbox entries intact.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Soft reset'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await agenda.clearRetainedAcknowledgements();
    await faultInjection.clearScenario();
    runtimeDebug.resetDemoSurface();

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Soft demo reset cleared transient diagnostics while preserving live task and push state.',
        ),
      ),
    );
  }

  Future<void> _confirmHardReset(
    BuildContext context, {
    required AgendaProvider agenda,
    required RuntimeDebugProvider runtimeDebug,
    required FaultInjectionProvider faultInjection,
    required bool hasAuthenticatedSession,
    required HardResetPreview preview,
  }) async {
    final requiresSession =
        preview.remoteDeleteCount > 0 && !hasAuthenticatedSession;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hard reset workspace?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hard reset immediately replays authenticated remote deletions to the database, then clears every local task and outbox entry on this device.',
              ),
              const SizedBox(height: 12),
              Text('Remote deletes: ${preview.remoteDeleteCount}'),
              Text(
                'Authenticated local-only removals: ${preview.authenticatedLocalOnlyRemovalCount}',
              ),
              Text(
                'Anonymous local removals: ${preview.anonymousRemovalCount}',
              ),
              if (requiresSession) ...[
                const SizedBox(height: 12),
                Text(
                  'A live authenticated session is required before this action can confirm remote deletions.',
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(requiresSession ? 'Close' : 'Cancel'),
            ),
            if (!requiresSession)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(
                    dialogContext,
                  ).colorScheme.errorContainer,
                  foregroundColor: Theme.of(
                    dialogContext,
                  ).colorScheme.onErrorContainer,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete and wipe'),
              ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      final completedPreview = await agenda.hardResetWorkspace();
      await faultInjection.clearScenario();
      runtimeDebug.resetDemoSurface();

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Hard reset deleted ${completedPreview.remoteDeleteCount} remote-backed task(s) and cleared all local task state.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Widget _statusRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  String _taskTitleForEntry(OutboxEntry entry) {
    return (entry.taskPayload['title'] as String?)?.trim().isNotEmpty == true
        ? entry.taskPayload['title'] as String
        : 'Untitled task';
  }

  String? _remoteSnapshotTitle(OutboxEntry entry) {
    final title = entry.remoteSnapshot?['title'] as String?;
    if (title == null || title.trim().isEmpty) {
      return null;
    }

    return title;
  }

  Widget _metricPill(BuildContext context, String label, String value) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }

  Widget _outcomeTile(
    BuildContext context, {
    required String title,
    required DateTime? timestamp,
    required String? message,
    required Color accent,
    bool isLast = false,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(color: accent),
          ),
          const SizedBox(height: 4),
          Text(_formatTimestamp(timestamp), style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            message ?? 'Not recorded yet.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(BuildContext context, String label, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: tone),
      ),
    );
  }

  Widget _stateCountChip(
    BuildContext context,
    String label,
    int count,
    Color color,
  ) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text('$label: $count', style: theme.textTheme.labelLarge),
    );
  }

  Color _syncAccent(RuntimeSyncPhase phase, ThemeData theme) {
    switch (phase) {
      case RuntimeSyncPhase.syncing:
        return theme.colorScheme.tertiary;
      case RuntimeSyncPhase.offline:
      case RuntimeSyncPhase.blockedNoSession:
      case RuntimeSyncPhase.blockedAnonymousReview:
        return theme.colorScheme.secondary;
      case RuntimeSyncPhase.error:
        return theme.colorScheme.error;
      case RuntimeSyncPhase.idle:
      case RuntimeSyncPhase.initialLoad:
        return theme.colorScheme.primary;
    }
  }

  Color _connectivityColor(ConnectivityStatus status, ThemeData theme) {
    switch (status) {
      case ConnectivityStatus.online:
        return theme.colorScheme.primary;
      case ConnectivityStatus.offline:
        return theme.colorScheme.secondary;
      case ConnectivityStatus.unknown:
        return theme.colorScheme.outline;
    }
  }

  Color _resultColor(RuntimeSyncResult result, ThemeData theme) {
    switch (result) {
      case RuntimeSyncResult.success:
        return theme.colorScheme.primary;
      case RuntimeSyncResult.skipped:
        return theme.colorScheme.secondary;
      case RuntimeSyncResult.partial:
        return theme.colorScheme.tertiary;
      case RuntimeSyncResult.failed:
        return theme.colorScheme.error;
      case RuntimeSyncResult.none:
        return theme.colorScheme.outline;
    }
  }

  String _identityAlignment(RuntimeDebugState state) {
    if (state.activeUserId == null && state.cachedUserId == null) {
      return 'No identity loaded';
    }
    if (state.activeUserId == state.cachedUserId) {
      return 'Matched';
    }
    if (state.activeUserId == null && state.cachedUserId != null) {
      return 'Cached only';
    }
    if (state.activeUserId != null && state.cachedUserId == null) {
      return 'Session only';
    }
    return 'Mismatch';
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) {
      return 'Not recorded';
    }

    final localTime = timestamp.toLocal();
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    final second = localTime.second.toString().padLeft(2, '0');
    return '${localTime.year}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')} $hour:$minute:$second';
  }

  String _summarizeId(String? value) {
    if (value == null || value.isEmpty) {
      return 'None';
    }
    if (value.length <= 12) {
      return value;
    }
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }
}

class _RuntimeEventTile extends StatefulWidget {
  const _RuntimeEventTile({
    super.key,
    required this.event,
    required this.compact,
  });

  final RuntimeEvent event;
  final bool compact;

  @override
  State<_RuntimeEventTile> createState() => _RuntimeEventTileState();
}

class _RuntimeEventTileState extends State<_RuntimeEventTile> {
  bool _detailsVisible = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = widget.event.payload;
    final hasDetailText =
        widget.event.detail != null && widget.event.detail!.isNotEmpty;
    final canInspect = widget.event.hasInspectableDetails;
    final shouldOfferDialog =
        canInspect &&
        (widget.compact ||
            (payload?.tasks.length ?? 0) > 2 ||
            (payload?.tasks.any((task) => task.fieldDiffs.length > 2) ??
                false));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _eventBadge(
                context,
                widget.event.category.label,
                theme.colorScheme.primary,
              ),
              _eventBadge(
                context,
                widget.event.level.label,
                _eventColor(widget.event.level, theme),
              ),
              if (payload?.stage case final stage?)
                _eventBadge(context, stage, theme.colorScheme.tertiary),
            ],
          ),
          const SizedBox(height: 10),
          Text(widget.event.message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            _formatRuntimeTimestamp(widget.event.timestamp),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (canInspect)
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _detailsVisible = !_detailsVisible;
                    });
                  },
                  icon: Icon(
                    _detailsVisible
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                  label: Text(
                    _detailsVisible ? 'Hide context' : 'View context',
                  ),
                ),
                if (shouldOfferDialog) ...[
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _showFullRecordDialog(context),
                    icon: const Icon(Icons.open_in_full_outlined),
                    label: const Text('Open full record'),
                  ),
                ],
              ],
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: canInspect && _detailsVisible
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _InlineEventDetails(
                      event: widget.event,
                      maxTasks: shouldOfferDialog ? 2 : 4,
                      showTruncationHint: shouldOfferDialog,
                      forceNotesVisible: hasDetailText,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _showFullRecordDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.all(20),
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
                              'Event record',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.event.message,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _InlineEventDetails(
                        event: widget.event,
                        maxTasks: null,
                        showTruncationHint: false,
                        forceNotesVisible: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InlineEventDetails extends StatelessWidget {
  const _InlineEventDetails({
    required this.event,
    required this.maxTasks,
    required this.showTruncationHint,
    required this.forceNotesVisible,
  });

  final RuntimeEvent event;
  final int? maxTasks;
  final bool showTruncationHint;
  final bool forceNotesVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = event.payload;
    final tasks = maxTasks == null || payload == null
        ? payload?.visibleTasks ?? const <RuntimeEventTaskDetail>[]
        : payload.visibleTasks.take(maxTasks!).toList(growable: false);
    final hasExtraTasks =
        payload != null &&
        maxTasks != null &&
        payload.visibleTasks.length > maxTasks!;
    final visibleMetrics =
        payload?.visibleMetrics ?? const <RuntimeEventMetric>[];
    final visibleNotes = payload?.visibleNotes ?? const <String>[];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (payload?.summary case final summary?) ...[
            Text('Operator summary', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(summary, style: theme.textTheme.bodyMedium),
          ],
          if (visibleMetrics.isNotEmpty) ...[
            if (payload?.summary != null) const SizedBox(height: 14),
            Text('Key metrics', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: visibleMetrics
                  .map(
                    (metric) =>
                        _MetricChip(label: metric.label, value: metric.value),
                  )
                  .toList(),
            ),
          ],
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Tasks touched', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ...tasks.map((task) => _TaskDetailCard(task: task)),
            if (hasExtraTasks || showTruncationHint) ...[
              const SizedBox(height: 8),
              Text(
                hasExtraTasks
                    ? 'More task-level evidence is available in the full record.'
                    : 'Open the full record when you want more room for the state diff.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
          if (forceNotesVisible ||
              (event.detail != null && event.detail!.isNotEmpty) ||
              visibleNotes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Notes', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (event.detail != null && event.detail!.isNotEmpty)
              _NoteLine(value: event.detail!),
            ...visibleNotes.map((note) => _NoteLine(value: note)),
            if ((event.detail == null || event.detail!.isEmpty) &&
                visibleNotes.isEmpty)
              Text(
                'No additional note was recorded for this event.',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _TaskDetailCard extends StatelessWidget {
  const _TaskDetailCard({required this.task});

  final RuntimeEventTaskDetail task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleTags = task.visibleTags;
    final visibleFieldDiffs = task.visibleFieldDiffs;
    final hasBadges =
        (task.syncStatus?.trim().isNotEmpty ?? false) ||
        (task.outcome?.trim().isNotEmpty ?? false) ||
        visibleTags.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title, style: theme.textTheme.titleSmall),
          if (hasBadges) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (task.syncStatus case final syncStatus?
                    when syncStatus.trim().isNotEmpty)
                  _eventBadge(context, syncStatus, theme.colorScheme.secondary),
                if (task.outcome case final outcome?
                    when outcome.trim().isNotEmpty)
                  _eventBadge(context, outcome, theme.colorScheme.tertiary),
                ...visibleTags.map(
                  (tag) => _eventBadge(context, tag, theme.colorScheme.primary),
                ),
              ],
            ),
          ],
          if (task.taskId case final taskId?) ...[
            const SizedBox(height: 8),
            Text('Task ID: $taskId', style: theme.textTheme.bodySmall),
          ],
          if (task.description case final description?) ...[
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodyMedium),
          ],
          if (visibleFieldDiffs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('State diff', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            ...visibleFieldDiffs.map((field) => _FieldDiffRow(field: field)),
          ],
        ],
      ),
    );
  }
}

class _FieldDiffRow extends StatelessWidget {
  const _FieldDiffRow({required this.field});

  final RuntimeEventFieldDiff field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text('Before: ${field.before}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text('After: ${field.after}', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(value, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

Widget _eventBadge(BuildContext context, String label, Color tone) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: tone.withValues(alpha: 0.18)),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: tone),
    ),
  );
}

Color _eventColor(RuntimeEventLevel level, ThemeData theme) {
  switch (level) {
    case RuntimeEventLevel.info:
      return theme.colorScheme.primary;
    case RuntimeEventLevel.warning:
      return theme.colorScheme.secondary;
    case RuntimeEventLevel.error:
      return theme.colorScheme.error;
  }
}

String _formatRuntimeTimestamp(DateTime timestamp) {
  final localTime = timestamp.toLocal();
  final hour = localTime.hour.toString().padLeft(2, '0');
  final minute = localTime.minute.toString().padLeft(2, '0');
  final second = localTime.second.toString().padLeft(2, '0');
  return '${localTime.year}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')} $hour:$minute:$second';
}
