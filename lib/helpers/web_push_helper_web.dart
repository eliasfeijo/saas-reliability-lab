import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';

const _pushRegistrationTimeout = Duration(seconds: 5);
const _pushCleanupTimeout = Duration(seconds: 3);

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

@JS('requestPushPermission')
external JSPromise<JSString> _requestPushPermission();

@JS('registerPush')
external JSPromise<PushSubscriptionJSON> _registerPush(JSString vapidPublicKey);

Future<String?> primeWebPushPermission({
  RuntimeDebugProvider? runtimeDebug,
}) async {
  try {
    final permission = await _requestPushPermission().toDart;
    final permissionValue = permission.toDart;
    runtimeDebug?.setPushPermissionFromRaw(
      permissionValue,
      message: 'Push permission is $permissionValue.',
    );
    return permissionValue;
  } catch (e) {
    runtimeDebug?.setPushPermission(
      PushPermissionState.unavailable,
      message: 'Failed to request notification permission.',
    );
    runtimeDebug?.addEvent(
      category: RuntimeEventCategory.push,
      message: 'Failed to request notification permission.',
      detail: e.toString(),
      level: RuntimeEventLevel.error,
    );
    debugPrint('[Push] Failed to request notification permission: $e');
    return null;
  }
}

Future<bool> _waitForAuthenticatedSession({
  RuntimeDebugProvider? runtimeDebug,
}) async {
  final auth = Supabase.instance.client.auth;
  final deadline = DateTime.now().add(_pushRegistrationTimeout);

  while (DateTime.now().isBefore(deadline)) {
    if (auth.currentUser != null && auth.currentSession != null) {
      runtimeDebug?.setUserState(
        cachedUserId: null,
        activeUserId: auth.currentUser?.id,
        hasAuthenticatedSession: true,
      );
      return true;
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  debugPrint(
    '[Push] Skipping registration because auth session is unavailable',
  );
  runtimeDebug?.setPushSubscriptionState(
    PushSubscriptionState.unavailable,
    message: 'Skipping push registration because auth session is unavailable.',
    level: RuntimeEventLevel.warning,
  );
  return false;
}

Future<Map<String, dynamic>?> _registerWebPush(String vapidPublicKey) async {
  try {
    final result = await _registerPush(vapidPublicKey.toJS).toDart;
    return {'endpoint': result.endpoint, 'keys': result.keys?.toMap()};
  } catch (e) {
    debugPrint('Error registering web push: $e');
    return null;
  }
}

Future<void> registerWebPushSubscription({
  RuntimeDebugProvider? runtimeDebug,
}) async {
  runtimeDebug?.setPushSubscriptionState(
    PushSubscriptionState.registering,
    message: 'Registering browser push subscription.',
  );

  if (!await _waitForAuthenticatedSession(runtimeDebug: runtimeDebug)) {
    return;
  }

  const vapidPublicKey = String.fromEnvironment(
    'VAPID_PUBLIC_KEY',
    defaultValue: '<your-vapid-public-key>',
  );

  if (vapidPublicKey.isEmpty || vapidPublicKey == '<your-vapid-public-key>') {
    runtimeDebug?.setPushSubscriptionState(
      PushSubscriptionState.unavailable,
      message:
          'Skipping push registration because the VAPID public key is unset.',
      level: RuntimeEventLevel.warning,
    );
    debugPrint(
      '[Push] Skipping registration because VAPID public key is unset',
    );
    return;
  }

  try {
    final subscription = await _registerWebPush(vapidPublicKey);
    if (subscription == null) {
      runtimeDebug?.setPushSubscriptionState(
        PushSubscriptionState.failed,
        message: 'Browser did not return a push subscription.',
        level: RuntimeEventLevel.error,
      );
      debugPrint('[Push] Browser did not return a push subscription');
      return;
    }

    runtimeDebug?.setPushPermission(
      PushPermissionState.granted,
      message: 'Browser push permission is granted.',
      logEvent: false,
    );

    final supabase = Supabase.instance.client;
    final res = await supabase.functions
        .invoke(
          'save_subscription',
          body: {
            'endpoint': subscription['endpoint'],
            'keys': subscription['keys'],
          },
        )
        .timeout(_pushRegistrationTimeout);

    if (res.status != 200) {
      runtimeDebug?.setPushSubscriptionState(
        PushSubscriptionState.failed,
        message: 'Failed to persist the browser push subscription.',
        level: RuntimeEventLevel.error,
      );
      debugPrint('[Push] Failed to save subscription: ${res.data}');
    } else {
      runtimeDebug?.setPushSubscriptionState(
        PushSubscriptionState.registered,
        message: 'Browser push subscription saved.',
      );
      debugPrint('[Push] Subscription saved!');
    }
  } catch (e) {
    runtimeDebug?.setPushSubscriptionState(
      PushSubscriptionState.failed,
      message: 'Failed to register browser push subscription.',
      level: RuntimeEventLevel.error,
    );
    runtimeDebug?.addEvent(
      category: RuntimeEventCategory.push,
      message: 'Failed to register browser push subscription.',
      detail: e.toString(),
      level: RuntimeEventLevel.error,
    );
    debugPrint('Failed to subscribe: $e');
  }
}

@JS('unregisterPush')
external JSPromise<JSString?> _unregisterPush();

Future<void> unregisterWebPushSubscription({
  RuntimeDebugProvider? runtimeDebug,
}) async {
  runtimeDebug?.setPushSubscriptionState(
    PushSubscriptionState.removing,
    message: 'Removing browser push subscription.',
  );

  try {
    final result = await _unregisterPush().toDart.timeout(_pushCleanupTimeout);
    final endpoint = result?.toDart;
    if (endpoint != null) {
      final res = await Supabase.instance.client.functions
          .invoke('delete_subscription', body: {'endpoint': endpoint})
          .timeout(_pushCleanupTimeout);
      if (res.status == 200) {
        runtimeDebug?.setPushSubscriptionState(
          PushSubscriptionState.removed,
          message: 'Browser push subscription removed from Supabase.',
        );
        debugPrint('[Push] Subscription removed from Supabase');
      } else {
        runtimeDebug?.setPushSubscriptionState(
          PushSubscriptionState.failed,
          message:
              'Failed to remove the browser push subscription from Supabase.',
          level: RuntimeEventLevel.error,
        );
        debugPrint('[Push] Failed to remove from Supabase: ${res.data}');
      }
    } else {
      runtimeDebug?.setPushSubscriptionState(
        PushSubscriptionState.removed,
        message: 'No browser push subscription was registered for cleanup.',
      );
    }
  } catch (e) {
    runtimeDebug?.setPushSubscriptionState(
      PushSubscriptionState.failed,
      message: 'Failed to unregister browser push subscription.',
      level: RuntimeEventLevel.error,
    );
    runtimeDebug?.addEvent(
      category: RuntimeEventCategory.push,
      message: 'Failed to unregister browser push subscription.',
      detail: e.toString(),
      level: RuntimeEventLevel.error,
    );
    debugPrint('[Push] Failed to unregister web push: $e');
  }
}
