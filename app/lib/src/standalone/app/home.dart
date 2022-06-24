import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';
import 'package:flutter_studio_app/src/standalone/workspace.dart';
import '../../ui.dart';
import 'home/changelog.dart';
import 'home/feature_tour.dart';
import 'home/projects.dart';

class HomeScreen extends StatelessWidget {
  final Workspace workspace;

  const HomeScreen(this.workspace, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: AppColors.backgroundGrey,
          child: SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 5,
                  ),
                  child: _AppVersion(),
                ),
                for (var menu in {
                  'Projects': 'projects',
                  'Tour': 'tour',
                  'Changelog': 'changelog',
                }.entries)
                  _HomeMenuItem(
                    menu.key,
                    isSelected: context.router.isSelected(menu.value),
                    onSelect: () => context.go(menu.value),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Material(
            color: Colors.white,
            child: RouterOutlet(
              {
                'projects': (_) => ProjectsTab(workspace),
                'tour': (_) => const FeatureTourTab(),
                'changelog': (_) => const ChangeLogTab(),
              },
              onNotFound: (_) => 'projects',
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeMenuItem extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onSelect;

  const _HomeMenuItem(
    this.title, {
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      child: Container(
        color: isSelected ? AppColors.selection : null,
        padding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 8,
        ),
        child: Text(
          title,
          style: TextStyle(color: isSelected ? Colors.white : null),
        ),
      ),
    );
  }
}

class _AppVersion extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: FlutterLogo(),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Flutter Studio',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                'v0.0.1',
                style: const TextStyle(color: Colors.black38, fontSize: 11),
              ),
            ],
          ),
        )
      ],
    );
  }
}
