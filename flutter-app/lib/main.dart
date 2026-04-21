import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/helpers/app_mode_helper.dart';
import 'package:todo_flutter/keys.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/fault_injection_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/outbox_repository.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/screens/lab_shell.dart';
import 'package:todo_flutter/services/fault_injection_policy.dart';
import 'package:todo_flutter/services/task_list_state_coordinator.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_local_state_coordinator.dart';
import 'package:todo_flutter/services/task_sync_coordinator.dart';
import 'package:todo_flutter/services/task_sync_flow_coordinator.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'package:todo_flutter/services/user_session_service.dart';
import 'package:todo_flutter/services/workspace_session_coordinator.dart';
import 'package:todo_flutter/theme/lab_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App mode detection
  configureAppModeInterop();

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: "https://<your-project-ref>.supabase.co",
  );

  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: "<your-anon-key>",
  );

  // debugPrint('Supabase URL: $supabaseUrl');
  // debugPrint('Supabase Anon Key: $supabaseAnonKey');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final TasksRepository _tasksRepository;
  late final OutboxRepository _outboxRepository;
  late final TaskLocalSnapshotCoordinator _taskLocalSnapshotCoordinator;
  late final TaskLocalStateCoordinator _taskLocalStateCoordinator;
  late final RuntimeDebugProvider _runtimeDebugProvider;
  late final FaultInjectionProvider _faultInjectionProvider;
  late final FaultInjectionPolicy _faultInjectionPolicy;
  late final TaskSyncService _taskSyncService;
  late final TaskSyncCoordinator _taskSyncCoordinator;
  late final UserSessionService _userSessionService;
  late final WorkspaceSessionCoordinator _workspaceSessionCoordinator;

  @override
  void initState() {
    super.initState();
    _runtimeDebugProvider = RuntimeDebugProvider();
    _tasksRepository = TasksSharedPreferencesRepository();
    _outboxRepository = SharedPreferencesOutboxRepository();
    _taskLocalSnapshotCoordinator = TaskLocalSnapshotCoordinator.fromRepository(
      _tasksRepository,
    );
    _taskLocalStateCoordinator = TaskLocalStateCoordinator(
      _taskLocalSnapshotCoordinator,
      _outboxRepository,
      runtimeDebug: _runtimeDebugProvider,
    );
    _faultInjectionProvider = FaultInjectionProvider(
      runtimeDebug: _runtimeDebugProvider,
    );
    _faultInjectionPolicy = FaultInjectionPolicy(
      readState: () => _faultInjectionProvider.state,
    );
    _taskSyncService = TaskSyncService(
      _tasksRepository,
      Supabase.instance.client,
      runtimeDebug: _runtimeDebugProvider,
      faultInjectionPolicy: _faultInjectionPolicy,
      localStateCoordinator: _taskLocalStateCoordinator,
    );
    _taskSyncCoordinator = TaskSyncCoordinator(
      _taskLocalSnapshotCoordinator,
      _taskSyncService,
      runtimeDebug: _runtimeDebugProvider,
      localStateCoordinator: _taskLocalStateCoordinator,
    );
    _userSessionService = UserSessionService(
      runtimeDebug: _runtimeDebugProvider,
    );
    _workspaceSessionCoordinator = WorkspaceSessionCoordinator(
      _userSessionService,
    );
  }

  @override
  void dispose() {
    _faultInjectionProvider.dispose();
    _runtimeDebugProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RuntimeDebugProvider>.value(
          value: _runtimeDebugProvider,
        ),
        ChangeNotifierProvider<FaultInjectionProvider>.value(
          value: _faultInjectionProvider,
        ),
        Provider<WorkspaceSessionCoordinator>.value(
          value: _workspaceSessionCoordinator,
        ),
        ChangeNotifierProvider(
          create: (context) {
            final taskListStateCoordinator = TaskListStateCoordinator(
              _taskLocalSnapshotCoordinator,
              runtimeDebug: _runtimeDebugProvider,
              localStateCoordinator: _taskLocalStateCoordinator,
            );

            return AgendaProvider(
              taskListStateCoordinator: taskListStateCoordinator,
              taskSyncFlowCoordinator: TaskSyncFlowCoordinator(
                taskListStateCoordinator,
                _taskSyncCoordinator,
              ),
            );
          },
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'SaaS Reliability Lab',
        theme: buildLabTheme(),
        home: const LabShell(),
      ),
    );
  }
}
