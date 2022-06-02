import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/app/add_project.dart';

import '../ui.dart';
import '../utils/data_loader.dart';
import '../workspace.dart';
import 'package:path/path.dart' as p;

class MainTabBar extends StatelessWidget {
  final Workspace workspace;

  const MainTabBar(this.workspace, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.separator),
        ),
      ),
      child: Material(
        color: AppColors.backgroundGrey,
        child: ValueListenableBuilder<List<Project>>(
          valueListenable: workspace.projects,
          builder: (context, projects, child) {
            return ValueListenableBuilder<Project?>(
              valueListenable: workspace.selectedProject,
              builder: (context, selected, child) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _HomeTab(
                      isSelected: selected == null,
                      onTap: () {
                        workspace.unselectProject();
                      },
                    ),
                    for (var project in projects)
                      _Tab(
                        project,
                        isSelected: project == selected,
                        onTap: () {
                          workspace.selectProject(project);
                        },
                        onClose: () {
                          workspace.closeProject(project);
                        },
                      ),
                    IconButton(
                      onPressed: () {
                        openProject(context, workspace);
                      },
                      icon: Icon(Icons.add),
                      padding:
                          EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                      tooltip: 'Open project',
                      iconSize: 16,
                      constraints: BoxConstraints(),
                    ),
                  ]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

const _tabHeight = 40.0;

class _Tab extends StatelessWidget {
  final Project project;
  final bool isSelected;
  final void Function() onClose;
  final void Function() onTap;

  const _Tab(
    this.project, {
    required this.isSelected,
    required this.onClose,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var selectedBorder = Border(
      bottom: BorderSide(
        color: isSelected ? AppColors.selection : Colors.transparent,
        width: 3,
      ),
    );
    return ValueListenableBuilder<Snapshot<Pubspec>>(
      valueListenable: project.pubspec,
      builder: (context, snapshot, child) {
        var projectName = snapshot.data?.name ?? p.basename(project.directory);
        return InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : null,
              border: selectedBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            height: _tabHeight,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    Icons.folder,
                    size: 20,
                    color: Color(0xffabb6bd),
                  ),
                ),
                Text(
                  projectName,
                  style: TextStyle(
                      fontSize: 13,
                      color: snapshot.hasError ? Colors.red : null),
                ),
                IconButton(
                  onPressed: onClose,
                  iconSize: 13,
                  color: Color(0xffbec4c6),
                  padding: EdgeInsets.all(5),
                  splashRadius: 10,
                  splashColor: Colors.black87,
                  hoverColor: Colors.black12,
                  constraints: BoxConstraints(),
                  tooltip: 'Close $projectName',
                  icon: Icon(Icons.close),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeTab extends StatelessWidget {
  final bool isSelected;
  final void Function() onTap;

  const _HomeTab({
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var selectedBorder = Border(
      bottom: BorderSide(
        color: isSelected ? AppColors.selection : Colors.transparent,
        width: 3,
      ),
    );
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : null,
          border: selectedBorder,
        ),
        height: _tabHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Icon(
          Icons.home,
          color: isSelected ? AppColors.selection : Colors.black87,
          size: 20,
        ),
      ),
    );
  }
}
