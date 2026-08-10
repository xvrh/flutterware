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
import 'package:flutterware_app/src/splash/model/surface.dart';
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

  Future<SplashCore> mount(
    WidgetTester tester, {
    SplashSurface? surface,
    SplashTheme? theme,
    VoidCallback? onShowAll,
  }) async {
    var c = core();
    await c.computeAll();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          // Subscribed the way the plugin subscribes. `SplashScreen` is
          // stateless and redraws only when something above it says to — in
          // production that is `NativePlugin`'s `AnimatedBuilder`, and a test
          // that skipped it would be asserting against a panel that can never
          // update.
          body: StreamBuilder<int>(
            stream: c.changes.stream,
            builder: (context, _) => SplashScreen(
              c,
              package: '.',
              surface: surface,
              theme: theme,
              onShowAll: onShowAll,
            ),
          ),
        ),
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

  group('one cell at a time', () {
    setUp(() {
      writePng('assets/logo.png', 1024, 1024);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
  image: assets/logo.png
  image_dark: assets/logo.png
''');
    });

    testWidgets('an address naming both axes shows that cell alone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await mount(
        tester,
        surface: SplashSurface.android,
        theme: SplashTheme.dark,
      );

      // One prediction, not eight thumbnails with a border round one of them.
      expect(find.byType(SplashVariantTile), findsOneWidget);
      expect(find.text('Android · Dark'), findsWidgets);
    });

    testWidgets('shows the generated files, alone, once generated', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      write('android/app/src/main/res/drawable/launch_background.xml', '''
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <bitmap android:gravity="fill" android:src="@drawable/background" />
    </item>
    <item>
        <bitmap android:gravity="center" android:src="@drawable/splash" />
    </item>
</layer-list>
''');
      writePng(
        'android/app/src/main/res/drawable-xxxhdpi/splash.png',
        1024,
        1024,
      );
      writePng('android/app/src/main/res/drawable/background.png', 4, 4);

      await mount(
        tester,
        surface: SplashSurface.android,
        theme: SplashTheme.light,
      );

      // One picture, not two. Showing the prediction beside the readback made
      // the reader arbitrate between them, which is the panel's job.
      expect(find.byType(SplashRender), findsOneWidget);
      expect(find.text('From the generated files'), findsOneWidget);
      expect(find.textContaining('Prediction'), findsNothing);
    });

    testWidgets('says why there is nothing to compare against', (tester) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Generated, so "nothing has been generated" is off the table and the
      // real iOS answer is the one that has to show.
      write(
        'ios/Runner/Assets.xcassets/LaunchBackground.imageset/'
            'Contents.json',
        '{}',
      );
      writePng('android/app/src/main/res/drawable/background.png', 1, 1);

      await mount(tester, surface: SplashSurface.ios, theme: SplashTheme.light);

      // Never "nothing generated" for iOS — there may be plenty on disk, we
      // simply cannot read a storyboard back.
      expect(find.textContaining('cannot be read back'), findsOne);
    });

    testWidgets('a project that has never run create is told so, not shown a '
        'black rectangle', (tester) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // What `flutter create` leaves in every project. Reading it as generator
      // output drew an empty composition — no colour, no layers — as a black
      // rectangle labelled "What shipped", which is a picture of a splash no
      // device would ever produce.
      write('android/app/src/main/res/drawable/launch_background.xml', '''
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@android:color/white" />
</layer-list>
''');

      await mount(
        tester,
        surface: SplashSurface.android,
        theme: SplashTheme.light,
      );

      expect(find.text('From the generated files'), findsNothing);
      expect(
        find.textContaining('Nothing has been generated yet'),
        findsOneWidget,
      );
      // And the command is on offer, not only named: a reader who has just been
      // told the picture is a guess wants the one action that makes it real.
      expect(find.text('Run flutter_native_splash:create'), findsOneWidget);
    });

    testWidgets('offers the way back to the matrix', (tester) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var showedAll = false;
      await mount(
        tester,
        surface: SplashSurface.web,
        theme: SplashTheme.light,
        onShowAll: () => showedAll = true,
      );

      // Back sits before the title, where every reader's eye goes for it.
      await tester.tap(find.text('← All eight'));
      expect(showedAll, isTrue);
    });
  });
}
