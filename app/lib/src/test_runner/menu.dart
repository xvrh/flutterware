import 'package:flutter/material.dart';
import '../app/ui/menu.dart';
import '../project.dart';
import 'service.dart';

class TestMenuLine extends StatelessWidget {
  final Project project;

  const TestMenuLine(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('Tests')),
        ValueListenableBuilder<DaemonState>(
          valueListenable: project.tests.state,
          builder: (context, state, child) {
            if (state is! DaemonState$Initial) {
              return IconButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => _DaemonDialog(project),
                  );
                },
                constraints: BoxConstraints(),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_vert, size: 12),
              );
            } else {
              return IntrinsicHeight(
                child: Container(
                  // decoration: BoxDecoration(
                  //     color: Colors.blueAccent,
                  //     borderRadius: BorderRadius.circular(5)),
                  // Put all this on the top of the main tab.
                  // Just keep the
                  child: Row(
                    children: [
                      Icon(
                        Icons.bolt,
                        color: Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        Icons.restart_alt,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 5),
                      VerticalDivider(),
                      const SizedBox(width: 5),
                      Icon(
                        Icons.more_vert,
                        size: 20,
                        //color: Colors.white,
                      ),
                    ],
                  ),
                ),
              );
              return const SizedBox();
            }
          },
        ),
      ],
    );
  }
}

class TestMenu extends StatelessWidget {
  final Project project;

  const TestMenu(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...[
          Text('''
When Tests is expanded or clicked
 => ensureStarted
Show loader in the expanded menu
Menu only comes from Daemon
'''),
          //MenuLine(
          //  selected: false,
          //  onTap: () {},
          //  type: LineType.collapsed,
          //  depth: 2,
          //  child: Row(
          //    children: [
          //      Icon(
          //        Icons.folder,
          //        size: 16,
          //        color: Color(0xff8cd3ec),
          //      ),
          //      const SizedBox(width: 4),
          //      Expanded(child: Text('onboarding_test.dart')),
          //    ],
          //  ),
          //),
          MenuLine(
            selected: false,
            onTap: () {},
            type: LineType.collapsed,
            depth: 2,
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  size: 16,
                  color: Color(0xff8cd3ec),
                ),
                const SizedBox(width: 4),
                Expanded(child: Text('app_test.dart')),
              ],
            ),
          ),
          MenuLine(
            selected: false,
            onTap: () {},
            type: LineType.collapsed,
            depth: 2,
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  size: 16,
                  color: Color(0xff8cd3ec),
                ),
                const SizedBox(width: 4),
                Expanded(child: Text('app_test.dart')),
              ],
            ),
          ),
        ]
      ],
    );
  }
}

class _DaemonDialog extends StatelessWidget {
  final Project project;

  const _DaemonDialog(this.project);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Test daemon'),
      content: ValueListenableBuilder<DaemonState>(
        valueListenable: project.tests.state,
        builder: (context, state, child) {
          if (state is DaemonState$Connected) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () {
                    state.daemon.stop();
                    Navigator.pop(context);
                  },
                  child: Text('Stop daemon'),
                ),
              ],
            );
          } else if (state is DaemonState$Stopped) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () {
                    project.tests.start();
                    Navigator.pop(context);
                  },
                  child: Text('Start daemon'),
                ),
              ],
            );
          } else if (state is DaemonState$Starting) {
            return Text('Daemon is starting...');
          } else {
            return Text('State is ${state.runtimeType}');
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text('OK'),
        ),
      ],
    );
  }
}
