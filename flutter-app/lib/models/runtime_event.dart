enum RuntimeEventLevel { info, warning, error }

enum RuntimeEventCategory { app, auth, sync, push, connectivity, storage }

class RuntimeEvent {
  const RuntimeEvent({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.detail,
  });

  final DateTime timestamp;
  final RuntimeEventLevel level;
  final RuntimeEventCategory category;
  final String message;
  final String? detail;
}

extension RuntimeEventLevelExtension on RuntimeEventLevel {
  String get label {
    switch (this) {
      case RuntimeEventLevel.info:
        return 'Info';
      case RuntimeEventLevel.warning:
        return 'Warning';
      case RuntimeEventLevel.error:
        return 'Error';
    }
  }
}

extension RuntimeEventCategoryExtension on RuntimeEventCategory {
  String get label {
    switch (this) {
      case RuntimeEventCategory.app:
        return 'App';
      case RuntimeEventCategory.auth:
        return 'Auth';
      case RuntimeEventCategory.sync:
        return 'Sync';
      case RuntimeEventCategory.push:
        return 'Push';
      case RuntimeEventCategory.connectivity:
        return 'Connectivity';
      case RuntimeEventCategory.storage:
        return 'Storage';
    }
  }
}
