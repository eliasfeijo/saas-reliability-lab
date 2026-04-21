import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';
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
    'delayed sync uses a demo-friendly default delay and can be reconfigured live',
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
      expect(
        faultInjection.state.effectiveDelayedSyncMode,
        DelayedSyncMode.local,
      );
      expect(
        faultInjection.state.effectiveDelayedSyncTarget,
        DelayedSyncTarget.fullPass,
      );
      expect(
        faultInjection.state.effectiveDelayedSyncBehavior,
        DelayedSyncBehavior.persistent,
      );

      await faultInjection.configureDelayedSync(
        delayMs: 10000,
        mode: DelayedSyncMode.transport,
        target: DelayedSyncTarget.update,
        behavior: DelayedSyncBehavior.oneShot,
      );

      expect(faultInjection.state.effectiveDelayMs, 10000);
      expect(
        faultInjection.state.effectiveDelayedSyncMode,
        DelayedSyncMode.transport,
      );
      expect(
        faultInjection.state.effectiveDelayedSyncTarget,
        DelayedSyncTarget.update,
      );
      expect(
        faultInjection.state.effectiveDelayedSyncBehavior,
        DelayedSyncBehavior.oneShot,
      );
      expect(
        runtimeDebug.state.activeFaultInjectionLabel,
        'Delayed sync (10 s)',
      );
      expect(
        runtimeDebug.state.activeFaultInjectionInstruction,
        allOf(contains('10 s'), contains('transport hold at update')),
      );
    },
  );

  test(
    'one-shot delayed sync clears itself after the configured seam is consumed',
    () async {
      final runtimeDebug = RuntimeDebugProvider();
      addTearDown(runtimeDebug.dispose);
      await Future<void>.delayed(Duration.zero);

      final faultInjection = FaultInjectionProvider(runtimeDebug: runtimeDebug);
      addTearDown(faultInjection.dispose);

      await faultInjection.activateScenario(
        FaultInjectionScenario.delayedSync,
        delayMs: 2000,
        delayedSyncMode: DelayedSyncMode.transport,
        delayedSyncTarget: DelayedSyncTarget.insert,
        delayedSyncBehavior: DelayedSyncBehavior.oneShot,
      );

      await faultInjection.consumeDelayedSyncIfNeeded(
        appliedTarget: DelayedSyncTarget.insert,
      );

      expect(faultInjection.state.isActive, isFalse);
      expect(runtimeDebug.state.activeFaultInjectionLabel, isNull);
      expect(
        runtimeDebug.state.recentEvents.first.message,
        'Fault injection consumed: one-shot delayed sync cleared after insert.',
      );
    },
  );
}
