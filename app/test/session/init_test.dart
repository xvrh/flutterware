import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/session/init.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory sdk;
  late StringBuffer out;
  late StringBuffer err;

  /// A directory `FlutterSdkPath` will accept: it needs both binaries present.
  Directory fakeSdk(String name) {
    var dir = Directory.systemTemp.createTempSync(name);
    for (var binary in ['flutter', 'dart']) {
      File(p.join(dir.path, 'bin', binary))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh');
    }
    return dir;
  }

  ProjectInit initWith({bool alreadyIgnored = false}) => ProjectInit(
    root: root.path,
    dartExecutable: p.join(sdk.path, 'bin', 'dart'),
    out: out,
    err: err,
    // `git check-ignore` exits 0 when the path is already covered.
    runProcess: (_, _, {workingDirectory}) async =>
        ProcessResult(0, alreadyIgnored ? 0 : 1, '', ''),
  );

  Link sdkLink() => Link(p.join(root.path, '.flutterware', 'sdk'));

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
    root = Directory.systemTemp.createTempSync('fw-init');
    sdk = fakeSdk('fw-init-sdk');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    sdk.deleteSync(recursive: true);
  });

  test('records the SDK that ran it', () async {
    expect(await initWith().run(), 0);

    var link = Link(p.join(root.path, '.flutterware', 'sdk'));
    expect(link.existsSync(), isTrue);
    expect(
      p.canonicalize(link.resolveSymbolicLinksSync()),
      p.canonicalize(sdk.resolveSymbolicLinksSync()),
    );
  });

  test('prefers .fvm/flutter_sdk when it names the same SDK', () async {
    // So that switching fvm versions moves this pointer too, instead of
    // leaving an absolute path naming the SDK that happened to be current.
    Link(p.join(root.path, '.fvm', 'flutter_sdk'))
      ..parent.createSync(recursive: true)
      ..createSync(sdk.path);

    await initWith().run();

    expect(
      Link(p.join(root.path, '.flutterware', 'sdk')).targetSync(),
      p.join('..', '.fvm', 'flutter_sdk'),
    );
  });

  test('records the SDK directly when fvm names a different one', () async {
    var other = fakeSdk('fw-init-other');
    addTearDown(() => other.deleteSync(recursive: true));
    Link(p.join(root.path, '.fvm', 'flutter_sdk'))
      ..parent.createSync(recursive: true)
      ..createSync(other.path);

    await initWith().run();

    expect(
      p.canonicalize(
        Link(
          p.join(root.path, '.flutterware', 'sdk'),
        ).resolveSymbolicLinksSync(),
      ),
      p.canonicalize(sdk.resolveSymbolicLinksSync()),
    );
  });

  test(
    'ignores the directory, since it holds a machine-specific path',
    () async {
      await initWith().run();

      expect(
        File(p.join(root.path, '.gitignore')).readAsStringSync(),
        contains('.flutterware/'),
      );
    },
  );

  test('leaves .gitignore alone when a pattern already covers it', () async {
    // A repo ignoring every dotfile with `.*` needs no line, and appending a
    // redundant one to a tracked file is worse than doing nothing.
    File(p.join(root.path, '.gitignore')).writeAsStringSync('.*\n');

    await initWith(alreadyIgnored: true).run();

    expect(File(p.join(root.path, '.gitignore')).readAsStringSync(), '.*\n');
  });

  test('writes a starter config when the project has none', () async {
    await initWith().run();

    var config = File(p.join(root.path, 'tool', 'flutterware.dart'));
    expect(config.existsSync(), isTrue);
    expect(config.readAsStringSync(), contains('Flutterware.configure'));
  });

  test('never overwrites an existing config', () async {
    File(p.join(root.path, 'tool', 'flutterware.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('// mine');

    await initWith().run();

    expect(
      File(p.join(root.path, 'tool', 'flutterware.dart')).readAsStringSync(),
      '// mine',
    );
  });

  group('running before every command', () {
    // `_autoInit` no longer skips on `.flutterware/sdk` existing, so `run` is
    // what a project meets on every invocation rather than once. These are the
    // properties that makes safe.

    test('restores what init writes after it is removed', () async {
      // The bug the gate caused, in the shape it will keep taking: something
      // init writes is added later — or deleted — and a project that ran once
      // already never sees it. Nothing here should need a migration.
      await initWith().run();
      File(p.join(root.path, '.mcp.json')).deleteSync();
      File(p.join(root.path, 'tool', 'flutterware.dart')).deleteSync();

      await initWith().run();

      expect(File(p.join(root.path, '.mcp.json')).existsSync(), isTrue);
      expect(
        File(p.join(root.path, 'tool', 'flutterware.dart')).existsSync(),
        isTrue,
      );
    });

    test('stops asking git once the line is written', () async {
      // The one part of a run that spawns a process. It has to fall out of the
      // steady state, or every command pays for an answer that cannot change.
      var gitCalls = 0;
      ProjectInit counted() => ProjectInit(
        root: root.path,
        dartExecutable: p.join(sdk.path, 'bin', 'dart'),
        out: out,
        err: err,
        runProcess: (_, _, {workingDirectory}) async {
          gitCalls++;
          return ProcessResult(0, 1, '', '');
        },
      );

      // Quiet, because that is what runs before every command — the `.mcp.json`
      // "is it hidden" note asks git too, and only when reporting to a human.
      await counted().run(quiet: true);
      expect(gitCalls, 1, reason: 'the first run has to ask');

      await counted().run(quiet: true);
      expect(gitCalls, 1, reason: 'the second reads .gitignore instead');
    });

    test('leaves the sdk link in place when nothing moved', () async {
      await initWith().run();
      var before = sdkLink().statSync().changed;

      await initWith().run();

      // Rewritten means deleted and recreated, which is a window with no link
      // at all for anything reading it concurrently.
      expect(sdkLink().statSync().changed, before);
    });

    test('still repoints the sdk link when the SDK changes', () async {
      await initWith().run();
      var other = fakeSdk('fw-init-moved');
      addTearDown(() => other.deleteSync(recursive: true));

      await ProjectInit(
        root: root.path,
        dartExecutable: p.join(other.path, 'bin', 'dart'),
        out: out,
        err: err,
        runProcess: (_, _, {workingDirectory}) async =>
            ProcessResult(0, 1, '', ''),
      ).run();

      expect(
        p.canonicalize(sdkLink().resolveSymbolicLinksSync()),
        p.canonicalize(other.resolveSymbolicLinksSync()),
      );
    });
  });

  test('is idempotent, and says nothing the second time', () async {
    await initWith().run();
    out.clear();

    expect(await initWith().run(), 0);
    expect(out.toString(), isNot(contains('.gitignore')));
    expect(out.toString(), isNot(contains('tool/flutterware.dart')));
    expect(out.toString(), isNot(contains('.mcp.json')));
    expect(Link(p.join(root.path, '.flutterware', 'sdk')).existsSync(), isTrue);
  });

  group('.mcp.json', () {
    File mcpConfig() => File(p.join(root.path, '.mcp.json'));
    Map<String, Object?> readConfig() =>
        jsonDecode(mcpConfig().readAsStringSync()) as Map<String, Object?>;

    test('registers `fw mcp` so an agent finds the project', () async {
      await initWith().run();

      expect(readConfig(), {
        'mcpServers': {
          'flutterware': {
            'command': 'fw',
            'args': ['mcp'],
          },
        },
      });
    });

    test('says `fw` has to be installed for the entry to resolve', () async {
      await initWith().run();

      expect(out.toString(), contains('dart install flutterware'));
    });

    test('keeps servers it did not write', () async {
      // The one outcome to rule out: this file is shared, and clobbering
      // someone else's server is worse than never having written ours.
      mcpConfig().writeAsStringSync('''
{
  "mcpServers": {
    "other": { "command": "other-server" }
  }
}
''');

      await initWith().run();

      var servers = readConfig()['mcpServers']! as Map<String, Object?>;
      expect(servers['other'], {'command': 'other-server'});
      expect(servers, contains('flutterware'));
    });

    test('never rewrites an entry someone has edited', () async {
      mcpConfig().writeAsStringSync('''
{
  "mcpServers": {
    "flutterware": { "command": "/opt/fw", "args": ["mcp", "--verbose"] }
  }
}
''');

      await initWith().run();

      var servers = readConfig()['mcpServers']! as Map<String, Object?>;
      expect(servers['flutterware'], {
        'command': '/opt/fw',
        'args': ['mcp', '--verbose'],
      });
    });

    test('leaves a file it cannot parse exactly as it found it', () async {
      // Replacing it with a valid file would mean deleting whatever it said,
      // which is not a repair anyone asked for.
      mcpConfig().writeAsStringSync('{ not json');

      expect(await initWith().run(), 0);

      expect(mcpConfig().readAsStringSync(), '{ not json');
      expect(out.toString(), isNot(contains('.mcp.json')));
    });

    test('leaves mcpServers alone when it is not an object', () async {
      mcpConfig().writeAsStringSync('{"mcpServers": []}');

      expect(await initWith().run(), 0);

      expect(readConfig()['mcpServers'], isEmpty);
    });

    test('says so when .gitignore hides it', () async {
      // A repo ignoring every dotfile with `.*` gets the file written and
      // hidden, which works for whoever ran init and for nobody else. Silence
      // would read as "your team has this now".
      await initWith(alreadyIgnored: true).run();

      expect(out.toString(), contains('.gitignore hides it'));
    });

    test(
      'says nothing about .gitignore when the file will be shared',
      () async {
        await initWith().run();

        expect(out.toString(), contains('.mcp.json'));
        expect(out.toString(), isNot(contains('.gitignore hides it')));
      },
    );

    test('preserves keys beside mcpServers', () async {
      mcpConfig().writeAsStringSync('{"inputs": [{"id": "token"}]}');

      await initWith().run();

      var config = readConfig();
      expect(config['inputs'], [
        {'id': 'token'},
      ]);
      expect(config['mcpServers'], contains('flutterware'));
    });

    test('reformats nothing, down to the indent width', () async {
      // Re-encoding the parsed file would reindent, requote and reorder all of
      // this, and the entry we added would be lost in a whole-file diff. The
      // only line it may touch is the one that used to be last, which gains a
      // comma.
      mcpConfig().writeAsStringSync('''
{
    "inputs": [{ "id": "token", "type": "promptString" }],
    "mcpServers": {
        "other": {
            "command": "other-server",
            "args": ["--stdio"]
        }
    }
}
''');

      await initWith().run();

      expect(mcpConfig().readAsStringSync(), '''
{
    "inputs": [{ "id": "token", "type": "promptString" }],
    "mcpServers": {
        "other": {
            "command": "other-server",
            "args": ["--stdio"]
        },
        "flutterware": {
            "command": "fw",
            "args": [
                "mcp"
            ]
        }
    }
}
''');
    });

    test('adds mcpServers to a file that has none, in place', () async {
      mcpConfig().writeAsStringSync('''
{
  "inputs": []
}
''');

      await initWith().run();

      expect(mcpConfig().readAsStringSync(), '''
{
  "inputs": [],
  "mcpServers": {
    "flutterware": {
      "command": "fw",
      "args": [
        "mcp"
      ]
    }
  }
}
''');
    });

    test('fills an empty mcpServers without collapsing the file', () async {
      mcpConfig().writeAsStringSync('''
{
  "mcpServers": {},
  "inputs": []
}
''');

      await initWith().run();

      expect(mcpConfig().readAsStringSync(), '''
{
  "mcpServers": {
    "flutterware": {
      "command": "fw",
      "args": [
        "mcp"
      ]
    }
  },
  "inputs": []
}
''');
    });

    test('keeps a file written on one line on one line', () async {
      mcpConfig().writeAsStringSync(
        '{"mcpServers":{"other":{"command":"other-server"}}}',
      );

      await initWith().run();

      expect(
        mcpConfig().readAsStringSync(),
        '{"mcpServers":{"other":{"command":"other-server"}, '
        '"flutterware": {"command":"fw","args":["mcp"]}}}',
      );
    });
  });

  test('reports a dart that is not inside a Flutter SDK', () async {
    var init = ProjectInit(
      root: root.path,
      dartExecutable: '/usr/bin/dart',
      out: out,
      err: err,
      runProcess: (_, _, {workingDirectory}) async =>
          ProcessResult(0, 1, '', ''),
    );

    expect(await init.run(), 64);
    expect(err.toString(), contains('no Flutter SDK'));
    expect(init.isInitialized, isFalse);
  });

  test('isInitialized is what the walker will test for', () async {
    expect(initWith().isInitialized, isFalse);
    await initWith().run();
    expect(initWith().isInitialized, isTrue);
  });

  test('leaves a copied-in SDK directory alone', () async {
    // Windows-style: the walker accepts a real directory at .flutterware/sdk,
    // so init must survive it — Link.createSync over a directory throws.
    var copied = Directory(sdkLink().path)..createSync(recursive: true);
    File(p.join(copied.path, 'marker')).writeAsStringSync('');

    expect(await initWith().run(), 0);
    expect(
      FileSystemEntity.typeSync(sdkLink().path, followLinks: false),
      FileSystemEntityType.directory,
    );
    expect(File(p.join(copied.path, 'marker')).existsSync(), isTrue);
    expect(initWith().isInitialized, isTrue);
  });
}
