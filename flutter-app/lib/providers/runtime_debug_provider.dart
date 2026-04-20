import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/models/task.dart';

class RuntimeDebugProvider extends ChangeNotifier {
  RuntimeDebugProvider({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity() {
    unawaited(refreshConnectivity());
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (results) => setConnectivityResults(results),
    );
  }

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  List<ConnectivityResult> _lastObservedConnectivityResults = const [];

  RuntimeDebugState _state = const RuntimeDebugState();

  RuntimeDebugState get state => _state;

  Future<void> refreshConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    setConnectivityResults(results, logEvent: false);
  }

  void setConnectivityResults(
    List<ConnectivityResult> results, {
    bool logEvent = true,
    bool updateObservedCache = true,
  }) {
    if (updateObservedCache) {
      _lastObservedConnectivityResults = List<ConnectivityResult>.from(results);
    }

    final nextStatus =
        results.isEmpty ||
            results.every((result) => result == ConnectivityResult.none)
        ? ConnectivityStatus.offline
        : ConnectivityStatus.online;

    if (_state.connectivityStatus == nextStatus) {
      return;
    }

    _replace(_state.copyWith(connectivityStatus: nextStatus));

    if (logEvent) {
      addEvent(
        category: RuntimeEventCategory.connectivity,
        message: nextStatus == ConnectivityStatus.online
            ? 'Connectivity restored.'
            : 'Connectivity lost.',
        level: nextStatus == ConnectivityStatus.online
            ? RuntimeEventLevel.info
            : RuntimeEventLevel.warning,
      );
    }
  }

  void restoreObservedConnectivity({bool logEvent = false}) {
    setConnectivityResults(
      _lastObservedConnectivityResults,
      logEvent: logEvent,
      updateObservedCache: false,
    );
  }

  void startInitialLoad(String message) {
    _replace(
      _state.copyWith(
        isInitialLoadRunning: true,
        syncPhase: RuntimeSyncPhase.initialLoad,
      ),
    );
    addEvent(category: RuntimeEventCategory.app, message: message);
  }

  void finishInitialLoad({String? message}) {
    _replace(
      _state.copyWith(
        isInitialLoadRunning: false,
        syncPhase: RuntimeSyncPhase.idle,
      ),
    );
    if (message != null && message.isNotEmpty) {
      addEvent(category: RuntimeEventCategory.app, message: message);
    }
  }

  void failInitialLoad(String message) {
    _replace(
      _state.copyWith(
        isInitialLoadRunning: false,
        syncPhase: RuntimeSyncPhase.error,
      ),
    );
    addEvent(
      category: RuntimeEventCategory.app,
      message: message,
      level: RuntimeEventLevel.error,
    );
  }

  void setUserState({
    required String? cachedUserId,
    required String? activeUserId,
    required bool hasAuthenticatedSession,
    bool logEvent = false,
    String? message,
  }) {
    final didChange =
        _state.cachedUserId != cachedUserId ||
        _state.activeUserId != activeUserId ||
        _state.hasAuthenticatedSession != hasAuthenticatedSession;

    _replace(
      _state.copyWith(
        cachedUserId: cachedUserId,
        activeUserId: activeUserId,
        hasAuthenticatedSession: hasAuthenticatedSession,
      ),
    );

    if (logEvent && didChange) {
      addEvent(
        category: RuntimeEventCategory.auth,
        message:
            message ??
            (hasAuthenticatedSession
                ? 'Authenticated session available.'
                : 'Authenticated session unavailable.'),
        level: hasAuthenticatedSession
            ? RuntimeEventLevel.info
            : RuntimeEventLevel.warning,
      );
    }
  }

  void updateTaskCounts(List<TaskModel> tasks) {
    final dirtyTaskCount = tasks
        .where((task) => task.syncStatus == SyncStatus.dirty)
        .length;
    final deletedTaskCount = tasks
        .where((task) => task.syncStatus == SyncStatus.deleted)
        .length;
    final anonymousTaskCount = tasks
        .where(
          (task) =>
              task.userId == null && task.syncStatus != SyncStatus.deleted,
        )
        .length;

    final nextState = _state.copyWith(
      dirtyTaskCount: dirtyTaskCount,
      deletedTaskCount: deletedTaskCount,
      anonymousTaskCount: anonymousTaskCount,
    );

    if (nextState.dirtyTaskCount == _state.dirtyTaskCount &&
        nextState.deletedTaskCount == _state.deletedTaskCount &&
        nextState.anonymousTaskCount == _state.anonymousTaskCount) {
      return;
    }

    _replace(nextState);
  }

  void markSyncStarted(String message) {
    _replace(
      _state.copyWith(
        syncPhase: RuntimeSyncPhase.syncing,
        lastSyncStartedAt: DateTime.now(),
        lastSyncMessage: message,
      ),
    );
    addEvent(category: RuntimeEventCategory.sync, message: message);
  }

