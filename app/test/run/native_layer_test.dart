import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/native/adb_driver.dart';
import 'package:flutterware_app/src/run/native/native_driver.dart';

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
