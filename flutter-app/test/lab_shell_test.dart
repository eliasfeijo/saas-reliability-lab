import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/services/task_sync_service.dart';

import 'test_support/app_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityPlatform originalConnectivityPlatform;
  late TestConnectivityPlatform connectivityPlatform;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ensureSupabaseInitialized();
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

  testWidgets('wide shell renders both rails beside the workspace', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final repository = InMemoryTasksRepository([]);
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
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      LabShellHarness(agenda: agenda, runtimeDebug: runtimeDebug),
    );
    await tester.pumpAndSettle();

    expect(find.text('Operator Rail'), findsOneWidget);
    expect(find.text('Task Workspace'), findsOneWidget);
    expect(find.text('Runtime Diagnostics'), findsOneWidget);
    expect(find.text('Reliability Lab'), findsNothing);
    expect(find.byType(SelectionArea), findsNWidgets(3));
  });

  testWidgets('narrow shell moves rails into drawers', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final repository = InMemoryTasksRepository([]);
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
    addTearDown(agenda.dispose);

    await tester.pumpWidget(
      LabShellHarness(agenda: agenda, runtimeDebug: runtimeDebug),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reliability Lab'), findsOneWidget);
    expect(find.text('Operator Rail'), findsNothing);
    expect(find.text('Runtime Diagnostics'), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dashboard_customize_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Operator Rail'), findsOneWidget);
    expect(find.byType(SelectionArea), findsNWidgets(2));

    Navigator.of(tester.element(find.text('Operator Rail'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.monitor_heart_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Runtime Diagnostics'), findsOneWidget);
    expect(find.byType(SelectionArea), findsNWidgets(2));
  });
}
