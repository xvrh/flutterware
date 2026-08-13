import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/run_plugin.dart';
import 'package:flutterware_app/src/plugins/native/run_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:flutterware_app/src/run/journal.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

/// The act action: guest bundle in (through the [RunCore.debugAct] seam),
/// result + journal + artifacts out. The guest side itself is exercised over
/// the real wire by the drive spike.
void main() {
  late Directory runDir;
  late Directory worktree;
  late RunCore core;
  late RunHandle handle;

  setUp(() {
    runDir = Directory.systemTemp.createTempSync('fw-act-');
    worktree = Directory.systemTemp.createTempSync('fw-act-wt-');
    RunCore.runDirProvider = () => runDir.path;
    var tree = Worktree(path: worktree.path, isMain: true);
    core = RunCore(
      PluginHost(
        id: runPluginId,
        label: 'Run',
        worktree: tree,
        config: const {},
        workspace: Workspace(
          root: tree.path,
          declared: [],
          discovered: [],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
      ),
    );
    // No device on the other end of these tests, so the native layer is not
    // one of the answers — said here rather than discovered by `adb` and
    // `xcrun` being run for every refusal.
    core.debugNativeAvailable = false;
    handle = RunHandle(
      worktree: worktree.path,
      worktreeName: '~',
      device: 'macos',
      entrypoint: 'lib/main.dart',
      launcherPid: pid,
      startedAt: DateTime.now(),
    ).publish(runDir.path);
  });

  tearDown(() {
    core.dispose();
    RunCore.runDirProvider = flutterwareRunDir;
    for (var dir in [runDir, worktree]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  test('a landed tap: result, artifact, journal entry', () async {
    Map<String, String>? wire;
    core.debugAct = (handle, args) async {
      wire = args;
      return {
        'step': {
          'verb': 'tap',
          'target': '"Pay"',
          'attempts': 2,
          'elapsedMs': 450,
          'settle': {
            'settled': true,
            'frames': 12,
            'forcedFrames': 0,
            'framesEnabled': true,
            'elapsedMs': 300,
          },
        },
        'lifecycle': 'resumed',
        'texts': ['Pay', 'Receipt'],
        // Boxes, and different ones: the host runs the noise filter over
        // whatever the guest sends, and two nodes that share a box are one
        // node with a wrapper on it — which is exactly what that filter is
        // for, and would make this a one-node tree.
        'tree': {
          'root': {
            'id': '',
            'type': 'MyApp',
            'layout': {'x': 0, 'y': 0, 'width': 100, 'height': 100},
            'children': [
              {
                'id': '0',
                'type': 'Receipt',
                'layout': {'x': 0, 'y': 0, 'width': 100, 'height': 40},
              },
            ],
          },
        },
        'screenshot': {'base64': base64Encode(_tinyPng), 'width': 1},
        'logs': [
          {'sequence': 1, 'text': 'paid'},
        ],
      };
    };

    var result =
        (await core.invoke(
              'act',
              arguments: {'verb': 'tap', 'target': 'Pay', 'tree': true},
            ))!
            as RunActResult;

    expect(wire!['verb'], 'tap');
    expect(wire!['target'], 'Pay');
    expect(wire!.containsKey('tree'), isFalse, reason: 'tree was asked for');
    expect(result.ok, isTrue);
    expect(result.verb, 'tap');
    expect(result.target, '"Pay"');
    expect(result.attempts, 2);
    expect(result.settled, isTrue);
    expect(result.texts, ['Pay', 'Receipt']);
    expect(result.nodes, 2);
    expect(result.logs!.single.text, 'paid');
    expect(File(result.screenshot!).existsSync(), isTrue);

    var entry = readJournal(handle).single;
    expect(entry.verb, 'tap');
    expect(entry.actor, 'agent');
    expect(entry.target, '"Pay"');
    expect(entry.settled, isTrue);
    expect(entry.screenshot, result.screenshot);
    expect(entry.logLines, 1);
  });

  test('every step archives the whole moment, whatever it returned', () async {
    core.debugAct = (handle, args) async => {
      'step': {
        'verb': 'observe',
        'settle': {'settled': true},
      },
      'lifecycle': 'resumed',
      'texts': ['Pay', 'Receipt'],
      // Two nodes sharing a box: the noise filter reports one and the
      // archive must still hold both.
      'tree': {
        'root': {
          'id': '',
          'type': 'MyApp',
          'layout': {'x': 0, 'y': 0, 'width': 100, 'height': 100},
          'children': [
            {
              'id': '0',
              'type': 'Receipt',
              'layout': {'x': 0, 'y': 0, 'width': 100, 'height': 100},
            },
          ],
        },
      },
      'semantics': {
        'rect': {'x': 0, 'y': 0, 'width': 100, 'height': 100},
        'label': 'Pay',
        'children': <Object?>[],
      },
      'screenshot': {'base64': base64Encode(_tinyPng), 'width': 1},
    };

    // Nothing asked for: no tree inline, no picture returned.
    var result =
        (await core.invoke('act', arguments: {'verb': 'observe'}))!
            as RunActResult;

    expect(result.tree, isNull, reason: 'the reply carries no tree');
    expect(
      result.screenshotArtifact,
      isNull,
      reason: 'no picture was asked for, so none is shown',
    );
    expect(result.capture, contains('/steps/'));

    // …and all four legs are on disk anyway, with a manifest naming them.
    var stem = result.screenshot!.replaceAll('.png', '');
    for (var leg in ['.png', '.tree.json', '.semantics.json', '.texts.json']) {
      expect(File('$stem$leg').existsSync(), isTrue, reason: leg);
    }

    var manifest =
        jsonDecode(File('$stem.capture.json').readAsStringSync())
            as Map<String, Object?>;
    expect(manifest['capture'], result.capture);
    expect(manifest['verb'], 'observe');
    expect(
      (manifest['tree']! as Map)['nodes'],
      2,
      reason: 'the archived tree is the whole one, not the filtered one',
    );
    expect(
      manifest['reported'],
      ['screen'],
      reason: 'the testimony says what came back, which was not the picture',
    );

    // The journal points at the same moment, and says the same thing.
    var entry = readJournal(handle).single;
    expect(entry.capture, result.capture);
    expect(entry.reported, ['screen']);
    expect(entry.semantics, '$stem.semantics.json');
  });

  group('acting on a screen item', () {
    /// One observation, so there is a numbered screen to act against.
    Future<RunActResult> observe() async {
      core.debugAct = (handle, args) async => {
        'step': {
          'verb': 'observe',
          'settle': {'settled': true},
        },
        'lifecycle': 'resumed',
        'texts': ['Pay'],
        'tree': {
          'root': {
            'id': '',
            'type': 'Column',
            'layout': {'x': 0, 'y': 0, 'width': 100, 'height': 100},
            'children': [
              {
                'id': '0',
                'type': 'InkWell',
                'label': 'Pay',
                'layout': {'x': 10, 'y': 20, 'width': 40, 'height': 30},
              },
              {
                'id': '1',
                'type': 'IconButton',
                'layout': {'x': 60, 'y': 20, 'width': 20, 'height': 20},
              },
            ],
          },
        },
        'screenshot': {'base64': base64Encode(_tinyPng), 'width': 1},
      };
      return (await core.invoke('act', arguments: {'verb': 'observe'}))!
          as RunActResult;
    }

    test('becomes a point at the centre of its box', () async {
      var seen = await observe();
      expect(seen.screen!.items.map((i) => i.words), ['Pay', null]);

      Map<String, String>? wire;
      core.debugAct = (handle, args) async {
        wire = args;
        return {
          'step': {
            'verb': 'tap',
            'settle': {'settled': true},
          },
          'lifecycle': 'resumed',
          'texts': ['Pay'],
        };
      };

      var result =
          (await core.invoke('act', arguments: {'verb': 'tap', 'item': 1}))!
              as RunActResult;

      expect(result.ok, isTrue);
      expect(
        wire!['target'],
        '{"at":{"x":30.0,"y":35.0}}',
        reason: 'the centre of [10, 20, 40, 30]',
      );
      // What was aimed at, in words, so the journal is not a list of numbers.
      expect(readJournal(handle).last.target, 'item 1 "Pay"');
    });

    test('reaches a control that has no words at all', () async {
      await observe();
      Map<String, String>? wire;
      core.debugAct = (handle, args) async {
        wire = args;
        return {
          'step': {
            'verb': 'tap',
            'settle': {'settled': true},
          },
          'lifecycle': 'resumed',
        };
      };

      await core.invoke('act', arguments: {'verb': 'tap', 'item': 2});
      expect(wire!['target'], '{"at":{"x":70.0,"y":30.0}}');
      expect(readJournal(handle).last.target, 'item 2');
    });

    test(
      'a number the screen does not have is refused with the count',
      () async {
        await observe();
        var result =
            (await core.invoke('act', arguments: {'verb': 'tap', 'item': 9}))!
                as RunActResult;

        expect(result.ok, isFalse);
        expect(result.error, contains('no item 9'));
        expect(result.error, contains('it had 2'));
      },
    );

    test('an item before anything was observed says so', () async {
      var result =
          (await core.invoke('act', arguments: {'verb': 'tap', 'item': 1}))!
              as RunActResult;

      expect(result.ok, isFalse);
      expect(result.error, contains('nothing has observed this app yet'));
    });
  });

  group('the lens', () {
    void observes() {
      core.debugAct = (handle, args) async => {
        'step': {
          'verb': 'observe',
          'settle': {'settled': true},
        },
        'lifecycle': 'resumed',
        'texts': ['Pay'],
        'tree': {
          'root': {
            'id': '',
            'type': 'Column',
            'layout': {'x': 0, 'y': 0, 'width': 100, 'height': 100},
            'children': [
              {
                'id': '0',
                'type': 'Text',
                'description': 'Text("Pay")',
                'layout': {'x': 0, 'y': 0, 'width': 40, 'height': 20},
                'properties': {'size': '12.5', 'color': '#111111'},
              },
            ],
          },
        },
        'screenshot': {'base64': base64Encode(_tinyPng), 'width': 1},
      };
    }

    Future<RunActResult> act([Map<String, Object?> extra = const {}]) async =>
        (await core.invoke('act', arguments: {'verb': 'observe', ...extra}))!
            as RunActResult;

    test('act is the default, and says so', () async {
      observes();
      var result = await act();
      expect(result.lens, 'act');
      expect(result.screen, isNotNull);
      expect(result.screenshotArtifact, isNull);
      expect(result.styles, isNull);
      expect(result.tree, isNull);
    });

    test(
      'design brings the picture and the styles, raw brings the tree',
      () async {
        observes();
        var design = await act({'lens': 'design'});
        expect(design.lens, 'design');
        expect(design.screenshotArtifact, isNotNull);
        expect(design.styles, isNotEmpty);
        expect(design.tree, isNull);

        var raw = await act({'lens': 'raw'});
        expect(raw.lens, 'raw');
        expect(raw.tree, isNotNull);
      },
    );

    test('a flag the caller named beats the lens', () async {
      observes();
      var result = await act({'lens': 'look', 'screenshot': false});
      expect(
        result.screenshotArtifact,
        isNull,
        reason: 'look wants a picture; this call said not to',
      );
    });

    test('a pin lasts, and every reply marks it as one', () async {
      observes();
      var set =
          (await core.invoke('lens', arguments: {'lens': 'design'}))!
              as RunLensResult;
      expect(set.lens, 'design');
      expect(set.pinned, isTrue);
      expect(set.was, 'act');

      var result = await act();
      expect(
        result.lens,
        'design (pinned)',
        reason: 'somebody else may have set it; the reply has to say so',
      );
      expect(result.styles, isNotEmpty);

      // Naming one for a call does not disturb the pin, and is not marked.
      expect((await act({'lens': 'act'})).lens, 'act');
      expect((await act()).lens, 'design (pinned)');

      var cleared =
          (await core.invoke('lens', arguments: {'lens': 'none'}))!
              as RunLensResult;
      expect(cleared.pinned, isFalse);
      expect(cleared.was, 'design');
      expect((await act()).lens, 'act');
    });

    test('reading the lens changes nothing and lists the choices', () async {
      var report = (await core.invoke('lens', arguments: {}))! as RunLensResult;
      expect(report.lens, 'act');
      expect(report.pinned, isFalse);
      expect(report.was, isNull, reason: 'nothing changed');
      expect(report.lenses.map((l) => l['lens']), [
        'act',
        'look',
        'design',
        'raw',
      ]);
    });

    test('an unknown lens is refused with the list', () async {
      observes();
      var result = await act({'lens': 'pretty'});
      expect(result.ok, isFalse);
      expect(result.error, contains('no lens "pretty"'));
      expect(result.error, contains('act, look, design, raw'));
    });
  });

  test('the picture shows itself when a step goes wrong', () async {
    core.debugAct = (handle, args) async => {
      'error': 'nothing matches "Nope", which `tap` needs.',
      'failure': 'notFound',
      'lifecycle': 'resumed',
      'texts': ['Pay'],
      'screenshot': {'base64': base64Encode(_tinyPng), 'width': 1},
    };

    var result =
        (await core.invoke(
              'act',
              arguments: {'verb': 'tap', 'target': 'Nope'},
            ))!
            as RunActResult;

    expect(result.ok, isFalse);
    expect(
      result.screenshotArtifact,
      isNotNull,
      reason: 'nobody asked, but looking is the useful thing to do here',
    );
  });

  test('a refusal is not ok, and still observes', () async {
    core.debugAct = (handle, args) async => {
      'error': 'nothing matches "Nope", which `tap` needs.',
      'failure': 'notFound',
      'lifecycle': 'resumed',
      'texts': ['Pay'],
    };

    var result =
        (await core.invoke(
              'act',
              arguments: {'verb': 'tap', 'target': 'Nope'},
            ))!
            as RunActResult;

    expect(result.ok, isFalse);
    expect(result.failure, 'notFound');
    expect(result.texts, ['Pay'], reason: 'a refusal still shows the screen');
    expect(readJournal(handle).single.failure, 'notFound');
  });

  test(
    'a refusal teaches the native layer, but only where there is one',
    () async {
      core.debugAct = (handle, args) async => {
        'error': 'nothing matches "Allow"',
        'failure': 'notFound',
        'texts': <String>['Pay'],
      };

      // How an agent finds this layer at all: not from documentation it read
      // once, but at the moment it is looking for something the widget tree does
      // not have.
      core.debugNativeAvailable = true;
      var taught =
          (await core.invoke(
                'act',
                arguments: {'verb': 'tap', 'target': 'Allow'},
              ))!
              as RunActResult;
      expect(taught.error, contains('layer: native'));

      // And silence where the advice would fail: a device with no native driver
      // must not be told to try one.
      core.debugNativeAvailable = false;
      var quiet =
          (await core.invoke(
                'act',
                arguments: {'verb': 'tap', 'target': 'Allow'},
              ))!
              as RunActResult;
      expect(quiet.error, isNot(contains('layer: native')));
    },
  );

  test('a native step journals as its own layer', () async {
    // The native path refuses without a device, which is the point: the
    // refusal is still a step, and the story records which tree it addressed.
    var result =
        (await core.invoke(
              'act',
              arguments: {
                'verb': 'observe',
                'layer': 'native',
                'device': 'macos',
              },
            ))!
            as RunActResult;

    expect(result.ok, isFalse);
    expect(result.layer, 'native');
    expect(result.error, contains('no driver'));
    var entry = readJournal(handle).single;
    expect(entry.layer, 'native');
    expect(entry.verb, 'observe');
  });

  test('observe and navigate funnel into act with the verb fixed', () async {
    var verbs = <String>[];
    core.debugAct = (handle, args) async {
      verbs.add(args['verb']!);
      return {'texts': <String>[]};
    };

    await core.invoke('observe');
    await core.invoke('navigate', arguments: {'route': 'shop/cart'});

    expect(verbs, ['observe', 'navigate']);
  });

  test('a guest-less app is named as such, not as a fault', () async {
    core.debugAct = (handle, args) async =>
        throw RPCError('callServiceExtension', -32601, 'Method not found');

    var result =
        (await core.invoke('act', arguments: {'verb': 'tap', 'target': 'Pay'}))!
            as RunActResult;

    expect(result.ok, isFalse);
    expect(result.error, contains('without the drive guest'));
    expect(readJournal(handle).single.error, contains('drive guest'));
  });

  test('human actions ride the reply, and journal ahead of the step', () async {
    core.debugAct = (handle, args) async => {
      'step': {
        'verb': 'observe',
        'settle': {'settled': true, 'elapsedMs': 50},
      },
      'human': [
        {'at': '2026-08-11T10:00:00.000Z', 'verb': 'tap', 'target': '"Pay"'},
        {
          'at': '2026-08-11T10:00:02.000Z',
          'verb': 'longPress',
          'target': "key 'cart'",
        },
      ],
      'texts': <String>[],
    };

    var result = (await core.invoke('observe'))! as RunActResult;

    expect(result.human, ['tap "Pay"', "longPress key 'cart'"]);

    var entries = readJournal(handle);
    expect(entries, hasLength(3));
    expect(entries[0].actor, 'human');
    expect(entries[0].verb, 'tap');
    expect(entries[0].target, '"Pay"');
    expect(entries[0].at, '2026-08-11T10:00:00.000Z');
    expect(entries[1].actor, 'human');
    expect(entries[1].verb, 'longPress');
    expect(entries[2].verb, 'observe', reason: 'the step closes the story');
    expect(entries[2].actor, 'agent');
  });

  test('a sibling worktree running the same device/entrypoint pair does not '
      'make selection ambiguous', () async {
    var sibling = Directory.systemTemp.createTempSync('fw-act-sibling-');
    addTearDown(() => sibling.deleteSync(recursive: true));
    RunHandle(
      worktree: sibling.path,
      worktreeName: 'sibling',
      device: 'macos',
      entrypoint: 'lib/main.dart',
      launcherPid: pid,
      startedAt: DateTime.now(),
    ).publish(runDir.path);
    core.debugAct = (handle, args) async => {'texts': <String>[]};

    var result = (await core.invoke('observe'))! as RunActResult;

    expect(result.ok, isTrue, reason: 'the sibling run is not a subject here');
    expect(result.worktree, '~');
  });

  test('a hidden window is said out loud', () async {
    core.debugAct = (handle, args) async => {
      'step': {
        'verb': 'observe',
        'settle': {'settled': true, 'framesEnabled': false, 'elapsedMs': 50},
      },
      'texts': <String>[],
    };

    var result = (await core.invoke('observe'))! as RunActResult;

    expect(result.framesEnabled, isFalse);
    expect(result.note, contains('hidden or occluded'));
  });
}

/// A 1×1 transparent PNG.
final _tinyPng = Uint8List.fromList([
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, //
  120, 156, 99, 250, 207, 192, 240, 31, 0, 5, 5, 2, 0, 95, 132, 84, 96, 0, //
  0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);
