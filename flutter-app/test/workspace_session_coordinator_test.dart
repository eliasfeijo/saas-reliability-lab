import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'package:todo_flutter/services/user_session_service.dart';
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
    'session coordinator coalesces concurrent push registration for the same authenticated user',
    () async {
      final anonymousTask = buildTask(
        id: 'task-session-init-race',
        title: 'Pending review race',
        beginsAt: DateTime(2026, 3, 5, 9),
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

      final registerCompleter = Completer<void>();
      var registerCalls = 0;
      final coordinator = WorkspaceSessionCoordinator(
        userSession,
        registerPushSubscription: ({runtimeDebug}) async {
          registerCalls++;
          await registerCompleter.future;
        },
        activeUserId: () => 'user-1',
        hasAuthenticatedSession: () => true,
      );

      final firstInitialize = coordinator.initialize(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
      );
      final secondInitialize = coordinator.initialize(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
      );

      await Future<void>.delayed(Duration.zero);
      expect(registerCalls, 1);

      registerCompleter.complete();
      final results = await Future.wait([firstInitialize, secondInitialize]);

      expect(results, hasLength(2));
      expect(
        results.every((result) => result.shouldShowAnonymousTaskReview),
        isTrue,
      );
      expect(registerCalls, 1);
    },
  );

  test(
    'session coordinator waits for bootstrap before processing signed-in setup',
    () async {
      final anonymousTask = buildTask(
        id: 'task-session-bootstrap',
        title: 'Bootstrap local task',
        beginsAt: DateTime(2026, 3, 6, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
      );

      final bootstrapLoadCompleter = Completer<void>();
      final repository = _DelayedFirstLoadTasksRepository([
        anonymousTask,
      ], firstLoadCompleter: bootstrapLoadCompleter);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final userSession = _DelayedLoadUserSessionService(
        initialLoadCompleter: bootstrapLoadCompleter,
        runtimeDebug: runtimeDebug,
      );

      final agenda = buildAgendaProviderForTesting(
        repository,
        TaskSyncService.forTesting(
          repository,
          remote: FakeTaskRemoteDataSource(const []),
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

      final initializeFuture = coordinator.initialize(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
      );
      await Future<void>.delayed(Duration.zero);

      final signInFuture = coordinator.handleAuthStateChange(
        AuthChangeEvent.signedIn,
        agenda: agenda,
        runtimeDebug: runtimeDebug,
      );
      await Future<void>.delayed(Duration.zero);

      expect(agenda.tasks, isEmpty);
      expect(await userSession.loadUserId(), isNull);
      expect(registerCalls, 0);

      bootstrapLoadCompleter.complete();
      final results = await Future.wait([initializeFuture, signInFuture]);

      expect(agenda.userId, 'user-1');
      expect(await userSession.loadUserId(), 'user-1');
      expect(agenda.tasks, hasLength(1));
      expect(agenda.tasks.single.id, anonymousTask.id);
      expect(results.last.shouldShowAnonymousTaskReview, isTrue);
      expect(registerCalls, 1);
    },
  );

  test(
    'session coordinator initialSession restores authenticated setup after bootstrap completes without a session',
    () async {
      final accountTask = buildTask(
        id: 'task-session-initial-session',
        title: 'Remote initial session task',
        beginsAt: DateTime(2026, 3, 7, 9),
        estimatedDuration: const Duration(hours: 1),
        updatedAt: DateTime(2026, 3, 7, 8, 30),
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );

      final repository = InMemoryTasksRepository(const <TaskModel>[]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final userSession = InMemoryUserSessionService(
        runtimeDebug: runtimeDebug,
      );
      final syncGateway = _RecordingTaskSyncGateway(
        repository: repository,
        reloadedTasks: [accountTask],
      );

      final agenda = buildAgendaProviderForTesting(
        repository,
        syncGateway,
        runtimeDebug: runtimeDebug,
      );
      addTearDown(agenda.dispose);

      var registerCalls = 0;
      var activeUserId = '';
      var hasAuthenticatedSession = false;
      final coordinator = WorkspaceSessionCoordinator(
        userSession,
        registerPushSubscription: ({runtimeDebug}) async {
          registerCalls++;
        },
        activeUserId: () => activeUserId,
        hasAuthenticatedSession: () => hasAuthenticatedSession,
      );

      final bootstrapResult = await coordinator.initialize(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
      );

      expect(bootstrapResult.shouldShowAnonymousTaskReview, isFalse);
      expect(agenda.userId, isNull);
      expect(agenda.tasks, isEmpty);
      expect(registerCalls, 0);

      activeUserId = 'user-1';
      hasAuthenticatedSession = true;

      final initialSessionResult = await coordinator.handleAuthStateChange(
        AuthChangeEvent.initialSession,
        agenda: agenda,
        runtimeDebug: runtimeDebug,
      );

      expect(initialSessionResult.shouldShowAnonymousTaskReview, isFalse);
      expect(agenda.userId, 'user-1');
      expect(await userSession.loadUserId(), 'user-1');
      expect(syncGateway.syncCallCount, 1);
      expect(agenda.tasks, hasLength(1));
      expect(agenda.tasks.single.id, accountTask.id);
      expect(agenda.tasks.single.syncStatus, SyncStatus.synced);
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
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
        hasRemoteBackingRecord: true,
      );

      final repository = InMemoryTasksRepository([accountTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final userSession = InMemoryUserSessionService(
        runtimeDebug: runtimeDebug,
      );
      await userSession.saveUserId('user-1');

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
      expect(runtimeDebug.state.blockedNoSessionEntryCount, 0);
      expect(await userSession.loadUserId(), isNull);
    },
  );
}

class _DelayedLoadUserSessionService extends UserSessionService {
  _DelayedLoadUserSessionService({
    required this.initialLoadCompleter,
    super.runtimeDebug,
  });

  final Completer<void> initialLoadCompleter;
  String? _userId;
  var _didDelayInitialLoad = false;

  @override
  Future<String?> loadUserId() async {
    if (!_didDelayInitialLoad) {
      _didDelayInitialLoad = true;
      await initialLoadCompleter.future;
    }

    return _userId;
  }

  @override
  Future<void> saveUserId(String userId) async {
    _userId = userId;
  }

  @override
  Future<void> clearUserId() async {
    _userId = null;
  }
}

class _DelayedFirstLoadTasksRepository implements TasksRepository {
  _DelayedFirstLoadTasksRepository(
    List<TaskModel> tasks, {
    required this.firstLoadCompleter,
  }) : _tasks = tasks.map(cloneTask).toList(growable: false);

  final Completer<void> firstLoadCompleter;
  List<TaskModel> _tasks;
  var _didDelayInitialLoad = false;

  @override
  Future<void> clearTasks() async {
    _tasks = const <TaskModel>[];
  }

  @override
  Future<List<TaskModel>> loadTasks() async {
    final snapshot = _tasks.map(cloneTask).toList(growable: false);
    if (!_didDelayInitialLoad) {
      _didDelayInitialLoad = true;
      await firstLoadCompleter.future;
    }

    return snapshot;
  }

  @override
  Future<void> saveTasks(List<TaskModel> tasks) async {
    _tasks = tasks.map(cloneTask).toList(growable: false);
  }
}

class _RecordingTaskSyncGateway implements TaskSyncGateway {
  _RecordingTaskSyncGateway({
    required this.repository,
    required this.reloadedTasks,
  });

  final TasksRepository repository;
  final List<TaskModel> reloadedTasks;
  var syncCallCount = 0;

  @override
  Future<TaskSyncRunResult> syncTasks(List<TaskModel> tasks) async {
    syncCallCount++;
    await repository.saveTasks(
      reloadedTasks.map(cloneTask).toList(growable: false),
    );
    return const TaskSyncRunResult();
  }

  @override
  void syncIfLoggedIn(
    TaskModel task,
    Function()? beforeSync,
    Function(TaskSyncRunResult result) callback,
  ) {
    throw UnimplementedError();
  }
}
