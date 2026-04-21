import 'package:flutter/material.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/fault_injection_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/widgets/debug/debug_status_card.dart';

class ResetControlsCard extends StatelessWidget {
  const ResetControlsCard({
    super.key,
    required this.agenda,
    required this.runtimeDebug,
    required this.faultInjection,
    required this.hasAuthenticatedSession,
  });

  final AgendaProvider agenda;
  final RuntimeDebugProvider runtimeDebug;
  final FaultInjectionProvider faultInjection;
  final bool hasAuthenticatedSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DebugStatusCard(
      title: 'Reset Controls',
      subtitle:
          'Convenience cleanup paths for demos, recordings, and destructive reset workflows.',
      leading: const Icon(Icons.cleaning_services_outlined),
      accentColor: theme.colorScheme.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Use these controls when you need a cleaner diagnostics surface for a live walkthrough or a confirmed full workspace reset.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => _confirmSoftReset(context),
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
                  preview: agenda.hardResetPreview,
                ),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Hard reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSoftReset(BuildContext context) async {
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
}
