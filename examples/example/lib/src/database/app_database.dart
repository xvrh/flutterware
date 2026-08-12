/// Brewline's own database — the dogfood for the db panel
/// (`docs/superpowers/specs/2026-08-12-sqlite-watch-design.md`, S-DB1).
///
/// sqlite_async over a real file, so the panel's `changes` ticks and `watch`
/// re-runs come from the same machinery a production app uses. The drinks
/// catalog is seeded on open; every delivered push is mirrored into
/// `notifications` as it arrives, which is what makes the db panel move while
/// the push panel is being driven.
library;

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../../shop/shop_app.dart';
import '../notifications/push_service.dart';

class AppDatabase {
  AppDatabase._(this.db);

  final SqliteDatabase db;

  static Future<AppDatabase> open() async {
    var directory = await getApplicationSupportDirectory();
    var db = SqliteDatabase(path: p.join(directory.path, 'brewline.db'));
    await db.execute('''
      CREATE TABLE IF NOT EXISTS drinks(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        emoji TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT,
        link TEXT,
        received_at INTEGER NOT NULL
      )''');
    await db.executeBatch(
      'INSERT OR REPLACE INTO drinks(id, name, price, emoji) '
      'VALUES(?, ?, ?, ?)',
      [
        for (var drink in drinks)
          [drink.id, drink.name, drink.price, drink.emoji],
      ],
    );
    return AppDatabase._(db);
  }

  /// Mirrors every delivered push into `notifications`, once per message.
  void persistPushes(PushService service) {
    var written = <String>{};
    service.addListener(() {
      for (var message in service.inbox) {
        if (!written.add(message.id)) continue;
        unawaited(
          db.execute(
            'INSERT OR REPLACE INTO '
            'notifications(id, title, body, link, received_at) '
            'VALUES(?, ?, ?, ?, ?)',
            [
              message.id,
              message.title,
              message.body,
              message.link,
              message.receivedAt.millisecondsSinceEpoch,
            ],
          ),
        );
      }
    });
  }
}
