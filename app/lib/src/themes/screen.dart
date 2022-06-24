import 'package:flutter/material.dart';

class ThemesScreen extends StatelessWidget {
  const ThemesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Text('''Themes
- Button add a Theme (create a file in lib/src/themes/xx.dart    
- List all files in the project with the // GENERATED-FILE: Theme file generated with Flutter Studio (pub.dev link)

ThemeData myThemeName() {
  var theme = ThemeData(material3: true);
  
  return theme;
}
''');
  }
}
