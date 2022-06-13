import 'dart:io';

class IconPlatform {
  static final android = IconPlatform('Android', [
    'android/app/src/main/res/mipmap-*dpi/ic_launcher.png',
  ]);
  static final ios = IconPlatform('iOS', [
    'app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*x*@?x.png',
  ]);
  static final web = IconPlatform('Web', [
    'web/favicon.png',
    'web/icons/Icon*.png',
  ]);
  static final macOS = IconPlatform('macOS', [
    'app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png',
  ]);
  static final windows = IconPlatform('Windows', [
    'app/windows/runner/resources/app_icon.ico',
  ]);
  static final linux = IconPlatform('Linux', [
    //TODO
  ]);

  final String name;
  final List<String> locations;

  IconPlatform(this.name, this.locations);
}

class ProjectIcons {
  final Map<IconPlatform, List<ProjectIcon>> icons;

  ProjectIcons(this.icons);

  List<ProjectIcon> get android => icons[IconPlatform.android] ?? const [];

  static File? findSampleIcon() {
    var locations = [
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-*dpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-*dpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-*dpi/ic_launcher.png',
    ];

    // Hardcode a few location to search for the icon

    // Best icon: keep order Android, iOS, Web etc...
    //  Find icon with best resolution? (bigger file size but under x mo?)
  }
}

class ProjectIcon {
  final File file;
  final int width, height;

  ProjectIcon(
    this.file, {
    required this.width,
    required this.height,
  });
}
