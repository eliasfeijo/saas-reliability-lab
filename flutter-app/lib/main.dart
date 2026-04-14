import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/helpers/app_mode_helper.dart';
import 'package:todo_flutter/keys.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_sync_coordinator.dart';
import 'package:todo_flutter/screens/lab_shell.dart';
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
  late final RuntimeDebugProvider _runtimeDebugProvider;
  late final TaskSyncService _taskSyncService;
  late final TaskSyncCoordinator _taskSyncCoordinator;
  late final UserSessionService _userSessionService;
  late final WorkspaceSessionCoordinator _workspaceSessionCoordinator;

  @override
  void initState() {
    super.initState();
    _tasksRepository = TasksSharedPreferencesRepository();
    _runtimeDebugProvider = RuntimeDebugProvider();
    _taskSyncService = TaskSyncService(
      _tasksRepository,
      Supabase.instance.client,
      runtimeDebug: _runtimeDebugProvider,
    );
    _taskSyncCoordinator = TaskSyncCoordinator(
      _tasksRepository,
      _taskSyncService,
      runtimeDebug: _runtimeDebugProvider,
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
        Provider<WorkspaceSessionCoordinator>.value(
          value: _workspaceSessionCoordinator,
        ),
        ChangeNotifierProvider(
          create: (context) => AgendaProvider(
            _tasksRepository,
            _taskSyncService,
            taskSyncCoordinator: _taskSyncCoordinator,
            runtimeDebug: _runtimeDebugProvider,
          ),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'SaaS Reliability Lab',
        theme: buildLabTheme(),
        home: const SelectionArea(child: LabShell()),
      ),
    );
  }
}
