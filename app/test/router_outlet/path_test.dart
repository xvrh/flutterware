import 'package:flutter_studio_app/src/utils/router_outlet/path.dart';
import 'package:test/test.dart';

void main() {
  test('PathPage class', () {
    expect(PagePath('', isAbsolute: true).toString(), '/');
    expect(PagePath('', isAbsolute: false).toString(), '');
    expect(PagePath.root.toString(), '/');
    expect(PagePath('some/url//').toString(), 'some/url');
    expect(PagePath('/some/url//').toString(), '/some/url');
    expect(PagePath('some/url', isAbsolute: true).toString(), '/some/url');
    expect(PagePath('//some/url', isAbsolute: true).toString(), '/some/url');
    expect('${PagePath(' //some//url//', isAbsolute: false)}', 'some/url');
    expect(PagePath('//some/url'), PagePath('/some/url'));
  });

  test('PathPage relative', () {
    expect(PagePath('aa/../bb').toString(), 'bb');
  });

  test('PathPattern.rootPath', () {
    var path = PagePath('/home');
    var rootMatch = path.rootMatch;
    expect(rootMatch.matched, PagePath('', isAbsolute: true));
    expect(rootMatch.full, path);
    expect(rootMatch.remaining, PagePath('home'));
    expect(rootMatch.args, {});
    expect(rootMatch.current, PagePath(''));
  });

  test('PathPattern class', () {
    expect(PathPattern('').pattern, '');
    expect(PathPattern('/home').pattern, 'home');
    expect(PathPattern('/home/:id-user').pattern, 'home/:id-user');
  });

  test('MatchedPath class 1', () {
    var path = PagePath('/users/1/profile');

    var matched = path.rootMatch.matchesRemaining(PathPattern('users/:id'))!;

    expect(matched.full.toString(), '/users/1/profile');
    expect(matched.matched.toString(), '/users/1');
    expect(matched.current.toString(), 'users/1');
    expect(matched.remaining.toString(), 'profile');
    expect(matched.args, {'id': '1'});
  });

  test('MatchedPath class 2', () {
    var path = PagePath('/users/1/profile');

    var matched = path.rootMatch
        .matchesRemaining(PathPattern('users'))!
        .matchesRemaining(PathPattern(':id'))!;

    expect(matched.pattern.pattern, ':id');
    expect(matched.full.toString(), '/users/1/profile');
    expect(matched.matched.toString(), '/users/1');
    expect(matched.current.toString(), '1');
    expect(matched.remaining.toString(), 'profile');
    expect(matched.args, {'id': '1'});
  });

  test('MatchedPath equals', () {
    var path = PagePath('/users/1/profile');

    var matched1 = path.rootMatch.matchesRemaining(PathPattern('users/:id'))!;
    var matched2 = path.rootMatch.matchesRemaining(PathPattern('users/:id'))!;
    expect(matched1, matched2);
    expect(matched1.hashCode, matched2.hashCode);
    expect(
        [
          path.rootMatch.matchesRemaining(PathPattern('users/:id'))!
        ].contains(path.rootMatch.matchesRemaining(PathPattern('users/:id'))!),
        isTrue);
  });

  test('MatchedPath class 3', () {
    var path = PagePath('/users/1-456/profile');

    var matched = path.rootMatch
        .matchesRemaining(PathPattern('users'))!
        .matchesRemaining(PathPattern(':id-:mac/profile'))!;

    expect(matched.full.toString(), '/users/1-456/profile');
    expect(matched.matched.toString(), '/users/1-456/profile');
    expect(matched.current.toString(), '1-456/profile');
    expect(matched.remaining.toString(), '');
    expect(matched.args, {'id': '1', 'mac': '456'});
  });

  test('MatchedPath decode parameters', () {
    var path = PagePath('/users/${Uri.encodeComponent('àab machin')}');

    var matched = path.rootMatch.matchesRemaining(PathPattern('users/:name'))!;

    expect(matched.full.toString(), '/users/%C3%A0ab%20machin');
    expect(matched.args, {'name': 'àab machin'});
  });

  test('MatchedPath.go 1', () {
    var path = PagePath('/users');

    var matched = path.rootMatch.matchesRemaining(PathPattern('users'))!;

    var newPath = matched.go('url');
    expect(newPath.toString(), '/users/url');

    var newPath2 = matched.go('/url');
    expect(newPath2.toString(), '/url');
  });

  test('MatchedPath.go 2', () {
    var path = PagePath('/users/1/profile');
    var matched = path.rootMatch.matchesRemaining(PathPattern('users'))!;

    var newPath = matched.go('url');
    expect(newPath.toString(), '/users/url');

    var newPath2 = matched.go('/url');
    expect(newPath2.toString(), '/url');
  });

  test('MatchedPath.go 3', () {
    var path = PagePath('/users/1/profile');
    var matched = path.rootMatch
        .matchesRemaining(PathPattern('users'))!
        .matchesRemaining(PathPattern(':id'))!;

    var newPath = matched.go('url');
    expect(newPath.toString(), '/users/1/url');

    var newPath2 = matched.go('/url');
    expect(newPath2.toString(), '/url');
  });

  test('MatchedPath.go up', () {
    var path = PagePath('/users/1/profile');
    var matched = path.rootMatch
        .matchesRemaining(PathPattern('users'))!
        .matchesRemaining(PathPattern(':id'))!;

    expect(matched.go('..').toString(), '/users');
    expect(matched.go('../2').toString(), '/users/2');
    expect(matched.go('../2/profile').toString(), '/users/2/profile');
    expect(matched.go('../../home').toString(), '/home');
    expect(matched.go('../../../home').toString(), '/../home');
  });

  test('MatchedPath.isSelected 1', () {
    var path = PagePath('/home/profile');
    var matched = path.rootMatch;

    expect(matched.isSelected('home'), true);
    expect(matched.isSelected('users'), false);
  });

  test('MatchedPath.isSelected 2', () {
    var path = PagePath('/home/profile/other');
    var matched = path.rootMatch.matchesRemaining(PathPattern('home'))!;
    expect(matched.isSelected('profile'), true);
    expect(matched.isSelected('profile/other'), true);
    expect(matched.isSelected('other'), false);
    expect(matched.isSelected('/other'), false);
    expect(matched.isSelected('/home'), true);
  });

  test('MatchedPath.isSelected 2', () {
    var path = PagePath('/home/profile/other');
    var matched = path.rootMatch.matchesRemaining(PathPattern('home'))!;
    expect(matched.isSelected('profile'), true);
    expect(matched.isSelected('profile/other'), true);
    expect(matched.isSelected('other'), false);
    expect(matched.isSelected('/other'), false);
    expect(matched.isSelected('/home'), true);
  });

  test('MatchedPath.isSelected 3', () {
    var path = PagePath('/home/profile/1');
    var rootMatch = path.rootMatch;
    var profileMatch =
        path.rootMatch.matchesRemaining(PathPattern('home/profile'))!;

    expect(rootMatch.selection('home'), SelectionType.ancestor);
    expect(rootMatch.selection('users'), SelectionType.none);
    expect(rootMatch.selection('home/profile'), SelectionType.ancestor);
    expect(rootMatch.selection('/home/profile/'), SelectionType.ancestor);
    expect(rootMatch.selection('/home/profile'), SelectionType.ancestor);
    expect(profileMatch.selection(''), SelectionType.ancestor);
    expect(profileMatch.selection('1'), SelectionType.selected);
    expect(profileMatch.selection('1/'), SelectionType.selected);
    expect(profileMatch.selection('/1'), SelectionType.none);
  });

  test('MatchedPath.selectedIndex', () {
    var path = PagePath('/users/1');
    var matched = path.rootMatch;
    expect(matched.selectedIndex(['', 'users', 'other']), 1);
  });
}
