import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// This file is used to register web push notifications in a Flutter web application.

extension type PushSubscriptionKeys._(JSObject _) implements JSObject {
  external PushSubscriptionKeys();

  external String? get p256dh;
  external String? get auth;

  Map<String, String> toMap() {
    return {'p256dh': p256dh ?? '', 'auth': auth ?? ''};
  }
}

extension type PushSubscriptionJSON._(JSObject _) implements JSObject {
  external PushSubscriptionJSON();

  external String? get endpoint;
  external PushSubscriptionKeys? get keys;
}

@JS('registerPush')
external JSPromise<PushSubscriptionJSON> _registerPush(JSString vapidPublicKey);

Future<Map<String, dynamic>?> _registerWebPush(String vapidPublicKey) async {
  try {
    final result = await _registerPush(vapidPublicKey.toJS).toDart;
    return {'endpoint': result.endpoint, 'keys': result.keys?.toMap()};
  } catch (e) {
    debugPrint('Error registering web push: $e');
    return null;
  }
}

Future<void> registerWebPushSubscription() async {
  const vapidPublicKey = String.fromEnvironment(
    'VAPID_PUBLIC_KEY',
    defaultValue: "<your-vapid-public-key>",
  );

  debugPrint('VAPID Public Key: $vapidPublicKey');

  try {
    final subscription = await _registerWebPush(vapidPublicKey);
    if (subscription != null) {
      final supabase = Supabase.instance.client;
      final res = await supabase.functions.invoke(
        'save_subscription',
        body: {
          'endpoint': subscription['endpoint'],
          'keys': subscription['keys'],
        },
      );

      if (res.status != 200) {
        debugPrint('[Push] Failed to save subscription: ${res.data}');
      } else {
        debugPrint('[Push] Subscription saved!');
      }
    }
  } catch (e) {
    debugPrint('Failed to subscribe: $e');
  }
}
