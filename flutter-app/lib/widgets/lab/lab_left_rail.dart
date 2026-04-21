import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/helpers/web_push_helper.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/fault_injection_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/widgets/bottomsheets/login.dart';
import 'package:todo_flutter/widgets/debug/debug_status_card.dart';

class LabLeftRail extends StatefulWidget {
  const LabLeftRail({super.key, this.compact = false});

  final bool compact;

  @override
  State<LabLeftRail> createState() => _LabLeftRailState();
}

class _LabLeftRailState extends State<LabLeftRail> {
  bool _isLoggingOut = false;
  bool _isReviewingAnonymousTasks = false;

  void _showLoginBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const LoginBottomSheet(),
    );
  }

  Future<void> _syncNow() async {
    final agenda = context.read<AgendaProvider>();
    final faultInjection = context.read<FaultInjectionProvider>();
    final runtimeDebug = context.read<RuntimeDebugProvider>();

    if (agenda.userId == null || agenda.userId!.isEmpty) {
      runtimeDebug.addEvent(
        category: RuntimeEventCategory.sync,
        message: 'Manual sync was requested without an authenticated session.',
        level: RuntimeEventLevel.warning,
        payload: const RuntimeEventPayload(
          stage: 'Manual sync blocked',
          summary:
              'An operator-triggered sync request was blocked because the workspace is not authenticated.',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to run a cloud sync.')),
      );
      return;
    }

    if (agenda.hasPendingAnonymousReview) {
      runtimeDebug.markSyncSkipped(
        phase: RuntimeSyncPhase.blockedAnonymousReview,
        message:
            'Anonymous local tasks are waiting for review. Keep or discard them before cloud sync.',
        payload: const RuntimeEventPayload(
          stage: 'Manual sync blocked',
          summary:
              'The requested sync pass cannot start until the operator resolves anonymous local tasks.',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review anonymous tasks before running cloud sync.'),
        ),
      );
      return;
    }

    runtimeDebug.addEvent(
      category: RuntimeEventCategory.sync,
      message: 'Manual sync requested from the operator rail.',
      payload: RuntimeEventPayload(
        stage: 'Manual sync requested',
        summary:
            'The operator explicitly triggered a sync pass from the left rail.',
        metrics: [
          RuntimeEventMetric(
            label: 'Pending review',
            value: agenda.hasPendingAnonymousReview ? 'Yes' : 'No',
          ),
          RuntimeEventMetric(
            label: 'Selected user',
            value: (agenda.userId == null || agenda.userId!.isEmpty)
                ? 'None'
                : 'Authenticated',
          ),
        ],
      ),
    );
    await agenda.syncAllTasks();

    if (!mounted) return;
    final syncMessage =
        faultInjection.state.activeScenario ==
            FaultInjectionScenario.connectivityLoss
        ? 'Connectivity loss scenario applied. Check diagnostics for the skipped sync outcome.'
        : 'Sync requested.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(syncMessage)));
  }

  Future<void> _activateScenario(FaultInjectionScenario scenario) async {
    final faultInjection = context.read<FaultInjectionProvider>();

    await faultInjection.activateScenario(scenario);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${scenario.label} activated.')));
  }

  Future<void> _clearScenario() async {
    final faultInjection = context.read<FaultInjectionProvider>();

    await faultInjection.clearScenario();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Scenario reset.')));
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;

    final runtimeDebug = context.read<RuntimeDebugProvider>();

    setState(() {
      _isLoggingOut = true;
    });

    String failureMessage = 'Logout failed. Please try again.';
    var loggedOut = false;

    try {
      try {
        await unregisterWebPushSubscription(runtimeDebug: runtimeDebug);
      } catch (error) {
        debugPrint(
          '[Auth] Failed to unregister web push during logout: $error',
        );
      }

      try {
        await Supabase.instance.client.auth.signOut();
        final auth = Supabase.instance.client.auth;
        loggedOut = auth.currentUser == null && auth.currentSession == null;
      } on AuthException catch (error) {
        final auth = Supabase.instance.client.auth;
        loggedOut = auth.currentUser == null && auth.currentSession == null;
        if (loggedOut) {
          debugPrint(
            '[Auth] Remote logout cleanup failed after local sign-out: ${error.message}',
          );
        } else {
          failureMessage = error.message;
        }
      } catch (error) {
        final auth = Supabase.instance.client.auth;
        loggedOut = auth.currentUser == null && auth.currentSession == null;
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

    runtimeDebug.addEvent(
      category: RuntimeEventCategory.auth,
      message: loggedOut
          ? 'User logged out from the operator rail.'
          : failureMessage,
      level: loggedOut ? RuntimeEventLevel.info : RuntimeEventLevel.error,
      payload: RuntimeEventPayload(
        stage: loggedOut ? 'Logout completed' : 'Logout failed',
        summary: loggedOut
            ? 'The operator completed a logout flow from the left rail.'
            : 'The left-rail logout flow did not complete successfully.',
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loggedOut ? 'Logged out' : failureMessage)),
    );
  }

  Future<void> _adoptAnonymousTasks() async {
    if (_isReviewingAnonymousTasks) return;

    final agenda = context.read<AgendaProvider>();
    final runtimeDebug = context.read<RuntimeDebugProvider>();

    setState(() {
      _isReviewingAnonymousTasks = true;
    });

    try {
      await agenda.takeOwnershipOfAnonymousTasks();
      runtimeDebug.addEvent(
        category: RuntimeEventCategory.storage,
        message: 'Anonymous tasks were adopted into the authenticated account.',
        payload: const RuntimeEventPayload(
          stage: 'Anonymous tasks kept',
          summary:
              'Local-only anonymous tasks were retained and adopted into the authenticated account.',
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Anonymous tasks adopted.')));
    } finally {
      if (mounted) {
        setState(() {
          _isReviewingAnonymousTasks = false;
        });
      }
    }
  }

  Future<void> _discardAnonymousTasks() async {
    if (_isReviewingAnonymousTasks) return;

    final agenda = context.read<AgendaProvider>();
    final runtimeDebug = context.read<RuntimeDebugProvider>();
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Anonymous Tasks'),
        content: const Text(
          'Discard all anonymous local tasks that are still waiting for review?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDiscard != true) {
      return;
    }

    setState(() {
      _isReviewingAnonymousTasks = true;
    });

    try {
      await agenda.discardAnonymousTasks();
      runtimeDebug.addEvent(
        category: RuntimeEventCategory.storage,
        message: 'Anonymous local tasks were discarded from local storage.',
        level: RuntimeEventLevel.warning,
        payload: const RuntimeEventPayload(
          stage: 'Anonymous tasks discarded',
          summary:
              'Local-only anonymous tasks were explicitly removed before cloud sync could continue.',
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anonymous tasks discarded.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isReviewingAnonymousTasks = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer3<
      AgendaProvider,
      RuntimeDebugProvider,
      FaultInjectionProvider
    >(
      builder: (context, agenda, runtimeDebug, faultInjection, child) {
        final state = runtimeDebug.state;
        final faultState = faultInjection.state;

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(widget.compact ? 0 : 28),
            border: widget.compact
                ? null
                : Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Operator Rail', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Persistent controls for session state, view scope, and reliability context.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              DebugStatusCard(
                title: 'Session Controls',
                subtitle: 'Primary auth and sync actions now live here.',
                leading: const Icon(Icons.verified_user_outlined),
                accentColor: state.hasAuthenticatedSession
                    ? theme.colorScheme.primary
                    : theme.colorScheme.secondary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusBadge(
                          context,
                          state.hasAuthenticatedSession
                              ? 'Authenticated'
                              : 'Anonymous',
                          state.hasAuthenticatedSession
                              ? theme.colorScheme.primary
                              : theme.colorScheme.secondary,
                        ),
                        _statusBadge(
                          context,
                          state.syncPhase.label,
                          _phaseColor(state.syncPhase, theme),
                        ),
                        _statusBadge(
                          context,
                          state.pushSubscriptionState.label,
                          _pushColor(state.pushSubscriptionState, theme),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _line(
                      context,
                      'Active user',
                      _summarizeId(state.activeUserId),
                    ),
                    _line(
                      context,
                      'Cached user',
                      _summarizeId(state.cachedUserId),
                    ),
                    _line(
                      context,
                      'Connectivity',
                      state.connectivityStatus.label,
                    ),
                    _line(context, 'Last sync', state.lastSyncResult.label),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!state.hasAuthenticatedSession)
                          FilledButton.tonalIcon(
                            onPressed: _showLoginBottomSheet,
                            icon: const Icon(Icons.login),
                            label: const Text('Open auth'),
                          ),
                        if (state.hasAuthenticatedSession)
                          FilledButton.tonalIcon(
                            onPressed: agenda.isLoading ? null : _syncNow,
                            icon: const Icon(Icons.sync),
                            label: const Text('Sync now'),
                          ),
                        if (state.hasAuthenticatedSession)
                          OutlinedButton.icon(
                            onPressed: _isLoggingOut ? null : _logout,
                            icon: const Icon(Icons.logout),
                            label: Text(
                              _isLoggingOut ? 'Logging out...' : 'Logout',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Task Scope',
                subtitle: 'Persistent view controls for the current workspace.',
                leading: const Icon(Icons.tune),
                accentColor: theme.colorScheme.tertiary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: TaskFilter.values.map((filter) {
                        return ChoiceChip(
                          label: Text(filter.displayName),
                          selected: agenda.currentFilter == filter,
                          onSelected: (_) => agenda.setFilter(filter),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _metricPill(
                          context,
                          'Visible',
                          agenda.filteredTasks.length.toString(),
                          valueKey: const ValueKey('task-scope-visible-value'),
                        ),
                        _metricPill(
                          context,
                          'Total',
                          agenda.totalTasks.toString(),
                          valueKey: const ValueKey('task-scope-total-value'),
                        ),
                        _metricPill(
                          context,
                          'Overdue',
                          agenda.overdueTasksCount.toString(),
                          valueKey: const ValueKey('task-scope-overdue-value'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Anonymous Task Review',
                subtitle: agenda.anonymousTasks.isEmpty
                    ? 'No anonymous tasks are waiting for review.'
                    : 'Resolve local-only tasks explicitly instead of hiding them in transient prompts.',
                leading: const Icon(Icons.person_search_outlined),
                accentColor: agenda.anonymousTasks.isEmpty
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.secondary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line(
                      context,
                      'Anonymous tasks',
                      agenda.anonymousTasks.length.toString(),
                      valueKey: const ValueKey('anonymous-review-count-value'),
                    ),
                    Text(
                      state.hasAuthenticatedSession
                          ? 'Review these local-only tasks here instead of relying only on the login-time dialog.'
                          : 'These tasks remain local-only until you sign in and choose how to reconcile them.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!state.hasAuthenticatedSession)
                          FilledButton.tonalIcon(
                            onPressed: agenda.anonymousTasks.isEmpty
                                ? null
                                : _showLoginBottomSheet,
                            icon: const Icon(Icons.login),
                            label: const Text('Sign in to review'),
                          ),
                        if (state.hasAuthenticatedSession)
                          FilledButton.tonalIcon(
                            onPressed:
                                agenda.anonymousTasks.isEmpty ||
                                    _isReviewingAnonymousTasks
                                ? null
                                : _adoptAnonymousTasks,
                            icon: const Icon(Icons.cloud_done_outlined),
                            label: Text(
                              _isReviewingAnonymousTasks
                                  ? 'Applying...'
                                  : 'Adopt tasks',
                            ),
                          ),
                        if (state.hasAuthenticatedSession)
                          OutlinedButton.icon(
                            onPressed:
                                agenda.anonymousTasks.isEmpty ||
                                    _isReviewingAnonymousTasks
                                ? null
                                : _discardAnonymousTasks,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Discard local'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Scenario Controls',
                subtitle: faultState.isActive
                    ? 'A controlled failure scenario is active. Use the normal lab controls to observe its effect.'
                    : 'Activate a controlled failure scenario here, then observe the resulting evidence in diagnostics and the event timeline.',
                leading: const Icon(Icons.science_outlined),
                accentColor: faultState.isActive
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: faultInjection.availableScenarios.map((
                        scenario,
                      ) {
                        final isActive =
                            faultState.isActive &&
                            faultState.activeScenario == scenario;
                        if (isActive) {
                          return InputChip(
                            avatar: Icon(
                              Icons.science_outlined,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            label: Text(scenario.label),
                            selected: true,
                            showCheckmark: false,
                            deleteIcon: Icon(
                              Icons.close,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            onDeleted: _clearScenario,
                            selectedColor: theme.colorScheme.error.withValues(
                              alpha: 0.14,
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.28,
                              ),
                            ),
                          );
                        }

                        return ChoiceChip(
                          label: Text(scenario.label),
                          selected: false,
                          onSelected: (_) async {
                            await _activateScenario(scenario);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      faultState.isActive
                          ? faultState.activeSummary ??
                                faultState.activeScenario.summary
                          : 'Connectivity loss and delayed sync are available now. Expired auth and partial replay drop are the next planned operator scenarios.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (faultState.activeScenario ==
                        FaultInjectionScenario.delayedSync) ...[
                      const SizedBox(height: 12),
                      Text('Delay preset', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: faultState.availableDelayPresets.map((
                          delayMs,
                        ) {
                          final label = formatFaultInjectionDuration(delayMs);
                          return ChoiceChip(
                            label: Text(label),
                            selected: faultState.effectiveDelayMs == delayMs,
                            onSelected: (_) async {
                              await faultInjection.setDelayedSyncDuration(
                                delayMs,
                              );
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use 5 s for most live walkthroughs. Use 10 s when you want extra narration time without making the behavior feel artificial.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            faultState.isActive
                                ? 'How to operate this scenario'
                                : 'How fault injection works here',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            faultState.isActive
                                ? faultState.operatorInstruction ?? ''
                                : 'Select a scenario chip to activate it. The active scenario keeps normal product controls in place, adds explicit evidence to runtime diagnostics, and writes a matching event to the timeline.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (faultState.isActive) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Tap the active red chip to clear the scenario instantly.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (!faultState.isActive) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const [
                          Chip(label: Text('Expired auth (planned)')),
                          Chip(label: Text('Partial replay drop (planned)')),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    String value, {
    Key? valueKey,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricPill(
    BuildContext context,
    String label,
    String value, {
    Key? valueKey,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, key: valueKey, style: theme.textTheme.titleMedium),
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
        border: Border.all(color: tone.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: tone),
      ),
    );
  }

  Color _phaseColor(RuntimeSyncPhase phase, ThemeData theme) {
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

  Color _pushColor(PushSubscriptionState state, ThemeData theme) {
    switch (state) {
      case PushSubscriptionState.registered:
        return theme.colorScheme.primary;
      case PushSubscriptionState.registering:
      case PushSubscriptionState.removing:
        return theme.colorScheme.tertiary;
      case PushSubscriptionState.failed:
        return theme.colorScheme.error;
      case PushSubscriptionState.unavailable:
        return theme.colorScheme.secondary;
      case PushSubscriptionState.unknown:
      case PushSubscriptionState.idle:
      case PushSubscriptionState.removed:
        return theme.colorScheme.outline;
    }
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
