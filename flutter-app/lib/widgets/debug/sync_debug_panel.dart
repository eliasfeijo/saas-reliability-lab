import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/widgets/debug/debug_status_card.dart';

class SyncDebugPanel extends StatelessWidget {
  const SyncDebugPanel({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<RuntimeDebugProvider>(
      builder: (context, runtimeDebug, child) {
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
                title: 'Future Operation States',
                subtitle:
                    'Reserved space for the explicit outbox and conflict model.',
                leading: const Icon(Icons.account_tree_outlined),
                accentColor: theme.colorScheme.outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _placeholderStateChip(context, 'Queued'),
                        _placeholderStateChip(context, 'Sending'),
                        _placeholderStateChip(context, 'Acknowledged'),
                        _placeholderStateChip(context, 'Failed'),
                        _placeholderStateChip(context, 'Conflict'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The current sync engine is task-based rather than operation-based. These placeholders deliberately reserve UI real estate so the explicit outbox can land here without another shell redesign.',
                      style: theme.textTheme.bodyMedium,
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
                            .map((event) => _eventTile(context, event))
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
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

  Widget _eventTile(BuildContext context, RuntimeEvent event) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusBadge(
                context,
                event.category.label,
                theme.colorScheme.primary,
              ),
              _statusBadge(
                context,
                event.level.label,
                _eventColor(event.level, theme),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(event.message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            _formatTimestamp(event.timestamp),
            style: theme.textTheme.bodySmall,
          ),
          if (event.detail != null && event.detail!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(event.detail!, style: theme.textTheme.bodySmall),
          ],
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

  Widget _placeholderStateChip(BuildContext context, String label) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(label, style: theme.textTheme.labelLarge),
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
