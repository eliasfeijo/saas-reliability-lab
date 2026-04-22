import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';
import 'package:todo_flutter/models/outbox_entry.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/fault_injection_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/outbox_repository.dart';
import 'package:todo_flutter/services/task_list_state_coordinator.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_local_state_coordinator.dart';
import 'package:todo_flutter/services/task_sync_coordinator.dart';
import 'package:todo_flutter/services/task_sync_flow_coordinator.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'package:todo_flutter/widgets/debug/sync_debug_panel.dart';

import 'test_support/app_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityPlatform originalConnectivityPlatform;
  late TestConnectivityPlatform connectivityPlatform;

  setUpAll(() async {
    originalConnectivityPlatform = ConnectivityPlatform.instance;
    connectivityPlatform = TestConnectivityPlatform(
      initialResults: const [ConnectivityResult.wifi],
    );
    ConnectivityPlatform.instance = connectivityPlatform;
  });

  tearDownAll(() async {
    ConnectivityPlatform.instance = originalConnectivityPlatform;
    await connectivityPlatform.dispose();
  });

  setUp(() {
    connectivityPlatform.emit(const [ConnectivityResult.wifi]);
  });

  testWidgets('debug panel renders explicit runtime evidence and placeholders', (
    tester,
  ) async {
    final runtimeDebug = RuntimeDebugProvider();
    addTearDown(runtimeDebug.dispose);
    final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
    addTearDown(faultInjection.dispose);
    runtimeDebug.setConnectivityResults(const [
      ConnectivityResult.wifi,
    ], logEvent: false);
    runtimeDebug.setUserState(
      cachedUserId: 'cached-user-123456',
      activeUserId: 'active-user-123456',
      hasAuthenticatedSession: true,
    );
    runtimeDebug.updateTaskCounts([
      buildTask(
        id: 'task-dirty',
        title: 'Dirty task',
        beginsAt: DateTime(2026, 4, 3, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      ),
      buildTask(
        id: 'task-anon',
        title: 'Anonymous task',
        beginsAt: DateTime(2026, 4, 3, 10),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      ),
      buildTask(
        id: 'task-deleted',
        title: 'Deleted task',
        beginsAt: DateTime(2026, 4, 3, 11),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.deleted,
        userId: 'user-1',
      ),
    ]);
    runtimeDebug.updateOutboxState(
      OutboxStorageState(
        isInitialized: true,
        activeEntries: [
          OutboxEntry(
            taskId: 'task-dirty',
            operationType: OutboxOperationType.upsert,
            state: OutboxEntryState.queued,
            ownerScope: OutboxOwnerScope.authenticated,
            taskPayload: const {'id': 'task-dirty'},
          ),
          OutboxEntry(
            taskId: 'task-anon',
            operationType: OutboxOperationType.upsert,
            state: OutboxEntryState.blockedAnonymousReview,
            ownerScope: OutboxOwnerScope.anonymous,
            taskPayload: const {'id': 'task-anon'},
          ),
          OutboxEntry(
            taskId: 'task-deleted',
            operationType: OutboxOperationType.delete,
            state: OutboxEntryState.conflict,
            ownerScope: OutboxOwnerScope.authenticated,
            taskPayload: const {'id': 'task-deleted'},
          ),
        ],
        recentAcknowledgements: [
          OutboxEntry(
            taskId: 'task-ack',
            operationType: OutboxOperationType.upsert,
            state: OutboxEntryState.acknowledged,
            ownerScope: OutboxOwnerScope.authenticated,
            taskPayload: const {'id': 'task-ack'},
          ),
        ],
      ),
    );
    runtimeDebug.markSyncPartial(
      'Sync completed. Some operations need review.',
    );
    await faultInjection.activateScenario(
      FaultInjectionScenario.connectivityLoss,
    );
    runtimeDebug.setPushPermission(
      PushPermissionState.granted,
      logEvent: false,
    );
    runtimeDebug.setPushSubscriptionState(
      PushSubscriptionState.registered,
      message: 'Push registration is active.',
    );
    runtimeDebug.addEvent(
      category: RuntimeEventCategory.sync,
      message: 'Timeline event for diagnostics.',
      payload: const RuntimeEventPayload(
        stage: 'Replay completed',
        summary:
            'The sync pass finished and captured structured operator evidence.',
        metrics: [
          RuntimeEventMetric(label: 'Acknowledged', value: '2'),
          RuntimeEventMetric(label: 'Remote truth kept', value: '1'),
        ],
        tasks: [
          RuntimeEventTaskDetail(
            title: 'Dirty task',
            taskId: 'task-dirty',
            syncStatus: 'Dirty',
            outcome: 'Updated remotely',
            description: '2026-04-03 09:00 for 1 h.',
            tags: ['High visibility'],
            fieldDiffs: [
              RuntimeEventFieldDiff(
                label: 'Title',
                before: 'Dirty task (local)',
                after: 'Dirty task',
              ),
            ],
          ),
        ],
        notes: [
          'A follow-up warning event would appear separately if review were needed.',
        ],
      ),
    );

    final repository = InMemoryTasksRepository([]);
    final agenda = buildAgendaProviderForTesting(
      repository,
      TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
      ),
      runtimeDebug: runtimeDebug,
    );
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      RailHarness(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
        faultInjection: faultInjection,
        child: const SyncDebugPanel(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Runtime Diagnostics'), findsOneWidget);
    expect(find.text('Reset Controls'), findsNothing);
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.text('Online'), findsWidgets);

    await tester.scrollUntilVisible(find.text('Fault Injection'), 300);

    expect(find.text('Fault Injection'), findsOneWidget);
    expect(find.text('Connectivity loss', skipOffstage: false), findsWidgets);
    expect(
      find.textContaining(
        'Leave the browser online, then run Sync now',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('Reset failure scenario'), findsOneWidget);

    final resetButton = find.widgetWithText(
      OutlinedButton,
      'Reset failure scenario',
    );
    expect(resetButton, findsOneWidget);

    await faultInjection.clearScenario();
    await tester.pumpAndSettle();

    expect(runtimeDebug.state.activeFaultInjectionLabel, isNull);
    expect(
      find.text('No controlled failure scenario is active right now.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(find.text('Push State'), 300);

    expect(
      find.text(
        'Sync completed. Some operations need review.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('Push State'), findsOneWidget);
    expect(find.text('Registered'), findsWidgets);
    expect(find.text('Queued: 1', skipOffstage: false), findsOneWidget);
    expect(find.text('Conflict: 1', skipOffstage: false), findsOneWidget);
    expect(find.text('Blocked Review: 1', skipOffstage: false), findsOneWidget);
    expect(find.text('Conflict review', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Keep remote version', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Reapply local intent', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('upsert task-ack', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Clear retained history', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Timeline event for diagnostics.', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Dirty', skipOffstage: false), findsOneWidget);
    expect(find.text('Deleted', skipOffstage: false), findsOneWidget);
    expect(find.text('Anonymous', skipOffstage: false), findsOneWidget);
  });

  testWidgets('debug panel shows delayed sync configuration details', (
    tester,
  ) async {
    final runtimeDebug = RuntimeDebugProvider();
    addTearDown(runtimeDebug.dispose);
    final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
    addTearDown(faultInjection.dispose);

    await faultInjection.activateScenario(
      FaultInjectionScenario.delayedSync,
      delayMs: 2000,
      delayedSyncMode: DelayedSyncMode.transport,
      delayedSyncTarget: DelayedSyncTarget.update,
      delayedSyncBehavior: DelayedSyncBehavior.oneShot,
    );

    final repository = InMemoryTasksRepository([]);
    final agenda = buildAgendaProviderForTesting(
      repository,
      TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
      ),
      runtimeDebug: runtimeDebug,
    );
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      RailHarness(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
        faultInjection: faultInjection,
        child: const SyncDebugPanel(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Fault Injection'), 300);

    expect(find.text('Mode'), findsOneWidget);
    expect(find.text('Transport'), findsWidgets);
    expect(find.text('Target'), findsOneWidget);
    expect(find.text('Update'), findsWidgets);
    expect(find.text('Behavior'), findsOneWidget);
    expect(find.text('One-shot'), findsWidgets);
  });
  testWidgets(
    'retained acknowledgements can be cleared from runtime diagnostics',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
      addTearDown(faultInjection.dispose);
      final repository = InMemoryTasksRepository([]);
      final outboxRepository = InMemoryOutboxRepository();
      final snapshotCoordinator = TaskLocalSnapshotCoordinator.fromRepository(
        repository,
      );
      final localStateCoordinator = TaskLocalStateCoordinator(
        snapshotCoordinator,
        outboxRepository,
        runtimeDebug: runtimeDebug,
      );
      final syncService = TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
        localStateCoordinator: localStateCoordinator,
      );
      final taskListStateCoordinator = TaskListStateCoordinator(
        snapshotCoordinator,
        runtimeDebug: runtimeDebug,
        localStateCoordinator: localStateCoordinator,
      );
      final agenda = AgendaProvider(
        taskListStateCoordinator: taskListStateCoordinator,
        taskSyncFlowCoordinator: TaskSyncFlowCoordinator(
          taskListStateCoordinator,
          TaskSyncCoordinator(
            snapshotCoordinator,
            syncService,
            runtimeDebug: runtimeDebug,
            localStateCoordinator: localStateCoordinator,
          ),
        ),
      );
      addTearDown(agenda.dispose);

      await localStateCoordinator.saveOutboxState(
        OutboxStorageState(
          isInitialized: true,
          activeEntries: [
            OutboxEntry(
              taskId: 'task-queued',
              operationType: OutboxOperationType.upsert,
              state: OutboxEntryState.queued,
              ownerScope: OutboxOwnerScope.authenticated,
              taskPayload: const {'id': 'task-queued'},
            ),
          ],
          recentAcknowledgements: [
            OutboxEntry(
              taskId: 'task-ack',
              operationType: OutboxOperationType.upsert,
              state: OutboxEntryState.acknowledged,
              ownerScope: OutboxOwnerScope.authenticated,
              taskPayload: const {'id': 'task-ack'},
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        RailHarness(
          agenda: agenda,
          runtimeDebug: runtimeDebug,
          faultInjection: faultInjection,
          child: const SyncDebugPanel(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Clear retained history', skipOffstage: false),
        300,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Clear retained history'),
      );
      await tester.pumpAndSettle();

      expect(find.text('upsert task-ack', skipOffstage: false), findsNothing);
      expect(runtimeDebug.state.acknowledgedEntryCount, 0);
      expect(runtimeDebug.state.queuedEntryCount, 1);
    },
  );

  testWidgets('timeline context can be revealed and hidden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final runtimeDebug = RuntimeDebugProvider();
    addTearDown(runtimeDebug.dispose);
    final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
    addTearDown(faultInjection.dispose);
    final repository = InMemoryTasksRepository([]);
    final agenda = buildAgendaProviderForTesting(
      repository,
      TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
      ),
      runtimeDebug: runtimeDebug,
    );
    addTearDown(agenda.dispose);

    runtimeDebug.addEvent(
      category: RuntimeEventCategory.sync,
      message: 'Timeline event for diagnostics.',
      payload: const RuntimeEventPayload(
        stage: 'Replay completed',
        summary:
            'The sync pass finished and captured structured operator evidence.',
        metrics: [RuntimeEventMetric(label: 'Acknowledged', value: '2')],
        tasks: [
          RuntimeEventTaskDetail(
            title: 'Dirty task',
            taskId: 'task-dirty',
            syncStatus: 'Dirty',
            outcome: 'Updated remotely',
            description: '2026-04-03 09:00 for 1 h.',
            fieldDiffs: [
              RuntimeEventFieldDiff(
                label: 'Title',
                before: 'Dirty task (local)',
                after: 'Dirty task',
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RailHarness(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
        faultInjection: faultInjection,
        child: const SyncDebugPanel(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Timeline event for diagnostics.', skipOffstage: false),
      300,
    );

    final detailsButton = find.text('View context', skipOffstage: false);

    expect(detailsButton, findsOneWidget);

    await tester.ensureVisible(detailsButton);
    await tester.pumpAndSettle();

    await tester.tap(detailsButton);
    await tester.pumpAndSettle();

    expect(find.text('Hide context', skipOffstage: false), findsOneWidget);
    expect(find.text('Operator summary', skipOffstage: false), findsOneWidget);
    expect(
      find.text(
        'The sync pass finished and captured structured operator evidence.',
      ),
      findsOneWidget,
    );
    expect(find.text('Acknowledged'), findsWidgets);
    expect(find.text('Tasks touched'), findsOneWidget);
    expect(find.text('State diff'), findsOneWidget);
    expect(find.text('Before: Dirty task (local)'), findsOneWidget);
    expect(find.text('After: Dirty task'), findsOneWidget);

    await tester.tap(find.text('Hide context', skipOffstage: false));
    await tester.pumpAndSettle();

    expect(find.text('Operator summary'), findsNothing);
  });

  testWidgets('timeline actions wrap without overflowing on compact widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final runtimeDebug = RuntimeDebugProvider();
    addTearDown(runtimeDebug.dispose);
    final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
    addTearDown(faultInjection.dispose);
    final repository = InMemoryTasksRepository([]);
    final agenda = buildAgendaProviderForTesting(
      repository,
      TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
      ),
      runtimeDebug: runtimeDebug,
    );
    addTearDown(agenda.dispose);

    runtimeDebug.addEvent(
      category: RuntimeEventCategory.sync,
      message: 'Compact timeline event.',
      payload: const RuntimeEventPayload(
        stage: 'Replay completed',
        summary: 'Compact layout should wrap action buttons safely.',
        metrics: [RuntimeEventMetric(label: 'Acknowledged', value: '3')],
        tasks: [
          RuntimeEventTaskDetail(
            title: 'Compact task',
            taskId: 'task-compact',
            syncStatus: 'Synced',
            outcome: 'Recorded',
            description: '2026-04-22 12:25 for 1 h.',
          ),
          RuntimeEventTaskDetail(
            title: 'Second compact task',
            taskId: 'task-compact-2',
            syncStatus: 'Synced',
            outcome: 'Recorded',
            description: '2026-04-22 13:25 for 1 h.',
          ),
          RuntimeEventTaskDetail(
            title: 'Third compact task',
            taskId: 'task-compact-3',
            syncStatus: 'Synced',
            outcome: 'Recorded',
            description: '2026-04-22 14:25 for 1 h.',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RailHarness(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
        faultInjection: faultInjection,
        child: const SyncDebugPanel(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Compact timeline event.'), 300);
    expect(find.widgetWithText(TextButton, 'View context'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open full record'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'event timeline can be cleared without resetting the wider diagnostics state',
    (tester) async {
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
      addTearDown(faultInjection.dispose);
      final repository = InMemoryTasksRepository([]);
      final agenda = buildAgendaProviderForTesting(
        repository,
        TaskSyncService.forTesting(
          repository,
          remote: FakeTaskRemoteDataSource([]),
          connectivityCheck: () async => [ConnectivityResult.wifi],
          hasActiveSession: () => true,
          runtimeDebug: runtimeDebug,
        ),
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      runtimeDebug.setConnectivityResults(const [
        ConnectivityResult.wifi,
      ], logEvent: false);
      runtimeDebug.markSyncPartial(
        'Sync completed. Some operations need review.',
      );
      runtimeDebug.setPushSubscriptionState(
        PushSubscriptionState.registered,
        message: 'Push registration is active.',
      );
      runtimeDebug.addEvent(
        category: RuntimeEventCategory.sync,
        message: 'Timeline event for diagnostics.',
      );

      await tester.pumpWidget(
        RailHarness(
          agenda: agenda,
          runtimeDebug: runtimeDebug,
          faultInjection: faultInjection,
          child: const SyncDebugPanel(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Event Timeline'), 300);

      expect(find.text('Clear timeline'), findsOneWidget);
      expect(
        find.text('Timeline event for diagnostics.', skipOffstage: false),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Clear timeline'));
      await tester.pumpAndSettle();

      expect(runtimeDebug.state.recentEvents, isEmpty);
      expect(
        find.text('Timeline event for diagnostics.', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.text(
          'Events will appear here as the app loads, authenticates, syncs, and registers push.',
        ),
        findsOneWidget,
      );
      expect(
        runtimeDebug.state.lastSyncMessage,
        'Sync completed. Some operations need review.',
      );
      expect(
        runtimeDebug.state.pushSubscriptionState,
        PushSubscriptionState.registered,
      );
    },
  );

  testWidgets(
    'expanded context stays attached to the original event when newer events arrive',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
      addTearDown(faultInjection.dispose);
      final repository = InMemoryTasksRepository([]);
      final agenda = buildAgendaProviderForTesting(
        repository,
        TaskSyncService.forTesting(
          repository,
          remote: FakeTaskRemoteDataSource([]),
          connectivityCheck: () async => [ConnectivityResult.wifi],
          hasActiveSession: () => true,
          runtimeDebug: runtimeDebug,
        ),
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      runtimeDebug.addEvent(
        category: RuntimeEventCategory.sync,
        message: 'Older sync event.',
        payload: const RuntimeEventPayload(
          stage: 'Replay completed',
          summary: 'Older event summary.',
        ),
      );

      await tester.pumpWidget(
        RailHarness(
          agenda: agenda,
          runtimeDebug: runtimeDebug,
          faultInjection: faultInjection,
          child: const SyncDebugPanel(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Older sync event.'), 300);

      final detailsButton = find.widgetWithText(TextButton, 'View context');

      await tester.ensureVisible(detailsButton);
      await tester.pumpAndSettle();

      await tester.tap(detailsButton);
      await tester.pumpAndSettle();

      expect(find.text('Older event summary.'), findsOneWidget);

      runtimeDebug.addEvent(
        category: RuntimeEventCategory.sync,
        message: 'Newest sync event.',
        payload: const RuntimeEventPayload(
          stage: 'Replay started',
          summary: 'Newest event summary.',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Newest sync event.'), findsOneWidget);
      expect(find.text('Older event summary.'), findsOneWidget);
      expect(find.text('Newest event summary.'), findsNothing);
      expect(find.text('Hide context'), findsOneWidget);

      final viewContextButtons = find.widgetWithText(
        TextButton,
        'View context',
      );
      expect(viewContextButtons, findsOneWidget);
    },
  );

  testWidgets('plain events without context do not show an inspect action', (
    tester,
  ) async {
    final runtimeDebug = RuntimeDebugProvider();
    addTearDown(runtimeDebug.dispose);
    final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
    addTearDown(faultInjection.dispose);
    final repository = InMemoryTasksRepository([]);
    final agenda = buildAgendaProviderForTesting(
      repository,
      TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
      ),
      runtimeDebug: runtimeDebug,
    );
    addTearDown(agenda.dispose);

    runtimeDebug.addEvent(
      category: RuntimeEventCategory.app,
      message: 'Bare app event.',
    );

    await tester.pumpWidget(
      RailHarness(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
        faultInjection: faultInjection,
        child: const SyncDebugPanel(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Bare app event.'), 300);

    expect(find.text('Bare app event.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'View context'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Open full record'), findsNothing);
  });

  testWidgets(
    'debug panel shows delayed sync evidence and injected delay details',
    (tester) async {
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
      addTearDown(faultInjection.dispose);
      runtimeDebug.setConnectivityResults(const [
        ConnectivityResult.wifi,
      ], logEvent: false);

      await faultInjection.activateScenario(FaultInjectionScenario.delayedSync);

      final repository = InMemoryTasksRepository([]);
      final agenda = buildAgendaProviderForTesting(
        repository,
        TaskSyncService.forTesting(
          repository,
          remote: FakeTaskRemoteDataSource([]),
          connectivityCheck: () async => [ConnectivityResult.wifi],
          hasActiveSession: () => true,
          runtimeDebug: runtimeDebug,
        ),
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      await tester.pumpWidget(
        RailHarness(
          agenda: agenda,
          runtimeDebug: runtimeDebug,
          faultInjection: faultInjection,
          child: const SyncDebugPanel(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Fault Injection'), 300);

      expect(
        find.text('Delayed sync (5 s)', skipOffstage: false),
        findsWidgets,
      );
      expect(find.text('Injected delay'), findsOneWidget);
      expect(find.text('5 s', skipOffstage: false), findsWidgets);
      expect(find.textContaining('make a small task change'), findsOneWidget);

      await faultInjection.setDelayedSyncDuration(10000);
      await tester.pumpAndSettle();

      expect(
        find.text('Delayed sync (10 s)', skipOffstage: false),
        findsWidgets,
      );
      expect(find.text('10 s', skipOffstage: false), findsWidgets);
    },
  );
}
