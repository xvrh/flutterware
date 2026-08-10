import 'package:flutterware/plugins.dart';
import 'package:test/test.dart';

void main() {
  group('parse', () {
    test('space, worktree, plugin and segments', () {
      var address = Address.parse(
        'fw:///worktrees/main/flutterware.ui_catalog/packages/admin/Team',
      );
      expect(address.project, isNull);
      expect(address.space, Address.worktreesSpace);
      expect(address.worktree, 'main');
      expect(address.plugin, 'flutterware.ui_catalog');
      expect(address.segments, ['packages', 'admin', 'Team']);
      expect(address.path, 'packages/admin/Team');
    });

    test("an empty authority means this session's project", () {
      // Which is every address anything emits today: one shell is one repo.
      expect(Address.parse('fw:///worktrees/main/p').project, isNull);
    });

    test('a project may be named, for an address that crossed', () {
      var address = Address.parse('fw://acme/worktrees/main/p');
      expect(address.project, 'acme');
      expect(address.space, Address.worktreesSpace);
      expect(address.worktree, 'main');
      expect(address.plugin, 'p');
    });

    test('naming nothing at all', () {
      for (var source in ['fw:///', 'fw://']) {
        var address = Address.parse(source);
        expect(address.project, isNull, reason: source);
        expect(address.space, isNull, reason: source);
        expect(address.worktree, isNull, reason: source);
        expect(address.plugin, isNull, reason: source);
      }
    });

    test('the space alone, naming the collection', () {
      for (var source in ['fw:///worktrees', 'fw:///worktrees/']) {
        var address = Address.parse(source);
        expect(address.space, Address.worktreesSpace, reason: source);
        expect(address.worktree, isNull, reason: source);
        expect(address.plugin, isNull, reason: source);
      }
    });

    test('a space name is data — the parser knows of no registry', () {
      // An unknown space resolves to nothing, which is reported where an
      // unknown worktree already is. It is not a parse failure.
      expect(Address.parse('fw:///ports').space, 'ports');
    });

    test('worktree alone, with and without a trailing slash', () {
      for (var source in [
        'fw:///worktrees/feature-x',
        'fw:///worktrees/feature-x/',
      ]) {
        var address = Address.parse(source);
        expect(address.worktree, 'feature-x', reason: source);
        expect(address.plugin, isNull, reason: source);
        expect(address.segments, isEmpty, reason: source);
      }
    });

    test('the old spaceless shape no longer names a worktree', () {
      // Deliberate: there is no compatibility branch, because telling a space
      // from a worktree name would need the registry of known spaces this
      // change exists to avoid.
      expect(Address.tryParse('fw:///main/flutterware.ui_catalog'), isNull);
      expect(Address.parse('fw:///main').worktree, isNull);
    });

    test('worktree case is preserved', () {
      // The reason the worktree is a path segment and not the authority: an
      // authority is case-insensitive and gets lowercased, and a worktree
      // directory may legitimately have capitals.
      expect(
        Address.parse('fw:///worktrees/MyWorktree/p').worktree,
        'MyWorktree',
      );
    });

    test('axes are decoded and sorted', () {
      var address = Address.parse(
        'fw:///worktrees/main/p/e?theme=dark&device=iPhone%2015&locale=fr_FR',
      );
      expect(address.axes, {
        'device': 'iPhone 15',
        'locale': 'fr_FR',
        'theme': 'dark',
      });
      expect(address.axes.keys, ['device', 'locale', 'theme']);
    });

    test('a segment may carry encoded structural characters', () {
      var address = Address.parse(
        'fw:///worktrees/main/flutterware.ui_catalog/'
        'lib%2Fdemo%2Fteam.dart%23TeamList',
      );
      expect(address.segments, ['lib/demo/team.dart#TeamList']);
    });

    test('tryParse rejects malformed input', () {
      for (var source in [
        'http://main/p',
        'main/p',
        '',
        // a raw fragment must be encoded, not dropped
        'fw:///worktrees/main/p#TeamList',
        'fw:///worktrees/main/p//e', // empty segment
        'fw:///worktrees/main/p?novalue',
        'fw:///ports/main/p', // only the worktrees space has worktrees
      ]) {
        expect(Address.tryParse(source), isNull, reason: source);
      }
    });

    test('parse throws where tryParse returns null', () {
      expect(() => Address.parse('nope'), throwsFormatException);
    });
  });

  group('toString', () {
    test('round-trips every shape', () {
      var encoded =
          'fw:///worktrees/main/flutterware.ui_catalog/'
          'lib%2Fdemo%2Fteam.dart%23TeamList';
      for (var source in [
        'fw:///',
        'fw:///worktrees',
        'fw:///worktrees/main',
        'fw:///worktrees/main/flutterware.ui_catalog/packages/admin/Team',
        'fw:///worktrees/main/p/e?device=iPhone%2015&theme=dark',
        encoded,
        'fw://acme/worktrees/main/p',
        'fw:///worktrees/~/flutterware.dependencies/app/packages/collection',
      ]) {
        expect(Address.parse(source).toString(), source, reason: source);
      }
    });

    test('the collection, built rather than parsed', () {
      var space = Address(space: Address.worktreesSpace);
      expect(space.toString(), 'fw:///worktrees');
      expect(Address.parse(space.toString()), space);
    });

    test('is canonical — axis order does not survive', () {
      var written = Address(
        worktree: 'main',
        plugin: 'p',
        axes: {'theme': 'dark', 'device': 'phone'},
      );
      expect(
        written.toString(),
        'fw:///worktrees/main/p?device=phone&theme=dark',
      );
    });

    test('the // survives an empty project', () {
      // Not cosmetic. Autolinkers key on `\\w+://`, so the RFC-equally-correct
      // `fw:/…` would not become a link anywhere it matters — and a link is how
      // an address gets from a chat window back into the app.
      expect(Address(worktree: 'main').toString(), startsWith('fw://'));
    });
  });

  group('Uri.parse agrees with us', () {
    // The reason the worktree stopped being the authority. While it was one,
    // this could not hold — and a parser that disagrees with the platform's is
    // a bug waiting for whoever reaches for `Uri` first. The space is a path
    // segment for the same reason.
    var cases = {
      'fw:///worktrees': ['worktrees'],
      'fw:///worktrees/main/p': ['worktrees', 'main', 'p'],
      'fw:///worktrees/MyWorktree/p': ['worktrees', 'MyWorktree', 'p'],
      'fw:///worktrees/~/flutterware.dependencies/app': [
        'worktrees',
        '~',
        'flutterware.dependencies',
        'app',
      ],
      'fw:///worktrees/main/c/lib%2Fdemo%2Fteam.dart%23TeamList': [
        'worktrees',
        'main',
        'c',
        'lib/demo/team.dart#TeamList',
      ],
    };

    cases.forEach((source, segments) {
      test(source, () {
        var uri = Uri.parse(source);
        expect(uri.scheme, Address.scheme);
        expect(uri.authority, isEmpty);
        expect(uri.pathSegments, segments);
      });
    });

    test('and on the axes', () {
      var uri = Uri.parse(
        'fw:///worktrees/main/p?axis.theme=dark&device=iPhone%2015',
      );
      expect(uri.queryParameters, {
        'axis.theme': 'dark',
        'device': 'iPhone 15',
      });
    });

    test('except a segment of only dots, which nothing can produce', () {
      // The one place the two part company, and it cannot be closed: Dart's
      // `Uri` decodes before it normalises, so `..` is resolved away however it
      // is escaped — `%2E%2E` included, verified. Our own round trip still
      // holds; it is only `Uri.parse` that loses it. Git sanitises worktree
      // names and no plugin or entry id is only dots, so nothing reaches here.
      var address = Address(worktree: '..', plugin: 'p');
      expect(Address.parse(address.toString()), address);
      expect(Uri.parse(address.toString()).pathSegments, ['p']);
    });
  });

  group('construction', () {
    test('a worktree implies its space', () {
      // What keeps the ~26 sites that name a worktree and a plugin unchanged.
      expect(Address(worktree: 'main').space, Address.worktreesSpace);
      expect(Address().space, isNull);
    });

    test('a worktree in another space is rejected', () {
      expect(
        () => Address(space: 'ports', worktree: 'main'),
        throwsArgumentError,
      );
    });

    test('segments without a plugin are rejected', () {
      expect(
        () => Address(worktree: 'main', segments: ['e']),
        throwsArgumentError,
      );
    });

    test('a plugin without a worktree is rejected', () {
      // The path is positional: a plugin sits after a worktree, so there is no
      // shape in which it can appear without one.
      expect(() => Address(plugin: 'p'), throwsArgumentError);
    });

    test('empty project, space, worktree or plugin is rejected', () {
      expect(() => Address(project: ''), throwsArgumentError);
      expect(() => Address(space: ''), throwsArgumentError);
      expect(() => Address(worktree: ''), throwsArgumentError);
      expect(() => Address(worktree: 'main', plugin: ''), throwsArgumentError);
    });
  });

  group('derivation', () {
    var base = Address.parse(
      'fw:///worktrees/main/flutterware.ui_catalog/admin?theme=dark',
    );

    test('child appends a segment', () {
      expect(base.child('Team').segments, ['admin', 'Team']);
    });

    test('withAxes merges over the existing ones', () {
      var next = base.withAxes({'theme': 'light', 'locale': 'fr'});
      expect(next.axes, {'locale': 'fr', 'theme': 'light'});
    });

    test('bare strips the axes and keeps the identity', () {
      expect(base.bare.axes, isEmpty);
      expect(base.bare.space, Address.worktreesSpace);
      expect(base.bare.segments, ['admin']);
      expect(base.withAxes({'theme': 'light'}).bare, base.bare);
    });

    test('copyWith carries the project', () {
      var scoped = Address.parse('fw://acme/worktrees/main/p');
      expect(scoped.child('e').project, 'acme');
      expect(scoped.bare.project, 'acme');
    });
  });

  group('equality', () {
    test('two addresses naming the same thing are equal and hash alike', () {
      var a = Address.parse('fw:///worktrees/main/p/e?theme=dark&locale=fr');
      var b = Address.parse('fw:///worktrees/main/p/e?locale=fr&theme=dark');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('the named parts and the parsed ones agree', () {
      expect(
        Address.parse('fw:///worktrees/main/p/e'),
        Address(worktree: 'main', plugin: 'p', segments: ['e']),
      );
    });

    test('axes are part of identity', () {
      expect(
        Address.parse('fw:///worktrees/main/p/e?theme=dark'),
        isNot(Address.parse('fw:///worktrees/main/p/e?theme=light')),
      );
    });

    test('the space is part of identity', () {
      expect(Address(space: Address.worktreesSpace), isNot(Address()));
    });

    test('the project is part of identity', () {
      expect(
        Address.parse('fw:///worktrees/main/p'),
        isNot(Address.parse('fw://acme/worktrees/main/p')),
      );
    });
  });
}
