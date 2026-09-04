// The shipped app's whole loop: a compiled scene, a compiled motion, and a
// clock — no document read from anywhere, no lookup by name, no editor.
//
// This is the path an app actually writes, and until now nothing pumped it:
// the pieces were each tested apart, and `playTimeline` was only ever parked
// by hand at a time.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import 'sample.scene.dart';

/// What an app writes. The definition is a FIELD, not something built in
/// `build()`: a new `SampleScene()` is new nodes, and the player would go on
/// writing its fx onto the ones that went away.
class _Banner extends StatefulWidget {
  const _Banner();

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  final scene = SampleScene();
  late final motion = SampleIntro(scene);
  late final playable = playTimeline(motion.timeline);
  late final player = MotionPlayer(playable, vsync: this);

  @override
  void initState() {
    super.initState();
    player.play();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SceneView(scene.scene);
}

void main() {
  testWidgets('a compiled scene plays its compiled motion', (tester) async {
    var widget = const _Banner();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(alignment: Alignment.topLeft, child: widget),
      ),
    );
    var state = tester.state<_BannerState>(find.byWidget(widget));

    expect(state.playable.duration, const Duration(milliseconds: 360));
    expect(state.scene.title.fxRendered('opacity'), 0.0);

    // The clock is real: pumping frames is what moves it, and the view
    // redraws because an fx write notifies the document it wrote into.
    await tester.pump(const Duration(milliseconds: 130));
    await tester.pump(const Duration(milliseconds: 130));
    var mid = state.scene.title.fxRendered('opacity') as double;
    expect(mid, greaterThan(0.0));
    expect(mid, lessThanOrEqualTo(1.0));

    await tester.pump(const Duration(milliseconds: 300));
    expect(state.scene.title.fxRendered('opacity'), 1.0);
    expect(state.player.status, MotionPlayerStatus.completed);

    // The authored plane was never touched — stopping drops the fx and the
    // scene is back to what the file says.
    state.player.stop();
    expect(state.scene.title.fxRendered('opacity'), 1.0);
    expect(state.scene.title.opacity, 1.0);
  });
}
