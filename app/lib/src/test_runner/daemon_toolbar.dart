import 'package:flutter/material.dart';

import '../project.dart';
import '../ui/colors.dart';
import '../utils/custom_popup_menu.dart';
import 'model/daemon.dart';
import 'model/service.dart';

class DaemonToolbar extends StatelessWidget {
  final Project project;

  const DaemonToolbar(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
    );
  }
}

class _DaemonConnectedToolbar extends StatelessWidget {
  final Daemon daemon;

  const _DaemonConnectedToolbar(this.daemon);

  @override
  Widget build(BuildContext context) {
    //TODO(xha): disable buttons when isReloading is true
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.inMenuToolbarBackground,
            borderRadius: BorderRadius.circular(15),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 0),
          margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HotReloadButton(daemon),
              _HotRestartButton(daemon),
              ////TODO(xha): open a dropdown with option to watch lib/** & test_app/**
              _ToolbarButton(
                onPressed: () {
                  daemon.stop();
                },
                icon: Icons.stop,
                iconColor: Colors.red,
                tooltip: 'Stop test runner',
              ),
              //Expanded(child: const SizedBox()),
            ],
          ),
        ),
        Positioned(
            right: 0,
            bottom: 0,
            top: 0,
            child: CustomPopupMenuButton(
              splashRadius: Material.defaultSplashRadius / 2,
              iconConstraints: BoxConstraints(),
              constraints: BoxConstraints(
                minWidth: 2.0 * 56.0,
                maxWidth: 10.0 * 56.0,
              ),
              tooltip: 'Configure auto hot reload',
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_vert,
                size: 15,
              ),
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  checked: true,
                  child: Text(
                    'Hot reload on change in lib/',
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
                CheckedPopupMenuItem(
                  checked: true,
                  child: Text(
                    'Hot reload on change in app_test/',
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              ],
            ),)
      ],
    );
  }
}

class _HotReloadButton extends StatelessWidget {
  final Daemon daemon;

  const _HotReloadButton(this.daemon);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
        valueListenable: daemon.isReloading,
        builder: (context, isReloading, child) {
          return _ToolbarButton(
            onPressed: isReloading
                ? null
                : () {
                    daemon.reload(fullRestart: false);
                  },
            icon: Icons.bolt,
            iconColor: Colors.orange,
            tooltip: 'Hot reload',
          );
        });
  }
}

class _HotRestartButton extends StatelessWidget {
  final Daemon daemon;

  const _HotRestartButton(this.daemon);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
        valueListenable: daemon.isReloading,
        builder: (context, isReloading, child) {
          return _ToolbarButton(
            onPressed: isReloading
                ? null
                : () {
                    daemon.reload(fullRestart: true);
                  },
            icon: Icons.restart_alt,
            iconColor: Colors.green,
            tooltip: 'Hot restart',
          );
        });
  }
}

class _ToolbarButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color iconColor;
  final String tooltip;

  const _ToolbarButton({
    required this.onPressed,
    required this.icon,
    required this.iconColor,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      splashRadius: Material.defaultSplashRadius / 2,
      onPressed: onPressed,
      constraints: BoxConstraints(),
      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
      icon: Icon(
        icon,
        color: onPressed != null ? iconColor : Colors.black26,
        size: 20,
      ),
      tooltip: tooltip,
    );
  }
}

class _DaemonStoppedToolbar extends StatelessWidget {
  final Project project;

  const _DaemonStoppedToolbar(this.project);

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ElevatedButton.icon(
        onPressed: () {
          project.tests.start();
        },
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 12),
          minimumSize: Size(0, 30),
        ),
        icon: Icon(
          Icons.play_arrow,
          size: 12,
        ),
        label: Text('Start test runner'),
      ),
    );
  }
}

class _DaemonStartingToolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inMenuToolbarBackground,
        borderRadius: BorderRadius.circular(15),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Text(
        'Launching test runner...',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.black26,
          fontSize: 13,
        ),
      ),
    );
  }
}
