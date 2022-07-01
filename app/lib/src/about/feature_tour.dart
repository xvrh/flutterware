import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class FeatureTourPage extends StatelessWidget {
  const FeatureTourPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Markdown(data: '''
## Features
#### test_ui
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
