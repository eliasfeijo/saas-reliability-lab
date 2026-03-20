import 'package:flutter/material.dart';
import 'package:todo_flutter/widgets/lab/task_workspace.dart';

class TaskList extends StatelessWidget {
  const TaskList({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Padding(padding: EdgeInsets.all(16), child: TaskWorkspace()),
      ),
    );
  }
}
