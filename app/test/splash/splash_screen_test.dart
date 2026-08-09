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

  group('fixing a problem from the panel', () {
    testWidgets('the button says the edit, and making it clears the row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      write('flutter_native_splash.yaml', '''
# Kept out of the pubspec on purpose.
flutter_native_splash:
  color: "FFFFFF"
  colour_dark: "101418"
''');

      var c = await mount(tester);
      var button = find.byKey(const ValueKey('fix:rename:colour_dark'));
      // The label is the edit, which is what makes a confirmation dialog
      // pointless here — it would say strictly less than the button does.
      expect(button, findsOneWidget);
      expect(find.text('Rename to "color_dark"'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(button);
        // Writing the file is real IO, and a widget test runs on a fake clock
        // that would never let it finish. Waiting on the work rather than on a
        // pump — or on a sleep long enough to look safe.
        while (c.scanFor('.')!.main!.config.raw.containsKey('colour_dark')) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();

      // The file, not just the model: this is the first thing in the plugin
      // that writes to the user's project.
      var after = File(
        p.join(root.path, 'flutter_native_splash.yaml'),
      ).readAsStringSync();
      expect(after, contains('# Kept out of the pubspec on purpose.'));
      expect(after, contains('color_dark: "101418"'));
      expect(after, isNot(contains('colour_dark')));

      // And the panel has already caught up — the action invalidates the scan,
      // so the row it was on is gone without anything being reloaded by hand.
      expect(button, findsNothing);
      expect(c.scanFor('.')!.main!.config.raw['color_dark'], '101418');
    });

    testWidgets('a problem with no fix gets no button', (tester) async {
      tester.view.physicalSize = const Size(2400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/gone.png
''');

      await mount(tester);

      expect(find.textContaining('was not found'), findsOneWidget);
      // Nothing here can invent the missing file, and a button that pretended
      // otherwise would be the reason nobody trusts the other ones.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('fix:'),
        ),
        findsNothing,
      );
    });
  });

  group('editing the value you are looking at', () {
    testWidgets('the caption opens an editor aimed at the key that won', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
''');

      await mount(tester);

      // Every cell whose colour came from `color_dark` offers the same edit.
      await tester.tap(find.byKey(const ValueKey('edit:color_dark')).first);
      await tester.pumpAndSettle();

      // Scoped to the dialog: the same key names are printed on the eight tiles
      // still sitting behind it.
      Finder inDialog(String text) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(text),
      );

      expect(find.text('Set the background'), findsOneWidget);
      // The key that won is the default and it is first; narrowing to one
      // platform is the second row, not the behaviour.
      expect(inDialog('color_dark'), findsOneWidget);
      expect(inDialog('where it is set now'), findsOneWidget);
      expect(inDialog('color_dark_android'), findsOneWidget);
      expect(inDialog('only for Android'), findsOneWidget);

      var selected = tester
          .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
          .toList();
      expect(selected.first.value, 'color_dark');
      // ignore: deprecated_member_use
      expect(selected.first.groupValue, 'color_dark');
    });

    testWidgets('a colour the generator would reject cannot be saved', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');

      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('edit:color')).first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'FFFFFFFF');
      await tester.pumpAndSettle();

      expect(find.textContaining('Six hex digits'), findsOneWidget);
      var save = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(save.onPressed, isNull);
    });

    testWidgets('saving writes the file and the tiles redraw', (tester) async {
      tester.view.physicalSize = const Size(2400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');

      var c = await mount(tester);
      await tester.tap(find.byKey(const ValueKey('edit:color')).first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '#1e1e1e');
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byType(FilledButton));
        while (c.scanFor('.')!.main!.config.raw['color'] == 'FFFFFF') {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();

      // Normalised on the way in: the generator accepts `#1e1e1e` but the rest
      // of the config is written as six bare uppercase digits.
      expect(c.scanFor('.')!.main!.config.raw['color'], '1E1E1E');
      expect(
        File(
          p.join(root.path, 'flutter_native_splash.yaml'),
        ).readAsStringSync(),
        contains('1E1E1E'),
      );
      expect(find.text('#1E1E1E'), findsWidgets);
    });
  });

  group('the image studio', () {
    testWidgets('the Android 12 warning is a door into it', (tester) async {
      tester.view.physicalSize = const Size(2400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      writePng('assets/logo.png', 1024, 1024);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  image: assets/logo.png
''');

      await mount(tester);

      // Somebody reading "there is no android_12 image" is exactly the person
      // who needs the 1152 canvas. Making them find a menu is how a tool ends
      // up unused.
      expect(
        find.textContaining(
          'every device from Android 12 on shows your '
          'launcher icon',
        ),
        findsOneWidget,
      );
      var door = find.byKey(const ValueKey('studio:android_12.image'));
      expect(door, findsOneWidget);

      await tester.tap(door);
      await tester.pumpAndSettle();

      expect(find.text('Prepare an image'), findsOneWidget);
      // Opened on the target the warning was about, not on a default.
      expect(
        find.widgetWithText(ChoiceChip, 'Android 12 icon'),
        findsOneWidget,
      );
      expect(find.text('Write it and set android_12.image'), findsOneWidget);
    });

    testWidgets('an info-toned note gets no studio offer', (tester) async {
      tester.view.physicalSize = const Size(2400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // "This .jpg will be converted" names an image key too, and a "make one"
      // button under it would be an offer nobody asked for. Sized correctly on
      // purpose: a wrong-sized icon is a `warn` and *does* deserve the offer,
      // and the point here is that tone decides it rather than the key.
      File(p.join(root.path, 'assets/logo.jpg'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(img.encodeJpg(img.Image(width: 1152, height: 1152)));
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  android_12:
    image: assets/logo.jpg
''');

      await mount(tester);

      expect(find.textContaining('converts it to PNG'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('studio:android_12.image')),
        findsNothing,
      );
    });

    testWidgets('the header offers it whether or not anything is wrong', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      writePng('assets/logo.png', 1152, 1152);
      write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
  color_dark: "101418"
  image: assets/logo.png
  image_dark: assets/logo.png
  android_12:
    image: assets/logo.png
    image_dark: assets/logo.png
''');

      await mount(tester);

      await tester.tap(find.text('Prepare an image…'));
      await tester.pumpAndSettle();
      expect(find.text('Prepare an image'), findsOneWidget);
      // Nothing chosen yet, so there is nothing to write.
      var apply = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(apply.onPressed, isNull);
    });
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

    testWidgets('shows what shipped beside it once generated', (tester) async {
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

      expect(find.text('What shipped'), findsOneWidget);
      // Two pictures: the prediction and the recomposition, same renderer.
      expect(find.byType(SplashRender), findsNWidgets(2));
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
      expect(find.textContaining('Only Android can be read back'), findsOne);
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

      expect(find.text('What shipped'), findsNothing);
      expect(
        find.textContaining('Nothing has been generated yet'),
        findsOneWidget,
      );
      // And it names the command rather than a button, because the question is
      // "what have I not done", not "which thing do I press".
      expect(
        find.textContaining('flutter_native_splash:create'),
        findsOneWidget,
      );
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
