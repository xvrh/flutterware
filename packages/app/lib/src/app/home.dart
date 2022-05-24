

import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Home'),
        Text('''
TODO(xha): Explain all features:
test_ui
 - Run normal test (without screenshots)
 - Allow to run integration_test
 - Fully inspect each screenshot
 - Capture animation
 - Display how many frames between each screenshot. Display how expensive it is. Allow to access the detailed timeline for the transition.
 - Export screenshots with “device_frame” in all languages. Allow to create “marketing material” (from UI and from CLI)
 - Export full animation of the whole test
Examples
 - Preview
 - Create new example
 - Devbar in the UI
Theme
Timeline
Assets
 - Optimization + resize
 - Available with CLI
 - Generate constants
'''),
      ],
    );
  }
}
