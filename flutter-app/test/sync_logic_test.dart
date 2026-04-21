import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/services/fault_injection_policy.dart';
import 'package:todo_flutter/services/task_sync_service.dart';

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

  test(
    'syncAllTasks keeps the fresher remote task when local state is stale',
    () async {
      final remoteTask = buildTask(
        id: 'task-1',
        title: 'Remote truth',
        beginsAt: DateTime(2026, 1, 10, 9),
        estimatedDuration: const Duration(hours: 1),
        updatedAt: DateTime(2026, 1, 10, 12),
        userId: 'user-1',
      );

      final localTask = buildTask(
        id: 'task-1',
        title: 'Stale local draft',
        beginsAt: DateTime(2026, 1, 10, 9),
        estimatedDuration: const Duration(hours: 1),
        lastModifiedAt: DateTime(2026, 1, 10, 10),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([localTask]);
      final remote = FakeTaskRemoteDataSource([remoteTask]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
      );

      final syncedTasks = await service.syncAllTasks(
        await repository.loadTasks(),
      );
      final savedTasks = await repository.loadTasks();

      expect(syncedTasks, isEmpty);
      expect(remote.updatedTaskIds, isEmpty);
      expect(savedTasks, hasLength(1));
      expect(savedTasks.single.title, 'Remote truth');
      expect(savedTasks.single.syncStatus, SyncStatus.synced);
      expect(savedTasks.single.updatedAt, DateTime(2026, 1, 10, 12));

      final adoptionEvent = runtimeDebug.state.recentEvents.firstWhere(
        (event) =>
            event.message ==
            'Remote task Stale local draft replaced stale local state.',
      );
      expect(adoptionEvent.payload, isNotNull);
      expect(adoptionEvent.payload!.stage, 'Remote truth adopted');
      expect(adoptionEvent.payload!.tasks, hasLength(1));
      expect(adoptionEvent.payload!.tasks.single.fieldDiffs, isNotEmpty);
      expect(
        adoptionEvent.payload!.tasks.single.fieldDiffs
            .where((field) => field.label == 'Title')
            .single,
        isA<RuntimeEventFieldDiff>()
            .having((field) => field.before, 'before', 'Stale local draft')
            .having((field) => field.after, 'after', 'Remote truth'),
      );
    },
  );

  test(
    'syncTasks skips cloud replay when connectivity loss is injected',
    () async {
      final localTask = buildTask(
        id: 'task-connectivity-loss',
        title: 'Will stay local',
        beginsAt: DateTime(2026, 1, 11, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([localTask]);
      final remote = FakeTaskRemoteDataSource([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
        faultInjectionPolicy: FaultInjectionPolicy(
          readState: () => const FaultInjectionState(
            activeScenario: FaultInjectionScenario.connectivityLoss,
            isEnabled: true,
          ),
        ),
      );

      final result = await service.syncTasks(await repository.loadTasks());
      final savedTasks = await repository.loadTasks();

      expect(result.acknowledgedTasks, isEmpty);
      expect(remote.insertedTaskIds, isEmpty);
      expect(remote.updatedTaskIds, isEmpty);
      expect(savedTasks.single.syncStatus, SyncStatus.dirty);
      expect(runtimeDebug.state.syncPhase, RuntimeSyncPhase.offline);
      expect(runtimeDebug.state.lastSyncResult, RuntimeSyncResult.skipped);
      expect(
        runtimeDebug.state.lastSyncMessage,
        'Connectivity loss scenario is active. Cloud sync is being forced offline.',
      );
    },
  );

  test(
    'syncTasks holds the sync phase open when delayed sync is injected',
    () async {
      final localTask = buildTask(
        id: 'task-delayed-sync',
        title: 'Delayed convergence',
        beginsAt: DateTime(2026, 1, 12, 9),
        estimatedDuration: const Duration(hours: 1),
        syncStatus: SyncStatus.dirty,
        userId: 'user-1',
      );

      final repository = InMemoryTasksRepository([localTask]);
      final remote = FakeTaskRemoteDataSource([]);
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      final delayCompleter = Completer<void>();
      Duration? delayedBy;

      final service = TaskSyncService.forTesting(
        repository,
        remote: remote,
        connectivityCheck: () async => [ConnectivityResult.wifi],
        hasActiveSession: () => true,
        runtimeDebug: runtimeDebug,
        faultInjectionPolicy: FaultInjectionPolicy(
          readState: () => const FaultInjectionState(
            activeScenario: FaultInjectionScenario.delayedSync,
            isEnabled: true,
            delayMs: 5000,
          ),
        ),
        delayExecution: (duration) {
          delayedBy = duration;
          return delayCompleter.future;
        },
      );

      final syncFuture = service.syncTasks(await repository.loadTasks());
      await Future<void>.delayed(Duration.zero);

      expect(delayedBy, const Duration(seconds: 5));
      expect(runtimeDebug.state.syncPhase, RuntimeSyncPhase.syncing);
      expect(runtimeDebug.state.lastSyncResult, RuntimeSyncResult.none);
      expect(
        runtimeDebug.state.lastSyncMessage,
        'Delayed sync scenario is active. Holding remote replay for 5 s before synchronizing 1 local task(s).',
      );
      expect(
        runtimeDebug.state.recentEvents.first.message,
        'Delayed sync scenario is holding the sync pass for 5 s before remote replay begins.',
      );
      expect(runtimeDebug.state.recentEvents.first.payload, isNotNull);
      expect(
        runtimeDebug.state.recentEvents.first.payload!.stage,
        'Deterministic hold',
      );
      expect(
        runtimeDebug.state.recentEvents.first.payload!.metrics
            .where((metric) => metric.label == 'Injected delay')
            .single
            .value,
        '5 s',
      );

      delayCompleter.complete();
      final result = await syncFuture;

      expect(result.acknowledgedTasks, hasLength(1));
      expect(remote.insertedTaskIds, ['task-delayed-sync']);
      expect(runtimeDebug.state.lastSyncResult, RuntimeSyncResult.success);
      expect(runtimeDebug.state.recentEvents.first.payload, isNotNull);
      expect(
        runtimeDebug.state.recentEvents.first.payload!.stage,
        'Replay completed',
      );
      expect(
        runtimeDebug.state.recentEvents.first.payload!.tasks.single.outcome,
        'Created remotely',
      );
    },
  );
}
