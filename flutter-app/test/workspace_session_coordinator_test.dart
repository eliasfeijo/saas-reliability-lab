import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'package:todo_flutter/services/workspace_session_coordinator.dart';

import 'test_support/app_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityPlatform originalConnectivityPlatform;
  late TestConnectivityPlatform connectivityPlatform;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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

  test(
    'session coordinator initialization surfaces anonymous review without forcing sync',
    () async {
      final anonymousTask = buildTask(
        id: 'task-session-init',
        title: 'Pending review',
        beginsAt: DateTime(2026, 3, 3, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = InMemoryTasksRepository([anonymousTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final userSession = InMemoryUserSessionService(
        runtimeDebug: runtimeDebug,
      );
      await userSession.saveUserId('user-1');

      final agenda = AgendaProvider(
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

      var registerCalls = 0;
      final coordinator = WorkspaceSessionCoordinator(
        userSession,
        registerPushSubscription: ({runtimeDebug}) async {
          registerCalls++;
        },
        activeUserId: () => 'user-1',
        hasAuthenticatedSession: () => true,
      );

      final result = await coordinator.initialize(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
      );

      expect(agenda.userId, 'user-1');
      expect(agenda.anonymousTasks, hasLength(1));
      expect(result.shouldShowAnonymousTaskReview, isTrue);
      expect(registerCalls, 1);
    },
  );

  test(
    'session coordinator signed-out flow clears local user and workspace snapshot',
    () async {
      final accountTask = buildTask(
        id: 'task-session-logout',
        title: 'Account task',
        beginsAt: DateTime(2026, 3, 4, 9),
        estimatedDuration: const Duration(hours: 1),
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([accountTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final userSession = InMemoryUserSessionService(
        runtimeDebug: runtimeDebug,
      );
      await userSession.saveUserId('user-1');

      final agenda = AgendaProvider(
        repository,
        TaskSyncService.forTesting(
          repository,
          remote: FakeTaskRemoteDataSource([]),
          connectivityCheck: () async => [ConnectivityResult.wifi],
          hasActiveSession: () => false,
          runtimeDebug: runtimeDebug,
        ),
        runtimeDebug: runtimeDebug,
      )..userId = 'user-1';
      agenda.tasks = [accountTask];
      addTearDown(agenda.dispose);

      final coordinator = WorkspaceSessionCoordinator(
        userSession,
        registerPushSubscription: ({runtimeDebug}) async {},
        activeUserId: () => null,
        hasAuthenticatedSession: () => false,
      );

      final result = await coordinator.handleAuthStateChange(
        AuthChangeEvent.signedOut,
        agenda: agenda,
        runtimeDebug: runtimeDebug,
      );

      expect(result.shouldClearSearch, isTrue);
      expect(agenda.userId, isNull);
      expect(agenda.tasks, isEmpty);
      expect(await userSession.loadUserId(), isNull);
    },
  );
}
