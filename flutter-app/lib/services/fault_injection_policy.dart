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

  bool get isDelayedSyncActive =>
      state.isActive &&
      state.activeScenario == FaultInjectionScenario.delayedSync;

  Duration? get delayedSyncDuration =>
      isDelayedSyncActive && state.effectiveDelayMs != null
      ? Duration(milliseconds: state.effectiveDelayMs!)
      : null;

  String? get delayedSyncDurationLabel =>
      delayedSyncDuration == null || state.effectiveDelayMs == null
      ? null
      : formatFaultInjectionDuration(state.effectiveDelayMs!);

  List<ConnectivityResult> applyConnectivityResults(
    List<ConnectivityResult> actualResults,
  ) {
    if (isConnectivityLossActive) {
      return const [ConnectivityResult.none];
    }

    return actualResults;
  }
}
