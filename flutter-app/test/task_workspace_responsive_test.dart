import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
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
    'queue sort control reorders tasks and notebook widths use attached details',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1100, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      final laterTask = TaskModel(
        id: 'task-later',
        title: 'Later task',
        beginsAt: now.add(const Duration(days: 2)),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );
      final earlierTask = TaskModel(
        id: 'task-earlier',
        title: 'Earlier task',
        beginsAt: now.subtract(const Duration(hours: 1)),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final repository = InMemoryTasksRepository([laterTask, earlierTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

      final syncService = TaskSyncService.forTesting(
        repository,
        remote: FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
        runtimeDebug: runtimeDebug,
      );

      final agenda = AgendaProvider(
        repository,
        syncService,
        InMemoryUserSessionService(runtimeDebug: runtimeDebug),
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      await tester.pumpWidget(
        NotebookWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
      );
      await tester.pumpAndSettle();

      expect(top(tester, 'Earlier task'), lessThan(top(tester, 'Later task')));
      expect(find.text('Sort: Closest'), findsOneWidget);

      await tester.tap(find.text('Sort: Closest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Latest first').last);
      await tester.pumpAndSettle();

      expect(top(tester, 'Later task'), lessThan(top(tester, 'Earlier task')));
      expect((left(tester, 'Task Queue') - left(tester, 'Queue Controls')).abs(), lessThan(1));

      await tester.ensureVisible(find.text('Earlier task'));
      await tester.tap(find.text('Earlier task'));
      await tester.pumpAndSettle();

      expect(find.text('Task details'), findsOneWidget);
      expect(find.text('Task Queue'), findsOneWidget);
    },
  );

  testWidgets('compact queue header stacks actions without losing the heading', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(540, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final seededTask = TaskModel(
      id: 'task-compact',
      title: 'Compact queue task',
      beginsAt: DateTime(2026, 2, 22, 9),
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

    final agenda = AgendaProvider(
      repository,
      syncService,
      InMemoryUserSessionService(runtimeDebug: runtimeDebug),
      runtimeDebug: runtimeDebug,
    );
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      CompactWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
    );
    await tester.pumpAndSettle();

    expect(find.text('Task Queue'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.textContaining('Select a row'), findsOneWidget);
  });

  testWidgets('compact queue controls wrap filter badges into multiple rows', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(540, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final seededTask = TaskModel(
      id: 'task-filter-wrap',
      title: 'Filter wrap task',
      beginsAt: DateTime(2026, 2, 22, 9),
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

    final agenda = AgendaProvider(
      repository,
      syncService,
      InMemoryUserSessionService(runtimeDebug: runtimeDebug),
      runtimeDebug: runtimeDebug,
    );
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      CompactWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sort: Closest'), findsOneWidget);
    expect(find.text('All 1'), findsOneWidget);
    expect(find.text('Upcoming 0'), findsOneWidget);
    expect(top(tester, 'All 1'), greaterThan(top(tester, 'Sort: Closest')));
    expect(tester.getTopLeft(find.text('Upcoming 0')).dy, greaterThan(top(tester, 'All 1')));
  });

  testWidgets('small screens use attached details instead of inline inspector space', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(540, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final seededTask = TaskModel(
      id: 'task-mobile-overlay',
      title: 'Mobile overlay task',
      beginsAt: DateTime(2026, 2, 23, 9),
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

    final agenda = AgendaProvider(
      repository,
      syncService,
      InMemoryUserSessionService(runtimeDebug: runtimeDebug),
      runtimeDebug: runtimeDebug,
    );
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      CompactWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Mobile overlay task'));
    await tester.tap(find.text('Mobile overlay task'));
    await tester.pumpAndSettle();

    expect(find.text('Task details'), findsOneWidget);
    expect(find.text('Task Queue'), findsOneWidget);
  });

  testWidgets('compact task details can be minimized into a persistent handle', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(540, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final seededTask = TaskModel(
      id: 'task-minimize',
      title: 'Minimize me',
      beginsAt: DateTime(2026, 2, 24, 9),
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

    final agenda = AgendaProvider(
      repository,
      syncService,
      InMemoryUserSessionService(runtimeDebug: runtimeDebug),
      runtimeDebug: runtimeDebug,
    );
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      CompactWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Minimize me'));
    await tester.tap(find.text('Minimize me'));
    await tester.pumpAndSettle();

    expect(find.text('Task details'), findsOneWidget);

    await tester.tap(find.byTooltip('Minimize panel'));
    await tester.pumpAndSettle();

    expect(find.text('Task details'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
}
