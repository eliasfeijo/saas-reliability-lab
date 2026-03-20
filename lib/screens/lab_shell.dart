import 'package:flutter/material.dart';
import 'package:todo_flutter/widgets/debug/sync_debug_panel.dart';
import 'package:todo_flutter/widgets/lab/lab_left_rail.dart';
import 'package:todo_flutter/widgets/lab/task_workspace.dart';

class LabShell extends StatelessWidget {
  const LabShell({super.key});

  static const double _wideBreakpoint = 1500;
  static const double _workspaceMaxWidth = 1040;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;

        return Scaffold(
          appBar: isWide
              ? null
              : AppBar(
                  title: const Text('Reliability Lab'),
                  leading: Builder(
                    builder: (context) {
                      return IconButton(
                        icon: const Icon(Icons.dashboard_customize_outlined),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      );
                    },
                  ),
                  actions: [
                    Builder(
                      builder: (context) {
                        return IconButton(
                          icon: const Icon(Icons.monitor_heart_outlined),
                          onPressed: () => Scaffold.of(context).openEndDrawer(),
                        );
                      },
                    ),
                  ],
                ),
          drawer: isWide
              ? null
              : const Drawer(
                  child: SafeArea(child: LabLeftRail(compact: true)),
                ),
          endDrawer: isWide
              ? null
              : const Drawer(
                  child: SafeArea(child: SyncDebugPanel(compact: true)),
                ),
          body: SafeArea(
            top: isWide,
            child: isWide
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: const [
                        SizedBox(width: 280, child: LabLeftRail()),
                        SizedBox(width: 20),
                        Expanded(
                          child: _WorkspaceCanvas(child: TaskWorkspace()),
                        ),
                        SizedBox(width: 20),
                        SizedBox(width: 360, child: SyncDebugPanel()),
                      ],
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: TaskWorkspace(),
                  ),
          ),
        );
      },
    );
  }
}

class _WorkspaceCanvas extends StatelessWidget {
  const _WorkspaceCanvas({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < LabShell._workspaceMaxWidth
            ? constraints.maxWidth
            : LabShell._workspaceMaxWidth;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: child,
          ),
        );
      },
    );
  }
}
