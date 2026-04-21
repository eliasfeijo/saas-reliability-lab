import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';

class DelayedSyncInjection {
  const DelayedSyncInjection({
    required this.duration,
    required this.durationLabel,
    required this.mode,
    required this.target,
    required this.behavior,
  });

  final Duration duration;
  final String durationLabel;
  final DelayedSyncMode mode;
  final DelayedSyncTarget target;
  final DelayedSyncBehavior behavior;
}

class FaultInjectionPolicy {
  FaultInjectionPolicy({
    FaultInjectionState Function()? readState,
    Future<void> Function(DelayedSyncTarget target)? consumeDelayedSync,
  }) : _readState = readState,
       _consumeDelayedSync = consumeDelayedSync;

  final FaultInjectionState Function()? _readState;
  final Future<void> Function(DelayedSyncTarget target)? _consumeDelayedSync;

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

  DelayedSyncInjection? injectionFor(DelayedSyncTarget target) {
    if (!isDelayedSyncActive ||
        delayedSyncDuration == null ||
        delayedSyncDurationLabel == null ||
        state.effectiveDelayedSyncTarget != target) {
      return null;
    }

    return DelayedSyncInjection(
      duration: delayedSyncDuration!,
      durationLabel: delayedSyncDurationLabel!,
      mode: state.effectiveDelayedSyncMode,
      target: state.effectiveDelayedSyncTarget,
      behavior: state.effectiveDelayedSyncBehavior,
    );
  }

  String? get plannedDelayDescription {
    final injection = injectionFor(state.effectiveDelayedSyncTarget);
    if (injection == null) {
      return null;
    }

    final targetLabel = injection.target.label.toLowerCase();
    final modeLabel = injection.mode.label.toLowerCase();
    if (injection.mode == DelayedSyncMode.local) {
      return 'Holding the full replay pass for ${injection.durationLabel} before remote work begins.';
    }

    return 'A ${injection.durationLabel} $modeLabel delay will be applied at $targetLabel during this sync pass.';
  }

  Future<void> consumeDelayedSyncIfNeeded(DelayedSyncTarget target) async {
    final injection = injectionFor(target);
    if (injection == null ||
        injection.behavior != DelayedSyncBehavior.oneShot ||
        _consumeDelayedSync == null) {
      return;
    }

    await _consumeDelayedSync(target);
  }

  List<ConnectivityResult> applyConnectivityResults(
    List<ConnectivityResult> actualResults,
  ) {
    if (isConnectivityLossActive) {
      return const [ConnectivityResult.none];
    }

    return actualResults;
  }
}
