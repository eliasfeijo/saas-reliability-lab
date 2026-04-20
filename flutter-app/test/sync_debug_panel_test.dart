import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/fault_injection_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
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

  testWidgets(
    'debug panel renders explicit runtime evidence and placeholders',
    (tester) async {
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
      expect(find.text('Queued', skipOffstage: false), findsOneWidget);
      expect(find.text('Conflict', skipOffstage: false), findsOneWidget);
      expect(
        find.text('Timeline event for diagnostics.', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Dirty', skipOffstage: false), findsOneWidget);
      expect(find.text('Deleted', skipOffstage: false), findsOneWidget);
      expect(find.text('Anonymous', skipOffstage: false), findsOneWidget);
    },
  );
}
