import 'package:todo_flutter/models/runtime_event.dart';

const Object _runtimeDebugUnset = Object();

enum ConnectivityStatus { unknown, online, offline }

enum RuntimeSyncPhase {
  idle,
  initialLoad,
  syncing,
  offline,
  blockedNoSession,
  blockedAnonymousReview,
  error,
}

enum RuntimeSyncResult { none, success, skipped, partial, failed }

enum PushPermissionState {
  unknown,
  prompt,
  granted,
  denied,
  unsupported,
  unavailable,
}

enum PushSubscriptionState {
  unknown,
  idle,
  registering,
  registered,
  removing,
  removed,
  failed,
  unavailable,
}

class RuntimeDebugState {
  const RuntimeDebugState({
    this.connectivityStatus = ConnectivityStatus.unknown,
    this.cachedUserId,
    this.activeUserId,
    this.hasAuthenticatedSession = false,
    this.isInitialLoadRunning = false,
    this.syncPhase = RuntimeSyncPhase.idle,
    this.lastSyncResult = RuntimeSyncResult.none,
    this.lastSyncMessage,
    this.lastSyncStartedAt,
    this.lastSyncCompletedAt,
    this.lastSuccessfulSyncAt,
    this.lastSuccessfulSyncMessage,
    this.lastSkippedSyncAt,
    this.lastSkippedSyncMessage,
    this.lastPartialSyncAt,
    this.lastPartialSyncMessage,
    this.lastFailedSyncAt,
    this.lastFailedSyncMessage,
    this.dirtyTaskCount = 0,
    this.deletedTaskCount = 0,
    this.anonymousTaskCount = 0,
    this.pushPermissionState = PushPermissionState.unknown,
    this.pushSubscriptionState = PushSubscriptionState.unknown,
    this.lastPushMessage,
    this.lastPushUpdatedAt,
    this.recentEvents = const [],
  });

  final ConnectivityStatus connectivityStatus;
  final String? cachedUserId;
  final String? activeUserId;
  final bool hasAuthenticatedSession;
  final bool isInitialLoadRunning;
  final RuntimeSyncPhase syncPhase;
  final RuntimeSyncResult lastSyncResult;
  final String? lastSyncMessage;
  final DateTime? lastSyncStartedAt;
  final DateTime? lastSyncCompletedAt;
  final DateTime? lastSuccessfulSyncAt;
  final String? lastSuccessfulSyncMessage;
  final DateTime? lastSkippedSyncAt;
  final String? lastSkippedSyncMessage;
  final DateTime? lastPartialSyncAt;
  final String? lastPartialSyncMessage;
  final DateTime? lastFailedSyncAt;
  final String? lastFailedSyncMessage;
  final int dirtyTaskCount;
  final int deletedTaskCount;
  final int anonymousTaskCount;
  final PushPermissionState pushPermissionState;
  final PushSubscriptionState pushSubscriptionState;
  final String? lastPushMessage;
  final DateTime? lastPushUpdatedAt;
  final List<RuntimeEvent> recentEvents;

