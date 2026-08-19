import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';

/// Where an attachment lands: riding the next capture, trailing onto the
/// last one when the flow ends with it, and dropped only when nothing was
/// captured at all.
void main() {
  var captures = <ScenarioStepCapture>[];
  var trailing = <List<ScenarioAttachment>>[];
  setUp(() {
    captures = [];
    trailing = [];
    scenarioRunListener = captures.add;
    scenarioTrailingAttachmentsListener = trailing.add;
  });
  tearDown(() {
    scenarioRunListener = null;
    scenarioTrailingAttachmentsListener = null;
  });

  scenario('an attachment rides the next capture', (s) async {
    await s.pumpWidget(const _App());
    s.attach('doc', [1, 2, 3], mimeType: 'application/octet-stream');
    await s.screen('Done');

    expect(captures.last.attachments.single.name, 'doc');
  });

  scenario('a notification is an attachment that decodes back', (s) async {
    await s.pumpWidget(const _App());
    s.notification('Your order shipped', title: 'Shop', appName: 'shop');
    await s.screen('Done');

    var attachment = captures.last.attachments.single;
    expect(attachment.mimeType, ScenarioNotification.mimeType);
    var decoded = ScenarioNotification.decode(attachment.bytes)!;
    expect(decoded.body, 'Your order shipped');
    expect(decoded.title, 'Shop');
    expect(decoded.appName, 'shop');
  });

  group('attached after the last capture', () {
    scenario('the flow ends with its document', (s) async {
      await s.pumpWidget(const _App());
      s.attach('receipt', [1], fileName: 'receipt.txt');
    });
    tearDown(() {
      expect(trailing.single.single.name, 'receipt');
      expect(captures, isNotEmpty);
      expect(captures.last.attachments, isEmpty);
    });
  });

  group('attached with no capture at all', () {
    scenario('there is no story to end, so it goes nowhere', (s) async {
      s.attach('orphan', [1]);
    });
    tearDown(() => expect(trailing, isEmpty));
  });

  group('attached after a split', () {
    scenario('each branch ends its own story', (s) async {
      await s.pumpWidget(const _App());
      await s.split({
        'left': () => s.screen('Left'),
        'right': () => s.screen('Right'),
      });
      s.attach('epilogue', [1]);
    });
    // One flush per replay, each landing on that branch's own last step —
    // the same shape the branch's tail captures have.
    tearDown(() => expect(trailing, hasLength(2)));
  });
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Hello'))),
    );
  }
}
