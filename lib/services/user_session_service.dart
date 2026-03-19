import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserSessionService {
  Future<String?> loadUserId() async {
    final user = Supabase.instance.client.auth.currentUser;
    final prefs = await SharedPreferences.getInstance();

    if (user != null) {
      final localId = prefs.getString('userId');
      if (localId != user.id) {
        await prefs.setString('userId', user.id);
      }
      return user.id;
    }

    if (prefs.containsKey('userId')) {
      await prefs.remove('userId');
    }

    return null;
  }

  Future<void> saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
  }

  Future<void> clearUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
  }
}
