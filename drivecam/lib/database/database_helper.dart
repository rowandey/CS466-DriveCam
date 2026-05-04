// DatabaseHelper provides a singleton-cached SQLite database for the app.
//
// Only one [Database] instance is created per app run. All model classes
// call [DatabaseHelper().database] to obtain it. The [setDatabaseForTesting]
// seam allows unit tests to inject an in-memory database without touching
// the on-disk 'drivecam.db' file.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'queries.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  /// Returns the cached database, opening and initializing it on first access.
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Injects [db] as the cached database instance.
  ///
  /// **Only for use in unit tests.** Call this before any code that accesses
  /// [database] so that the singleton never opens the on-disk file. Reset by
  /// passing `null` after the test completes.
  @visibleForTesting
  static void setDatabaseForTesting(Database? db) {
    _database = db;
  }

  /// Overrides the database file path used by [_initDatabase].
  ///
  /// **Only for use in unit tests.** Set to [inMemoryDatabasePath] before
  /// calling [database] with `_database == null` to exercise the full
  /// `_initDatabase()` → `_onCreate` path without writing to disk.
  /// Reset to `null` after the test completes.
  @visibleForTesting
  static String? testDatabasePath;

  Future<Database> _initDatabase() async {
    // Use the test-injected path when set; otherwise fall back to the real
    // on-disk path so production behaviour is unchanged.
    final path = testDatabasePath ?? join(await getDatabasesPath(), 'drivecam.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(createRecordingTable);
    await db.execute(createClipsTable);
  }
}
