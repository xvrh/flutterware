import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/permission_matrix.dart';
import 'package:flutterware_app/src/run/permission_write.dart';

void main() {
  group('parseMatrixProfiles', () {
    test('nothing means every profile', () {
      expect(parseMatrixProfiles(null).profiles, PermissionProfile.values);
      expect(parseMatrixProfiles('').profiles, PermissionProfile.values);
      expect(
        parseMatrixProfiles(const <String>[]).profiles,
        PermissionProfile.values,
      );
    });

    test('keeps the order it was given', () {
      var parsed = parseMatrixProfiles('granted,first-run');
      expect(parsed.error, isNull);
      expect(parsed.profiles, [
        PermissionProfile.granted,
        PermissionProfile.firstRun,
      ]);
    });

    test('tolerates spaces and empty entries', () {
      expect(parseMatrixProfiles(' granted , , denied ').profiles, [
        PermissionProfile.granted,
        PermissionProfile.denied,
      ]);
    });

    test('collapses duplicates rather than running a cell twice', () {
      expect(parseMatrixProfiles('granted,granted').profiles, [
        PermissionProfile.granted,
      ]);
    });

    test('takes a list as well as a comma-separated string', () {
      expect(parseMatrixProfiles(['denied-forever']).profiles, [
        PermissionProfile.deniedForever,
      ]);
    });

    // The point of the refusal: a matrix that quietly ran three of the four
    // cells asked for would have an invisible hole in it.
    test('refuses an unknown name instead of skipping it', () {
      var parsed = parseMatrixProfiles('granted,all-of-them');
      expect(parsed.profiles, isEmpty);
      expect(parsed.error, contains('all-of-them'));
      expect(parsed.error, contains('first-run'));
      expect(parsed.error, contains('denied-forever'));
    });
  });

  group('textsAdded', () {
    test('is what this cell has and the baseline did not', () {
      expect(
        textsAdded(
          const ['Home', 'Take a photo'],
          const ['Home', 'Take a photo', 'Camera unavailable'],
        ),
        ['Camera unavailable'],
      );
    });

    test('keeps the cell’s order and drops repeats', () {
      expect(textsAdded(const ['a'], const ['b', 'a', 'c', 'b']), ['b', 'c']);
    });

    test('is empty when nothing was added', () {
      expect(textsAdded(const ['a', 'b'], const ['b', 'a']), isEmpty);
    });

    // A cell whose launch failed has no screen, and inventing a difference for
    // it would read as a finding.
    test('says nothing when either side has no screen', () {
      expect(textsAdded(null, const ['a']), isEmpty);
      expect(textsAdded(const ['a'], null), isEmpty);
    });
  });

  group('identicalScreens', () {
    test('true when every screen matches', () {
      expect(
        identicalScreens(const [
          ['a', 'b'],
          ['a', 'b'],
        ]),
        isTrue,
      );
    });

    test('false on a different text', () {
      expect(
        identicalScreens(const [
          ['a', 'b'],
          ['a', 'c'],
        ]),
        isFalse,
      );
    });

    test('false on a different length', () {
      expect(
        identicalScreens(const [
          ['a'],
          ['a', 'b'],
        ]),
        isFalse,
      );
    });

    // One cell agreeing with itself is not a finding.
    test('needs two screens', () {
      expect(identicalScreens(const []), isFalse);
      expect(
        identicalScreens(const [
          ['a'],
        ]),
        isFalse,
      );
      expect(
        identicalScreens(const [
          ['a'],
          null,
        ]),
        isFalse,
      );
    });

    test('ignores cells that produced no screen', () {
      expect(
        identicalScreens(const [
          ['a'],
          null,
          ['a'],
        ]),
        isTrue,
      );
    });
  });

  group('sameScreenNote', () {
    test('offers the way out when every screen was the same', () {
      var note = sameScreenNote(const [
        ['a'],
        ['a'],
      ]);
      expect(note, isNotNull);
      expect(note, contains('route'));
    });

    test('is silent when the cells differed', () {
      expect(
        sameScreenNote(const [
          ['a'],
          ['b'],
        ]),
        isNull,
      );
    });
  });
}
