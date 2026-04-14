import 'package:duration_picker/duration_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_flutter/models/task.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';

class TaskForm extends StatefulWidget {
  final TaskModel? task; // Make it nullable to support both create and edit
  final VoidCallback? onSaved; // Callback for when task is saved

  const TaskForm({super.key, this.task, this.onSaved});

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  DateTime? _selectedBeginDate;
  Duration? _selectedDuration;
  TaskPriority? _selectedPriority;

  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    // Initialize with existing task data or defaults
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _selectedBeginDate = widget.task?.beginsAt ?? DateTime.now();
    _selectedDuration =
        widget.task?.estimatedDuration ?? const Duration(hours: 1);
    _selectedPriority = widget.task?.priority ?? TaskPriority.medium;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _selectDuration(BuildContext context) async {
    final Duration? picked = await showDurationPicker(
      context: context,
      initialTime: _selectedDuration ?? const Duration(hours: 1),
    );
    if (picked != null && picked != _selectedDuration) {
      setState(() {
        _selectedDuration = picked;
      });
    }
  }

  Future<void> _selectDateBegin(BuildContext context) async {
    final DateTime initialDate = _selectedBeginDate ?? DateTime.now();

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (pickedDate != null && context.mounted) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
        initialEntryMode: TimePickerEntryMode.input,
        // 24-hour format
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        setState(() {
          _selectedBeginDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  void _submitForm() {
    // Validate the form before proceeding
    if (!_formKey.currentState!.validate()) return;

    final agendaProvider = Provider.of<AgendaProvider>(context, listen: false);

    if (_isEditing) {
      // Update existing task
      final updatedTask = widget.task!.copyWith(
        title: _titleController.text.trim(),
        beginsAt: _selectedBeginDate,
        estimatedDuration: _selectedDuration,
        priority: _selectedPriority!,
      );
      agendaProvider.updateTask(updatedTask);
    } else {
      // Create new task
      final newTask = TaskModel(
        title: _titleController.text.trim(),
        beginsAt: _selectedBeginDate,
        estimatedDuration: _selectedDuration!,
        priority: _selectedPriority!,
      );
      agendaProvider.addTask(newTask);
    }

    widget.onSaved?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isEditing ? 'Task Updated' : 'Task Created'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Select Date & Time';
    DateTime now = DateTime.now();
    if (dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day) {
      return 'Today ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }

    final date = '${dateTime.toLocal()}'.split(' ')[0];
    final time =
        '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'Select Duration';

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, maxWidth: 300),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Priority: ${_selectedPriority!.displayName}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _buildPriorityChips(),
              ),
              SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter a title'
                    : null,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),

              _buildDateTimeRow(),
              const SizedBox(height: 8),

              _buildDurationRow(),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitForm,
                  child: Text(_isEditing ? 'Update Task' : 'Create Task'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPriorityChips() {
    return TaskPriority.values.map((priority) {
      return PriorityChip(
        priority: priority,
        isSelected: _selectedPriority == priority,
        onTap: () {
          setState(() {
            _selectedPriority = priority;
          });
        },
      );
    }).toList();
  }

  Widget _buildDateTimeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Begins at:', style: Theme.of(context).textTheme.labelLarge),
        TextButton(
          onPressed: () => _selectDateBegin(context),
          child: Text(_formatDateTime(_selectedBeginDate)),
        ),
      ],
    );
  }

  Widget _buildDurationRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Duration:', style: Theme.of(context).textTheme.labelLarge),
        TextButton(
          onPressed: () => _selectDuration(context),
          child: Text(_formatDuration(_selectedDuration)),
        ),
      ],
    );
  }
}

class PriorityChip extends StatelessWidget {
  final TaskPriority priority;
  final VoidCallback? onTap;
  final bool isSelected;

  const PriorityChip({
    super.key,
    required this.priority,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: CircleBorder(),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: priority.color.withAlpha(isSelected ? 255 : 127),
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
      ),
    );
  }
}
