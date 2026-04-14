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

  testWidgets('anonymous create-delete clears queue controls and review counters', (
    tester,
  ) async {
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

    final agenda = AgendaProvider(
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
    expect(find.text('No anonymous tasks are waiting for review.'), findsOneWidget);
    expect(textValue(tester, 'task-workspace-in-view-value'), '0');
    expect(textValue(tester, 'task-workspace-pending-value'), '0');
    expect(textValue(tester, 'task-scope-visible-value'), '0');
    expect(textValue(tester, 'task-scope-total-value'), '0');
    expect(textValue(tester, 'anonymous-review-count-value'), '0');
  });

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

      final agenda = AgendaProvider(
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
}
