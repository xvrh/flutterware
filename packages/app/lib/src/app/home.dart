import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../ui.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
                'projects': (_) => _ProjectsTab(),
                'tour': (_) => _FeaturesTab(),
                'changelog': (_) => _ChangeLogTab(),
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

class _ProjectsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
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
                onPressed: () {},
                child: Text('Open project'),
              )
            ],
          ),
          Divider(),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  title: Text('some project'),
                  onTap: () {},
                  subtitle: Text(
                    'full/path/to/the/project',
                    style: const TextStyle(color: AppColors.lightText),
                  ),
                ),
                ListTile(
                  title: Text('some project'),
                  onTap: () {},
                  subtitle: Text(
                    'full/path/to/the/project',
                    style: const TextStyle(color: AppColors.lightText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturesTab extends StatelessWidget {
  const _FeaturesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Markdown(data: '''
### TODO(xha): Explain all features:
test_ui
 - Run normal test (without screenshots)
 - Allow to run integration_test
 - Fully inspect each screenshot
 - Capture animation
 - Display how many frames between each screenshot. Display how expensive it is. Allow to access the detailed timeline for the transition.
 - Export screenshots with “device_frame” in all languages. Allow to create “marketing material” (from UI and from CLI)
 - Export full animation of the whole test
Launcher
 - Preview (example folder)
 - Create new example
 - Devbar in the UI (change language, etc...)
Theme
 - Synchronisation with Figma
Timeline
 - Editor
 - New animation API
Assets
 - Optimization + resize
 - Available with CLI
 - Generate constants
 - Synchronisation with Figma
Pubspec
 - Upgrade packages
 - See changelogs etc...
Flutter version management
 - Download flutter installations
 - Set system path to main version
Translations
 - Synchronize with Translation platform
''');
  }
}

class _ChangeLogTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Markdown(data: '''
## Changelog

#### v0.1.0
- Initial launching

''');
  }
}
