import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
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
import 'package:flutterware_app/src/splash/model/studio.dart';
import 'package:flutterware_app/src/splash/model/surface.dart';
import 'package:flutterware_app/src/splash/ui/splash_render.dart';
import 'package:flutterware_app/src/splash/ui/studio_dialog.dart';
import 'package:flutterware_app/src/ui/theme.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The studio's whole loop: pick a file, see it cropped, write it, and have the
/// config point at it.
///
/// The picker is stood in for at the platform interface rather than through a
/// parameter on the dialog — a test seam in the production API would be a second
/// way to open a file that only the tests use.
class _FakePicker extends FileSelectorPlatform with MockPlatformInterfaceMixin {
  _FakePicker(this.path);

  final String? path;
  String? askedIn;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    askedIn = initialDirectory;
    return path == null ? null : XFile(path!);
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => const [];
}

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
      pollInterval: Duration.zero,
    );
  }

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String writePng(String relative, int width, int height) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      img.encodePng(img.Image(width: width, height: height, numChannels: 4)),
    );
    return file.path;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('splash_studio_dialog');
    write('pubspec.yaml', '''
name: sample
environment:
  sdk: ^3.0.0
dev_dependencies:
  flutter_native_splash: ^2.4.0
''');
    write('flutter_native_splash.yaml', '''
flutter_native_splash:
  color: "FFFFFF"
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<SplashCore> open(
    WidgetTester tester, {
    SplashStudioTarget target = SplashStudioTarget.android12Icon,
    SplashTheme theme = SplashTheme.light,
  }) async {
    var c = core();
    await c.computeAll();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSplashStudioDialog(
                context,
                core: c,
                package: '.',
                config: c.scanFor('.')!.main!,
                target: target,
                theme: theme,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('picking a source draws it, then writing it sets the key', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var source = writePng('art/logo.png', 2048, 2048);
    var picker = _FakePicker(source);
    FileSelectorPlatform.instance = picker;

    var c = await open(tester);

    // Nothing to write before a source is chosen.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Choose an image…'));
      // The preview is a real encoded PNG written to a temp file, so it needs
      // the actual event loop rather than a pumped frame.
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.byType(SplashRender).evaluate().isNotEmpty) break;
      }
    });
    await tester.pumpAndSettle();

    // Opened where the project is, not wherever the OS last was.
    expect(picker.askedIn, root.path);
    expect(find.textContaining('logo.png · 2048×2048'), findsOneWidget);
    // The numbers, said out loud — the whole reason this exists.
    expect(find.textContaining('1152×1152'), findsOneWidget);
    expect(find.textContaining('768px circle'), findsOneWidget);
    // A live tile drawn from the encoded file, not from a second drawing path.
    expect(find.byType(SplashRender), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Write it and set android_12.image'));
      while (c.scanFor('.')!.main!.config.android12Section['image'] == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();

    var written =
        c.scanFor('.')!.main!.config.android12Section['image']! as String;
    // This config references no images at all, so there is no convention to
    // follow and the fallback is the only guess in the whole resolution.
    expect(p.dirname(written), p.join('assets', 'splash'));
    var png = img.decodePng(
      File(p.join(root.path, written)).readAsBytesSync(),
    )!;
    expect((png.width, png.height), (1152, 1152));
    // And the dialog is gone.
    expect(find.text('Prepare an image'), findsNothing);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    FileSelectorPlatform.instance = _FakePicker(null);
    await open(tester);

    await tester.tap(find.text('Choose an image…'));
    await tester.pumpAndSettle();

    expect(find.text('Choose an image…'), findsOneWidget);
    expect(find.byType(SplashRender), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('a file it cannot decode is said so, not thrown', (tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    write('art/broken.png', 'not a png at all');
    FileSelectorPlatform.instance = _FakePicker(
      p.join(root.path, 'art', 'broken.png'),
    );
    await open(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Choose an image…'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be decoded'), findsOneWidget);
  });

  testWidgets('the dark theme writes the dark key', (tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    FileSelectorPlatform.instance = _FakePicker(
      writePng('art/logo.png', 1024, 1024),
    );
    await open(tester, theme: SplashTheme.dark);

    expect(find.text('Write it and set android_12.image_dark'), findsOneWidget);
  });
}
