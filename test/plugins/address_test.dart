import 'package:flutterware/plugins.dart';
import 'package:test/test.dart';

void main() {
  group('parse', () {
    test('worktree, plugin and segments', () {
      var address = Address.parse(
        'fw:///main/flutterware.ui_catalog/packages/admin/Team',
      );
      expect(address.project, isNull);
      expect(address.worktree, 'main');
      expect(address.plugin, 'flutterware.ui_catalog');
      expect(address.segments, ['packages', 'admin', 'Team']);
      expect(address.path, 'packages/admin/Team');
    });

    test("an empty authority means this session's project", () {
      // Which is every address anything emits today: one shell is one repo.
      expect(Address.parse('fw:///main/p').project, isNull);
    });

    test('a project may be named, for an address that crossed', () {
      var address = Address.parse('fw://acme/main/p');
      expect(address.project, 'acme');
      expect(address.worktree, 'main');
      expect(address.plugin, 'p');
    });

    test('naming nothing at all', () {
      for (var source in ['fw:///', 'fw://']) {
        var address = Address.parse(source);
        expect(address.project, isNull, reason: source);
        expect(address.worktree, isNull, reason: source);
        expect(address.plugin, isNull, reason: source);
      }
    });

    test('worktree alone, with and without a trailing slash', () {
      for (var source in ['fw:///feature-x', 'fw:///feature-x/']) {
        var address = Address.parse(source);
        expect(address.worktree, 'feature-x', reason: source);
        expect(address.plugin, isNull, reason: source);
        expect(address.segments, isEmpty, reason: source);
      }
    });

    test('worktree case is preserved', () {
      // The reason the worktree is a path segment and not the authority: an
      // authority is case-insensitive and gets lowercased, and a worktree
      // directory may legitimately have capitals.
      expect(Address.parse('fw:///MyWorktree/p').worktree, 'MyWorktree');
    });

    test('axes are decoded and sorted', () {
      var address = Address.parse(
        'fw:///main/p/e?theme=dark&device=iPhone%2015&locale=fr_FR',
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
        'fw:///main/flutterware.ui_catalog/lib%2Fdemo%2Fteam.dart%23TeamList',
      );
      expect(address.segments, ['lib/demo/team.dart#TeamList']);
    });

    test('tryParse rejects malformed input', () {
      for (var source in [
        'http://main/p',
        'main/p',
        '',
        'fw:///main/p#TeamList', // a raw fragment must be encoded, not dropped
        'fw:///main/p//e', // empty segment
        'fw:///main/p?novalue',
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
      for (var source in [
        'fw:///',
        'fw:///main',
        'fw:///main/flutterware.ui_catalog/packages/admin/Team',
        'fw:///main/p/e?device=iPhone%2015&theme=dark',
        'fw:///main/flutterware.ui_catalog/lib%2Fdemo%2Fteam.dart%23TeamList',
        'fw://acme/main/p',
        'fw:///~/flutterware.dependencies/app/packages/collection',
      ]) {
        expect(Address.parse(source).toString(), source, reason: source);
      }
    });

    test('is canonical — axis order does not survive', () {
      var written = Address(
        worktree: 'main',
        plugin: 'p',
        axes: {'theme': 'dark', 'device': 'phone'},
      );
      expect(written.toString(), 'fw:///main/p?device=phone&theme=dark');
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
    // a bug waiting for whoever reaches for `Uri` first.
    var cases = {
      'fw:///main/p': ['main', 'p'],
      'fw:///MyWorktree/p': ['MyWorktree', 'p'],
      'fw:///~/flutterware.dependencies/app': [
        '~',
        'flutterware.dependencies',
        'app',
      ],
      'fw:///main/c/lib%2Fdemo%2Fteam.dart%23TeamList': [
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
      var uri = Uri.parse('fw:///main/p?axis.theme=dark&device=iPhone%2015');
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

    test('empty project, worktree or plugin is rejected', () {
      expect(() => Address(project: ''), throwsArgumentError);
      expect(() => Address(worktree: ''), throwsArgumentError);
      expect(() => Address(worktree: 'main', plugin: ''), throwsArgumentError);
    });
  });

  group('derivation', () {
    var base = Address.parse(
      'fw:///main/flutterware.ui_catalog/admin?theme=dark',
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
      expect(base.bare.segments, ['admin']);
      expect(base.withAxes({'theme': 'light'}).bare, base.bare);
    });

    test('copyWith carries the project', () {
      var scoped = Address.parse('fw://acme/main/p');
      expect(scoped.child('e').project, 'acme');
      expect(scoped.bare.project, 'acme');
    });
  });

  group('equality', () {
    test('two addresses naming the same thing are equal and hash alike', () {
      var a = Address.parse('fw:///main/p/e?theme=dark&locale=fr');
      var b = Address.parse('fw:///main/p/e?locale=fr&theme=dark');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('axes are part of identity', () {
      expect(
        Address.parse('fw:///main/p/e?theme=dark'),
        isNot(Address.parse('fw:///main/p/e?theme=light')),
      );
    });

    test('the project is part of identity', () {
      expect(
        Address.parse('fw:///main/p'),
        isNot(Address.parse('fw://acme/main/p')),
      );
    });
  });
}
