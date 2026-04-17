import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/screens/lab_shell.dart';
import 'package:todo_flutter/services/task_list_state_coordinator.dart';
import 'package:todo_flutter/services/task_local_snapshot_coordinator.dart';
import 'package:todo_flutter/services/task_sync_coordinator.dart';
import 'package:todo_flutter/services/task_sync_flow_coordinator.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'package:todo_flutter/services/user_session_service.dart';
import 'package:todo_flutter/services/workspace_session_coordinator.dart';
import 'package:todo_flutter/theme/lab_theme.dart';
import 'package:todo_flutter/widgets/lab/lab_left_rail.dart';
import 'package:todo_flutter/widgets/lab/task_workspace.dart';

AgendaProvider buildAgendaProviderForTesting(
  TasksRepository repository,
  TaskSyncGateway taskSyncGateway, {
  RuntimeDebugProvider? runtimeDebug,
}) {
  final snapshotCoordinator = TaskLocalSnapshotCoordinator.fromRepository(
    repository,
  );
  final taskListStateCoordinator = TaskListStateCoordinator(
    snapshotCoordinator,
    runtimeDebug: runtimeDebug,
  );
  final taskSyncCoordinator = TaskSyncCoordinator(
    snapshotCoordinator,
    taskSyncGateway,
    runtimeDebug: runtimeDebug,
  );

  return AgendaProvider(
    taskListStateCoordinator: taskListStateCoordinator,
    taskSyncFlowCoordinator: TaskSyncFlowCoordinator(
      taskListStateCoordinator,
      taskSyncCoordinator,
    ),
  );
}

Future<void> ensureSupabaseInitialized() async {
  try {
    Supabase.instance.client;
    return;
  } catch (_) {}

  await Supabase.initialize(
    url: 'https://example.supabase.co',
    anonKey: 'test-anon-key',
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
  );
}

String textValue(WidgetTester tester, String keyValue) {
  final widget = tester.widget<Text>(find.byKey(ValueKey(keyValue)));
  return widget.data ?? '';
}

double top(WidgetTester tester, String text) {
  return tester.getTopLeft(find.text(text).first).dy;
}

double left(WidgetTester tester, String text) {
  return tester.getTopLeft(find.text(text).first).dx;
}

class LabWorkspaceHarness extends StatelessWidget {
  const LabWorkspaceHarness({
    super.key,
    required this.agenda,
    required this.runtimeDebug,
  });

  final AgendaProvider agenda;
  final RuntimeDebugProvider runtimeDebug;

  @override
  Widget build(BuildContext context) {
    final sessionCoordinator = WorkspaceSessionCoordinator(
      InMemoryUserSessionService(runtimeDebug: runtimeDebug),
      registerPushSubscription: ({runtimeDebug}) async {},
      hasAuthenticatedSession: () => false,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RuntimeDebugProvider>.value(value: runtimeDebug),
        Provider<WorkspaceSessionCoordinator>.value(value: sessionCoordinator),
        ChangeNotifierProvider<AgendaProvider>.value(value: agenda),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLabTheme(),
        home: Scaffold(
          body: Row(
            children: const [
              SizedBox(width: 320, child: LabLeftRail()),
              SizedBox(width: 20),
              Expanded(child: TaskWorkspace()),
            ],
          ),
        ),
      ),
    );
  }
}

class NotebookWorkspaceHarness extends StatelessWidget {
  const NotebookWorkspaceHarness({
    super.key,
    required this.agenda,
    required this.runtimeDebug,
  });

  final AgendaProvider agenda;
  final RuntimeDebugProvider runtimeDebug;

  @override
  Widget build(BuildContext context) {
    final sessionCoordinator = WorkspaceSessionCoordinator(
      InMemoryUserSessionService(runtimeDebug: runtimeDebug),
      registerPushSubscription: ({runtimeDebug}) async {},
      hasAuthenticatedSession: () => false,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RuntimeDebugProvider>.value(value: runtimeDebug),
        Provider<WorkspaceSessionCoordinator>.value(value: sessionCoordinator),
        ChangeNotifierProvider<AgendaProvider>.value(value: agenda),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLabTheme(),
        home: Scaffold(
          body: Center(child: SizedBox(width: 780, child: TaskWorkspace())),
        ),
      ),
    );
  }
}

class CompactWorkspaceHarness extends StatelessWidget {
  const CompactWorkspaceHarness({
    super.key,
    required this.agenda,
    required this.runtimeDebug,
  });

  final AgendaProvider agenda;
  final RuntimeDebugProvider runtimeDebug;

  @override
  Widget build(BuildContext context) {
    final sessionCoordinator = WorkspaceSessionCoordinator(
      InMemoryUserSessionService(runtimeDebug: runtimeDebug),
      registerPushSubscription: ({runtimeDebug}) async {},
      hasAuthenticatedSession: () => false,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RuntimeDebugProvider>.value(value: runtimeDebug),
        Provider<WorkspaceSessionCoordinator>.value(value: sessionCoordinator),
        ChangeNotifierProvider<AgendaProvider>.value(value: agenda),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLabTheme(),
        home: Scaffold(
          body: Center(child: SizedBox(width: 360, child: TaskWorkspace())),
        ),
      ),
    );
  }
}

class LabShellHarness extends StatelessWidget {
  const LabShellHarness({
    super.key,
    required this.agenda,
    required this.runtimeDebug,
  });

