import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutterware_app/src/about/changelog.dart';

import '../ui/side_menu.dart';
import '../utils.dart';
import 'about.dart';
import 'feature_tour.dart';

class AboutMenuItem extends StatelessWidget {
  const AboutMenuItem({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        context.router.go('/about/what');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 15,
            ),
            const SizedBox(width: 5),
            Text(
              'Flutterware v0.2.0',
            ),
          ],
        ),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var backButton = InkWell(
      onTap: () {
        context.router.go('/project/home');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
        child: Row(
          children: [
            Icon(
              Icons.arrow_back_outlined,
              size: 18,
            ),
            const SizedBox(width: 5),
            Text(
              'Back to project',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SideMenu(
          bottom: [backButton],
          children: [
            backButton,
            CollapsibleMenu(
              initiallyExpanded: true,
              title: Text('About'),
              children: [
                MenuLink(
                  url: 'what',
                  title: Text('What is it'),
                ),
                MenuLink(
                  url: 'features',
                  title: Text('Features'),
                ),
                MenuLink(
                  url: 'changelog',
                  title: Text('Changelog'),
                ),
              ],
            ),
          ],
        ),
        Expanded(
          child: RouterOutlet(
            {
              'what': (route) => AboutPage(),
              'features': (route) => FeatureTourPage(),
              'changelog': (route) => ChangeLogPage(),
            },
            onNotFound: (_) => 'what',
          ),
        ),
      ],
    );
  }
}