  void markSyncSuccess(String message) {
    _replace(
      _state.copyWith(
        syncPhase: RuntimeSyncPhase.idle,
        lastSyncResult: RuntimeSyncResult.success,
        lastSyncCompletedAt: DateTime.now(),
        lastSyncMessage: message,
        lastSuccessfulSyncAt: DateTime.now(),
        lastSuccessfulSyncMessage: message,
      ),
    );
    addEvent(category: RuntimeEventCategory.sync, message: message);
  }

  void markSyncSkipped({
    required RuntimeSyncPhase phase,
    required String message,
  }) {
    _replace(
      _state.copyWith(
        syncPhase: phase,
        lastSyncResult: RuntimeSyncResult.skipped,
        lastSyncCompletedAt: DateTime.now(),
        lastSyncMessage: message,
        lastSkippedSyncAt: DateTime.now(),
        lastSkippedSyncMessage: message,
      ),
    );
    addEvent(
      category: RuntimeEventCategory.sync,
      message: message,
      level: RuntimeEventLevel.warning,
    );
  }

  void markSyncPartial(String message) {
    _replace(
      _state.copyWith(
        syncPhase: RuntimeSyncPhase.idle,
        lastSyncResult: RuntimeSyncResult.partial,
        lastSyncCompletedAt: DateTime.now(),
        lastSyncMessage: message,
        lastPartialSyncAt: DateTime.now(),
        lastPartialSyncMessage: message,
      ),
    );
    addEvent(
      category: RuntimeEventCategory.sync,
      message: message,
      level: RuntimeEventLevel.warning,
    );
  }

  void markSyncFailure(String message) {
    _replace(
      _state.copyWith(
        syncPhase: RuntimeSyncPhase.error,
        lastSyncResult: RuntimeSyncResult.failed,
        lastSyncCompletedAt: DateTime.now(),
        lastSyncMessage: message,
        lastFailedSyncAt: DateTime.now(),
        lastFailedSyncMessage: message,
      ),
    );
    addEvent(
      category: RuntimeEventCategory.sync,
      message: message,
      level: RuntimeEventLevel.error,
    );
  }

  void setActiveFaultInjection({
    required String label,
    required String message,
    required String instruction,
  }) {
    _replace(
      _state.copyWith(
        activeFaultInjectionLabel: label,
        activeFaultInjectionMessage: message,
        activeFaultInjectionInstruction: instruction,
      ),
    );
  }

  void clearActiveFaultInjection() {
    if (_state.activeFaultInjectionLabel == null &&
        _state.activeFaultInjectionMessage == null &&
        _state.activeFaultInjectionInstruction == null) {
      return;
    }

    _replace(
      _state.copyWith(
        activeFaultInjectionLabel: null,
        activeFaultInjectionMessage: null,
        activeFaultInjectionInstruction: null,
      ),
    );
  }

  void setPushPermission(
    PushPermissionState permissionState, {
    String? message,
    bool logEvent = true,
  }) {
    _replace(_state.copyWith(pushPermissionState: permissionState));
    if (logEvent && message != null && message.isNotEmpty) {
      addEvent(category: RuntimeEventCategory.push, message: message);
    }
  }

  void setPushPermissionFromRaw(
    String? permission, {
    String? message,
    bool logEvent = true,
  }) {
    final permissionState = switch (permission) {
      'default' => PushPermissionState.prompt,
      'granted' => PushPermissionState.granted,
      'denied' => PushPermissionState.denied,
      'unsupported' => PushPermissionState.unsupported,
      null => PushPermissionState.unavailable,
      _ => PushPermissionState.unavailable,
    };

    setPushPermission(
      permissionState,
      message: message ?? 'Push permission is ${permissionState.label}.',
      logEvent: logEvent,
    );
  }

  void setPushSubscriptionState(
    PushSubscriptionState subscriptionState, {
    String? message,
    RuntimeEventLevel level = RuntimeEventLevel.info,
    bool logEvent = true,
  }) {
    _replace(
      _state.copyWith(
        pushSubscriptionState: subscriptionState,
        lastPushMessage: message,
        lastPushUpdatedAt: DateTime.now(),
      ),
    );

    if (logEvent && message != null && message.isNotEmpty) {
      addEvent(
        category: RuntimeEventCategory.push,
        message: message,
        level: level,
      );
    }
  }

  void addEvent({
    required RuntimeEventCategory category,
    required String message,
    RuntimeEventLevel level = RuntimeEventLevel.info,
    String? detail,
  }) {
    final updatedEvents = [
      RuntimeEvent(
        timestamp: DateTime.now(),
        level: level,
        category: category,
        message: message,
        detail: detail,
      ),
      ..._state.recentEvents,
    ].take(20).toList(growable: false);

    _replace(_state.copyWith(recentEvents: updatedEvents));
  }

  void _replace(RuntimeDebugState nextState) {
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
