import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:flutterware_app/src/run/native/adb_driver.dart';
import 'package:flutterware_app/src/run/native/native_driver.dart';
import 'package:flutterware_app/src/run/native/native_session.dart';
import 'package:path/path.dart' as p;

/// A dump from the Android emulator this feature was built against — the real
/// bytes, trimmed to one screen: a Flutter app whose semantics the dump armed
/// by itself (that is why Flutter's texts are in a *platform* tree at all), a
/// switch, a button, and a webview with its DOM inside.
const _dump = '''
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" package="com.example.app" content-desc="" bounds="[0,0][1080,2400]">
    <node index="0" text="" class="android.view.View" package="com.example.app" content-desc="Flutter Demo Home Page" clickable="false" bounds="[42,100][688,173]" />
    <node index="1" text="" class="android.view.View" package="com.example.app" content-desc="You have pushed the button&#10;0" bounds="[53,473][1028,756]" />
    <node index="2" text="" class="android.widget.Switch" package="com.example.app" checkable="true" checked="true" clickable="true" bounds="[53,945][1028,1071]" />
    <node index="3" text="" class="android.widget.Button" package="com.example.app" content-desc="OK" clickable="true" bounds="[53,1071][1028,1197]" />
    <node index="4" text="" class="android.widget.Button" package="com.example.app" content-desc="Increment" clickable="true" enabled="false" bounds="[891,2148][1038,2295]" />
    <node index="5" text="" class="android.webkit.WebView" package="com.example.app" bounds="[53,1292][1028,2342]">
      <node index="0" text="Web Button" class="android.widget.Button" package="com.example.app" clickable="true" bounds="[74,1557][297,1617]" />
    </node>
  </node>
</hierarchy>
''';

