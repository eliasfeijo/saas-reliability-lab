import 'package:todo_flutter/models/fault_injection_scenario.dart';

const Object _faultInjectionUnset = Object();

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

  String get activeLabel => isActive ? activeScenario.label : 'None';

  String? get activeSummary => isActive ? activeScenario.summary : null;

  String? get operatorInstruction =>
      isActive ? activeScenario.operatorInstruction : null;

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
