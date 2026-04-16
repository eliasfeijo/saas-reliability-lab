import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
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
    expect(find.text('Conflict view', skipOffstage: false), findsOneWidget);
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
}
