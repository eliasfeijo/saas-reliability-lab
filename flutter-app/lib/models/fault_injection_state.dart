import 'package:todo_flutter/models/fault_injection_scenario.dart';

const Object _faultInjectionUnset = Object();
const delayedSyncPresetDurationsMs = <int>[500, 2000, 5000, 10000];

enum DelayedSyncMode { local, transport, backend }

extension DelayedSyncModePresentation on DelayedSyncMode {
  String get label {
    switch (this) {
      case DelayedSyncMode.local:
        return 'Local';
      case DelayedSyncMode.transport:
        return 'Transport';
      case DelayedSyncMode.backend:
        return 'Backend';
    }
  }

  String get summary {
    switch (this) {
      case DelayedSyncMode.local:
        return 'Pause the full replay pass before any remote work begins.';
      case DelayedSyncMode.transport:
        return 'Pause a named outbound remote seam so replay stays visibly in flight longer.';
      case DelayedSyncMode.backend:
        return 'Pause acknowledgement after a remote mutation succeeds so the outbox stays in sending longer.';
    }
  }
}

enum DelayedSyncTarget {
  fullPass,
  fetchById,
  insert,
  update,
  deleteOperation,
  fetchAllMerge,
  acknowledgement,
}

extension DelayedSyncTargetPresentation on DelayedSyncTarget {
  String get label {
    switch (this) {
      case DelayedSyncTarget.fullPass:
        return 'Full pass';
      case DelayedSyncTarget.fetchById:
        return 'Fetch by id';
      case DelayedSyncTarget.insert:
        return 'Insert';
      case DelayedSyncTarget.update:
        return 'Update';
      case DelayedSyncTarget.deleteOperation:
        return 'Delete';
      case DelayedSyncTarget.fetchAllMerge:
        return 'Fetch-all merge';
      case DelayedSyncTarget.acknowledgement:
        return 'Acknowledgement';
    }
  }
}

enum DelayedSyncBehavior { persistent, oneShot }

extension DelayedSyncBehaviorPresentation on DelayedSyncBehavior {
  String get label {
    switch (this) {
      case DelayedSyncBehavior.persistent:
        return 'Persistent';
      case DelayedSyncBehavior.oneShot:
        return 'One-shot';
    }
  }

  String get summary {
    switch (this) {
      case DelayedSyncBehavior.persistent:
        return 'Apply this delay every time the selected seam is reached while the scenario stays active.';
      case DelayedSyncBehavior.oneShot:
        return 'Apply this delay once, then clear the scenario automatically.';
    }
  }
}

