// What the fixture scene may place, declared the way an app declares it.
//
// The test's second grader reads this: the generator writes `scene_args.dart`
// from it, the compiler checks `sample.scene.dart` against that, and the
// parser reads the same file back.
import 'package:flutterware/scene_authoring.dart';

import 'sample_widget.dart' as app;

final sceneExternals = [
  ExternalWidget(
    'SampleChip',
    args: [const Arg<String>('label', 'chip'), const Arg<double>('weight')],
    build: (a) => app.SampleChip(label: a.text('label') ?? 'chip'),
  ),
];
