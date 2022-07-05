import 'package:flutter/material.dart';
import 'package:flutterware_app/src/test_runner/protocol/api.dart';
import '../project.dart';
import '../ui.dart';
import '../utils.dart';
import 'daemon.dart';
import 'listing.dart';
import 'service.dart';

class _TestMenuLine extends StatelessWidget {
  final Project project;

  const _TestMenuLine(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('Tests')),
        ValueListenableBuilder<DaemonState>(
            valueListenable: project.tests.state,
            builder: (context, state, child) {
              return IconButton(
                onPressed: () {
                  project.tests.ensureStarted();
                },
                constraints: BoxConstraints(),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_vert, size: 12),
              );
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
            }),
      ],
    );
  }
}

class TestMenu extends StatelessWidget {
  final Project project;

  const TestMenu(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TestRunnerApi>>(
      stream: project.tests.clients,
      initialData: project.tests.clients.value,
      builder: (context, snapshot) {
        var clients = snapshot.requireData;
        if (clients.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1,
                ),
              ),
            ),
          );
        } else {
          var client = clients.last;
          return TestListingView(client);
        }
      },
    );
  }
}

class DaemonToolbar extends StatelessWidget {
  final Project project;

  const DaemonToolbar(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    project.tests.ensureStarted();

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.menuBackground,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text('Test runner'),
          const SizedBox(width: 20),
          Expanded(
            child: ValueListenableBuilder<DaemonState>(
              valueListenable: project.tests.state,
              builder: (context, state, child) {
                if (state is DaemonState$Connected) {
                  return _DaemonConnectedToolbar(state.daemon);
                } else if (state is DaemonState$Stopped) {
                  return _DaemonStoppedToolbar(project);
                } else {
                  return _DaemonStartingToolbar();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DaemonConnectedToolbar extends StatelessWidget {
  final Daemon daemon;

  const _DaemonConnectedToolbar(this.daemon, {super.key});

  @override
  Widget build(BuildContext context) {
    //TODO(xha): disable buttons when isReloading is true
    return Row(
      children: [
        IconButton(
          onPressed: () {
            daemon.reload(fullRestart: false);
          },
          constraints: BoxConstraints(),
          padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
          icon: Icon(
            Icons.bolt,
            color: Colors.orange,
            size: 20,
          ),
          tooltip: 'Hot reload',
        ),
        IconButton(
          onPressed: () {
            daemon.reload(fullRestart: true);
          },
          constraints: BoxConstraints(),
          padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
          icon: Icon(
            Icons.restart_alt,
            size: 20,
            color: Colors.green,
          ),
          tooltip: 'Hot restart',
        ),
        //TODO(xha): open a dropdown with option to watch lib/** & test_app/**
        Text('Auto reload'),
        Checkbox(value: true, onChanged: (v) {}),
        OutlinedButton(onPressed: () {}, child: Text('Auto reload')),
        Expanded(
          child: const SizedBox(),
        ),
        IconButton(
          onPressed: () {
            daemon.stop();
          },
          constraints: BoxConstraints(),
          padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
          icon: Icon(
            Icons.stop,
            color: Colors.red,
            size: 20,
          ),
          tooltip: 'Stop test runner',
        ),
      ],
    );
  }
}

class _DaemonStoppedToolbar extends StatelessWidget {
  final Project project;

  const _DaemonStoppedToolbar(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () {
            project.tests.start();
          },
          constraints: BoxConstraints(),
          padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
          icon: Icon(
            Icons.play_arrow,
            color: Colors.green,
            size: 20,
          ),
        ),
      ],
    );
  }
}

class _DaemonStartingToolbar extends StatelessWidget {
  const _DaemonStartingToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Launching test runner...',
      style: TextStyle(
        color: Colors.black26,
        fontSize: 13,
      ),
    );
  }
}
