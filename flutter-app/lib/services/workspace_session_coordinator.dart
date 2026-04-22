import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/helpers/web_push_helper.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';
import 'package:todo_flutter/services/user_session_service.dart';

typedef PushRegistrationCallback =
    Future<void> Function({RuntimeDebugProvider? runtimeDebug});
typedef ActiveUserIdResolver = String? Function();
typedef AuthenticatedSessionResolver = bool Function();

class WorkspaceSessionResult {
  const WorkspaceSessionResult({
    this.shouldShowAnonymousTaskReview = false,
    this.shouldClearSearch = false,
  });

  final bool shouldShowAnonymousTaskReview;
  final bool shouldClearSearch;
}

class WorkspaceSessionCoordinator {
  WorkspaceSessionCoordinator(
    this._userSession, {
    PushRegistrationCallback? registerPushSubscription,
    ActiveUserIdResolver? activeUserId,
    AuthenticatedSessionResolver? hasAuthenticatedSession,
  }) : _registerPushSubscription =
           registerPushSubscription ?? registerWebPushSubscription,
       _activeUserId =
           activeUserId ??
           (() => Supabase.instance.client.auth.currentUser?.id),
       _hasAuthenticatedSession =
           hasAuthenticatedSession ??
           (() {
             final auth = Supabase.instance.client.auth;
             return auth.currentUser != null && auth.currentSession != null;
           });

  final UserSessionService _userSession;
  final PushRegistrationCallback _registerPushSubscription;
  final ActiveUserIdResolver _activeUserId;
  final AuthenticatedSessionResolver _hasAuthenticatedSession;
  Future<WorkspaceSessionResult>? _activeInitialization;
  Future<void>? _activePushRegistration;
  String? _activePushRegistrationUserId;

  Future<WorkspaceSessionResult> initialize({
    required AgendaProvider agenda,
    required RuntimeDebugProvider runtimeDebug,
  }) async {
    final inFlightInitialization = _activeInitialization;
    if (inFlightInitialization != null) {
      return inFlightInitialization;
    }

    final initializationFuture = _runInitialize(
      agenda: agenda,
      runtimeDebug: runtimeDebug,
    );
    _activeInitialization = initializationFuture;

    try {
      return await initializationFuture;
    } finally {
      if (identical(_activeInitialization, initializationFuture)) {
        _activeInitialization = null;
      }
    }
  }

  Future<WorkspaceSessionResult> _runInitialize({
    required AgendaProvider agenda,
    required RuntimeDebugProvider runtimeDebug,
  }) async {
    runtimeDebug.startInitialLoad('Loading local session and task snapshot.');

    try {
      agenda.userId = await _userSession.loadUserId();
      await agenda.loadTasks();
      runtimeDebug.finishInitialLoad(
        message: 'Loaded local session and task snapshot.',
      );

      if (_hasAuthenticatedSession() &&
          agenda.userId != null &&
          agenda.userId!.isNotEmpty) {
        return _completeAuthenticatedSetup(
          agenda: agenda,
          runtimeDebug: runtimeDebug,
        );
      }

      return const WorkspaceSessionResult();
    } catch (error) {
      runtimeDebug.failInitialLoad(
        'Failed to initialize the workspace: $error',
      );
      rethrow;
    }
  }

  Future<WorkspaceSessionResult> handleAuthStateChange(
    AuthChangeEvent event, {
    required AgendaProvider agenda,
    required RuntimeDebugProvider runtimeDebug,
  }) async {
    final inFlightInitialization = _activeInitialization;
    if (inFlightInitialization != null) {
      await inFlightInitialization;
    }

    runtimeDebug.setUserState(
      cachedUserId: agenda.userId,
      activeUserId: _activeUserId(),
      hasAuthenticatedSession: _hasAuthenticatedSession(),
      logEvent: true,
      message: 'Auth event: ${event.name}',
    );

    if (event == AuthChangeEvent.signedIn ||
        event == AuthChangeEvent.initialSession) {
      final userId = _activeUserId();
      if (userId == null || userId.isEmpty) {
        return const WorkspaceSessionResult();
      }

      if (agenda.userId == userId) {
        return const WorkspaceSessionResult();
      }

      await _userSession.saveUserId(userId);
      agenda.userId = userId;
      return _completeAuthenticatedSetup(
        agenda: agenda,
        runtimeDebug: runtimeDebug,
      );
    }

    if (event == AuthChangeEvent.signedOut) {
      agenda.clearSelection();
      agenda.clearSearch();
      await _userSession.clearUserId();
      agenda.userId = null;
      await agenda.clearAllTasksFromLocalStorage();
      return const WorkspaceSessionResult(shouldClearSearch: true);
    }

    return const WorkspaceSessionResult();
  }

  Future<WorkspaceSessionResult> _completeAuthenticatedSetup({
    required AgendaProvider agenda,
    required RuntimeDebugProvider runtimeDebug,
  }) async {
    if (agenda.hasPendingAnonymousReview) {
      runtimeDebug.addEvent(
        category: RuntimeEventCategory.storage,
        message:
            'Anonymous local tasks are waiting for review before cloud sync can continue.',
        level: RuntimeEventLevel.warning,
        payload: const RuntimeEventPayload(
          stage: 'Local review required',
          summary:
              'Cloud replay is paused until the operator explicitly keeps or discards anonymous local tasks.',
        ),
      );

      await _registerPushSubscriptionForActiveUser(runtimeDebug: runtimeDebug);
      return const WorkspaceSessionResult(shouldShowAnonymousTaskReview: true);
    }

    await agenda.syncAllTasks();
    await _registerPushSubscriptionForActiveUser(runtimeDebug: runtimeDebug);
    return const WorkspaceSessionResult();
  }

  Future<void> _registerPushSubscriptionForActiveUser({
    required RuntimeDebugProvider runtimeDebug,
  }) async {
    final userId = _activeUserId();
    if (userId == null || userId.isEmpty) {
      return;
    }

    final inFlightRegistration = _activePushRegistration;
    if (inFlightRegistration != null &&
        _activePushRegistrationUserId == userId) {
      await inFlightRegistration;
      return;
    }

    final registrationFuture = _registerPushSubscription(
      runtimeDebug: runtimeDebug,
    );
    _activePushRegistration = registrationFuture;
    _activePushRegistrationUserId = userId;

    try {
      await registrationFuture;
    } finally {
      if (identical(_activePushRegistration, registrationFuture)) {
        _activePushRegistration = null;
        _activePushRegistrationUserId = null;
      }
    }
  }
}
