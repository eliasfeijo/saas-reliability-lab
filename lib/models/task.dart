import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

enum SyncStatus { synced, dirty, deleted }

class TaskModel {
  final String id;
  String title;
  DateTime beginsAt;
  Duration estimatedDuration;
  bool isCompleted;
  DateTime? completedAt;
  String? description;
  TaskPriority priority;
  List<String> tags;

  SyncStatus syncStatus;
  DateTime? lastModifiedAt;

  // DB Timestamps
  DateTime? createdAt;
  DateTime? updatedAt;

  // User ID for cloud sync
  // This is used to identify the user for cloud sync operations.
  String? userId;

  TaskModel({
    this.isCompleted = false,
    this.title = '',
    this.estimatedDuration = const Duration(hours: 1),
    this.description,
    this.priority = TaskPriority.medium,
    this.tags = const [],
    this.syncStatus = SyncStatus.synced,
    this.completedAt,
    String? id,
    DateTime? beginsAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastModifiedAt,
    String? userId,
  }) : id = id ?? const Uuid().v4(),
       beginsAt = beginsAt ?? DateTime.now();

  // Computed Properties
  DateTime get endsAt => beginsAt.add(estimatedDuration);

  bool get isToday {
    final today = DateTime.now();
    return beginsAt.year == today.year &&
        beginsAt.month == today.month &&
        beginsAt.day == today.day;
  }

  bool get isUpcoming => beginsAt.isAfter(DateTime.now());

  bool get isOverdue => !isCompleted && DateTime.now().isAfter(endsAt);

  bool get isInProgress {
    final now = DateTime.now();
    return !isCompleted && now.isAfter(beginsAt) && now.isBefore(endsAt);
  }

  bool get hasStarted => DateTime.now().isAfter(beginsAt);

  Duration get timeUntilStart {
    final now = DateTime.now();
    return beginsAt.isAfter(now) ? beginsAt.difference(now) : Duration.zero;
  }

  Duration get timeUntilEnd {
    final now = DateTime.now();
    return endsAt.isAfter(now) ? endsAt.difference(now) : Duration.zero;
  }

  Duration get overdueDuration {
    final now = DateTime.now();
    return isOverdue ? now.difference(endsAt) : Duration.zero;
  }

  TaskStatus get status {
    if (isCompleted) return TaskStatus.completed;
    if (isOverdue) return TaskStatus.overdue;
    if (isInProgress) return TaskStatus.inProgress;
    if (isUpcoming) return TaskStatus.upcoming;
    return TaskStatus.pending;
  }

  // Methods
  void dirty() {
    syncStatus = SyncStatus.dirty;
    lastModifiedAt = DateTime.now();
  }

  void markAsDeleted() {
    syncStatus = SyncStatus.deleted;
    lastModifiedAt = DateTime.now();
  }

  void toggleCompletion() {
    isCompleted = !isCompleted;
    completedAt = isCompleted ? DateTime.now() : null;
    dirty();
  }

  void markAsCompleted() {
    if (!isCompleted) {
      isCompleted = true;
      completedAt = DateTime.now();
      dirty();
    }
  }

  void markAsPending() {
    if (isCompleted) {
      isCompleted = false;
      completedAt = null;
      dirty();
    }
  }

  void addTag(String tag) {
    if (!tags.contains(tag)) {
      tags = [...tags, tag];
      dirty();
    }
  }

  void removeTag(String tag) {
    tags = tags.where((t) => t != tag).toList();
    dirty();
  }

  bool hasTag(String tag) => tags.contains(tag);

  // Reschedule task to a new start time
  void reschedule(DateTime newBeginTime) {
    beginsAt = newBeginTime;
    dirty();
  }

  // Extend or reduce task estimatedDuration
  void updateDuration(Duration newDuration) {
    if (newDuration.inMinutes > 0) {
      estimatedDuration = newDuration;
      dirty();
    }
  }

  // Copy method with all fields
  TaskModel copyWith({
    String? id,
    String? title,
    DateTime? beginsAt,
    Duration? estimatedDuration,
    bool? isCompleted,
    DateTime? completedAt,
    String? description,
    TaskPriority? priority,
    List<String>? tags,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      beginsAt: beginsAt ?? this.beginsAt,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      tags: tags ?? List.from(this.tags),
    );
  }

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      beginsAt.hashCode ^
      estimatedDuration.hashCode ^
      isCompleted.hashCode ^
      (completedAt?.hashCode ?? 0) ^
      (description?.hashCode ?? 0) ^
      priority.hashCode ^
      tags.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    final TaskModel otherTask = other as TaskModel;
    return id == otherTask.id &&
        title == otherTask.title &&
        beginsAt == otherTask.beginsAt &&
        estimatedDuration == otherTask.estimatedDuration &&
        isCompleted == otherTask.isCompleted &&
        completedAt == otherTask.completedAt &&
        description == otherTask.description &&
        priority == otherTask.priority &&
        _listEquals(tags, otherTask.tags);
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() {
    return 'TaskModel('
        'id: $id, '
        'title: $title, '
        'beginsAt: $beginsAt, '
        'estimatedDuration: $estimatedDuration, '
        'isCompleted: $isCompleted, '
        'priority: $priority, '
        'status: $status'
        ')';
  }

