import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/splash_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/splash/screen.dart';
import 'package:flutterware_app/src/splash/ui/splash_render.dart';
import 'package:flutterware_app/src/splash/ui/variant_tile.dart';
import 'package:flutterware_app/src/ui/theme.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// The panel, mounted for real.
///
/// The render tests cover one cell in isolation; this covers the thing the user
/// actually looks at — eight cells together, each captioned with the key that
/// produced it. The captions are the half that makes the pictures actionable,
/// so they are asserted rather than assumed.
void main() {
  late Directory root;

  SplashCore core() {
    var worktree = Worktree(path: root.path);
    return SplashCore(
      PluginHost(
        id: splashPluginId,
        label: 'Splash screen',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: const [Pkg('.')],
          discovered: const ['.'],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
        config: const {
          'packages': [
            {'path': '.'},
          ],
        },
      ),
    );
  }

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void writePng(String relative, int width, int height) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      img.encodePng(img.Image(width: width, height: height)),
    );
  }

  Future<SplashCore> mount(WidgetTester tester) async {
    var c = core();
    await c.computeAll();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(body: SplashScreen(c, package: '.')),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('splash_screen_test');
    write('pubspec.yaml', '''
name: sample
environment:
  sdk: ^3.0.0
dev_dependencies:
  flutter_native_splash: ^2.4.0
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('draws all eight cells of the matrix', (tester) async {
    tester.view.physicalSize = const Size(2400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    writePng('assets/logo.png', 1024, 1024);
    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
  image: assets/logo.png
''');

    await mount(tester);

    expect(find.byType(SplashVariantTile), findsNWidgets(8));
    expect(find.byType(SplashRender), findsNWidgets(8));
    expect(find.text('Android 12+ · Dark'), findsOneWidget);
    expect(find.text('Web · Light'), findsOneWidget);
  });

  testWidgets('captions each value with the key that produced it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
  color_dark_android: "000000"
''');

    await mount(tester);

    // Without this the eight pictures tell you something is wrong and not where
    // to change it.
    expect(find.text('color_dark_android'), findsWidgets);
    expect(find.text('#000000'), findsWidgets);
  });

  testWidgets('says so when a config file is not usable', (tester) async {
    // Keys at the root rather than under `flutter_native_splash:` — the
    // generator throws on this, so the panel must not render an empty matrix.
    write('flutter_native_splash.yaml', '''
color: "FFFFFF"
''');
    await mount(tester);

    expect(find.byType(SplashVariantTile), findsNothing);
    expect(find.textContaining('flutter_native_splash:'), findsOneWidget);
  });

  testWidgets('explains itself when there is no config at all', (tester) async {
    await mount(tester);
    expect(
      find.textContaining('No flutter_native_splash config'),
      findsOneWidget,
    );
  });

  testWidgets('lists the problems below the matrix', (tester) async {
    tester.view.physicalSize = const Size(2400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/gone.png
''');

    await mount(tester);

    expect(find.text('Problems'), findsOneWidget);
    expect(find.textContaining('was not found'), findsOneWidget);
    expect(find.textContaining('stops `create` from running'), findsWidgets);
  });
}
