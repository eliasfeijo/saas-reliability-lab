import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  final SupabaseClient supabase;

  PushNotificationService(this.supabase);

  Future<void> sendPendingNotifications() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await supabase.functions.invoke(
        'send-push-notifications',
      );
      if (response.status != 200) {
        debugPrint('Failed to send notifications: ${response.toString()}');
        throw Exception(
          'Failed to send notifications: ${response.data!.error}',
        );
      }

      debugPrint('Sent notifications: ${response.data}');
    } catch (e) {
      debugPrint('Error invoking send-push-notifications function: $e');
      throw Exception('Failed to invoke send-push-notifications function');
    }
  }
}
