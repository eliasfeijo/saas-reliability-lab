import 'package:uuid/uuid.dart';

const Object _outboxUnset = Object();

enum OutboxOperationType { upsert, delete }

enum OutboxEntryState {
  queued,
  sending,
  acknowledged,
  failed,
  conflict,
  blockedNoSession,
  blockedAnonymousReview,
}

enum OutboxOwnerScope { anonymous, authenticated }

class OutboxEntry {
  OutboxEntry({
    String? id,
    required this.taskId,
    required this.operationType,
    required this.state,
    required this.ownerScope,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.firstQueuedAt,
    this.lastAttemptAt,
    this.attemptCount = 0,
    this.lastError,
    this.baseRemoteUpdatedAt,
    required Map<String, dynamic> taskPayload,
    Map<String, dynamic>? remoteSnapshot,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc(),
       taskPayload = Map<String, dynamic>.from(taskPayload),
       remoteSnapshot = remoteSnapshot == null
           ? null
           : Map<String, dynamic>.from(remoteSnapshot);

  final String id;
  final String taskId;
  final OutboxOperationType operationType;
  final OutboxEntryState state;
  final OutboxOwnerScope ownerScope;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? firstQueuedAt;
  final DateTime? lastAttemptAt;
  final int attemptCount;
  final String? lastError;
  final DateTime? baseRemoteUpdatedAt;
  final Map<String, dynamic> taskPayload;
  final Map<String, dynamic>? remoteSnapshot;

  OutboxEntry copyWith({
    String? id,
    String? taskId,
    OutboxOperationType? operationType,
    OutboxEntryState? state,
    OutboxOwnerScope? ownerScope,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? firstQueuedAt = _outboxUnset,
    Object? lastAttemptAt = _outboxUnset,
    int? attemptCount,
    Object? lastError = _outboxUnset,
    Object? baseRemoteUpdatedAt = _outboxUnset,
    Map<String, dynamic>? taskPayload,
    Object? remoteSnapshot = _outboxUnset,
  }) {
    return OutboxEntry(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      operationType: operationType ?? this.operationType,
      state: state ?? this.state,
      ownerScope: ownerScope ?? this.ownerScope,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      firstQueuedAt: identical(firstQueuedAt, _outboxUnset)
          ? this.firstQueuedAt
          : firstQueuedAt as DateTime?,
      lastAttemptAt: identical(lastAttemptAt, _outboxUnset)
          ? this.lastAttemptAt
          : lastAttemptAt as DateTime?,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: identical(lastError, _outboxUnset)
          ? this.lastError
          : lastError as String?,
      baseRemoteUpdatedAt: identical(baseRemoteUpdatedAt, _outboxUnset)
          ? this.baseRemoteUpdatedAt
          : baseRemoteUpdatedAt as DateTime?,
      taskPayload: taskPayload ?? this.taskPayload,
      remoteSnapshot: identical(remoteSnapshot, _outboxUnset)
          ? this.remoteSnapshot
          : remoteSnapshot as Map<String, dynamic>?,
    );
  }

  factory OutboxEntry.fromJson(Map<String, dynamic> json) {
    return OutboxEntry(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      operationType: OutboxOperationType.values[json['operation_type'] as int],
      state: OutboxEntryState.values[json['state'] as int],
      ownerScope: OutboxOwnerScope.values[json['owner_scope'] as int],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      firstQueuedAt: json['first_queued_at'] == null
          ? null
          : DateTime.parse(json['first_queued_at'] as String),
      lastAttemptAt: json['last_attempt_at'] == null
          ? null
          : DateTime.parse(json['last_attempt_at'] as String),
      attemptCount: json['attempt_count'] as int? ?? 0,
      lastError: json['last_error'] as String?,
      baseRemoteUpdatedAt: json['base_remote_updated_at'] == null
          ? null
          : DateTime.parse(json['base_remote_updated_at'] as String),
      taskPayload: Map<String, dynamic>.from(
        json['task_payload'] as Map<String, dynamic>? ?? const {},
      ),
      remoteSnapshot: json['remote_snapshot'] == null
          ? null
          : Map<String, dynamic>.from(
              json['remote_snapshot'] as Map<String, dynamic>,
            ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'operation_type': operationType.index,
      'state': state.index,
      'owner_scope': ownerScope.index,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'first_queued_at': firstQueuedAt?.toUtc().toIso8601String(),
      'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
      'attempt_count': attemptCount,
      'last_error': lastError,
      'base_remote_updated_at': baseRemoteUpdatedAt?.toUtc().toIso8601String(),
      'task_payload': taskPayload,
      'remote_snapshot': remoteSnapshot,
    };
  }
}
