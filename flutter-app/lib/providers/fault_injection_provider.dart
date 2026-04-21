import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:todo_flutter/models/fault_injection_scenario.dart';
import 'package:todo_flutter/models/fault_injection_state.dart';
import 'package:todo_flutter/models/runtime_event.dart';
import 'package:todo_flutter/providers/runtime_debug_provider.dart';

class FaultInjectionProvider extends ChangeNotifier {
  FaultInjectionProvider({RuntimeDebugProvider? runtimeDebug})
    : _runtimeDebug = runtimeDebug;

  final RuntimeDebugProvider? _runtimeDebug;

  FaultInjectionState _state = const FaultInjectionState();

  FaultInjectionState get state => _state;

  List<FaultInjectionScenario> get availableScenarios =>
      implementedFaultInjectionScenarios;

  Future<void> activateScenario(FaultInjectionScenario scenario) async {
    if (!scenario.isImplemented) {
      return;
    }

    if (_state.isActive && _state.activeScenario == scenario) {
      return;
    }

    _state = FaultInjectionState(
      activeScenario: scenario,
      isEnabled: true,
      delayMs: scenario == FaultInjectionScenario.delayedSync ? 5000 : null,
    );
    _publishRuntimeState();

    if (scenario == FaultInjectionScenario.connectivityLoss) {
      _runtimeDebug?.setConnectivityResults(
        const [ConnectivityResult.none],
        logEvent: false,
        updateObservedCache: false,
      );
    }

    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.sync,
      message: _state.activationEventMessage,
      level: RuntimeEventLevel.warning,
      payload: RuntimeEventPayload(
        stage: 'Fault injection active',
        summary:
            'A controlled scenario is now influencing the sync runtime so operators can observe deterministic evidence.',
        metrics: [
          RuntimeEventMetric(label: 'Scenario', value: _state.activeLabel),
          if (_state.delayLabel != null)
            RuntimeEventMetric(
              label: 'Injected delay',
              value: _state.delayLabel!,
            ),
        ],
        notes: [
          if (_state.activeSummary != null) _state.activeSummary!,
          if (_state.operatorInstruction != null) _state.operatorInstruction!,
        ],
      ),
    );
    notifyListeners();
  }

  Future<void> setDelayedSyncDuration(int delayMs) async {
    if (!_state.isActive ||
        _state.activeScenario != FaultInjectionScenario.delayedSync ||
        _state.effectiveDelayMs == delayMs) {
      return;
    }

    _state = _state.copyWith(delayMs: delayMs);
    _publishRuntimeState();
    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.sync,
      message:
          'Fault injection updated: delayed sync now holds the sync pass for ${_state.delayLabel}.',
      payload: RuntimeEventPayload(
        stage: 'Fault injection updated',
        summary:
            'The delayed-sync scenario was reconfigured without leaving the current operator flow.',
        metrics: [
          RuntimeEventMetric(label: 'Scenario', value: _state.activeLabel),
          if (_state.delayLabel != null)
            RuntimeEventMetric(
              label: 'Injected delay',
              value: _state.delayLabel!,
            ),
        ],
      ),
    );
    notifyListeners();
  }

  Future<void> clearScenario() async {
    if (!_state.isActive) {
      return;
    }

    final activeScenario = _state.activeScenario;
    _state = const FaultInjectionState();
    _runtimeDebug?.clearActiveFaultInjection();

    if (activeScenario == FaultInjectionScenario.connectivityLoss) {
      _runtimeDebug?.restoreObservedConnectivity();
    }

    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.sync,
      message: _state
          .copyWith(activeScenario: activeScenario, isEnabled: true)
          .resetEventMessage,
      payload: RuntimeEventPayload(
        stage: 'Fault injection cleared',
        summary:
            'The controlled scenario has been removed and the sync runtime is returning to live behavior.',
        metrics: [
          RuntimeEventMetric(label: 'Scenario', value: activeScenario.label),
        ],
      ),
    );
    notifyListeners();
  }

  void _publishRuntimeState() {
    if (!_state.isActive) {
      _runtimeDebug?.clearActiveFaultInjection();
      return;
    }

    _runtimeDebug?.setActiveFaultInjection(
      label: _state.activeLabel,
      message: _state.activeSummary ?? _state.activeScenario.summary,
      instruction:
          _state.operatorInstruction ??
          _state.activeScenario.operatorInstruction,
    );
  }
}
