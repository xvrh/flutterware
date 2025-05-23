import 'package:flutterware/src/router_outlet/path.dart';
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

    expect(rootMatch.isSelectedType('home'), RouteSelectedType.descendant);
    expect(rootMatch.isSelectedType('users'), null);
    expect(
        rootMatch.isSelectedType('home/profile'), RouteSelectedType.descendant);
    expect(rootMatch.isSelectedType('/home/profile/'),
        RouteSelectedType.descendant);
    expect(rootMatch.isSelectedType('/home/profile'),
        RouteSelectedType.descendant);
    expect(profileMatch.isSelectedType(''), RouteSelectedType.descendant);
    expect(profileMatch.isSelectedType('1'), RouteSelectedType.self);
    expect(profileMatch.isSelectedType('1/'), RouteSelectedType.self);
    expect(profileMatch.isSelectedType('/1'), null);
  });

  test('MatchedPath.selectedIndex', () {
    var path = PagePath('/users/1');
    var matched = path.rootMatch;
    expect(matched.selectedIndex(['', 'users', 'other']), 1);
  });

  test('Query parameters in PagePath', () {
    expect(PagePath('some/url?query=true&param=false').queryParameters,
        {'query': 'true', 'param': 'false'});
    expect(PagePath('some/url?').queryParameters, {});
    expect(PagePath('some/url').queryParameters, {});
    expect(PagePath('some/url?a').queryParameters, {'a': ''});
    expect(PagePath('some/url?a').toString(), 'some/url?a');
    expect(PagePath('some/url?query=true&param=false').toString(),
        'some/url?query=true&param=false');
  });

  test('MatchedPath decode query parameters parameters', () {
    var path = PagePath('/users/machin?arg=1');

    var matched = path.rootMatch.matchesRemaining(PathPattern('users/:name'))!;

    expect(matched.queryParameters, {'arg': '1'});
    expect(matched.full.toString(), '/users/machin?arg=1');
    expect(matched.current.toString(), 'users/machin');
  });

  test('MatchedPath.go 3 with query parameters', () {
    var path = PagePath('/users/1/profile?auto');
    var matched = path.rootMatch
        .matchesRemaining(PathPattern('users'))!
        .matchesRemaining(PathPattern(':id'))!;

    var newPath = matched.go('url');
    expect(newPath.toString(), '/users/1/url');

    var newPath2 = matched.go('/url');
    expect(newPath2.toString(), '/url');
  });

  test('MatchedPath.go 3 with extra parameters', () {
    var path = PagePath('/users/1/profile?auto');
    var matched = path.rootMatch
        .matchesRemaining(PathPattern('users'))!
        .matchesRemaining(PathPattern(':id'))!;

    var newPath = matched.go('url', extra: {'one': 1});
    expect(newPath.extra, {'one': 1});

    var newPath2 = matched.go('/url');
    expect(newPath2.extra, {});
  });

  test('Navigate with extra parameters', () {
    var matched = PagePath.root.rootMatch;

    var newPath = matched.go('/', extra: {'one': 1});
    expect(newPath.extra, {'one': 1});
    expect(newPath.isAbsolute, true);
    expect(newPath.toPath(), '/');

    var newPath2 = matched.go('/url');
    expect(newPath2.extra, {});
  });
}
