import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutterware_app/src/comparison/channels.dart';
import 'package:flutterware_app/src/comparison/runner.dart';
import 'package:flutterware_app/src/comparison/shot_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

/// The assembly: decide, render what is left, diff, report.
///
/// Driven through a fake side, because none of what can go wrong here — what
/// gets skipped, which side broke, what the index says — needs a compiler or a
/// guest to go wrong, and a real one would make these tests minutes long.
void main() {
  late Directory root;
  late _FakeSide side;
  late ShotCache cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_runner');
    side = _FakeSide();
    cache = ShotCache(p.join(root.path, 'shots'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A checkout holding [files], and an SDK for it to pin so the runner's
  /// first check passes.
  String checkout(String name, Map<String, String> files) {
    var dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    files.forEach((relative, content) {
      File(p.join(dir.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    });
    var sdk = Directory(p.join(root.path, 'sdk', 'bin'))
      ..createSync(recursive: true);
    File(p.join(sdk.path, 'flutter')).writeAsStringSync('');
    File(p.join(sdk.path, 'dart')).writeAsStringSync('');
    var cacheDir = Directory(p.join(sdk.path, 'cache'))
      ..createSync(recursive: true);
    File(p.join(cacheDir.path, 'flutter.version.json')).writeAsStringSync(
      jsonEncode({
        'frameworkVersion': '3.47.0',
        'frameworkRevision': 'rev',
        'engineContentHash': 'engine',
      }),
    );
    var fvm = Directory(p.join(dir.path, '.fvm'))..createSync();
    Link(p.join(fvm.path, 'flutter_sdk')).createSync(p.dirname(sdk.path));
    return dir.path;
  }

  Future<ComparisonResult> compare({
    required String base,
    required String head,
    List<String>? only,
  }) => ComparisonRunner(
    headRoot: head,
    baseRoot: base,
    baseSha: 'abc123',
    side: side,
    cache: cache,
    only: only,
  ).run();

  ComparedItem itemFor(ComparisonResult result, String id) =>
      result.items.firstWhere((item) => item.id == id);

  // What a tab says before you click it. An estimate that had to render to
  // know would be the work rather than an estimate of it.
  group('the plan costs only hashing', () {
    ComparisonRunner runnerFor({required String base, required String head}) =>
        ComparisonRunner(
          headRoot: head,
          baseRoot: base,
          baseSha: 'abc123',
          side: side,
          cache: cache,
        );

    test('it counts what has to be rendered, and renders nothing', () async {
      side.declared['*'] = ['demo/card.dart#card', 'demo/list.dart#list'];

      var plan = await runnerFor(
        base: checkout('base', {
          'demo/card.dart': '1',
          'demo/list.dart': 'same',
        }),
        head: checkout('head', {
          'demo/card.dart': '2',
          'demo/list.dart': 'same',
        }),
      ).plan();

      expect(plan.estimate, '1 of 2');
      expect(plan.toRender, ['demo/card.dart#card']);
      expect(side.renderedFor, isEmpty);
    });

    // Every row that needs no picture is answered here, which is what lets a
    // list draw its full shape while the pictures are still arriving.
    test('added, removed and skipped are settled before any render', () async {
      side.declared[p.join(root.path, 'base')] = ['demo/gone.dart#gone'];
      side.declared[p.join(root.path, 'head')] = ['demo/new.dart#fresh'];

      var plan = await runnerFor(
        base: checkout('base', {'demo/gone.dart': '1'}),
        head: checkout('head', {'demo/new.dart': '1'}),
      ).plan();

      expect(plan.toRender, isEmpty);
      expect(plan.settled.map((i) => '${i.id}:${i.state.name}'), [
        'demo/new.dart#fresh:added',
        'demo/gone.dart#gone:removed',
      ]);
    });

    test('a plan already made is not made again', () async {
      side.declared['*'] = ['demo/card.dart#card'];
      var runner = runnerFor(
        base: checkout('base', {'demo/card.dart': '1'}),
        head: checkout('head', {'demo/card.dart': '2'}),
      );

      var plan = await runner.plan();
      var result = await runner.run(from: plan);

      expect(result.rendered, 2);
      expect(itemFor(result, 'demo/card.dart#card').state, isNot(isNull));
    });

    // The estimate is the first thing a tab asks for, so it is the first place
    // an SDK mismatch can be caught — before a base checkout is even built.
    test('a mismatched SDK refuses at plan time', () async {
      side.declared['*'] = ['demo/card.dart#card'];
      var base = checkout('base', {'demo/card.dart': '1'});
      var head = checkout('head', {'demo/card.dart': '2'});
      var other = Directory(p.join(root.path, 'other-sdk', 'bin'))
        ..createSync(recursive: true);
      Directory(p.join(other.path, 'cache')).createSync();
      File(
        p.join(other.path, 'cache', 'flutter.version.json'),
      ).writeAsStringSync(jsonEncode({'frameworkVersion': '3.40.0'}));
      Link(
        p.join(head, '.fvm', 'flutter_sdk'),
      ).updateSync(p.dirname(other.path));

      await expectLater(
        runnerFor(base: base, head: head).plan(),
        throwsA(isA<ComparisonRefused>()),
      );
    });
  });

  group('the skip rule decides before anything renders', () {
    test('a branch that changed nothing renders nothing', () async {
      var files = {'demo/card.dart': 'const card = 1;'};
      side.declared['*'] = ['demo/card.dart#card'];

      var result = await compare(
        base: checkout('base', files),
        head: checkout('head', files),
      );

      expect(result.rendered, 0);
      expect(side.renderedFor, isEmpty);
      expect(
        itemFor(result, 'demo/card.dart#card').state,
        ComparedState.skipped,
      );
    });

    test('a touched entry is rendered on both sides', () async {
      side.declared['*'] = ['demo/card.dart#card'];

      var result = await compare(
        base: checkout('base', {'demo/card.dart': 'const card = 1;'}),
        head: checkout('head', {'demo/card.dart': 'const card = 2;'}),
      );

      expect(result.rendered, 2);
      expect(side.renderedFor, hasLength(2));
    });

    // The entry's own file is untouched; something three imports away moved.
    test('a change in the closure counts, not just in the entry', () async {
      side.declared['*'] = ['demo/card.dart#card'];
      var files = {'demo/card.dart': "import '../lib/theme.dart';"};

      var result = await compare(
        base: checkout('base', {...files, 'lib/theme.dart': 'blue'}),
        head: checkout('head', {...files, 'lib/theme.dart': 'green'}),
      );

      expect(result.rendered, 2);
    });

    // An entry id is relative to its *package*; a checkout can hold several.
    // Deriving the file from the id alone made every entry in a workspace look
    // like a missing file — which hashes the same on both sides, so a
    // genuinely changed preview was skipped and reported as no change at all.
    // Found by running it, not by testing it.
    test(
      'an entry inside a workspace package is found on both sides',
      () async {
        side = _FakeSide(packagePath: 'examples/example');
        side.declared['*'] = ['demo/card.dart#card'];

        var result = await compare(
          base: checkout('base', {'examples/example/demo/card.dart': '1'}),
          head: checkout('head', {'examples/example/demo/card.dart': '2'}),
        );

        expect(result.rendered, 2);
        expect(
          itemFor(result, 'demo/card.dart#card').state,
          isNot(ComparedState.skipped),
        );
      },
    );

    test('only the named entries are looked at', () async {
      side.declared['*'] = ['demo/a.dart#a', 'demo/b.dart#b'];

      var result = await compare(
        base: checkout('base', {'demo/a.dart': '1', 'demo/b.dart': '1'}),
        head: checkout('head', {'demo/a.dart': '2', 'demo/b.dart': '2'}),
        only: ['demo/a.dart#a'],
      );

      expect(result.items.map((item) => item.id), ['demo/a.dart#a']);
    });
  });

  test(
    'an entry only one side has is added or removed, and never rendered',
    () async {
      side.declared[p.join(root.path, 'head')] = [
        'demo/a.dart#a',
        'demo/new.dart#fresh',
      ];
      side.declared[p.join(root.path, 'base')] = [
        'demo/a.dart#a',
        'demo/old.dart#gone',
      ];

      var files = {'demo/a.dart': '1'};
      var result = await compare(
        base: checkout('base', files),
        head: checkout('head', files),
      );

      expect(itemFor(result, 'demo/new.dart#fresh').state, ComparedState.added);
      expect(
        itemFor(result, 'demo/old.dart#gone').state,
        ComparedState.removed,
      );
      expect(side.renderedFor, isEmpty);
    },
  );

  group('the channels reach the verdict', () {
    test('two identical pictures of changed code are still the same', () async {
      side.declared['*'] = ['demo/card.dart#card'];
      side.frame = (entry, checkout) => _frame(entry, value: 10);

      var result = await compare(
        base: checkout('base', {'demo/card.dart': '1'}),
        head: checkout('head', {'demo/card.dart': '2'}),
      );

      expect(result.rendered, 2);
      expect(itemFor(result, 'demo/card.dart#card').state, ComparedState.same);
    });

    test('different pixels are a change, with the region named', () async {
      side.declared['*'] = ['demo/card.dart#card'];
      side.frame = (entry, checkout) =>
          _frame(entry, value: checkout.endsWith('head') ? 200 : 10);

      var result = await compare(
        base: checkout('base', {'demo/card.dart': '1'}),
        head: checkout('head', {'demo/card.dart': '2'}),
      );

      var item = itemFor(result, 'demo/card.dart#card');
      expect(item.state, ComparedState.changed);
      expect(item.pixels!.diff.clusters, isNotEmpty);
    });

    test('the tree explains the pixels', () async {
      side.declared['*'] = ['demo/card.dart#card'];
      side.frame = (entry, checkout) => _frame(
        entry,
        value: checkout.endsWith('head') ? 200 : 10,
        description: checkout.endsWith('head') ? 'Text("Pay")' : 'Text("Save")',
      );

      var result = await compare(
        base: checkout('base', {'demo/card.dart': '1'}),
        head: checkout('head', {'demo/card.dart': '2'}),
      );

      var deltas = itemFor(result, 'demo/card.dart#card').tree!.diff.deltas;
      expect(deltas.single.head, 'Text("Pay")');
    });
  });

  // A complaint about a frame is not the absence of one. This used to drop
  // any frame that reported anything, which threw away a perfectly comparable
  // screen because something overflowed by 1.5 pixels.
  group('a frame that was drawn anyway', () {
    test('an overflow is compared, and carried as the note', () async {
      side.declared['*'] = ['demo/card.dart#card'];
      side.complain = (entry, checkout) => checkout.endsWith('head')
          ? 'A RenderFlex overflowed by 1.5 pixels on the right.'
          : null;

      var result = await compare(
        base: checkout('base', {'demo/card.dart': '1'}),
        head: checkout('head', {'demo/card.dart': '2'}),
      );

      var item = itemFor(result, 'demo/card.dart#card');
      expect(item.state, isNot(ComparedState.failed));
      expect(item.pixels, isNotNull);
      expect(item.note, contains('overflowed'));
    });

    // A build that throws leaves an error screen where the entry was, and
    // comparing one of those against a working screen measures nothing.
    test('a build that threw is still not a frame', () async {
      side.declared['*'] = ['demo/card.dart#card'];
      side.fatal['demo/card.dart#card'] = 'Bad state: no';

      var result = await compare(
        base: checkout('base', {'demo/card.dart': '1'}),
        head: checkout('head', {'demo/card.dart': '2'}),
      );

      expect(
        itemFor(result, 'demo/card.dart#card').state,
        ComparedState.failed,
      );
    });

    // Both sides overflowing is the state of the world, not something this
    // branch did.
    test('a complaint both sides make is not a note', () async {
      side.declared['*'] = ['demo/card.dart#card'];
      side.complain = (entry, checkout) => 'overflowed by 1.5 pixels';

      var result = await compare(
        base: checkout('base', {'demo/card.dart': '1'}),
        head: checkout('head', {'demo/card.dart': '2'}),
      );

      expect(itemFor(result, 'demo/card.dart#card').note, isNull);
    });
  });

  group('the severity ladder', () {
    test('an entry that stopped rendering is the loudest row', () async {
      side.declared['*'] = ['demo/a.dart#a', 'demo/b.dart#b'];
      side.refuse = (entry, checkout) =>
          entry == 'demo/b.dart#b' && checkout.endsWith('head')
          ? 'threw while building'
          : null;

      var result = await compare(
        base: checkout('base', {'demo/a.dart': '1', 'demo/b.dart': '1'}),
        head: checkout('head', {'demo/a.dart': '2', 'demo/b.dart': '2'}),
      );

      expect(result.items.first.id, 'demo/b.dart#b');
      expect(result.items.first.state, ComparedState.broke);
      expect(result.items.first.note, contains('threw'));
    });

    test('an entry already broken on base says so quietly', () async {
      side.declared['*'] = ['demo/a.dart#a'];
      side.refuse = (entry, checkout) =>
          checkout.endsWith('base') ? 'was broken' : null;

      var result = await compare(
        base: checkout('base', {'demo/a.dart': '1'}),
        head: checkout('head', {'demo/a.dart': '2'}),
      );

      expect(result.items.single.state, ComparedState.wasBroken);
    });
  });

  test(
    'two checkouts on different SDKs are refused before any render',
    () async {
      side.declared['*'] = ['demo/a.dart#a'];
      var base = checkout('base', {'demo/a.dart': '1'});
      var head = checkout('head', {'demo/a.dart': '2'});
      // Repoint head at an SDK of its own.
      var other = Directory(p.join(root.path, 'other-sdk', 'bin'))
        ..createSync(recursive: true);
      File(p.join(other.path, 'flutter')).writeAsStringSync('');
      File(p.join(other.path, 'dart')).writeAsStringSync('');
      Directory(p.join(other.path, 'cache')).createSync();
      File(
        p.join(other.path, 'cache', 'flutter.version.json'),
      ).writeAsStringSync(jsonEncode({'frameworkVersion': '3.40.0'}));
      Link(
        p.join(head, '.fvm', 'flutter_sdk'),
      ).updateSync(p.dirname(other.path));

      await expectLater(
        compare(base: base, head: head),
        throwsA(isA<ComparisonRefused>()),
      );
      expect(side.renderedFor, isEmpty);
    },
  );

  test('a second run against the same base renders only the head', () async {
    side.declared['*'] = ['demo/card.dart#card'];
    var base = checkout('base', {'demo/card.dart': '1'});

    await compare(base: base, head: checkout('head', {'demo/card.dart': '2'}));
    side.renderedFor.clear();
    await compare(base: base, head: checkout('head2', {'demo/card.dart': '3'}));

    expect(side.renderedFor.map((r) => r.$2), everyElement(endsWith('head2')));
  });

  test('the half reports what it did and did not do', () async {
    side.declared['*'] = ['demo/card.dart#card'];
    var result = await compare(
      base: checkout('base', {'demo/card.dart': '1'}),
      head: checkout('head', {'demo/card.dart': '1'}),
    );

    var json = result.toJson();

    expect(json['rendered'], 0);
    expect((json['counts']! as Map)['skipped'], 1);
    expect((json['items']! as List).single, containsPair('state', 'skipped'));
  });
}

Uint8List _bytes(int value) =>
    Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, value);

RenderedEntry _frame(String entry, {int value = 0, String? description}) =>
    RenderedEntry(
      entryId: entry,
      rgba: _bytes(value),
      width: 8,
      height: 8,
      tree: InspectNode(
        id: '',
        type: 'Card',
        description: description,
        createdByLocalProject: true,
        children: const [],
      ),
    );

class _FakeSide implements ComparisonSide {
  _FakeSide({this.packagePath = '.'});

  /// Where the package sits inside each checkout — `.` for a single-package
  /// project, `examples/example` in a workspace.
  final String packagePath;

  @override
  String fileOf(String entryId) {
    var hash = entryId.indexOf('#');
    var file = hash < 0 ? entryId : entryId.substring(0, hash);
    return p.normalize(p.join(packagePath, file));
  }

  /// Checkout path → entry ids, or `'*'` for both sides.
  final declared = <String, List<String>>{};

  /// (entry, checkout) pairs this was asked to render.
  final renderedFor = <(String, String)>[];

  RenderedEntry Function(String entry, String checkout) frame =
      (entry, checkout) => _frame(entry);

  String? Function(String entry, String checkout)? refuse;

  /// What the framework said while drawing it anyway, per side — a complaint
  /// about a frame rather than the absence of one.
  String? Function(String entry, String checkout)? complain;

  /// Entry id → a build that threw, leaving no frame.
  final fatal = <String, String>{};

  @override
  Future<List<String>> entries(String checkout) async =>
      declared[checkout] ?? declared['*'] ?? const [];

  @override
  Future<Map<String, String>> render({
    required String checkout,
    required List<String> entryIds,
    required Future<void> Function(RenderedEntry frame) onFrame,
  }) async {
    var failed = <String, String>{};
    for (var entry in entryIds) {
      renderedFor.add((entry, checkout));
      if (refuse?.call(entry, checkout) case var why?) {
        failed[entry] = why;
        continue;
      }
      if (fatal[entry] case var why?) {
        failed[entry] = why;
        continue;
      }
      var drawn = frame(entry, checkout);
      await onFrame(
        RenderedEntry(
          entryId: drawn.entryId,
          rgba: drawn.rgba,
          width: drawn.width,
          height: drawn.height,
          tree: drawn.tree,
          complaint: complain?.call(entry, checkout),
        ),
      );
    }
    return failed;
  }
}
