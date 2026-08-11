import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/channels.dart';
import 'package:flutterware/devbar.dart';

class _FlagsPlugin implements DevbarPlugin, DevbarPanelSource {
  @override
  String get panelId => 'flags';

  @override
  String get panelLabel => 'Feature flags';

  @override
  void describePanel(Panel panel) => panel.feed('changes', 'Changes');

  @override
  void dispose() {}
}

/// **The gate, in its own file because it needs an app nobody is watching.**
///
/// `GuestChannels.install()` is process-wide and cannot be undone, so this has
/// to run in an isolate where it has not happened — which is what a separate
/// test file buys. Merged into `bridge_test.dart` it would silently become a
/// test of whatever ran first.
void main() {
  testWidgets('a devbar outside flutterware mirrors nothing', (tester) async {
    expect(GuestChannels.installed, isFalse);

    await tester.pumpWidget(
      Devbar(
        plugins: [(_) => _FlagsPlugin()],
        headless: true,
        child: const SizedBox(),
      ),
    );
    await tester.pumpAndSettle();

    // The plugin loaded and the devbar hosts it; there is simply no reader, so
    // no panel and no channel were created.
    expect(GuestChannels.panels.descriptors, isEmpty);
    expect(GuestChannels.core.channels, isNot(contains('flags')));
  });
}
