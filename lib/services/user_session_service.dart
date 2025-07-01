import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserSessionService {
  Future<String?> loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final localId = prefs.getString('userId');
    final user = Supabase.instance.client.auth.currentUser;
    return user?.id ?? localId;
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
