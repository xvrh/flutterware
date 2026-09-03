// Emit a scene file from its own parse, so the canonical spelling of a
// hand-written one can be read off. Development tool; not wired anywhere.
import 'dart:io';

import 'package:flutterware_app/src/scene/scene_file.dart';

void main(List<String> args) {
  var source = File(args.single).readAsStringSync();
  var parsed = parseSceneFile(source);
  if (!parsed.ok) {
    for (var refusal in parsed.refusals) {
      stderr.writeln('REFUSED $refusal');
    }
    exit(1);
  }
  var out = emitSceneFile(
    parsed.doc!,
    className: parsed.className!,
    motions: parsed.motions,
  );
  var again = parseSceneFile(out);
  for (var refusal in again.refusals) {
    stderr.writeln('RE-REFUSED $refusal');
  }
  if (again.ok) {
    var twice = emitSceneFile(
      again.doc!,
      className: again.className!,
      motions: again.motions,
    );
    stderr.writeln(out == twice ? 'STABLE' : 'UNSTABLE');
  }
  stdout.write(out);
}
