import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'package:todo_flutter/services/user_session_service.dart';
import 'package:todo_flutter/theme/lab_theme.dart';
import 'package:todo_flutter/widgets/lab/lab_left_rail.dart';
import 'package:todo_flutter/widgets/lab/task_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityPlatform originalConnectivityPlatform;
  late _TestConnectivityPlatform connectivityPlatform;
  var didOverrideConnectivityPlatform = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await _ensureSupabaseInitialized();
    originalConnectivityPlatform = ConnectivityPlatform.instance;
    connectivityPlatform = _TestConnectivityPlatform(
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
    'anonymous create-delete clears queue controls and review counters',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final repository = _InMemoryTasksRepository([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

      final syncService = TaskSyncService.forTesting(
        repository,
        remote: _FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
        runtimeDebug: runtimeDebug,
      );

      final agenda = AgendaProvider(
        repository,
        syncService,
        _InMemoryUserSessionService(runtimeDebug: runtimeDebug),
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      await tester.pumpWidget(
        _LabWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
      );
      await tester.pumpAndSettle();

      expect(_textValue(tester, 'task-workspace-pending-value'), '0');
      expect(_textValue(tester, 'task-scope-total-value'), '0');
      expect(_textValue(tester, 'anonymous-review-count-value'), '0');

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
      expect(_textValue(tester, 'task-workspace-in-view-value'), '1');
      expect(_textValue(tester, 'task-workspace-pending-value'), '1');
      expect(_textValue(tester, 'task-scope-visible-value'), '1');
      expect(_textValue(tester, 'task-scope-total-value'), '1');
      expect(_textValue(tester, 'anonymous-review-count-value'), '1');

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
      expect(
        find.text('No anonymous tasks are waiting for review.'),
        findsOneWidget,
      );
      expect(_textValue(tester, 'task-workspace-in-view-value'), '0');
      expect(_textValue(tester, 'task-workspace-pending-value'), '0');
      expect(_textValue(tester, 'task-scope-visible-value'), '0');
      expect(_textValue(tester, 'task-scope-total-value'), '0');
      expect(_textValue(tester, 'anonymous-review-count-value'), '0');
    },
  );

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

      final repository = _InMemoryTasksRepository([seededTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

      final syncService = TaskSyncService.forTesting(
        repository,
        remote: _FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
        runtimeDebug: runtimeDebug,
      );

      final agenda = AgendaProvider(
        repository,
        syncService,
        _InMemoryUserSessionService(runtimeDebug: runtimeDebug),
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      await tester.pumpWidget(
        _LabWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
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

      final repository = _InMemoryTasksRepository([laterTask, earlierTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

      final syncService = TaskSyncService.forTesting(
        repository,
        remote: _FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
        runtimeDebug: runtimeDebug,
      );

      final agenda = AgendaProvider(
        repository,
        syncService,
        _InMemoryUserSessionService(runtimeDebug: runtimeDebug),
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      await tester.pumpWidget(
        _NotebookWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
      );
      await tester.pumpAndSettle();

      expect(
        _top(tester, 'Earlier task'),
        lessThan(_top(tester, 'Later task')),
      );
      expect(find.text('Sort: Closest'), findsOneWidget);

      await tester.tap(find.text('Sort: Closest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Latest first').last);
      await tester.pumpAndSettle();

      expect(
        _top(tester, 'Later task'),
        lessThan(_top(tester, 'Earlier task')),
      );
      expect(
        (_left(tester, 'Task Queue') - _left(tester, 'Queue Controls')).abs(),
        lessThan(1),
      );

      await tester.tap(find.text('Earlier task'));
      await tester.pumpAndSettle();

      expect(find.text('Task details'), findsOneWidget);
      expect(find.text('Task Queue'), findsOneWidget);
    },
  );

  testWidgets(
    'compact queue header stacks actions without losing the heading',
    (tester) async {
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

      final repository = _InMemoryTasksRepository([seededTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

      final syncService = TaskSyncService.forTesting(
        repository,
        remote: _FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
        runtimeDebug: runtimeDebug,
      );

      final agenda = AgendaProvider(
        repository,
        syncService,
        _InMemoryUserSessionService(runtimeDebug: runtimeDebug),
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      await tester.pumpWidget(
        _CompactWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
      );
      await tester.pumpAndSettle();

      expect(find.text('Task Queue'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
      expect(find.textContaining('Select a row'), findsOneWidget);
    },
  );

  testWidgets(
    'small screens use attached details instead of inline inspector space',
    (tester) async {
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

      final repository = _InMemoryTasksRepository([seededTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

      final syncService = TaskSyncService.forTesting(
        repository,
        remote: _FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
        runtimeDebug: runtimeDebug,
      );

      final agenda = AgendaProvider(
        repository,
        syncService,
        _InMemoryUserSessionService(runtimeDebug: runtimeDebug),
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      await tester.pumpWidget(
        _CompactWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mobile overlay task'));
      await tester.pumpAndSettle();

      expect(find.text('Task details'), findsOneWidget);
      expect(find.text('Task Queue'), findsOneWidget);
    },
  );

  testWidgets(
    'compact task details can be minimized into a persistent handle',
    (tester) async {
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

      final repository = _InMemoryTasksRepository([seededTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

      final syncService = TaskSyncService.forTesting(
        repository,
        remote: _FakeTaskRemoteDataSource([]),
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => false,
        runtimeDebug: runtimeDebug,
      );

      final agenda = AgendaProvider(
        repository,
        syncService,
        _InMemoryUserSessionService(runtimeDebug: runtimeDebug),
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      await tester.pumpWidget(
        _CompactWorkspaceHarness(agenda: agenda, runtimeDebug: runtimeDebug),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Minimize me'));
      await tester.pumpAndSettle();

      expect(find.text('Task details'), findsOneWidget);

      await tester.tap(find.byTooltip('Minimize panel'));
      await tester.pumpAndSettle();

      expect(find.text('Task details'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    },
  );
}

String _textValue(WidgetTester tester, String keyValue) {
  final widget = tester.widget<Text>(find.byKey(ValueKey(keyValue)));
  return widget.data ?? '';
}

double _top(WidgetTester tester, String text) {
  return tester.getTopLeft(find.text(text).first).dy;
}

double _left(WidgetTester tester, String text) {
  return tester.getTopLeft(find.text(text).first).dx;
}

Future<void> _ensureSupabaseInitialized() async {
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

class _LabWorkspaceHarness extends StatelessWidget {
  const _LabWorkspaceHarness({
    required this.agenda,
    required this.runtimeDebug,
  });

  final AgendaProvider agenda;
  final RuntimeDebugProvider runtimeDebug;

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

class _NotebookWorkspaceHarness extends StatelessWidget {
  const _NotebookWorkspaceHarness({
    required this.agenda,
    required this.runtimeDebug,
  });

  final AgendaProvider agenda;
  final RuntimeDebugProvider runtimeDebug;

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
        home: Scaffold(
          body: Center(child: SizedBox(width: 780, child: TaskWorkspace())),
        ),
      ),
    );
  }
}

class _CompactWorkspaceHarness extends StatelessWidget {
  const _CompactWorkspaceHarness({
    required this.agenda,
    required this.runtimeDebug,
  });

  final AgendaProvider agenda;
  final RuntimeDebugProvider runtimeDebug;

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
        home: Scaffold(
          body: Center(child: SizedBox(width: 360, child: TaskWorkspace())),
        ),
      ),
    );
  }
}

class _InMemoryUserSessionService extends UserSessionService {
  _InMemoryUserSessionService({super.runtimeDebug});

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

class _InMemoryTasksRepository implements TasksRepository {
  List<TaskModel> _tasks;

  _InMemoryTasksRepository(List<TaskModel> tasks)
    : _tasks = tasks.map(_cloneTask).toList();

  @override
  Future<void> clearTasks() async {
    _tasks = [];
  }

  @override
  Future<List<TaskModel>> loadTasks() async {
    return _tasks.map(_cloneTask).toList();
  }

  @override
  Future<void> saveTasks(List<TaskModel> tasks) async {
    _tasks = tasks.map(_cloneTask).toList();
  }
}

class _FakeTaskRemoteDataSource implements TaskRemoteDataSource {
  _FakeTaskRemoteDataSource(List<TaskModel> tasks)
    : _tasksById = {for (final task in tasks) task.id: _cloneTask(task)};

  final Map<String, TaskModel> _tasksById;

  @override
  Future<void> deleteTask(String taskId) async {
    _tasksById.remove(taskId);
  }

  @override
  Future<List<TaskModel>> fetchAllTasks() async {
    return _tasksById.values.map(_cloneTask).toList();
  }

  @override
  Future<TaskModel?> fetchTaskById(String taskId) async {
    final task = _tasksById[taskId];
    if (task == null) {
      return null;
    }

    return _cloneTask(task);
  }

  @override
  Future<void> insertTask(TaskModel task) async {
    _tasksById[task.id] = _cloneTask(
      task,
      syncStatus: SyncStatus.synced,
      updatedAt: task.lastModifiedAt ?? DateTime.now(),
    );
  }

  @override
  Future<void> updateTask(TaskModel task) async {
    _tasksById[task.id] = _cloneTask(
      task,
      syncStatus: SyncStatus.synced,
      updatedAt: task.lastModifiedAt ?? DateTime.now(),
    );
  }
}

class _TestConnectivityPlatform extends ConnectivityPlatform {
  _TestConnectivityPlatform({
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

TaskModel _cloneTask(
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
