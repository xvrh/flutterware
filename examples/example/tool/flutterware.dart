import 'dart:io';

import 'package:flutterware/plugins.dart';

/// The sample project, configured as a project in its own right.
///
/// It is also a member of flutterware's own pub workspace, which is why the
/// repo root has a config too. Opening this directory gives you what a user
/// with a single Flutter app sees; opening the repo root gives you the monorepo
/// case. Neither is a special mode — a config is whatever `tool/flutterware.dart`
/// is found beside the directory you opened.
const app = Pkg('.');

/// The dart this config is running under — see the [DevStack] note below.
final dart = Platform.resolvedExecutable;

void main() => Flutterware.configure((fw) {
  fw.use(Dependencies(packages: [.new(app)]));
  fw.use(Assets(packages: [.new(app)]));
  fw.use(NativeSplash(packages: [.new(app)]));
  fw.use(LauncherIcon(packages: [.new(app)]));
  // No `directory:` — the ordinary case, where the whole package is scanned
  // and previews are found wherever they were written.
  fw.use(Previews(packages: [.new(app)]));
  // Zero config: servers announce themselves at runtime — see
  // bin/example_server.dart.
  fw.use(ServerInspection());
  // The stack this project talks to locally: its own toy server, run in the
  // background by `tool/stack.dart`. That script is the authority — flutterware
  // asks it what state things are in and tells it to change them, and knows
  // nothing else. Start the server in a terminal instead and the panel reports
  // exactly the same thing, which is the property that makes a stack worth
  // *observing* rather than owning.
  //
  // `Platform.resolvedExecutable` rather than the string `dart`: a config runs
  // under the SDK the project is pinned to, and that is the one that can run
  // this project's scripts. Whatever `dart` is on PATH is a different question
  // with a frequently different answer — here it is two versions behind and
  // refuses the file outright.
  //
  // `dart tool/stack.dart`, not `dart run tool/stack.dart`, which a person
  // would type: `run` costs 450ms of resolution the script does not need, and
  // announces `Running build hooks...` on stderr while doing it.
  fw.use(
    DevStack.background(
      label: 'Example server',
      // JSON rather than an exit code, for the one state an exit code cannot
      // report: port 8080 already taken by something that is not this server.
      // `down` would offer a bring-up that is certain to fail.
      probe: Probe.json([dart, 'tool/stack.dart', 'status', '--json']),
      start: [dart, 'tool/stack.dart', 'up'],
      stop: [dart, 'tool/stack.dart', 'down'],
      // No `stopIsDestructive:` — stopping this server destroys nothing. The
      // flag is for a `down --volumes` that takes the database with it.
      poll: const Duration(seconds: 15),
      commands: [
        StackCommand(
          'logs',
          'Logs',
          [dart, 'tool/stack.dart', 'logs'],
          description:
              'The last 40 lines the server logged. A background process has '
              'no terminal, so it appends to a file instead.',
        ),
        StackCommand(
          'hit',
          'Send a request',
          [dart, 'tool/stack.dart', 'hit'],
          argument: 'path',
          description:
              'Requests a path — /users, /slow, /error — so the Server panel '
              'has traffic to show. Defaults to /users.',
        ),
      ],
    ),
  );
  // No `directory:` — scenarios live in `test/scenarios/`.
  fw.use(
    Scenarios(
      packages: [
        .new(app, languages: ['en', 'fr']),
      ],
    ),
  );
});
