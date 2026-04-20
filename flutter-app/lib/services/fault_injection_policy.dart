import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';

class FaultInjectionPolicy {
  FaultInjectionPolicy({FaultInjectionState Function()? readState})
    : _readState = readState;

  final FaultInjectionState Function()? _readState;

  FaultInjectionState get state =>
      _readState?.call() ?? const FaultInjectionState();

  bool get isConnectivityLossActive =>
      state.isActive &&
      state.activeScenario == FaultInjectionScenario.connectivityLoss;

  List<ConnectivityResult> applyConnectivityResults(
    List<ConnectivityResult> actualResults,
  ) {
    if (isConnectivityLossActive) {
      return const [ConnectivityResult.none];
    }

    return actualResults;
  }
}
