import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/utils/image_clipboard.dart';

/// What the Swift side is asked, and what it is believed when it answers.
///
/// The pasteboard write itself cannot be reached from a test — it is
/// `NSPasteboard` in the app's own runner. What *can* drift without anything
/// noticing is the contract between the two halves: a renamed method or a
/// renamed argument key compiles on both sides and fails only under a pointer.
/// That is what these pin.
void main() {
  // Up here rather than inside `answerWith`, which is where it used to happen:
  // off macOS every test that calls it is skipped, and then `tearDown` reached
  // for a binding nothing had built.
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutterware/clipboard');
  var png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

  late List<MethodCall> calls;

  void answerWith(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  // **Three of the four only have something to pin on macOS.** `setPng`
  // refuses before it reaches the channel anywhere else, so off macOS they
  // would be asserting the refusal rather than the contract. The last test is
  // the one that runs everywhere, and it is the one that says so.
  var noChannel = ImageClipboard.isSupported
      ? null
      : 'the clipboard channel is implemented in the macOS runner only';

  setUp(() => calls = []);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('the bytes reach the platform under the name it reads them by', () async {
    answerWith((_) => true);
    await ImageClipboard.setPng(png);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setImage');
    // A typed list, not a plain List<int>: the standard codec sends the latter
    // as an int array, which `FlutterStandardTypedData` on the Swift side
    // declines — and declines at run time, in the one path no test covers.
    var argument = (calls.single.arguments as Map)['png'] as Uint8List;
    expect(argument, png);
  }, skip: noChannel);

  test('a platform that says it did not write is a failure, not a shrug', () async {
    answerWith((_) => false);
    // The alternative is a copy that reports success and puts nothing on the
    // clipboard, which is discovered at the paste — by then nowhere near here.
    await expectLater(ImageClipboard.setPng(png), throwsA(isA<StateError>()));
  }, skip: noChannel);

  test('an error from the platform is not swallowed', () async {
    answerWith((_) => throw PlatformException(code: 'decode_failed'));
    await expectLater(
      ImageClipboard.setPng(png),
      throwsA(isA<PlatformException>()),
    );
  }, skip: noChannel);

  test('support tracks where the preview can actually exist', () {
    // The picture being copied is composited by the embedder host, which is
    // Metal and IOSurface throughout. Anywhere else there is nothing to copy,
    // so this is the real answer rather than a placeholder.
    expect(ImageClipboard.isSupported, Platform.isMacOS);
  });
}
