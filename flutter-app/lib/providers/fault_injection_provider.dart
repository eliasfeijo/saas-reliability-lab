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

    _state = FaultInjectionState(activeScenario: scenario, isEnabled: true);
    _runtimeDebug?.setActiveFaultInjection(
      label: scenario.label,
      message: scenario.summary,
      instruction: scenario.operatorInstruction,
    );

    if (scenario == FaultInjectionScenario.connectivityLoss) {
      _runtimeDebug?.setConnectivityResults(
        const [ConnectivityResult.none],
        logEvent: false,
        updateObservedCache: false,
      );
    }

    _runtimeDebug?.addEvent(
      category: RuntimeEventCategory.sync,
      message: scenario.activationEventMessage,
      level: RuntimeEventLevel.warning,
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
      message: activeScenario.resetEventMessage,
    );
    notifyListeners();
  }
}
