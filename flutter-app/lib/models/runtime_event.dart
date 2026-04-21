enum RuntimeEventLevel { info, warning, error }

enum RuntimeEventCategory { app, auth, sync, push, connectivity, storage }

class RuntimeEventMetric {
  const RuntimeEventMetric({required this.label, required this.value});

  final String label;
  final String value;

  bool get hasContent => label.trim().isNotEmpty || value.trim().isNotEmpty;
}

class RuntimeEventFieldDiff {
  const RuntimeEventFieldDiff({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final String before;
  final String after;

  bool get hasContent =>
      label.trim().isNotEmpty ||
      before.trim().isNotEmpty ||
      after.trim().isNotEmpty;
}

class RuntimeEventTaskDetail {
  const RuntimeEventTaskDetail({
    required this.title,
    this.taskId,
    this.syncStatus,
    this.outcome,
    this.description,
    this.tags = const [],
    this.fieldDiffs = const [],
  });

  final String title;
  final String? taskId;
  final String? syncStatus;
  final String? outcome;
  final String? description;
  final List<String> tags;
  final List<RuntimeEventFieldDiff> fieldDiffs;

  List<String> get visibleTags =>
      tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList();

  List<RuntimeEventFieldDiff> get visibleFieldDiffs =>
      fieldDiffs.where((field) => field.hasContent).toList();

  bool get hasContent =>
      (taskId != null && taskId!.isNotEmpty) ||
      (syncStatus != null && syncStatus!.isNotEmpty) ||
      (outcome != null && outcome!.isNotEmpty) ||
      (description != null && description!.isNotEmpty) ||
      visibleTags.isNotEmpty ||
      visibleFieldDiffs.isNotEmpty;
}

class RuntimeEventPayload {
  const RuntimeEventPayload({
    this.stage,
    this.summary,
    this.metrics = const [],
    this.tasks = const [],
    this.notes = const [],
  });

  final String? stage;
  final String? summary;
  final List<RuntimeEventMetric> metrics;
  final List<RuntimeEventTaskDetail> tasks;
  final List<String> notes;

  List<RuntimeEventMetric> get visibleMetrics =>
      metrics.where((metric) => metric.hasContent).toList();

  List<RuntimeEventTaskDetail> get visibleTasks =>
      tasks.where((task) => task.hasContent).toList();

  List<String> get visibleNotes => notes
      .map((note) => note.trim())
      .where((note) => note.isNotEmpty)
      .toList();

  bool get hasContent =>
      (stage != null && stage!.isNotEmpty) ||
      (summary != null && summary!.isNotEmpty) ||
      visibleMetrics.isNotEmpty ||
      visibleTasks.isNotEmpty ||
      visibleNotes.isNotEmpty;
}

class RuntimeEvent {
  const RuntimeEvent({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.detail,
    this.payload,
  });

  final String id;
  final DateTime timestamp;
  final RuntimeEventLevel level;
  final RuntimeEventCategory category;
  final String message;
  final String? detail;
  final RuntimeEventPayload? payload;

  bool get hasInspectableDetails =>
      (detail != null && detail!.trim().isNotEmpty) ||
      (payload?.hasContent ?? false);
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
