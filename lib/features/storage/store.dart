import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// All payload checkpoints are committed only after the .part file is flushed.
class Store {
  late final Database db;
  Store(String path) {
    db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute(
      'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS transfers (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS outgoing (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS history (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
  }
  String? setting(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) =>
      db.execute('INSERT OR REPLACE INTO settings VALUES (?,?)', [key, value]);
  Map<String, dynamic>? get(String table, String id) {
    _table(table);
    final rows = db.select('SELECT data FROM $table WHERE id=?', [id]);
    return rows.isEmpty
        ? null
        : jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> all(String table) {
    _table(table);
    return db
        .select('SELECT data FROM $table ORDER BY rowid DESC')
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  void put(String table, String id, Map<String, dynamic> data) {
    _table(table);
    db.execute('INSERT OR REPLACE INTO $table VALUES (?,?)', [
      id,
      jsonEncode(data),
    ]);
  }

  void remove(String table, String id) {
    _table(table);
    db.execute('DELETE FROM $table WHERE id=?', [id]);
  }

  void clearHistory() => db.execute('DELETE FROM history');
  void close() => db.close();
  void _table(String name) {
    if (!{'transfers', 'outgoing', 'history'}.contains(name)) {
      throw ArgumentError('Invalid table');
    }
  }
}
