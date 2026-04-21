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

  Future<void> activateScenario(
    FaultInjectionScenario scenario, {
    int? delayMs,
    DelayedSyncMode delayedSyncMode = DelayedSyncMode.local,
    DelayedSyncTarget? delayedSyncTarget,
    DelayedSyncBehavior delayedSyncBehavior = DelayedSyncBehavior.persistent,
  }) async {
    if (!scenario.isImplemented) {
      return;
    }

    final nextTarget =
        delayedSyncTarget ?? delayedSyncTargetsForMode(delayedSyncMode).first;
    final nextState = FaultInjectionState(
      activeScenario: scenario,
      isEnabled: true,
      delayMs: scenario == FaultInjectionScenario.delayedSync
          ? delayMs ?? 5000
          : null,
      delayedSyncMode: scenario == FaultInjectionScenario.delayedSync
          ? delayedSyncMode
          : DelayedSyncMode.local,
      delayedSyncTarget: scenario == FaultInjectionScenario.delayedSync
          ? nextTarget
          : DelayedSyncTarget.fullPass,
      delayedSyncBehavior: scenario == FaultInjectionScenario.delayedSync
          ? delayedSyncBehavior
          : DelayedSyncBehavior.persistent,
    );

    if (_state == nextState) {
      return;
    }

    _state = nextState;
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
          if (_state.isDelayedSyncActive)
            RuntimeEventMetric(
              label: 'Mode',
              value: _state.effectiveDelayedSyncMode.label,
            ),
          if (_state.isDelayedSyncActive)
            RuntimeEventMetric(
              label: 'Target',
              value: _state.effectiveDelayedSyncTarget.label,
            ),
          if (_state.isDelayedSyncActive)
            RuntimeEventMetric(
              label: 'Behavior',
              value: _state.effectiveDelayedSyncBehavior.label,
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

  Future<void> configureDelayedSync({
    required int delayMs,
    required DelayedSyncMode mode,
    required DelayedSyncTarget target,
    required DelayedSyncBehavior behavior,
  }) async {
    if (!_state.isDelayedSyncActive) {
      return;
    }

    final normalizedTarget = delayedSyncTargetsForMode(mode).contains(target)
        ? target
        : delayedSyncTargetsForMode(mode).first;
    final nextState = _state.copyWith(
      delayMs: delayMs,
      delayedSyncMode: mode,
      delayedSyncTarget: normalizedTarget,
      delayedSyncBehavior: behavior,
    );
    if (_state == nextState) {
      return;
    }

    _state = nextState;
    _publishRuntimeState();
    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.sync,
      message:
          'Fault injection updated: delayed sync now holds ${_state.effectiveDelayedSyncTarget.label.toLowerCase()} in ${_state.effectiveDelayedSyncMode.label.toLowerCase()} mode for ${_state.delayLabel}.',
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
          RuntimeEventMetric(
            label: 'Mode',
            value: _state.effectiveDelayedSyncMode.label,
          ),
          RuntimeEventMetric(
            label: 'Target',
            value: _state.effectiveDelayedSyncTarget.label,
          ),
          RuntimeEventMetric(
            label: 'Behavior',
            value: _state.effectiveDelayedSyncBehavior.label,
          ),
        ],
      ),
    );
    notifyListeners();
  }

  Future<void> setDelayedSyncDuration(int delayMs) async {
    if (!_state.isDelayedSyncActive) {
      return;
    }

    await configureDelayedSync(
      delayMs: delayMs,
      mode: _state.effectiveDelayedSyncMode,
      target: _state.effectiveDelayedSyncTarget,
      behavior: _state.effectiveDelayedSyncBehavior,
    );
  }

  Future<void> consumeDelayedSyncIfNeeded({
    required DelayedSyncTarget appliedTarget,
  }) async {
    if (!_state.isDelayedSyncActive ||
        _state.effectiveDelayedSyncBehavior != DelayedSyncBehavior.oneShot ||
        _state.effectiveDelayedSyncTarget != appliedTarget) {
      return;
    }

    final consumedState = _state;
    _state = const FaultInjectionState();
    _runtimeDebug?.clearActiveFaultInjection();
    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.sync,
      message:
          'Fault injection consumed: one-shot delayed sync cleared after ${appliedTarget.label.toLowerCase()}.',
      payload: RuntimeEventPayload(
        stage: 'Fault injection consumed',
        summary:
            'The one-shot delayed-sync scenario applied once and then cleared itself automatically.',
        metrics: [
          RuntimeEventMetric(
            label: 'Scenario',
            value: consumedState.activeLabel,
          ),
          RuntimeEventMetric(
            label: 'Mode',
            value: consumedState.effectiveDelayedSyncMode.label,
          ),
          RuntimeEventMetric(label: 'Target', value: appliedTarget.label),
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
