import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
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
import 'package:todo_flutter/widgets/lab/lab_left_rail.dart';

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

  testWidgets('anonymous rail exposes auth and review controls', (
    tester,
  ) async {
    final anonymousTask = buildTask(
      id: 'task-anon-rail',
      title: 'Anonymous rail task',
      beginsAt: DateTime(2026, 4, 1, 9),
      estimatedDuration: const Duration(hours: 1),
      syncStatus: SyncStatus.dirty,
    );

    final repository = InMemoryTasksRepository([anonymousTask]);
    final runtimeDebug = RuntimeDebugProvider();
    addTearDown(runtimeDebug.dispose);
    final agenda = buildAgendaProviderForTesting(
      repository,
      TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
        runtimeDebug: runtimeDebug,
      ),
      runtimeDebug: runtimeDebug,
    );
    agenda.tasks = [anonymousTask];
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      RailHarness(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
        child: const LabLeftRail(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Operator Rail'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Sign in to review'), 300);

    expect(find.text('Open auth'), findsOneWidget);
    expect(find.text('Sign in to review'), findsOneWidget);
    expect(find.text('Connectivity loss', skipOffstage: false), findsOneWidget);
    expect(textValue(tester, 'anonymous-review-count-value'), '1');
    expect(textValue(tester, 'task-scope-total-value'), '1');
  });

  testWidgets('authenticated rail switches to sync and ownership actions', (
    tester,
  ) async {
    final anonymousTask = buildTask(
      id: 'task-auth-rail',
      title: 'Owned later',
      beginsAt: DateTime(2026, 4, 2, 9),
      estimatedDuration: const Duration(hours: 1),
      syncStatus: SyncStatus.dirty,
    );

    final repository = InMemoryTasksRepository([anonymousTask]);
    final runtimeDebug = RuntimeDebugProvider();
    addTearDown(runtimeDebug.dispose);
    runtimeDebug.setUserState(
      cachedUserId: 'user-1234567890',
      activeUserId: 'user-1234567890',
      hasAuthenticatedSession: true,
    );
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
    )..userId = 'user-1234567890';
    agenda.tasks = [anonymousTask];
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      RailHarness(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
        child: const LabLeftRail(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Operator Rail'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Adopt tasks'), 300);

    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    expect(find.text('Adopt tasks'), findsOneWidget);
    expect(find.text('Discard local'), findsOneWidget);
    expect(find.text('Authenticated'), findsOneWidget);
  });

  testWidgets(
    'scenario controls activate connectivity loss with operator instructions',
    (tester) async {
      final repository = InMemoryTasksRepository([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
      addTearDown(faultInjection.dispose);
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
          child: const LabLeftRail(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Connectivity loss'), 300);
      expect(
        find.widgetWithText(ChoiceChip, 'Connectivity loss'),
        findsOneWidget,
      );

      await faultInjection.activateScenario(
        FaultInjectionScenario.connectivityLoss,
      );
      await tester.pumpAndSettle();

      expect(runtimeDebug.state.activeFaultInjectionLabel, 'Connectivity loss');
      await tester.scrollUntilVisible(
        find.textContaining('Leave the browser online'),
        300,
      );

      expect(find.byIcon(Icons.close), findsWidgets);
      expect(find.text('How to operate this scenario'), findsOneWidget);
      expect(
        find.text('Tap the active red chip to clear the scenario instantly.'),
        findsOneWidget,
      );
      expect(find.textContaining('Leave the browser online'), findsOneWidget);

      final activeScenarioChip = find.widgetWithText(
        InputChip,
        'Connectivity loss',
      );
      final activeScenarioDeleteIcon = find.descendant(
        of: activeScenarioChip,
        matching: find.byIcon(Icons.close),
      );

      await tester.ensureVisible(activeScenarioChip);
      await tester.pumpAndSettle();
      await tester.tap(activeScenarioDeleteIcon);
      await tester.pumpAndSettle();

      expect(runtimeDebug.state.activeFaultInjectionLabel, isNull);
    },
  );

  testWidgets(
    'scenario controls activate delayed sync with live-demo presets',
    (tester) async {
      final repository = InMemoryTasksRepository([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
      addTearDown(faultInjection.dispose);
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
          child: const LabLeftRail(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Delayed sync'), 300);
      await faultInjection.activateScenario(FaultInjectionScenario.delayedSync);
      await tester.pumpAndSettle();

      expect(
        runtimeDebug.state.activeFaultInjectionLabel,
        'Delayed sync (5 s)',
      );
      expect(find.text('Delay preset'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '5 s'), findsOneWidget);
      expect(
        find.textContaining('Use 5 s for most live walkthroughs'),
        findsOneWidget,
      );
      expect(find.textContaining('make a small task change'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, '10 s'),
        300,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '10 s'));
      await tester.pumpAndSettle();

      expect(
        runtimeDebug.state.activeFaultInjectionLabel,
        'Delayed sync (10 s)',
      );
    },
  );

  testWidgets(
    'reset controls live below scenario controls in the operator rail and soft reset preserves live state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
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

      runtimeDebug.setUserState(
        cachedUserId: 'cached-user-123456',
        activeUserId: 'active-user-123456',
        hasAuthenticatedSession: true,
      );
      runtimeDebug.markSyncPartial(
        'Sync completed. Some operations need review.',
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
      );
      await faultInjection.activateScenario(
        FaultInjectionScenario.connectivityLoss,
      );

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
          child: const LabLeftRail(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Reset Controls'), 300);

      expect(find.text('Reset Controls'), findsOneWidget);
      expect(find.text('Soft demo reset'), findsOneWidget);
      expect(find.text('Hard reset'), findsOneWidget);
      expect(
        top(tester, 'Reset Controls') > top(tester, 'Scenario Controls'),
        isTrue,
      );
      expect(
        tester
            .getSize(find.widgetWithText(OutlinedButton, 'Soft demo reset'))
            .width,
        tester.getSize(find.widgetWithText(FilledButton, 'Hard reset')).width,
      );

      final softResetButton = find.widgetWithText(
        OutlinedButton,
        'Soft demo reset',
      );
      await tester.ensureVisible(softResetButton);
      await tester.pumpAndSettle();
      await tester.tap(softResetButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Soft reset'));
      await tester.pumpAndSettle();

      expect(runtimeDebug.state.hasAuthenticatedSession, isTrue);
      expect(runtimeDebug.state.activeUserId, 'active-user-123456');
      expect(runtimeDebug.state.queuedEntryCount, 1);
      expect(runtimeDebug.state.acknowledgedEntryCount, 0);
      expect(runtimeDebug.state.lastSyncResult, RuntimeSyncResult.none);
      expect(runtimeDebug.state.lastSyncMessage, isNull);
      expect(
        runtimeDebug.state.pushSubscriptionState,
        PushSubscriptionState.registered,
      );
      expect(
        runtimeDebug.state.lastPushMessage,
        'Push registration is active.',
      );
      expect(runtimeDebug.state.activeFaultInjectionLabel, isNull);
      expect(runtimeDebug.state.recentEvents, isEmpty);
      expect(find.text('upsert task-ack', skipOffstage: false), findsNothing);
      expect(
        find.text('Timeline event for diagnostics.', skipOffstage: false),
        findsNothing,
      );
    },
  );
}
