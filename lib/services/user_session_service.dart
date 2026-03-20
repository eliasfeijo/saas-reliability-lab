import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';

class UserSessionService {
  UserSessionService({RuntimeDebugProvider? runtimeDebug})
    : _runtimeDebug = runtimeDebug;

  final RuntimeDebugProvider? _runtimeDebug;

  Future<String?> loadUserId() async {
    final auth = Supabase.instance.client.auth;
    final user = auth.currentUser;
    final hasAuthenticatedSession =
        auth.currentUser != null && auth.currentSession != null;
    final prefs = await SharedPreferences.getInstance();

    if (user != null) {
      final localId = prefs.getString('userId');
      if (localId != user.id) {
        await prefs.setString('userId', user.id);
      }
      _runtimeDebug?.setUserState(
        cachedUserId: user.id,
        activeUserId: user.id,
        hasAuthenticatedSession: hasAuthenticatedSession,
      );
      return user.id;
    }

    if (prefs.containsKey('userId')) {
      await prefs.remove('userId');
      _runtimeDebug?.addEvent(
        category: RuntimeEventCategory.auth,
        message:
            'Cleared stale cached user id because no active session was found.',
        level: RuntimeEventLevel.warning,
      );
    }

    _runtimeDebug?.setUserState(
      cachedUserId: null,
      activeUserId: null,
      hasAuthenticatedSession: false,
    );

    return null;
  }

  Future<void> saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
    final auth = Supabase.instance.client.auth;
    _runtimeDebug?.setUserState(
      cachedUserId: userId,
      activeUserId: auth.currentUser?.id,
      hasAuthenticatedSession:
          auth.currentUser != null && auth.currentSession != null,
    );
  }

  Future<void> clearUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    final auth = Supabase.instance.client.auth;
    _runtimeDebug?.setUserState(
      cachedUserId: null,
      activeUserId: auth.currentUser?.id,
      hasAuthenticatedSession:
          auth.currentUser != null && auth.currentSession != null,
    );
  }
}
