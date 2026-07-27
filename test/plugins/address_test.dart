import 'package:flutterware/plugins.dart';
import 'package:test/test.dart';

void main() {
  group('parse', () {
    test('worktree, plugin and segments', () {
      var address = Address.parse(
        'fw://main/flutterware.ui_catalog/packages/admin/Team',
      );
      expect(address.worktree, 'main');
      expect(address.plugin, 'flutterware.ui_catalog');
      expect(address.segments, ['packages', 'admin', 'Team']);
      expect(address.path, 'packages/admin/Team');
      expect(address.isRelative, isFalse);
    });

    test('empty authority means session-relative', () {
      var address = Address.parse('fw:///flutterware.tests/admin');
      expect(address.isRelative, isTrue);
      expect(address.worktree, isNull);
      expect(address.plugin, 'flutterware.tests');
      expect(address.segments, ['admin']);
    });

    test('worktree alone, with and without a trailing slash', () {
      for (var source in ['fw://feature-x', 'fw://feature-x/']) {
        var address = Address.parse(source);
        expect(address.worktree, 'feature-x', reason: source);
        expect(address.plugin, isNull, reason: source);
        expect(address.segments, isEmpty, reason: source);
      }
    });

    test('worktree case is preserved', () {
      // Uri.parse would lowercase the authority; a worktree directory may
      // legitimately have capitals.
      expect(Address.parse('fw://MyWorktree/p').worktree, 'MyWorktree');
    });

    test('axes are decoded and sorted', () {
      var address = Address.parse(
        'fw://main/p/e?theme=dark&device=iPhone%2015&locale=fr_FR',
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
        'fw://main/flutterware.ui_catalog/lib%2Fdemo%2Fteam.dart%23TeamList',
      );
      expect(address.segments, ['lib/demo/team.dart#TeamList']);
    });

    test('tryParse rejects malformed input', () {
      for (var source in [
        'http://main/p',
        'main/p',
        '',
        'fw://main/p#TeamList', // a raw fragment must be encoded, not dropped
        'fw://main/p//e', // empty segment
        'fw://main/p?novalue',
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
        'fw://main',
        'fw:///flutterware.tests',
        'fw://main/flutterware.ui_catalog/packages/admin/Team',
        'fw://main/p/e?device=iPhone%2015&theme=dark',
        'fw://main/flutterware.ui_catalog/lib%2Fdemo%2Fteam.dart%23TeamList',
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
      expect(written.toString(), 'fw://main/p?device=phone&theme=dark');
    });
  });

  group('construction', () {
    test('segments without a plugin are rejected', () {
      expect(
        () => Address(worktree: 'main', segments: ['e']),
        throwsArgumentError,
      );
    });

    test('empty worktree or plugin is rejected', () {
      expect(() => Address(worktree: ''), throwsArgumentError);
      expect(() => Address(plugin: ''), throwsArgumentError);
    });
  });

  group('derivation', () {
    var base = Address.parse('fw:///flutterware.ui_catalog/admin?theme=dark');

    test('resolveIn fills a relative address and leaves an absolute one', () {
      expect(base.resolveIn('main').worktree, 'main');
      expect(base.resolveIn('main').resolveIn('other').worktree, 'main');
    });

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
  });

  group('equality', () {
    test('two addresses naming the same thing are equal and hash alike', () {
      var a = Address.parse('fw://main/p/e?theme=dark&locale=fr');
      var b = Address.parse('fw://main/p/e?locale=fr&theme=dark');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('axes are part of identity', () {
      expect(
        Address.parse('fw://main/p/e?theme=dark'),
        isNot(Address.parse('fw://main/p/e?theme=light')),
      );
    });

    test('a relative address is not equal to a resolved one', () {
      expect(Address.parse('fw:///p'), isNot(Address.parse('fw://main/p')));
    });
  });
}