  // From JSON
  TaskModel.fromJson(Map<String, dynamic> json)
    : id = json['id'],
      title = json['title'],
      beginsAt = DateTime.parse(json['start_date']).toLocal(),
      estimatedDuration = DateTime.parse(
        json['due_date'],
      ).difference(DateTime.parse(json['start_date'])),
      isCompleted = json['completed'],
      completedAt = json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      description = json['description'],
      priority =
          TaskPriority.values[json['priority'] ?? TaskPriority.medium.index],
      tags = List<String>.from(json['tags'] ?? []),
      syncStatus =
          SyncStatus.values[json['sync_status'] ?? SyncStatus.synced.index],
      createdAt = json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt = json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      lastModifiedAt = json['modified_at'] != null
          ? DateTime.parse(json['modified_at'])
          : json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      userId = json['user_id'];

  // To JSON (for local storage)
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start_date': beginsAt.toUtc().toIso8601String(),
    'due_date': endsAt.toUtc().toIso8601String(),
    'completed': isCompleted,
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'description': description,
    'priority': priority.index,
    'tags': tags,
    'sync_status': syncStatus.index,
    'modified_at': lastModifiedAt?.toUtc().toIso8601String(),
    'user_id': userId,
  };
  // To JSON (for cloud sync)
  Map<String, dynamic> toCloudJson() => {
    'id': id,
    'title': title,
    'start_date': beginsAt.toUtc().toIso8601String(),
    'due_date': endsAt.toUtc().toIso8601String(),
    'completed': isCompleted,
    // 'completed_at': completedAt?.toUtc().toIso8601String(),
    'description': description,
    'priority': priority.index,
    'notify_at': beginsAt
        .subtract(Duration(minutes: 30))
        .toUtc()
        .toIso8601String(),
    // 'tags': tags,
    // 'sync_status': syncStatus.index,
    // 'user_id': userId,
  };
}

enum TaskPriority { low, medium, high, urgent }

enum TaskStatus { pending, upcoming, inProgress, completed, overdue }

enum TaskFilter { all, completed, pending, today, upcoming, overdue }

extension TaskPriorityExtension on TaskPriority {
  String get displayName {
    switch (this) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.high:
        return 'High';
      case TaskPriority.urgent:
        return 'Urgent';
    }
  }

  int get value {
    switch (this) {
      case TaskPriority.low:
        return 1;
      case TaskPriority.medium:
        return 2;
      case TaskPriority.high:
        return 3;
      case TaskPriority.urgent:
        return 4;
    }
  }

  Color get color {
    switch (this) {
      case TaskPriority.low:
        return Colors.green;
      case TaskPriority.medium:
        return Colors.orange;
      case TaskPriority.high:
        return Colors.red;
      case TaskPriority.urgent:
        return Colors.red.shade900;
    }
  }
}

extension TaskStatusExtension on TaskStatus {
  String get displayName {
    switch (this) {
      case TaskStatus.pending:
        return 'Pending';
      case TaskStatus.upcoming:
        return 'Upcoming';
      case TaskStatus.inProgress:
        return 'In Progress';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.overdue:
        return 'Overdue';
    }
  }
}

extension TaskFilterExtension on TaskFilter {
  String get displayName {
    switch (this) {
      case TaskFilter.all:
        return 'All Tasks';
      case TaskFilter.completed:
        return 'Completed';
      case TaskFilter.pending:
        return 'Pending';
      case TaskFilter.today:
        return 'Today';
      case TaskFilter.upcoming:
        return 'Upcoming';
      case TaskFilter.overdue:
        return 'Overdue';
    }
  }

  String get description {
    switch (this) {
      case TaskFilter.all:
        return 'Show all tasks';
      case TaskFilter.completed:
        return 'Show completed tasks only';
      case TaskFilter.pending:
        return 'Show pending tasks only';
      case TaskFilter.today:
        return 'Show tasks scheduled for today';
      case TaskFilter.upcoming:
        return 'Show future tasks';
      case TaskFilter.overdue:
        return 'Show overdue tasks';
    }
  }

  String get title {
    switch (this) {
      case TaskFilter.all:
        return 'All Tasks';
      case TaskFilter.completed:
        return 'Completed Tasks';
      case TaskFilter.pending:
        return 'Pending Tasks';
      case TaskFilter.today:
        return 'Today\'s Tasks';
      case TaskFilter.upcoming:
        return 'Upcoming Tasks';
      case TaskFilter.overdue:
        return 'Overdue Tasks';
    }
  }
}
