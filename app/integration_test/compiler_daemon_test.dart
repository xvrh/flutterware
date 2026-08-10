@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:flutterware_app/src/previews/catalog_entry.dart';
import 'package:flutterware_app/src/previews/compiler_daemon_client.dart';
import 'package:flutterware_app/src/previews/protocol.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The compiler daemon, as a real process, against this package's own demos.
///
/// Everything here is a claim about the daemon that only a running daemon can
/// answer: that it starts, that it drops an entry it cannot compile instead of
/// dying, that a second client attaches to the first one's warm compiler and
/// stays isolated from it, that an edit on disk is noticed, and that the set of
/// servable entries is announced to clients that did not ask. The unit tests in
/// `test/previews/` cover the wire format, the address, the depfile and the
/// client's own bookkeeping against a fake; none of them can see any of the
/// above, because in all of them there is no daemon.
///
/// **No guest.** Nothing here launches the embedder or renders a frame, and that
/// is deliberate: the guest composites through Metal, so a check that needs one
/// cannot block a CI run on a machine whose GPU situation nobody can promise.
/// Everything below stops at the kernel. What that gives up is real — hot reload
/// putting an edit on screen, knobs, axes, hover, view insets, the inspection
/// surface — and none of it is covered anywhere else. Restoring it means
/// deciding where a GPU can be relied on, not writing more assertions.
///
/// Not run by `flutter test`, which would want a device and
/// `package:integration_test` for anything under this directory:
///
/// ```sh
/// cd app && dart test integration_test
/// ```
void main() {
  late String appRoot;
  late String demosDir;
  late String dartExecutable;
  late String flutterRoot;
  late DaemonConfig config;
  late CompilerDaemonClient daemon;
  late DaemonReady ready;

  /// Two entries known to compile, named rather than taken off the front of the
  /// list: entries sort by id, so `entries.first` moves whenever a demo is added
  /// — and a check that quietly starts asserting about a different demo than it
  /// was written for goes on passing.
  CatalogEntry entry(String symbol) =>
      ready.entries.firstWhere((e) => e.symbol == symbol);

  setUpAll(() async {
    appRoot = await _appPackageRoot();
    demosDir = p.join(appRoot, 'tool', 'catalog', 'demos');
    var cache = FlutterCache.fromRunningSdk();
    flutterRoot = cache.flutterRoot;
    dartExecutable = p.join(flutterRoot, 'bin', 'dart');
    config = DaemonConfig.forPackage(
      appToolDirectory: appRoot,
      // The demos live under `app/tool/catalog/`, so the app package is both the
      // scan root and the entrypoint's package — the one case where these two
      // are the same directory.
      packageRoot: appRoot,
      flutterSdkRoot: flutterRoot,
      roots: const ['tool/catalog'],
    );

    // A fixture left over from a run that was killed before its teardown is
    // worse than clutter: `addPreview` waits for the daemon to *announce* the
    // demo, and rewriting a file that is already an entry announces no change,
    // so every test that adds one waits out its timeout.
    for (var entity in Directory(demosDir).listSync()) {
      if (entity is File && p.basename(entity.path).startsWith('fixture_')) {
        entity.deleteSync();
      }
    }

    // A daemon left over from an earlier run carries that run's state — which
    // entries it quarantined above all, and these tests quarantine on purpose.
    // Sharing is measured deliberately further down, by a second client.
    var (stale, _) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    // The recorded quarantine is that run's state too, and the more subtle
    // half: a daemon that starts already knowing `doesNotCompile` is broken
    // generates an entrypoint without it, so nothing fails, nothing is blamed,
    // and there is no whole-program rebuild — which is exactly what the
    // discovery test below asserts the presence of. Cleared here so that test
    // describes a first encounter rather than whatever the last run left.
    var recorded = File(
      p.join(appRoot, 'build', 'catalog', stale.address.key, 'quarantine.json'),
    );
    if (recorded.existsSync()) recorded.deleteSync();
    await stale.stopDaemon();

    (daemon, ready) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
      onLog: (line) => print('  [daemon] $line'),
    );
  });

  tearDownAll(() => daemon.close());

  /// The next announcement to [client] that satisfies [predicate].
  ///
  /// Call this *before* whatever provokes the change and await the future after:
  /// [CompilerDaemonClient.catalogChanges] is a plain broadcast stream, so a
  /// change announced while nobody is listening is gone. Getting that backwards
  /// is not a hypothetical — an implementation that replayed a held value into a
  /// generator lost exactly the change a caller was already waiting for.
  Future<CatalogChanged> announced(
    CompilerDaemonClient client,
    bool Function(CatalogChanged) predicate,
    String describe,
  ) => client.catalogChanges
      .firstWhere(predicate)
      .timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw StateError('nothing announced that $describe'),
      );

  /// Writes a demo into the scan root, waits for the daemon to say it exists,
  /// and takes it away again when the test ends.
  ///
  /// Fixtures are written rather than checked in, and every one of them is
  /// named `fixture_*` so a run killed halfway leaves an untracked file behind
  /// rather than a modified tracked one. Nothing here rewrites a file that is
  /// under version control.
  ///
  /// They used to be *gitignored* as well, which discovery has made impossible:
  /// the scan honours `.gitignore`, so an ignored demo is one it correctly
  /// refuses to see, and every test below waited out its timeout for an entry
  /// that was never going to be announced. Worth knowing as a rule rather than
  /// as a test detail — a preview in an ignored file does not exist.
  Future<(File, CatalogEntry)> addPreview(
    String name,
    String source, {
    CompilerDaemonClient? via,
  }) async {
    var relative = 'tool/catalog/demos/fixture_$name.dart';
    var file = File(p.join(demosDir, 'fixture_$name.dart'));
    addTearDown(() async {
      if (!file.existsSync()) return;
      // Drained as well as deleted: the daemon outlives this test, and a
      // withdrawal nobody consumed would be the next test's first event.
      // Tolerant of a timeout because a test that failed before the refresh
      // leaves nothing to withdraw.
      var withdrawn = daemon.catalogChanges.firstWhere(
        (c) => !c.entries.any((e) => e.path == relative),
      );
      file.deleteSync();
      daemon.refresh();
      await withdrawn.timeout(
        const Duration(seconds: 30),
        onTimeout: () => const CatalogChanged(entries: []),
      );
    });

    var appeared = announced(
      daemon,
      (c) => c.entries.any((e) => e.path == relative),
      'the new demo',
    );
    file.writeAsStringSync(source);
    // A refresh, not a select: this is the panel's timer, which has to notice a
    // file without compiling anything.
    (via ?? daemon).refresh();
    return (
      file,
      (await appeared).entries.firstWhere((e) => e.path == relative),
    );
  }

  group('starting up', () {
    test('builds the guest host', () {
      expect(File(ready.hostPath).existsSync(), isTrue);
    });

    test('discovers the demos, and groups a file that declares several', () {
      expect(ready.entries.length, greaterThanOrEqualTo(5));
      expect(ready.entries.map((e) => e.group), contains('Avatar tile'));
    });

    test("compiles a demo carrying Flutter's own @Preview", () {
      // `plain_preview.dart` imports nothing of ours: Flutter's annotation, and
      // no `package:flutterware`. The scanner has always accepted `@Preview`,
      // and the generated wrapper used to declare `Demo get fwPreview`, so every
      // such entry assigned a supertype to a subtype and failed to compile.
      //
      // Asserted here rather than left to the suite passing, because the
      // daemon's answer to a demo that does not compile is to quarantine it and
      // carry on — the failure this covers is one every other test is designed
      // to survive.
      expect(
        ready.quarantined.map((q) => q.entry.symbol),
        isNot(contains('plainPreview')),
        reason: 'the whole point is that it compiles',
      );
      expect(ready.entries.map((e) => e.symbol), contains('plainPreview'));
    });

    test('quarantines a demo that does not compile instead of failing', () {
      // The entrypoint imports every entry — that is what makes one compiler
      // safe to share — so one demo mid-edit fails the compile for all of them.
      // Dropping what can be blamed is what keeps the catalog usable.
      expect(
        ready.quarantined.map((q) => q.entry.symbol),
        contains('doesNotCompile'),
      );
      expect(
        ready.entries.map((e) => e.symbol),
        isNot(contains('doesNotCompile')),
        reason: 'a quarantined entry is not offered',
      );
      expect(
        ready.quarantined.map((q) => q.error).join('\n'),
        contains('ThisTypeDoesNotExist'),
        reason:
            'the quarantine carries the compiler error, so a renderer can '
            'show it',
      );
      expect(
        ready.timings.keys,
        contains('rebuild after quarantine'),
        reason:
            'the prepared kernel was rebuilt whole once the quarantine '
            'settled',
      );
    });
  });

  test('selecting a quarantined entry retries it and reports why not', () async {
    // Selecting it *is* the retry, and it has to be: nothing else compiles that
    // entry, so an id the daemon simply refused to look up would be an entry
    // only an edit to some other file could ever bring back.
    var retried = await daemon.select(
      'tool/catalog/demos/does_not_compile.dart#doesNotCompile',
    );
    expect(retried.ok, isFalse, reason: 'it does not pretend to succeed');
    expect(
      retried.error,
      contains('ThisTypeDoesNotExist'),
      reason: 'and answers with the compiler error, not "no such entry"',
    );
    expect(
      (await daemon.select(entry('counter').id)).ok,
      isTrue,
      reason: 'the catalog still compiles after a failed retry',
    );
  });

  test('an edit on disk is found, and nothing else is recompiled', () async {
    // The invalidation is the daemon's to do: `frontend_server` recompiles
    // exactly the files a `recompile` request names and nothing else. Without
    // the stat sweep this compiles, reports success in milliseconds, and hands
    // back a kernel of the file as it was when the daemon started.
    var (file, added) = await addPreview(
      'edited',
      _preview('fixtureEdited', 'first'),
    );
    expect((await daemon.select(added.id)).ok, isTrue);

    // The contract the focus-triggered reload rests on: a request nobody
    // pressed must cost nothing when nothing was edited. A reload that always
    // works reassembles the guest and resets the demo's state, which would make
    // alt-tabbing back to the panel a way to lose your place.
    var quiet = await daemon.select(added.id, ifChanged: true);
    expect(quiet.unchanged, isTrue, reason: 'ifChanged skips an idle poll');
    expect(quiet.dill, isNull, reason: 'and hands back no kernel to reload');

    file.writeAsStringSync(_preview('fixtureEdited', 'second'));
    var noisy = await daemon.select(added.id, ifChanged: true);
    expect(noisy.unchanged, isFalse, reason: 'and does not skip a real edit');
    expect(noisy.ok, isTrue, reason: noisy.error ?? '');
    expect(
      noisy.editedCount,
      1,
      reason: 'the sweep found exactly the file that moved',
    );
  });

  test('a demo that stops compiling is dropped, and comes back when '
      'fixed', () async {
    var (file, added) = await addPreview(
      'broken',
      _preview('fixtureBroken', 'fine'),
    );
    expect((await daemon.select(added.id)).ok, isTrue);
    // The sweep that puts the new file into the invalidator's baseline. A file
    // seen for the first time is recorded and deliberately *not* reported —
    // otherwise every compile after a rescan would invalidate the file it just
    // discovered — so without this the edit below would be the fixture's first
    // sighting and go unnoticed.
    expect((await daemon.select(added.id, ifChanged: true)).unchanged, isTrue);

    var dropped = announced(
      daemon,
      (c) => c.quarantined.any((q) => q.entry.id == added.id),
      'the entry that stopped compiling',
    );
    file.writeAsStringSync(_brokenPreview('fixtureBroken'));
    var afterBreak = await daemon.select(entry('counter').id);
    expect(
      afterBreak.ok,
      isTrue,
      reason: 'the rest of the catalog still compiles: ${afterBreak.error}',
    );
    expect(
      (await dropped).entries.map((e) => e.id),
      isNot(contains(added.id)),
      reason: 'and the broken entry stops being offered',
    );

    // Re-admission is the half that says fixing the file is enough: no restart,
    // no rescan, nothing but a compile that happened to succeed this time.
    var back = announced(
      daemon,
      (c) => c.entries.any((e) => e.id == added.id),
      'the repaired entry',
    );
    file.writeAsStringSync(_preview('fixtureBroken', 'fixed'));
    expect((await daemon.select(entry('counter').id)).ok, isTrue);
    expect(
      (await back).quarantined.map((q) => q.entry.id),
      isNot(contains(added.id)),
      reason: 'and the quarantine lets it go',
    );
    expect(
      (await daemon.select(added.id)).ok,
      isTrue,
      reason: 'the repaired entry can be selected',
    );
  });

  group('a second client', () {
    late CompilerDaemonClient second;
    late DaemonReady secondReady;
    late Duration attaching;

    setUp(() async {
      var attach = Stopwatch()..start();
      (second, secondReady) = await CompilerDaemonClient.connect(
        dartExecutable: dartExecutable,
        config: config,
        onLog: (line) => print('  [daemon] $line'),
      );
      attaching = attach.elapsed;
      addTearDown(second.close);
    });

    test('attaches to the warm compiler rather than starting its own', () {
      expect(secondReady.reused, isTrue);
      // Generous on purpose: what this rules out is a *cold start*, which is
      // tens of seconds, and a tighter bound would only buy flakes on a loaded
      // machine.
      expect(
        attaching,
        lessThan(const Duration(seconds: 10)),
        reason: 'attaching cost $attaching',
      );
      expect(
        secondReady.assetsDir,
        isNot(ready.assetsDir),
        reason: 'and still gets its own asset directory',
      );
    });

    test(
      'gets the kernel it asked for, not whatever was compiled last',
      () async {
        // The compiler, the generated entrypoint and the compiler's output file
        // are one mutable thing shared between the two clients. When that leaked,
        // one client decided what the other rendered — and it produced
        // screenshots of the wrong entry that every test passed.
        var mine = await daemon.select(entry('counter').id, full: true);
        var theirs = await second.select(entry('dashboard').id, full: true);
        expect(mine.ok, isTrue, reason: mine.error ?? '');
        expect(theirs.ok, isTrue, reason: theirs.error ?? '');
        expect(
          mine.dill,
          isNot(theirs.dill),
          reason: 'each client got its own kernel, not one shared path',
        );
        expect(
          const ListEquality<int>().equals(
            File(mine.dill!).readAsBytesSync(),
            File(theirs.dill!).readAsBytesSync(),
          ),
          isFalse,
          reason:
              'and the two differ — a shared file would have made them '
              'identical',
        );
      },
    );

    test('an ifChanged reflex survives the other client selecting '
        'elsewhere', () async {
      // The focus-triggered reload asks "has anything moved for *my* guest".
      // It used to be answered from the daemon's own active entry, so an agent
      // screenshotting a different entry made the panel's next alt-tab a real
      // recompile and a state-resetting reload — two clients alternating was
      // constant ping-pong.
      var mine = entry('counter').id;
      expect((await daemon.select(mine, full: true)).ok, isTrue);
      expect(
        (await second.select(entry('dashboard').id, full: true)).ok,
        isTrue,
      );

      var reflex = await daemon.select(mine, ifChanged: true);
      expect(
        reflex.unchanged,
        isTrue,
        reason:
            "another client's select is not an edit; this guest's picture "
            'is still current',
      );
    });

    test('an edit reaches both clients, though only one sweep sees it', () async {
      // Edits are consumed by whichever session's sweep runs first. Without a
      // per-session change generation, the first client's reflex would eat the
      // edit and the second's would see a clean world — and keep rendering the
      // stale build.
      var (file, added) = await addPreview(
        'interleaved',
        _preview('fixtureInterleaved', 'first'),
      );
      expect((await daemon.select(added.id, full: true)).ok, isTrue);
      expect((await second.select(added.id, full: true)).ok, isTrue);

      file.writeAsStringSync(_preview('fixtureInterleaved', 'second'));
      var one = await daemon.select(added.id, ifChanged: true);
      expect(one.ok, isTrue, reason: one.error ?? '');
      expect(one.unchanged, isFalse, reason: 'the sweeping client recompiles');

      var two = await second.select(added.id, ifChanged: true);
      expect(two.ok, isTrue, reason: two.error ?? '');
      expect(
        two.unchanged,
        isFalse,
        reason:
            'and so does the other one, whose own sweep no longer sees the '
            'edit — the change generation is what remembers it',
      );
    });

    test('a demo it discovers is announced to the client that did not '
        'ask', () async {
      // The case that separates a shared daemon from a private one. Discovery
      // runs once at startup, so a file added while the catalog is open is a
      // file it would otherwise never mention — and the daemon outlives the
      // panel, so "restart it" means closing the worktree.
      var (_, added) = await addPreview(
        'announced',
        _preview('fixtureAnnounced', 'late'),
        via: second,
      );
      expect(
        (await daemon.select(added.id)).ok,
        isTrue,
        reason: 'and the entry the other client found compiles here',
      );
    });
  });

  test('a preview written while the daemon is warm is in the next '
      "client's handshake", () async {
    // **The handshake is the only entry list a headless caller ever sees.** It
    // checks the id it was given against `ready.entries` and refuses before it
    // reaches the `select` whose rescan would have found the entry — so the
    // staleness was self-sustaining: a preview written after the daemon started
    // was invisible to every client that attached, and re-running the command
    // read the same snapshot again. Measured on this repo: `fw run previews
    // entries` listed a new entry, and `screenshot` answered "no such entry"
    // for it until the daemon's ten-minute idle timeout expired.
    //
    // Nothing here tells the daemon anything — no refresh, no select. A client
    // arriving is the notice.
    var relative = 'tool/catalog/demos/fixture_attached.dart';
    var file = File(p.join(demosDir, 'fixture_attached.dart'));
    addTearDown(() async {
      if (!file.existsSync()) return;
      var withdrawn = daemon.catalogChanges.firstWhere(
        (c) => !c.entries.any((e) => e.path == relative),
      );
      file.deleteSync();
      daemon.refresh();
      await withdrawn.timeout(
        const Duration(seconds: 30),
        onTimeout: () => const CatalogChanged(entries: []),
      );
    });

    Future<DaemonReady> attach() async {
      var (client, fresh) = await CompilerDaemonClient.connect(
        dartExecutable: dartExecutable,
        config: config,
        onLog: (line) => print('  [daemon] $line'),
      );
      addTearDown(client.close);
      // Otherwise a daemon that had died and been replaced would pass this by
      // rescanning at startup, which is the one case that was never broken.
      expect(fresh.reused, isTrue, reason: 'it attached to the warm daemon');
      return fresh;
    }

    file.writeAsStringSync(_preview('fixtureAttached', 'a new file'));
    expect(
      (await attach()).entries.map((e) => e.id),
      contains('$relative#fixtureAttached'),
    );

    // And the half the report was about: an entry added to a file the daemon
    // has already scanned, generated a wrapper for and compiled. It reaches the
    // scan by a different route — the file's mtime rather than the walk finding
    // a name it had never seen — and both were equally invisible.
    file.writeAsStringSync(
      '${_preview('fixtureAttached', 'a new file')}\n'
      "@Preview(name: 'Second')\n"
      "Widget fixtureAppended() => const Center(child: Text('appended'));\n",
    );
    expect(
      (await attach()).entries.map((e) => e.id),
      containsAll(['$relative#fixtureAttached', '$relative#fixtureAppended']),
    );
  });

  test('a second project does not collide with the first', () async {
    // Every daemon runs out of the GUI's package, so they all wanted one
    // `app/build/catalog`: the generated entrypoint, the compiler's output, the
    // published kernel, the session directories. Two catalogs then generated
    // wrappers over each other and compiled to the same file, and a name
    // present in both projects — `wrapInApp`, which each project's demo shell
    // exports — resolved to whichever wrote last. The symptom was a hot reload
    // failing with `lookup Failed: wrapInApp in @method`, intermittently, in
    // whichever catalog lost the race.
    var (other, otherReady) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: DaemonConfig.forPackage(
        appToolDirectory: appRoot,
        packageRoot: p.join(p.dirname(appRoot), 'examples', 'example'),
        flutterSdkRoot: flutterRoot,
        roots: const ['demo'],
      ),
      onLog: (line) => print('  [other] $line'),
    );
    addTearDown(other.close);

    expect(otherReady.entries, isNotEmpty, reason: 'it has its own entries');
    expect(
      otherReady.assetsDir,
      isNot(ready.assetsDir),
      reason: 'and its own working directory',
    );
    // The first project must still compile *after* the second has generated its
    // own entrypoint — that is the collision.
    var afterOther = await daemon.select(entry('counter').id);
    expect(
      afterOther.ok,
      isTrue,
      reason: 'the first project still compiles: ${afterOther.error}',
    );
  });

  test('a quarantine survives a restart, and a repair ends it', () async {
    // **A start that has to rediscover a broken demo costs three compiles** —
    // the one that fails, the one that succeeds without it, and the
    // whole-program rebuild that repairs the delta. Measured on this catalog:
    // 5.5s against 1.2s. Paid on every start, for a fact the previous run
    // already had.
    //
    // Its own project rather than the shared daemon's, so stopping and starting
    // a daemon three times here does not pull the compiler out from under
    // every other test in this file.
    var projectRoot = p.join(p.dirname(appRoot), 'examples', 'example');
    var otherConfig = DaemonConfig.forPackage(
      appToolDirectory: appRoot,
      packageRoot: projectRoot,
      flutterSdkRoot: flutterRoot,
      roots: const ['demo'],
    );

    var broken = File(p.join(projectRoot, 'demo', 'fixture_broken.dart'));
    addTearDown(() async {
      if (broken.existsSync()) broken.deleteSync();
      // Left running, this daemon serves an entry whose file is gone.
      var (last, _) = await CompilerDaemonClient.connect(
        dartExecutable: dartExecutable,
        config: otherConfig,
      );
      await last.stopDaemon();
    });

    Future<DaemonReady> restart() async {
      var (client, ready) = await CompilerDaemonClient.connect(
        dartExecutable: dartExecutable,
        config: otherConfig,
      );
      await client.stopDaemon();
      return ready;
    }

    // Nothing serving, and nothing remembered: a first encounter.
    await restart();
    broken.writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Broken')
Widget fixtureBroken() => NoSuchWidgetExistsHere();
''');

    var discovered = await restart();
    expect(
      discovered.quarantined.map((q) => q.entry.symbol),
      contains('fixtureBroken'),
    );
    expect(
      discovered.timings.keys,
      contains('rebuild after quarantine'),
      reason: 'discovering it costs the blame cycle and the rebuild',
    );

    var remembered = await restart();
    expect(
      remembered.quarantined.map((q) => q.entry.symbol),
      contains('fixtureBroken'),
      reason: 'the entry is still held back, and still carries its error',
    );
    expect(
      remembered.timings.keys,
      isNot(contains('rebuild after quarantine')),
      reason:
          'nothing was blamed this time, because the entrypoint was generated '
          'without it — which is the whole saving',
    );

    // **The safety property.** The record is only honoured while the source is
    // exactly as old as it was when it failed. Anything else and the entry is
    // compiled like any other, so a repair can never be locked out by a stale
    // note — which is the one way this optimisation could do real harm.
    broken.writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Broken')
Widget fixtureBroken() => const Placeholder();
''');

    var repaired = await restart();
    expect(repaired.quarantined, isEmpty);
    expect(
      repaired.entries.map((e) => e.symbol),
      contains('fixtureBroken'),
      reason: 'fixing the demo is enough to get it back',
    );
  });

  test('a line the daemon cannot read does not take it down', () async {
    // The daemon reads a line and decodes it into a request, and used to do
    // that without a guard — so an unknown request type threw a
    // `FormatException` out of a `listen` callback, which is an unhandled async
    // error, which kills the isolate. Every other client's warm compiler died
    // with it, and the only evidence was a socket that stopped answering.
    //
    // From a raw socket rather than through the client, because the client is
    // exactly what cannot produce this: the failure arrives from something the
    // daemon was not built to expect — a newer client, a stray line — and the
    // property under test is that the process survives it.
    var rude = await Socket.connect(
      InternetAddress(
        daemon.address.socketPath,
        type: InternetAddressType.unix,
      ),
      0,
    );
    rude
      ..writeln('{"type":"a-request-from-a-later-flutterware"}')
      ..writeln('{"no":"type at all"}')
      ..writeln('not json in the first place');
    await rude.flush();
    await rude.close();
    rude.destroy();

    var after = await daemon.select(entry('counter').id);
    expect(after.ok, isTrue, reason: 'still serving: ${after.error}');
  });

  test(
    'a daemon that fails to prepare says why, without the 30s wait',
    () async {
      // **The regression this exists for is a stopwatch, not a message.**
      //
      // A daemon whose preparation fails quickly fails before its client has
      // connected: it binds, scans, throws, sends `DaemonFailed` to an empty
      // session list, unlinks the socket and exits — all inside a few
      // milliseconds. The client was then polling a path that would never come
      // back, and did so until its 30-second deadline before reporting "never
      // started listening", which names no cause at all.
      //
      // Measured before the fix: **31629ms** for a catalog directory holding
      // nothing, which the daemon had detected in 1ms. After: 249ms warm.
      // The reason now goes to a file the client checks while it polls.
      var watch = Stopwatch()..start();
      await expectLater(
        CompilerDaemonClient.connect(
          dartExecutable: dartExecutable,
          config: DaemonConfig.forPackage(
            appToolDirectory: appRoot,
            packageRoot: appRoot,
            flutterSdkRoot: flutterRoot,
            roots: const ['tool/catalog/no_such_directory'],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              // The cause, not the timeout.
              contains('no catalog entries found'),
              isNot(contains('never started listening')),
              // Where it looked, absolutely, and that the place is not there —
              // the two questions a bare relative root left unanswered.
              contains(p.join(appRoot, 'tool', 'catalog', 'no_such_directory')),
              contains('does not exist'),
              // And the way out.
              contains('directory:'),
            ),
          ),
        ),
      );
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 15)),
        reason:
            'the failure took ${watch.elapsedMilliseconds}ms — it used to take '
            'the full 30s deadline, which is the bug this guards',
      );
    },
  );

  test('a recorded failure is read once, so a retry is not poisoned', () async {
    // The marker outlives the process that wrote it, which is the point and
    // also the hazard: found again on the next connect it would report a
    // failure that has since been fixed. It is deleted as it is read, and
    // again before every spawn.
    var failing = DaemonConfig.forPackage(
      appToolDirectory: appRoot,
      packageRoot: appRoot,
      flutterSdkRoot: flutterRoot,
      roots: const ['tool/catalog/still_not_there'],
    );
    await expectLater(
      CompilerDaemonClient.connect(
        dartExecutable: dartExecutable,
        config: failing,
      ),
      throwsA(isA<StateError>()),
    );

    // A different package, whose daemon has no reason to fail, must not pick
    // up anything left behind — and the failing one must fail on its own
    // merits a second time rather than on a stale file.
    var (client, ready) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    expect(ready.entries, isNotEmpty);
    await client.close();

    await expectLater(
      CompilerDaemonClient.connect(
        dartExecutable: dartExecutable,
        config: failing,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('no catalog entries found'),
        ),
      ),
    );
  });
}

/// This package's root, from its own package URI rather than from
/// [Platform.script] or the working directory — under `dart test` the script is
/// a generated entrypoint, and the working directory is whoever's shell.
Future<String> _appPackageRoot() async {
  var lib = await Isolate.resolvePackageUri(
    Uri.parse('package:flutterware_app/flutterware_app.dart'),
  );
  return p.dirname(p.dirname(p.fromUri(lib!)));
}

String _preview(String symbol, String text) =>
    '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Fixture')
Widget $symbol() => const Center(child: Text('$text'));
''';

/// The same demo with a type that does not exist, which is what makes the
/// compiler blame this file — and so what makes the entry quarantinable.
String _brokenPreview(String symbol) =>
    '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Fixture')
Widget $symbol() => ThisTypeDoesNotExist(missing: 1);
''';
