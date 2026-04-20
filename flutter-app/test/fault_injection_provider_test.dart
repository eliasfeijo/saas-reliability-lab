import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/runtime_debug_state.dart';
import 'package:todo_flutter/providers/fault_injection_provider.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'connectivity loss can be activated, cleared, and activated again without losing observed connectivity',
    () async {
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);

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
}
