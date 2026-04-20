import 'package:todo_flutter/models/fault_injection_scenario.dart';

const Object _faultInjectionUnset = Object();
const delayedSyncPresetDurationsMs = <int>[500, 2000, 5000, 10000];

String formatFaultInjectionDuration(int milliseconds) {
  if (milliseconds < 1000) {
    return '$milliseconds ms';
  }

  final seconds = milliseconds / 1000;
  if (seconds == seconds.roundToDouble()) {
    return '${seconds.toInt()} s';
  }

  return '${seconds.toStringAsFixed(1)} s';
}

class FaultInjectionState {
  const FaultInjectionState({
    this.activeScenario = FaultInjectionScenario.none,
    this.isEnabled = false,
    this.delayMs,
    this.triggerStep,
    this.isOneShot = false,
    this.operatorNote,
  });

  final FaultInjectionScenario activeScenario;
  final bool isEnabled;
  final int? delayMs;
  final String? triggerStep;
  final bool isOneShot;
  final String? operatorNote;

  bool get isActive =>
      isEnabled && activeScenario != FaultInjectionScenario.none;

  int? get effectiveDelayMs {
    if (activeScenario == FaultInjectionScenario.delayedSync) {
      return delayMs ?? 5000;
    }

    return delayMs;
  }

  String? get delayLabel => effectiveDelayMs == null
      ? null
      : formatFaultInjectionDuration(effectiveDelayMs!);

  List<int> get availableDelayPresets =>
      activeScenario == FaultInjectionScenario.delayedSync
      ? delayedSyncPresetDurationsMs
      : const <int>[];

  String get activeLabel {
    if (!isActive) {
      return 'None';
    }

    if (activeScenario == FaultInjectionScenario.delayedSync &&
        delayLabel != null) {
      return '${activeScenario.label} ($delayLabel)';
    }

    return activeScenario.label;
  }

  String? get activeSummary {
    if (!isActive) {
      return null;
    }

    if (activeScenario == FaultInjectionScenario.delayedSync &&
        delayLabel != null) {
      return 'Hold the full sync pass for $delayLabel before remote work begins, so viewers can see local changes settle first and then watch cloud convergence happen on a visible timer.';
    }

    return activeScenario.summary;
  }

  String? get operatorInstruction {
    if (!isActive) {
      return null;
    }

    if (activeScenario == FaultInjectionScenario.delayedSync &&
        delayLabel != null) {
      return 'Delayed sync is active with a $delayLabel hold. For a live demo, stay signed in and online, make a small task change that is easy to spot, then run Sync now and keep the Runtime Diagnostics rail visible while Syncing stays active for $delayLabel. Narrate that the product remains responsive locally while remote convergence is intentionally delayed, then wait for the success outcome and timeline entry before resetting the scenario.';
    }

    return activeScenario.operatorInstruction;
  }

  String get activationEventMessage {
    if (activeScenario == FaultInjectionScenario.delayedSync &&
        delayLabel != null) {
      return 'Fault injection activated: delayed sync with a $delayLabel hold before remote replay.';
    }

    return activeScenario.activationEventMessage;
  }

  String get resetEventMessage {
    if (activeScenario == FaultInjectionScenario.delayedSync &&
        delayLabel != null) {
      return 'Fault injection reset: delayed sync ($delayLabel hold) cleared.';
    }

    return activeScenario.resetEventMessage;
  }

  FaultInjectionState copyWith({
    FaultInjectionScenario? activeScenario,
    bool? isEnabled,
    Object? delayMs = _faultInjectionUnset,
    Object? triggerStep = _faultInjectionUnset,
    bool? isOneShot,
    Object? operatorNote = _faultInjectionUnset,
  }) {
    return FaultInjectionState(
      activeScenario: activeScenario ?? this.activeScenario,
      isEnabled: isEnabled ?? this.isEnabled,
      delayMs: identical(delayMs, _faultInjectionUnset)
          ? this.delayMs
          : delayMs as int?,
      triggerStep: identical(triggerStep, _faultInjectionUnset)
          ? this.triggerStep
          : triggerStep as String?,
      isOneShot: isOneShot ?? this.isOneShot,
      operatorNote: identical(operatorNote, _faultInjectionUnset)
          ? this.operatorNote
          : operatorNote as String?,
    );
  }
}
