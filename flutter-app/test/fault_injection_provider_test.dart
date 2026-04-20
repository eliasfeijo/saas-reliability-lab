import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/providers/fault_injection_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';

import 'test_support/app_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityPlatform originalConnectivityPlatform;
  late TestConnectivityPlatform connectivityPlatform;

  setUpAll(() async {
    originalConnectivityPlatform = ConnectivityPlatform.instance;
    connectivityPlatform = TestConnectivityPlatform(
      initialResults: const [ConnectivityResult.wifi],
    );
    ConnectivityPlatform.instance = connectivityPlatform;
  });

  tearDownAll(() async {
    ConnectivityPlatform.instance = originalConnectivityPlatform;
    await connectivityPlatform.dispose();
  });

  setUp(() {
    connectivityPlatform.emit(const [ConnectivityResult.wifi]);
  });

  test(
    'connectivity loss can be activated, cleared, and activated again without losing observed connectivity',
    () async {
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      await Future<void>.delayed(Duration.zero);

      runtimeDebug.setConnectivityResults(const [
        ConnectivityResult.wifi,
      ], logEvent: false);

      final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
      addTearDown(faultInjection.dispose);

      await faultInjection.activateScenario(
        FaultInjectionScenario.connectivityLoss,
      );
      expect(runtimeDebug.state.connectivityStatus, ConnectivityStatus.offline);
      expect(runtimeDebug.state.activeFaultInjectionLabel, 'Connectivity loss');

      await faultInjection.clearScenario();
      expect(runtimeDebug.state.connectivityStatus, ConnectivityStatus.online);
      expect(runtimeDebug.state.activeFaultInjectionLabel, isNull);

      await faultInjection.activateScenario(
        FaultInjectionScenario.connectivityLoss,
      );
      expect(runtimeDebug.state.connectivityStatus, ConnectivityStatus.offline);
      expect(runtimeDebug.state.activeFaultInjectionLabel, 'Connectivity loss');
    },
  );

  test(
    'delayed sync uses a demo-friendly default delay and can be retuned live',
    () async {
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      await Future<void>.delayed(Duration.zero);

      final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
      addTearDown(faultInjection.dispose);

      await faultInjection.activateScenario(FaultInjectionScenario.delayedSync);

      expect(
        faultInjection.state.activeScenario,
        FaultInjectionScenario.delayedSync,
      );
      expect(faultInjection.state.effectiveDelayMs, 5000);
      expect(
        runtimeDebug.state.activeFaultInjectionLabel,
        'Delayed sync (5 s)',
      );

      await faultInjection.setDelayedSyncDuration(10000);

      expect(faultInjection.state.effectiveDelayMs, 10000);
      expect(
        runtimeDebug.state.activeFaultInjectionLabel,
        'Delayed sync (10 s)',
      );
      expect(
        runtimeDebug.state.activeFaultInjectionInstruction,
        contains('10 s'),
      );
    },
  );
}
