import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/widgets/debug/debug_status_card.dart';

class LabLeftRail extends StatelessWidget {
  const LabLeftRail({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer2<AgendaProvider, RuntimeDebugProvider>(
      builder: (context, agenda, runtimeDebug, child) {
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
              Text('Lab Workspace', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Operator-facing context for session state, filters, and future scenarios.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              DebugStatusCard(
                title: 'Session Snapshot',
                subtitle:
                    'What the lab currently believes about the signed-in user.',
                leading: const Icon(Icons.verified_user_outlined),
                accentColor: state.hasAuthenticatedSession
                    ? theme.colorScheme.primary
                    : theme.colorScheme.secondary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line(
                      context,
                      'Mode',
                      state.hasAuthenticatedSession
                          ? 'Authenticated'
                          : 'Anonymous',
                    ),
                    _line(context, 'Local user', agenda.userId ?? 'None'),
                    _line(
                      context,
                      'Anonymous tasks',
                      agenda.anonymousTasks.length.toString(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Task Scope',
                subtitle: 'Current visible filter controls.',
                leading: const Icon(Icons.tune),
                accentColor: theme.colorScheme.tertiary,
                child: Wrap(
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
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Visible Counts',
                subtitle: 'Quick read on the current task set.',
                leading: const Icon(Icons.stacked_bar_chart_outlined),
                accentColor: theme.colorScheme.secondary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line(context, 'Total', agenda.totalTasks.toString()),
                    _line(
                      context,
                      'Completed',
                      agenda.completedTasksCount.toString(),
                    ),
                    _line(
                      context,
                      'Pending',
                      agenda.pendingTasksCount.toString(),
                    ),
                    _line(context, 'Today', agenda.todayTasksCount.toString()),
                    _line(
                      context,
                      'Overdue',
                      agenda.overdueTasksCount.toString(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DebugStatusCard(
                title: 'Scenario Controls',
                subtitle:
                    'Reserved for fault injection and reliability experiments.',
                leading: const Icon(Icons.science_outlined),
                accentColor: theme.colorScheme.primary,
                child: Text(
                  'Future phases will add toggles for connectivity loss, delayed sync, expired sessions, duplicate delivery, and other controlled failure modes.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _line(BuildContext context, String label, String value) {
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
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
