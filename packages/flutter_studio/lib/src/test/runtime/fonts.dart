import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:package_config/package_config.dart';

Future<String> commonFontsPath = (() async {
  var packageConfig = (await findPackageConfig(Directory.current))!;
  var testUtilsPackage = packageConfig['flutter_studio']!;
  return testUtilsPackage.packageUriRoot
      .resolve('src/test/runtime/fonts')
      .toFilePath();
})();

Future<Map<String, String>> get commonFonts async {
  final path = await commonFontsPath;
  return {
    'Roboto': '$path/Roboto',
    //TODO(xha): delete or find an alternative?
    //'.SF UI Display': '$path/SF-UI-Display',
    //'.SF UI Text': '$path/SF-UI-Text',
    //'.SF Pro Display': '$path/SF-Pro-Display',
    //'.SF Pro Text': '$path/SF-Pro-Text',
  };
}

Future<void> loadFonts(Map<String, String> fonts) async {
  for (var font in fonts.entries) {
    var fontLoader = FontLoader(font.key);

    var fontFiles = Directory(font.value).listSync().whereType<File>().toList();
    fontFiles.sort((a, b) => a.path.compareTo(b.path));
    for (var file in fontFiles) {
      var future =
          file.readAsBytes().then((value) => value.buffer.asByteData());
      fontLoader.addFont(future);
    }
    await fontLoader.load();
  }
}

Future<void> loadAppFonts(AssetBundle bundle) async {
  final fontManifest = await bundle.loadStructuredData<Iterable<dynamic>>(
    'FontManifest.json',
    (string) async => json.decode(string) as List,
  );

  for (var font in fontManifest.cast<Map<String, dynamic>>()) {
    var fontFamily = font['family'] as String;
    final fontLoader = FontLoader(fontFamily);
    for (final fontType
        in (font['fonts'] as List).cast<Map<String, dynamic>>()) {
      fontLoader.addFont(bundle.load(fontType['asset'] as String));
    }
    await fontLoader.load();
  }
}