  final AgendaProvider agenda;
  final RuntimeDebugProvider runtimeDebug;

  @override
  Widget build(BuildContext context) {
    final sessionCoordinator = WorkspaceSessionCoordinator(
      InMemoryUserSessionService(runtimeDebug: runtimeDebug),
      registerPushSubscription: ({runtimeDebug}) async {},
      hasAuthenticatedSession: () => false,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RuntimeDebugProvider>.value(value: runtimeDebug),
        Provider<WorkspaceSessionCoordinator>.value(value: sessionCoordinator),
        ChangeNotifierProvider<AgendaProvider>.value(value: agenda),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLabTheme(),
        home: const LabShell(),
      ),
    );
  }
}

class RailHarness extends StatelessWidget {
  const RailHarness({
    super.key,
    required this.agenda,
    required this.runtimeDebug,
    required this.child,
  });

  final AgendaProvider agenda;
  final RuntimeDebugProvider runtimeDebug;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RuntimeDebugProvider>.value(value: runtimeDebug),
        ChangeNotifierProvider<AgendaProvider>.value(value: agenda),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLabTheme(),
        home: Scaffold(body: child),
      ),
    );
  }
}

class InMemoryUserSessionService extends UserSessionService {
  InMemoryUserSessionService({super.runtimeDebug});

  String? _userId;

  @override
  Future<String?> loadUserId() async => _userId;

  @override
  Future<void> saveUserId(String userId) async {
    _userId = userId;
  }

  @override
  Future<void> clearUserId() async {
    _userId = null;
  }
}

class InMemoryTasksRepository implements TasksRepository {
  InMemoryTasksRepository(List<TaskModel> tasks)
    : _tasks = tasks.map(cloneTask).toList();

  List<TaskModel> _tasks;

  @override
  Future<void> clearTasks() async {
    _tasks = [];
  }

  @override
  Future<List<TaskModel>> loadTasks() async {
    return _tasks.map(cloneTask).toList();
  }

  @override
  Future<void> saveTasks(List<TaskModel> tasks) async {
    _tasks = tasks.map(cloneTask).toList();
  }
}

class FakeTaskRemoteDataSource implements TaskRemoteDataSource {
  FakeTaskRemoteDataSource(List<TaskModel> tasks)
    : _tasksById = {for (final task in tasks) task.id: cloneTask(task)};

  final Map<String, TaskModel> _tasksById;
  final List<String> insertedTaskIds = [];
  final List<String> updatedTaskIds = [];

  @override
  Future<void> deleteTask(String taskId) async {
    _tasksById.remove(taskId);
  }

  @override
  Future<List<TaskModel>> fetchAllTasks() async {
    return _tasksById.values.map(cloneTask).toList();
  }

  @override
  Future<TaskModel?> fetchTaskById(String taskId) async {
    final task = _tasksById[taskId];
    if (task == null) {
      return null;
    }

    return cloneTask(task);
  }

  @override
  Future<void> insertTask(TaskModel task) async {
    insertedTaskIds.add(task.id);
    _tasksById[task.id] = cloneTask(
      task,
      syncStatus: SyncStatus.synced,
      updatedAt: task.lastModifiedAt ?? DateTime.now(),
    );
  }

  @override
  Future<void> updateTask(TaskModel task) async {
    updatedTaskIds.add(task.id);
    _tasksById[task.id] = cloneTask(
      task,
      syncStatus: SyncStatus.synced,
      updatedAt: task.lastModifiedAt ?? DateTime.now(),
    );
  }
}

class TestConnectivityPlatform extends ConnectivityPlatform {
  TestConnectivityPlatform({
    List<ConnectivityResult> initialResults = const [ConnectivityResult.wifi],
  }) : _results = List<ConnectivityResult>.from(initialResults);

  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  List<ConnectivityResult> _results;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    return List<ConnectivityResult>.from(_results);
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> results) {
    _results = List<ConnectivityResult>.from(results);
    _controller.add(List<ConnectivityResult>.from(_results));
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

TaskModel buildTask({
  required String id,
  required String title,
  required DateTime beginsAt,
  required Duration estimatedDuration,
  SyncStatus syncStatus = SyncStatus.synced,
  DateTime? updatedAt,
  DateTime? lastModifiedAt,
  String? userId,
}) {
  return TaskModel(
    id: id,
    title: title,
    beginsAt: beginsAt,
    estimatedDuration: estimatedDuration,
    syncStatus: syncStatus,
    updatedAt: updatedAt,
    lastModifiedAt: lastModifiedAt,
    userId: userId,
  );
}

TaskModel cloneTask(
  TaskModel task, {
  SyncStatus? syncStatus,
  DateTime? updatedAt,
}) {
  return TaskModel(
    id: task.id,
    title: task.title,
    beginsAt: task.beginsAt,
    estimatedDuration: task.estimatedDuration,
    isCompleted: task.isCompleted,
    completedAt: task.completedAt,
    description: task.description,
    priority: task.priority,
    tags: List<String>.from(task.tags),
    syncStatus: syncStatus ?? task.syncStatus,
    createdAt: task.createdAt,
    updatedAt: updatedAt ?? task.updatedAt,
    lastModifiedAt: task.lastModifiedAt,
    userId: task.userId,
  );
}
