import 'package:flutter/foundation.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';

Future<String?> primeWebPushPermission({
  RuntimeDebugProvider? runtimeDebug,
}) async {
  runtimeDebug?.setPushPermission(
    PushPermissionState.unsupported,
    message: 'Push permission is only available in the web runtime.',
  );
  return null;
}

Future<void> registerWebPushSubscription({
  RuntimeDebugProvider? runtimeDebug,
}) async {
  runtimeDebug?.setPushSubscriptionState(
    PushSubscriptionState.unavailable,
    message: 'Browser push registration is only available in the web runtime.',
    level: RuntimeEventLevel.warning,
  );
}

Future<void> unregisterWebPushSubscription({
  RuntimeDebugProvider? runtimeDebug,
}) async {
  runtimeDebug?.setPushSubscriptionState(
    PushSubscriptionState.unavailable,
    message: 'Browser push cleanup is only available in the web runtime.',
    level: RuntimeEventLevel.warning,
  );
  debugPrint('[Push] Skipping browser push cleanup outside the web runtime');
}