void main() {
  group('the Android dump becomes an addressable tree', () {
    late NativeObservation observation;

    setUp(() {
      observation = AdbNativeDriver.debugParse(_dump);
    });

    test('content-desc and text both read as the label', () {
      // Android puts a Flutter semantics label in content-desc and a webview's
      // DOM text in text; an agent should not have to know which.
      expect(
        observation.texts,
        containsAll(<String>['Flutter Demo Home Page', 'OK', 'Web Button']),
      );
    });

    test('a webview publishes its DOM as ordinary nodes', () {
      // The finding that made Android the cheap platform: with JavaScript on,
      // the page's own buttons are in the platform tree, tappable by text.
      var button = NativeTarget.parse('Web Button').resolve(observation);
      expect(button.role, 'android.widget.Button');
      expect(button.bounds!.centerX, 185.5);
    });

    test('state rides along', () {
      var toggle = NativeTarget.parse(
        '{"role": "android.widget.Switch"}',
      ).resolve(observation);
      expect(toggle.checked, isTrue);
      expect(toggle.clickable, isTrue);
    });

    test('disabled is reported, not hidden', () {
      var fab = NativeTarget.parse('Increment').resolve(observation);
      expect(fab.enabled, isFalse);
    });

    test('layout wrappers collapse, addressable nodes never do', () {
      // The dump wraps everything in FrameLayouts nobody would call an
      // element. Collapsing them is only safe because it drops nothing that
      // can be addressed — so the count is what carries the guarantee.
      expect(observation.speaking.length, 6);
      expect(
        observation.nodes.map((node) => node.role),
        contains('android.widget.FrameLayout'),
        reason:
            'the root frame has several children, so nothing collapses '
            'it — only single-child wrappers go',
      );
    });

    test('a platform view keeps its own name when it wraps one child', () {
      // The whole reason an agent reaches for this layer is that Flutter could
      // not show it what a webview contains; erasing the word `WebView` while
      // collapsing wrappers would take away the explanation.
      var webview = NativeTarget.parse(
        '{"role": "android.webkit.WebView"}',
      ).resolve(observation);
      expect(webview.children.single.label, 'Web Button');
    });

    test('bounds are physical pixels, the space taps use', () {
      var ok = NativeTarget.parse('OK').resolve(observation);
      expect(ok.bounds!.centerX, 540.5);
      expect(ok.bounds!.centerY, 1134);
    });
  });

  group('targets refuse the way the drive layer refuses', () {
    late NativeObservation observation;

    setUp(() {
      observation = AdbNativeDriver.debugParse(_dump);
    });

    test('nothing matching lists what the layer does see', () {
      expect(
        () => NativeTarget.parse('Nope').resolve(observation),
        throwsA(
          isA<NativeRefusal>()
              .having((e) => e.failure, 'failure', 'notFound')
              .having((e) => e.message, 'message', contains('"OK"')),
        ),
      );
    });

    test('several matches refuse and teach nth, never pick one', () {
      var twice = _dump
          .replaceFirst('content-desc="OK"', 'content-desc="Go"')
          .replaceFirst('content-desc="Increment"', 'content-desc="Go"');
      var screen = AdbNativeDriver.debugParse(twice);
      expect(
        () => NativeTarget.parse('Go').resolve(screen),
        throwsA(
          isA<NativeRefusal>()
              .having((e) => e.failure, 'failure', 'multiple')
              .having((e) => e.message, 'message', contains('"nth"')),
        ),
      );
      expect(
        NativeTarget.parse(
          '{"nth": {"target": "Go", "index": 1}}',
        ).resolve(screen).bounds!.centerY,
        2221.5,
      );
    });

    test('a Flutter-only target says so instead of matching nothing', () {
      // The failure this avoids is subtle: {"key": …} would match no native
      // node, and a plain notFound would read as "the button is missing".
      for (var spec in const [
        '{"key": "cart"}',
        '{"tooltip": "Delete"}',
        '{"within": {"scope": "a", "child": "b"}}',
      ]) {
        expect(
          () => NativeTarget.parse(spec),
          throwsA(
            isA<NativeRefusal>()
                .having((e) => e.failure, 'failure', 'unsupported')
                .having((e) => e.message, 'message', contains('layer')),
          ),
          reason: spec,
        );
      }
    });

    test('containing matches a truncated label the way the cap teaches', () {
      var target = NativeTarget.parse('{"containing": "You have pushed"}');
      expect(target.resolve(observation).label, startsWith('You have pushed'));
    });

    test('a point target resolves to no node at all', () {
      // The webview escape hatch: `at` never consults the tree, because the
      // whole reason to use it is that the thing you want is not in one.
      var target = NativeTarget.parse('{"at": {"x": 10, "y": 20}}');
      expect(target.point, (10.0, 20.0));
      expect(target.description, contains('10'));
    });

    test('a zero-sized node is not addressable', () {
      var collapsed = _dump.replaceFirst(
        'bounds="[53,1071][1028,1197]"',
        'bounds="[53,1071][53,1071]"',
      );
      expect(
        () => NativeTarget.parse(
          'OK',
        ).resolve(AdbNativeDriver.debugParse(collapsed)),
        throwsA(isA<NativeRefusal>()),
      );
    });
  });

  group('the macOS bundle is the one that is running', () {
    late Directory worktree;

    /// A worktree whose `Products` holds every configuration in
    /// [configurations], each with an `app.app` in it.
    String products(List<String> configurations) {
      var root = p.join(
        worktree.path,
        'app',
        'build',
        'macos',
        'Build',
        'Products',
      );
      for (var configuration in configurations) {
        Directory(
          p.join(root, configuration, 'app.app', 'Contents', 'MacOS'),
        ).createSync(recursive: true);
      }
      return root;
    }

    String executable(String configuration) => p.join(
      products(const []),
      configuration,
      'app.app',
      'Contents',
      'MacOS',
      'app',
    );

    NativeSession session({String? flavor}) => NativeSession(
      RunHandle(
        worktree: worktree.path,
        worktreeName: 'wt',
        device: 'macos',
        entrypoint: 'lib/main_dev.dart',
        package: 'app',
        flavor: flavor,
        launcherPid: 1,
        startedAt: DateTime.utc(2026),
      ),
    );

    setUp(() {
      worktree = Directory.systemTemp.createTempSync('fw_native_bundle');
    });

    tearDown(() => worktree.deleteSync(recursive: true));

    test('a Release directory does not outrank the running Debug app', () async {
      // The bug, exactly: a checkout that has ever been released keeps Release
      // next to Debug, and walking `Products` in filesystem order handed the
      // helper a bundle nothing was running from — so `layer: native` refused
      // with notFound on the one case it exists for, the debug inner loop.
      // Only Release is on disk, so nothing about the directory can produce
      // this answer: the process table is what decides, and a scan of any
      // ordering has one wrong bundle to offer.
      products(const ['Release']);
      expect(
        await session().macosBundle(executables: [executable('Debug')]),
        endsWith('/Debug/app.app'),
      );
    });

    test('a process in another worktree is not this run', () async {
      // Several worktrees run identically-named apps at once; only the path
      // separates them, which is why the process table is read by path.
      products(const ['Debug']);
      var elsewhere = p.join(
        Directory.systemTemp.path,
        'other',
        'app',
        'build',
        'macos',
        'Build',
        'Products',
        'Debug',
        'app.app',
        'Contents',
        'MacOS',
        'app',
      );
      expect(
        await session().macosBundle(executables: [elsewhere]),
        endsWith('/Debug/app.app'),
        reason:
            'the other worktree contributes nothing, so this falls through '
            'to the build directory rather than attaching to it',
      );
    });

    test(
      'nothing running falls back to the configuration a launch uses',
      () async {
        // Still building, or already stopped. `flutter run` takes no mode flag
        // here, so Debug is what a launch from this plugin would have written.
        products(const ['Release', 'Debug']);
        expect(
          await session().macosBundle(executables: const []),
          endsWith('/Debug/app.app'),
        );
      },
    );

    test('a flavored run names its own configuration', () async {
      products(const ['Debug', 'Debug-staging', 'Release-staging']);
      expect(
        await session(flavor: 'staging').macosBundle(executables: const []),
        endsWith('/Debug-staging/app.app'),
      );
    });

    test('an unbuilt worktree has no bundle to name', () async {
      expect(await session().macosBundle(executables: const []), isNull);
    });

    test('the walk up stops at the bundle, not at the products root', () {
      expect(
        NativeSession.runningBundleUnder('/w/Products', const [
          '/w/Products/Debug/app.app/Contents/MacOS/app',
        ]),
        '/w/Products/Debug/app.app',
      );
      expect(
        NativeSession.runningBundleUnder('/w/Products', const [
          '/w/Products/Debug/some_tool',
        ]),
        isNull,
        reason: 'a loose executable is in no bundle at all',
      );
    });

    test('configuration preference is order-independent', () {
      expect(
        NativeSession.preferredConfiguration(const ['Release', 'Debug']),
        'Debug',
      );
      expect(
        NativeSession.preferredConfiguration(const ['Debug', 'Release']),
        'Debug',
      );
      expect(
        NativeSession.preferredConfiguration(const ['Release']),
        isNull,
        reason:
            'this plugin never launches release, so naming one would be a '
            'guess dressed as an answer',
      );
    });
  });

  test('a long label is capped, with the ellipsis the refusal teaches', () {
    var essay = 'x' * (nativeTextCap + 50);
    var screen = AdbNativeDriver.debugParse(
      _dump.replaceFirst('content-desc="OK"', 'content-desc="$essay"'),
    );
    var capped = screen.texts.firstWhere((text) => text.startsWith('xxx'));
    expect(capped.length, nativeTextCap + 1);
    expect(capped, endsWith('…'));
  });
}
