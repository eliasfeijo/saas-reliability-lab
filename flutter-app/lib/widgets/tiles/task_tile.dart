import 'package:flutter/material.dart';
import 'package:todo_flutter/models/task.dart';

class TaskTile extends StatelessWidget {
  final TaskModel task;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleComplete;

  const TaskTile({
    super.key,
    required this.task,
    required this.isSelected,
    required this.onTap,
    required this.onToggleComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isSelected
          ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
          : Theme.of(context).cardColor,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                      color: task.priority.color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Checkbox(
                    value: task.isCompleted,
                    onChanged: (_) => onToggleComplete(),
                  ),
                ],
              ),
              SizedBox(width: 8),
              // Task Title and Details
              Expanded(
                flex: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(
                        task.title,
                        style: Theme.of(context).textTheme.titleMedium!
                            .copyWith(
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: task.isCompleted ? Colors.grey : null,
                            ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_formatDateTime(task.beginsAt)),
                          Text(
                            _formattedStatusMessage,
                            style: TextStyle(
                              color: _getStatusColor(task.status),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 8),
              // Priority Indicator and Selection Icon
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildPriorityIndicator(task.priority),
                    const SizedBox(width: 8),
                    Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityIndicator(TaskPriority priority) {
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: priority.color,
        borderRadius: BorderRadius.all(Radius.circular(4)),
        shape: BoxShape.rectangle,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Tooltip(
            message: "${priority.displayName} Priority",
            child: Text(
              priority.displayName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.completed:
        return Colors.green;
      case TaskStatus.overdue:
        return Colors.red;
      case TaskStatus.inProgress:
        return Colors.blue;
      case TaskStatus.upcoming:
        return Colors.orange;
      case TaskStatus.pending:
        return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);

    if (dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day) {
      return 'Today ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Tomorrow ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == -1) {
      return 'Yesterday ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.day}/${dateTime.month} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  String get _formattedStatusMessage {
    if (task.isCompleted) {
      return 'Completed on ${task.completedAt?.toLocal().toIso8601String().split('T').first}';
    }
    if (task.isOverdue) {
      if (task.overdueDuration.inDays > 0) {
        return 'Overdue by ${task.overdueDuration.inDays} days';
      } else if (task.overdueDuration.inHours > 0) {
        return 'Overdue by ${task.overdueDuration.inHours} hours';
      } else if (task.overdueDuration.inMinutes > 0) {
        return 'Overdue by ${task.overdueDuration.inMinutes} minutes';
      } else {
        return 'Overdue';
      }
    }
    if (task.isInProgress) {
      return 'In Progress • ${_formatDuration(task.timeUntilEnd)} left';
    }
    if (task.isUpcoming) {
      return 'Upcoming • ${_formatDuration(task.timeUntilStart)} until start';
    }
    return 'Pending';
  }
}