  RuntimeDebugState copyWith({
    ConnectivityStatus? connectivityStatus,
    Object? cachedUserId = _runtimeDebugUnset,
    Object? activeUserId = _runtimeDebugUnset,
    bool? hasAuthenticatedSession,
    bool? isInitialLoadRunning,
    RuntimeSyncPhase? syncPhase,
    RuntimeSyncResult? lastSyncResult,
    Object? lastSyncMessage = _runtimeDebugUnset,
    Object? lastSyncStartedAt = _runtimeDebugUnset,
    Object? lastSyncCompletedAt = _runtimeDebugUnset,
    Object? lastSuccessfulSyncAt = _runtimeDebugUnset,
    Object? lastSuccessfulSyncMessage = _runtimeDebugUnset,
    Object? lastSkippedSyncAt = _runtimeDebugUnset,
    Object? lastSkippedSyncMessage = _runtimeDebugUnset,
    Object? lastPartialSyncAt = _runtimeDebugUnset,
    Object? lastPartialSyncMessage = _runtimeDebugUnset,
    Object? lastFailedSyncAt = _runtimeDebugUnset,
    Object? lastFailedSyncMessage = _runtimeDebugUnset,
    int? dirtyTaskCount,
    int? deletedTaskCount,
    int? anonymousTaskCount,
    PushPermissionState? pushPermissionState,
    PushSubscriptionState? pushSubscriptionState,
    Object? lastPushMessage = _runtimeDebugUnset,
    Object? lastPushUpdatedAt = _runtimeDebugUnset,
    List<RuntimeEvent>? recentEvents,
  }) {
    return RuntimeDebugState(
      connectivityStatus: connectivityStatus ?? this.connectivityStatus,
      cachedUserId: identical(cachedUserId, _runtimeDebugUnset)
          ? this.cachedUserId
          : cachedUserId as String?,
      activeUserId: identical(activeUserId, _runtimeDebugUnset)
          ? this.activeUserId
          : activeUserId as String?,
      hasAuthenticatedSession:
          hasAuthenticatedSession ?? this.hasAuthenticatedSession,
      isInitialLoadRunning: isInitialLoadRunning ?? this.isInitialLoadRunning,
      syncPhase: syncPhase ?? this.syncPhase,
      lastSyncResult: lastSyncResult ?? this.lastSyncResult,
      lastSyncMessage: identical(lastSyncMessage, _runtimeDebugUnset)
          ? this.lastSyncMessage
          : lastSyncMessage as String?,
      lastSyncStartedAt: identical(lastSyncStartedAt, _runtimeDebugUnset)
          ? this.lastSyncStartedAt
          : lastSyncStartedAt as DateTime?,
      lastSyncCompletedAt: identical(lastSyncCompletedAt, _runtimeDebugUnset)
          ? this.lastSyncCompletedAt
          : lastSyncCompletedAt as DateTime?,
      lastSuccessfulSyncAt: identical(lastSuccessfulSyncAt, _runtimeDebugUnset)
          ? this.lastSuccessfulSyncAt
          : lastSuccessfulSyncAt as DateTime?,
      lastSuccessfulSyncMessage:
          identical(lastSuccessfulSyncMessage, _runtimeDebugUnset)
          ? this.lastSuccessfulSyncMessage
          : lastSuccessfulSyncMessage as String?,
      lastSkippedSyncAt: identical(lastSkippedSyncAt, _runtimeDebugUnset)
          ? this.lastSkippedSyncAt
          : lastSkippedSyncAt as DateTime?,
      lastSkippedSyncMessage:
          identical(lastSkippedSyncMessage, _runtimeDebugUnset)
          ? this.lastSkippedSyncMessage
          : lastSkippedSyncMessage as String?,
      lastPartialSyncAt: identical(lastPartialSyncAt, _runtimeDebugUnset)
          ? this.lastPartialSyncAt
          : lastPartialSyncAt as DateTime?,
      lastPartialSyncMessage:
          identical(lastPartialSyncMessage, _runtimeDebugUnset)
          ? this.lastPartialSyncMessage
          : lastPartialSyncMessage as String?,
      lastFailedSyncAt: identical(lastFailedSyncAt, _runtimeDebugUnset)
          ? this.lastFailedSyncAt
          : lastFailedSyncAt as DateTime?,
      lastFailedSyncMessage:
          identical(lastFailedSyncMessage, _runtimeDebugUnset)
          ? this.lastFailedSyncMessage
          : lastFailedSyncMessage as String?,
      dirtyTaskCount: dirtyTaskCount ?? this.dirtyTaskCount,
      deletedTaskCount: deletedTaskCount ?? this.deletedTaskCount,
      anonymousTaskCount: anonymousTaskCount ?? this.anonymousTaskCount,
      pushPermissionState: pushPermissionState ?? this.pushPermissionState,
      pushSubscriptionState:
          pushSubscriptionState ?? this.pushSubscriptionState,
      lastPushMessage: identical(lastPushMessage, _runtimeDebugUnset)
          ? this.lastPushMessage
          : lastPushMessage as String?,
      lastPushUpdatedAt: identical(lastPushUpdatedAt, _runtimeDebugUnset)
          ? this.lastPushUpdatedAt
          : lastPushUpdatedAt as DateTime?,
      recentEvents: recentEvents ?? this.recentEvents,
    );
  }
}

extension ConnectivityStatusExtension on ConnectivityStatus {
  String get label {
    switch (this) {
      case ConnectivityStatus.unknown:
        return 'Unknown';
      case ConnectivityStatus.online:
        return 'Online';
      case ConnectivityStatus.offline:
        return 'Offline';
    }
  }
}

extension RuntimeSyncPhaseExtension on RuntimeSyncPhase {
  String get label {
    switch (this) {
      case RuntimeSyncPhase.idle:
        return 'Idle';
      case RuntimeSyncPhase.initialLoad:
        return 'Initial Load';
      case RuntimeSyncPhase.syncing:
        return 'Syncing';
      case RuntimeSyncPhase.offline:
        return 'Waiting for Network';
      case RuntimeSyncPhase.blockedNoSession:
        return 'Waiting for Session';
      case RuntimeSyncPhase.blockedAnonymousReview:
        return 'Waiting for Local Review';
      case RuntimeSyncPhase.error:
        return 'Error';
    }
  }
}

extension RuntimeSyncResultExtension on RuntimeSyncResult {
  String get label {
    switch (this) {
      case RuntimeSyncResult.none:
        return 'None';
      case RuntimeSyncResult.success:
        return 'Success';
      case RuntimeSyncResult.skipped:
        return 'Skipped';
      case RuntimeSyncResult.partial:
        return 'Partial';
      case RuntimeSyncResult.failed:
        return 'Failed';
    }
  }
}

extension PushPermissionStateExtension on PushPermissionState {
  String get label {
    switch (this) {
      case PushPermissionState.unknown:
        return 'Unknown';
      case PushPermissionState.prompt:
        return 'Prompt';
      case PushPermissionState.granted:
        return 'Granted';
      case PushPermissionState.denied:
        return 'Denied';
      case PushPermissionState.unsupported:
        return 'Unsupported';
      case PushPermissionState.unavailable:
        return 'Unavailable';
    }
  }
}

extension PushSubscriptionStateExtension on PushSubscriptionState {
  String get label {
    switch (this) {
      case PushSubscriptionState.unknown:
        return 'Unknown';
      case PushSubscriptionState.idle:
        return 'Idle';
      case PushSubscriptionState.registering:
        return 'Registering';
      case PushSubscriptionState.registered:
        return 'Registered';
      case PushSubscriptionState.removing:
        return 'Removing';
      case PushSubscriptionState.removed:
        return 'Removed';
      case PushSubscriptionState.failed:
        return 'Failed';
      case PushSubscriptionState.unavailable:
        return 'Unavailable';
    }
  }
}
