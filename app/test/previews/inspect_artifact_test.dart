import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/plugins/native/previews_results.dart';

/// `inspect --screenshot` has to hand back the *picture*, not a path to one.
///
/// `screenshot` returns an `Artifact` as its whole value, so every surface that
/// can render an image renders it. `inspect` carries one in a field instead —
/// its answer is the reading, and the picture is part of it — and a field
/// reaches `JobResult.artifacts` only through [ProducesArtifacts]. Until it
/// declared that, the flag came back as a path and nothing else: the caller
/// most likely to hit it being the one that took the action's own advice and
/// folded the picture into the render it was already paying for.
void main() {
  Artifact shot() => Artifact(
    kind: Artifact.png,
    path: 'build/catalog/screenshots/buttons.png',
    address: Address(
      worktree: 'wt',
      plugin: 'flutterware.previews',
      segments: const ['.', 'demo/buttons.dart#buttons'],
    ),
  );

  CatalogInspectResult inspected({Artifact? screenshot}) =>
      CatalogInspectResult(
        entry: 'demo/buttons.dart#buttons',
        address: 'fw:///worktrees/wt/flutterware.previews/./demo',
        readFrom: 'render',
        lens: 'act',
        ok: true,
        errors: const [],
        screenshot: screenshot,
      );

  test('the picture is offered where a renderer looks for it', () {
    var picture = shot();
    expect(inspected(screenshot: picture).artifacts, [picture]);
  });

  test('a reading with no picture offers none', () {
    // Not an empty picture — no picture. Every flag but `--screenshot` answers
    // off the frame without writing one.
    expect(inspected().artifacts, isEmpty);
  });

  test('the artifact is not sent twice', () {
    // It is already on the wire under `screenshot`; `artifacts` is the same
    // value by the route a renderer looks down, and duplicating it would put
    // the whole address and meta map in the reply a second time.
    expect(
      inspected(screenshot: shot()).toJson(),
      isNot(contains('artifacts')),
    );
    expect(inspected(screenshot: shot()).toJson(), contains('screenshot'));
  });
}
