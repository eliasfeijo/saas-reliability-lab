import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/outbox_entry.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/fault_injection_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/outbox_repository.dart';
import 'package:todo_flutter/services/fault_injection_policy.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_local_state_coordinator.dart';
import 'package:todo_flutter/services/task_sync_service.dart';

import 'test_support/app_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityPlatform originalConnectivityPlatform;
  late TestConnectivityPlatform connectivityPlatform;
  var didOverrideConnectivityPlatform = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ensureSupabaseInitialized();
    originalConnectivityPlatform = ConnectivityPlatform.instance;
    connectivityPlatform = TestConnectivityPlatform(
      initialResults: const [ConnectivityResult.wifi],
    );
    ConnectivityPlatform.instance = connectivityPlatform;
    didOverrideConnectivityPlatform = true;
  });

  tearDownAll(() async {
    if (!didOverrideConnectivityPlatform) {
      return;
    }

    ConnectivityPlatform.instance = originalConnectivityPlatform;
    await connectivityPlatform.dispose();
  });

  setUp(() {
    connectivityPlatform.emit(const [ConnectivityResult.wifi]);
  });

  testWidgets(
    'anonymous create-delete clears queue controls and review counters',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final repository = InMemoryTasksRepository([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

      final syncService = TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
        runtimeDebug: runtimeDebug,
      );

      final agenda = buildAgendaProviderForTesting(
        repository,
        syncService,
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      await tester.pumpWidget(
        LabWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
      );
      await tester.pumpAndSettle();

      expect(textValue(tester, 'task-workspace-pending-value'), '0');
      expect(textValue(tester, 'task-scope-total-value'), '0');
      expect(textValue(tester, 'anonymous-review-count-value'), '0');

      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();

      final createDialog = find.byType(AlertDialog);
      expect(createDialog, findsOneWidget);

      await tester.enterText(
        find.descendant(of: createDialog, matching: find.byType(TextFormField)),
        'Anonymous cleanup task',
      );
      await tester.tap(
        find.descendant(
          of: createDialog,
          matching: find.widgetWithText(ElevatedButton, 'Create Task'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Anonymous cleanup task'), findsOneWidget);
      expect(textValue(tester, 'task-workspace-in-view-value'), '1');
      expect(textValue(tester, 'task-workspace-pending-value'), '1');
      expect(textValue(tester, 'task-scope-visible-value'), '1');
      expect(textValue(tester, 'task-scope-total-value'), '1');
      expect(textValue(tester, 'anonymous-review-count-value'), '1');

      await tester.tap(find.text('Anonymous cleanup task'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      final deleteDialog = find.byType(AlertDialog);
      expect(deleteDialog, findsOneWidget);

      await tester.tap(
        find.descendant(
          of: deleteDialog,
          matching: find.widgetWithText(TextButton, 'Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Anonymous cleanup task'), findsNothing);
      expect(find.text('No tasks scheduled yet'), findsOneWidget);
      expect(
        find.text('No anonymous tasks are waiting for review.'),
        findsOneWidget,
      );
      expect(textValue(tester, 'task-workspace-in-view-value'), '0');
      expect(textValue(tester, 'task-workspace-pending-value'), '0');
      expect(textValue(tester, 'task-scope-visible-value'), '0');
      expect(textValue(tester, 'task-scope-total-value'), '0');
      expect(textValue(tester, 'anonymous-review-count-value'), '0');
    },
  );

  testWidgets(
    'task queue uses explicit mark-done CTA and only shows checkboxes in batch mode',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final seededTask = TaskModel(
        id: 'task-cta',
        title: 'Queue CTA task',
        beginsAt: DateTime(2026, 2, 20, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = InMemoryTasksRepository([seededTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

      final syncService = TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
        runtimeDebug: runtimeDebug,
      );

      final agenda = buildAgendaProviderForTesting(
        repository,
        syncService,
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      await tester.pumpWidget(
        LabWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
      );
      await tester.pumpAndSettle();

      expect(find.text('Queue CTA task'), findsOneWidget);
      expect(find.text('Mark done'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('Done selecting'), findsOneWidget);
    },
  );

  testWidgets('delayed sync notice does not block workspace interaction', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final seededTask = TaskModel(
      id: 'task-delayed-workspace',
      title: 'Interactive delay task',
      beginsAt: DateTime(2026, 2, 23, 9),
      estimatedDuration: const Duration(hours: 1),
      syncStatus: SyncStatus.dirty,
      userId: 'user-1',
    );

    final repository = InMemoryTasksRepository([seededTask]);
    final runtimeDebug = RuntimeDebugProvider();
    addTearDown(runtimeDebug.dispose);
    final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
    addTearDown(faultInjection.dispose);
    final delayCompleter = Completer<void>();

    final syncService = TaskSyncService.forTesting(
      repository,
      remote: FakeTaskRemoteDataSource([]),
      connectivityCheck: () async => [ConnectivityResult.wifi],
      hasActiveSession: () => true,
      runtimeDebug: runtimeDebug,
      faultInjectionPolicy: FaultInjectionPolicy(
        readState: () => faultInjection.state,
      ),
      delayExecution: (_) => delayCompleter.future,
    );

    final agenda = buildAgendaProviderForTesting(
      repository,
      syncService,
      runtimeDebug: runtimeDebug,
    );
    agenda.tasks = [seededTask];
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      LabWorkspaceHarness(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
        faultInjection: faultInjection,
      ),
    );
    await tester.pumpAndSettle();

    agenda.userId = 'user-1';
    runtimeDebug.setUserState(
      cachedUserId: 'user-1',
      activeUserId: 'user-1',
      hasAuthenticatedSession: true,
    );
    await faultInjection.activateScenario(FaultInjectionScenario.delayedSync);
    await tester.pump();

    unawaited(agenda.syncAllTasks());
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('task-workspace-sync-activity')),
      findsOneWidget,
    );
    expect(find.text('Sync in progress'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task-workspace-sync-delay-label')),
      findsOneWidget,
    );

    final progressIndicator = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('task-workspace-sync-delay-progress')),
    );
    expect(progressIndicator.value, isNotNull);

    await tester.tap(find.text('Interactive delay task').first);
    await tester.pump();

    expect(agenda.selectedTask?.title, 'Interactive delay task');

    delayCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('task workspace surfaces conflict review in a modal diff flow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 2200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final localTask = TaskModel(
      id: 'task-conflict-workspace',
      title: 'Local task title',
      beginsAt: DateTime(2026, 3, 4, 9),
      estimatedDuration: const Duration(hours: 2),
      description: 'Local notes',
      priority: TaskPriority.high,
      tags: const ['focus'],
      syncStatus: SyncStatus.dirty,
      userId: 'user-1',
      hasRemoteBackingRecord: true,
    );
    final remoteTask = TaskModel(
      id: localTask.id,
      title: 'Remote task title',
      beginsAt: DateTime(2026, 3, 4, 11),
      estimatedDuration: const Duration(hours: 1),
      description: 'Remote notes',
      priority: TaskPriority.low,
      tags: const ['ops'],
      syncStatus: SyncStatus.synced,
      userId: 'user-1',
      hasRemoteBackingRecord: true,
    );

    final repository = InMemoryTasksRepository([localTask]);
    final runtimeDebug = RuntimeDebugProvider();
    addTearDown(runtimeDebug.dispose);
    final outboxRepository = InMemoryOutboxRepository();
    final localStateCoordinator = TaskLocalStateCoordinator(
      TaskLocalSnapshotCoordinator.fromRepository(repository),
      outboxRepository,
      runtimeDebug: runtimeDebug,
    );
    await localStateCoordinator.saveState(
      TaskLocalState(
        tasks: [localTask],
        outboxState: OutboxStorageState(
          isInitialized: true,
          activeEntries: [
            OutboxEntry(
              taskId: localTask.id,
              operationType: OutboxOperationType.upsert,
              state: OutboxEntryState.conflict,
              ownerScope: OutboxOwnerScope.authenticated,
              taskPayload: localTask.toJson(),
              remoteSnapshot: remoteTask.toJson(),
              lastError:
                  'Remote state changed after the local update was queued.',
            ),
          ],
        ),
      ),
    );

    final syncService = TaskSyncService.forTesting(
      repository,
      remote: FakeTaskRemoteDataSource([remoteTask]),
      connectivityCheck: () async => [ConnectivityResult.wifi],
      hasActiveSession: () => true,
      runtimeDebug: runtimeDebug,
      localStateCoordinator: localStateCoordinator,
    );

    final agenda = buildAgendaProviderForTesting(
      repository,
      syncService,
      runtimeDebug: runtimeDebug,
      localStateCoordinator: localStateCoordinator,
      outboxRepository: outboxRepository,
    );
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      LabWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task-workspace-conflict-alert')),
      findsOneWidget,
    );
    expect(find.text('Sync conflict needs review'), findsOneWidget);
    expect(find.text('Review conflicts'), findsOneWidget);

    await tester.tap(find.text('Review conflicts'));
    await tester.pumpAndSettle();

    expect(find.text('Conflict review'), findsOneWidget);
    expect(find.text('Local version'), findsOneWidget);
    expect(find.text('Remote version'), findsOneWidget);
    expect(find.text('What changed'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Local task title'), findsWidgets);
    expect(find.text('Remote task title'), findsWidgets);
    expect(find.text('Keep my local changes'), findsOneWidget);
    expect(find.text('Keep remote version'), findsOneWidget);
  });
}
