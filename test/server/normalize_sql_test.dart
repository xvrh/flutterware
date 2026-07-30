import 'package:flutterware/server.dart';
import 'package:test/test.dart';

void main() {
  test('the N+1 shape collapses to one group', () {
    // The reason this function exists: these differ only in their literals,
    // and exact-string grouping would see three distinct queries.
    expect(
      {
        normalizeSql('select count(*) from posts where user_id = 1'),
        normalizeSql('select count(*) from posts where user_id = 2'),
        normalizeSql('select count(*) from posts where user_id = 3'),
      },
      {'select count(*) from posts where user_id = ?'},
    );
  });

  group('literals', () {
    test('integers and decimals', () {
      expect(
        normalizeSql('select * from t where a = 42 and b < 3.14'),
        'select * from t where a = ? and b < ?',
      );
    });

    test('single-quoted strings, including escaped quotes', () {
      expect(
        normalizeSql("select * from t where name = 'O''Brien'"),
        'select * from t where name = ?',
      );
    });

    test('digits inside a string are not visited twice', () {
      expect(
        normalizeSql("select * from t where tag = 'v1.2'"),
        'select * from t where tag = ?',
      );
    });

    test('digits inside identifiers stay', () {
      expect(
        normalizeSql('select user_id2 from t2 where x = 7'),
        'select user_id2 from t2 where x = ?',
      );
    });

    test('postgres placeholders group with inlined literals', () {
      expect(
        normalizeSql(r'select * from t where id = $1'),
        normalizeSql('select * from t where id = 9'),
      );
    });
  });

  group('IN lists', () {
    test('collapse regardless of length', () {
      expect(
        normalizeSql('select * from t where id in (1, 2, 3)'),
        normalizeSql('select * from t where id in (4)'),
      );
      expect(
        normalizeSql('select * from t where id in (1, 2, 3)'),
        'select * from t where id in (?)',
      );
    });

    test('keep the keyword casing they arrived in', () {
      expect(
        normalizeSql('SELECT * FROM t WHERE id IN (1, 2)'),
        'SELECT * FROM t WHERE id IN (?)',
      );
    });
  });

  test('whitespace folds', () {
    expect(
      normalizeSql('select *\n  from t\n  where a = 1'),
      'select * from t where a = ?',
    );
  });

  test('double-quoted identifiers are left alone', () {
    // Standard SQL: double quotes are identifiers. Rewriting them would merge
    // queries over *different columns*, which reports an N+1 that is not
    // there — the expensive direction to be wrong in.
    expect(
      normalizeSql('select "count" from t where a = 1'),
      'select "count" from t where a = ?',
    );
  });
}
