import 'package:flutter/material.dart';

import '../../../project.dart';
import '../../../ui.dart';
import '../../../utils/async_value.dart';
import '../../workspace.dart';
import '../add_project.dart';

class ProjectsTab extends StatelessWidget {
  final Workspace workspace;

  const ProjectsTab(this.workspace, {super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return ValueListenableBuilder<List<Project>>(
        valueListenable: workspace.projects,
        builder: (context, projects, child) {
          return Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Projects',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => openProject(context, workspace),
                      child: Text('Open project'),
                    )
                  ],
                ),
                Divider(),
                Expanded(
                  child: ListView(
                    children: [
                      for (var project in projects)
                        _ProjectTile(
                          project,
                          onTap: () {
                            workspace.selectProject(project);
                          },
                        )
                    ],
                  ),
                ),
              ],
            ),
          );
        });
  }
}

class _ProjectTile extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;

  const _ProjectTile(
    this.project, {
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Snapshot<Pubspec>>(
      valueListenable: project.pubspec,
      builder: (context, snapshot, child) {
        Widget title;
        if (snapshot.hasError) {
          title = Tooltip(
            message: '${snapshot.error}',
            child: Text(project.directory.path),
          );
        } else {
          title = Text(snapshot.data?.name ?? '');
        }

        return ListTile(
          title: title,
          onTap: onTap,
          subtitle: Text(
            project.directory.path,
            style: const TextStyle(color: AppColors.lightText),
          ),
        );
      },
    );
  }
}
