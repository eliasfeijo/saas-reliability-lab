enum FaultInjectionScenario {
  none,
  connectivityLoss,
  delayedSync,
  expiredAuth,
  partialReplayDrop,
  duplicateReplay,
  conflictUpdateUpdate,
}

const implementedFaultInjectionScenarios = <FaultInjectionScenario>[
  FaultInjectionScenario.connectivityLoss,
  FaultInjectionScenario.delayedSync,
];

extension FaultInjectionScenarioPresentation on FaultInjectionScenario {
  bool get isImplemented => implementedFaultInjectionScenarios.contains(this);

  String get label {
    switch (this) {
      case FaultInjectionScenario.none:
        return 'None';
      case FaultInjectionScenario.connectivityLoss:
        return 'Connectivity loss';
      case FaultInjectionScenario.delayedSync:
        return 'Delayed sync';
      case FaultInjectionScenario.expiredAuth:
        return 'Expired auth';
      case FaultInjectionScenario.partialReplayDrop:
        return 'Partial replay drop';
      case FaultInjectionScenario.duplicateReplay:
        return 'Duplicate replay';
      case FaultInjectionScenario.conflictUpdateUpdate:
        return 'Update/update conflict';
    }
  }

  String get summary {
    switch (this) {
      case FaultInjectionScenario.none:
        return 'No controlled failure scenario is active.';
      case FaultInjectionScenario.connectivityLoss:
        return 'Force the sync boundary to behave as if the app has no network connectivity.';
      case FaultInjectionScenario.delayedSync:
        return 'Delay the sync pass so local changes take longer to converge remotely.';
      case FaultInjectionScenario.expiredAuth:
        return 'Simulate session unavailability around sync.';
      case FaultInjectionScenario.partialReplayDrop:
        return 'Interrupt sync after work has already begun.';
      case FaultInjectionScenario.duplicateReplay:
        return 'Replay the same logical operation more than once.';
      case FaultInjectionScenario.conflictUpdateUpdate:
        return 'Capture divergent local and remote updates explicitly.';
    }
  }

  String get operatorInstruction {
    switch (this) {
      case FaultInjectionScenario.none:
        return 'Select a scenario from the operator rail to begin a controlled experiment.';
      case FaultInjectionScenario.connectivityLoss:
        return 'Connectivity loss is active. Leave the browser online, then run Sync now. The lab will force the sync boundary offline, record a skipped sync outcome, and show Waiting for Network in diagnostics. Reset the scenario to restore live connectivity behavior.';
      case FaultInjectionScenario.delayedSync:
        return 'Delay the full sync pass so local state changes immediately while remote convergence stays intentionally behind.';
      case FaultInjectionScenario.expiredAuth:
        return 'Expired auth is planned but not implemented yet.';
      case FaultInjectionScenario.partialReplayDrop:
        return 'Partial replay drop is planned but not implemented yet.';
      case FaultInjectionScenario.duplicateReplay:
        return 'Duplicate replay depends on the future outbox and backend idempotency contract.';
      case FaultInjectionScenario.conflictUpdateUpdate:
        return 'Update/update conflict depends on explicit outbox and conflict semantics.';
    }
  }

  String get activationEventMessage {
    switch (this) {
      case FaultInjectionScenario.none:
        return 'Fault injection cleared.';
      case FaultInjectionScenario.connectivityLoss:
        return 'Fault injection activated: connectivity loss. Run Sync now to observe a forced offline sync boundary.';
      case FaultInjectionScenario.delayedSync:
        return 'Fault injection activated: delayed sync. Run Sync now to observe a controlled hold before remote replay begins.';
      case FaultInjectionScenario.expiredAuth:
        return 'Fault injection activated: expired auth.';
      case FaultInjectionScenario.partialReplayDrop:
        return 'Fault injection activated: partial replay drop.';
      case FaultInjectionScenario.duplicateReplay:
        return 'Fault injection activated: duplicate replay.';
      case FaultInjectionScenario.conflictUpdateUpdate:
        return 'Fault injection activated: update/update conflict.';
    }
  }

  String get resetEventMessage {
    switch (this) {
      case FaultInjectionScenario.none:
        return 'Fault injection reset.';
      case FaultInjectionScenario.connectivityLoss:
        return 'Fault injection reset: connectivity loss is no longer forcing the sync boundary offline.';
      case FaultInjectionScenario.delayedSync:
        return 'Fault injection reset: delayed sync cleared.';
      case FaultInjectionScenario.expiredAuth:
        return 'Fault injection reset: expired auth cleared.';
      case FaultInjectionScenario.partialReplayDrop:
        return 'Fault injection reset: partial replay drop cleared.';
      case FaultInjectionScenario.duplicateReplay:
        return 'Fault injection reset: duplicate replay cleared.';
      case FaultInjectionScenario.conflictUpdateUpdate:
        return 'Fault injection reset: update/update conflict cleared.';
    }
  }
}
