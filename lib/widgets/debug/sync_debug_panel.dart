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
                      label: 'Initial load',
                      value: state.isInitialLoadRunning ? 'Running' : 'Settled',
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
                title: 'Recent Events',
                subtitle: 'Most recent runtime events retained in memory.',
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
          Row(
            children: [
              Text(event.category.label, style: theme.textTheme.labelLarge),
              const Spacer(),
              Text(
                event.level.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _eventColor(event.level, theme),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
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

  Color _syncAccent(RuntimeSyncPhase phase, ThemeData theme) {
    switch (phase) {
      case RuntimeSyncPhase.syncing:
        return theme.colorScheme.tertiary;
      case RuntimeSyncPhase.offline:
      case RuntimeSyncPhase.blockedNoSession:
        return theme.colorScheme.secondary;
      case RuntimeSyncPhase.error:
        return theme.colorScheme.error;
      case RuntimeSyncPhase.idle:
      case RuntimeSyncPhase.initialLoad:
        return theme.colorScheme.primary;
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