List<DelayedSyncTarget> delayedSyncTargetsForMode(DelayedSyncMode mode) {
  switch (mode) {
    case DelayedSyncMode.local:
      return const [DelayedSyncTarget.fullPass];
    case DelayedSyncMode.transport:
      return const [
        DelayedSyncTarget.fetchById,
        DelayedSyncTarget.insert,
        DelayedSyncTarget.update,
        DelayedSyncTarget.deleteOperation,
        DelayedSyncTarget.fetchAllMerge,
      ];
    case DelayedSyncMode.backend:
      return const [DelayedSyncTarget.acknowledgement];
  }
}

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
    this.delayedSyncMode = DelayedSyncMode.local,
    this.delayedSyncTarget = DelayedSyncTarget.fullPass,
    this.delayedSyncBehavior = DelayedSyncBehavior.persistent,
  });

  final FaultInjectionScenario activeScenario;
  final bool isEnabled;
  final int? delayMs;
  final DelayedSyncMode delayedSyncMode;
  final DelayedSyncTarget delayedSyncTarget;
  final DelayedSyncBehavior delayedSyncBehavior;

  bool get isActive =>
      isEnabled && activeScenario != FaultInjectionScenario.none;

  bool get isDelayedSyncActive =>
      isActive && activeScenario == FaultInjectionScenario.delayedSync;

  int? get effectiveDelayMs {
    if (isDelayedSyncActive) {
      return delayMs ?? 5000;
    }

    return delayMs;
  }

  DelayedSyncMode get effectiveDelayedSyncMode =>
      isDelayedSyncActive ? delayedSyncMode : DelayedSyncMode.local;

  DelayedSyncBehavior get effectiveDelayedSyncBehavior => isDelayedSyncActive
      ? delayedSyncBehavior
      : DelayedSyncBehavior.persistent;

  DelayedSyncTarget get effectiveDelayedSyncTarget {
    if (!isDelayedSyncActive) {
      return DelayedSyncTarget.fullPass;
    }

    final availableTargets = delayedSyncTargetsForMode(
      effectiveDelayedSyncMode,
    );
    if (availableTargets.contains(delayedSyncTarget)) {
      return delayedSyncTarget;
    }

    return availableTargets.first;
  }

  String? get delayLabel => effectiveDelayMs == null
      ? null
      : formatFaultInjectionDuration(effectiveDelayMs!);

  List<int> get availableDelayPresets =>
      isDelayedSyncActive ? delayedSyncPresetDurationsMs : const <int>[];

  List<DelayedSyncTarget> get availableDelayedSyncTargets =>
      delayedSyncTargetsForMode(effectiveDelayedSyncMode);

  String? get delayedSyncConfigurationLabel {
    if (!isDelayedSyncActive || delayLabel == null) {
      return null;
    }

    return '${effectiveDelayedSyncMode.label} ${effectiveDelayedSyncTarget.label.toLowerCase()} · ${effectiveDelayedSyncBehavior.label.toLowerCase()} · $delayLabel';
  }

  String get activeLabel {
    if (!isActive) {
      return 'None';
    }

    if (isDelayedSyncActive && delayLabel != null) {
      return '${activeScenario.label} ($delayLabel)';
    }

    return activeScenario.label;
  }

  String? get activeSummary {
    if (!isActive) {
      return null;
    }

    if (isDelayedSyncActive && delayLabel != null) {
      switch (effectiveDelayedSyncMode) {
        case DelayedSyncMode.local:
          return 'Hold the full sync pass for $delayLabel before remote work begins so viewers can watch local state settle first and then observe delayed cloud convergence.';
        case DelayedSyncMode.transport:
          return 'Hold the ${effectiveDelayedSyncTarget.label.toLowerCase()} transport seam for $delayLabel so replay stays visibly in flight at a real outbound boundary.';
        case DelayedSyncMode.backend:
          return 'Hold acknowledgement for $delayLabel after remote success so the outbox stays in sending and the lab can demonstrate slow backend confirmation honestly at the client-owned seam.';
      }
    }

    return activeScenario.summary;
  }

  String? get operatorInstruction {
    if (!isActive) {
      return null;
    }

    if (isDelayedSyncActive && delayLabel != null) {
      final behaviorInstruction =
          effectiveDelayedSyncBehavior == DelayedSyncBehavior.oneShot
          ? 'The scenario will clear itself after the first delayed seam is exercised.'
          : 'The scenario will keep applying this delay until you clear it.';
      switch (effectiveDelayedSyncMode) {
        case DelayedSyncMode.local:
          return 'Delayed sync is active with a $delayLabel local hold. Stay signed in and online, make a small task change, then run Sync now while keeping Runtime Diagnostics visible. The full replay pass will pause before any remote work begins. $behaviorInstruction';
        case DelayedSyncMode.transport:
          return 'Delayed sync is active with a $delayLabel transport hold at ${effectiveDelayedSyncTarget.label.toLowerCase()}. Run Sync now and keep the diagnostics rail open so viewers can see replay remain active at that outbound seam. $behaviorInstruction';
        case DelayedSyncMode.backend:
          return 'Delayed sync is active with a $delayLabel backend-shaped acknowledgement hold. Run Sync now and keep the diagnostics rail open so viewers can see the outbox stay in sending after remote success. $behaviorInstruction';
      }
    }

    return activeScenario.operatorInstruction;
  }

  String get activationEventMessage {
    if (isDelayedSyncActive && delayLabel != null) {
      return 'Fault injection activated: delayed sync with a $delayLabel ${effectiveDelayedSyncMode.label.toLowerCase()} hold at ${effectiveDelayedSyncTarget.label.toLowerCase()} (${effectiveDelayedSyncBehavior.label.toLowerCase()}).';
    }

    return activeScenario.activationEventMessage;
  }

  String get resetEventMessage {
    if (isDelayedSyncActive && delayLabel != null) {
      return 'Fault injection reset: delayed sync ($delayLabel ${effectiveDelayedSyncMode.label.toLowerCase()} hold) cleared.';
    }

    return activeScenario.resetEventMessage;
  }

  FaultInjectionState copyWith({
    FaultInjectionScenario? activeScenario,
    bool? isEnabled,
    Object? delayMs = _faultInjectionUnset,
    DelayedSyncMode? delayedSyncMode,
    DelayedSyncTarget? delayedSyncTarget,
    DelayedSyncBehavior? delayedSyncBehavior,
  }) {
    return FaultInjectionState(
      activeScenario: activeScenario ?? this.activeScenario,
      isEnabled: isEnabled ?? this.isEnabled,
      delayMs: identical(delayMs, _faultInjectionUnset)
          ? this.delayMs
          : delayMs as int?,
      delayedSyncMode: delayedSyncMode ?? this.delayedSyncMode,
      delayedSyncTarget: delayedSyncTarget ?? this.delayedSyncTarget,
      delayedSyncBehavior: delayedSyncBehavior ?? this.delayedSyncBehavior,
    );
  }
}
