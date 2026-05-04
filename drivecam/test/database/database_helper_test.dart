// Unit tests for the database schema and SQL workflow.
//
// These tests use the FFI SQLite backend so they can run in the Linux test
// environment. They verify that the app schema is created correctly and that
// the SQL constants in `queries.dart` behave correctly when executed.
//
// Each test opens its own fresh in-memory database so that [_onCreate] always
// runs and no test can observe rows or schema mutations left by a previous run.
// This avoids the isolation problem that arises when tests target the app's
// fixed on-disk 'drivecam.db' file.
//
// Model-layer tests use [DatabaseHelper.setDatabaseForTesting] to inject the
// in-memory database into the singleton so that methods like
// [Clip.deleteOldestClipDB] and [Recording.insertRecordingDB] exercise the
// same code path the app runs.
//
// A dedicated test also exercises [DatabaseHelper._initDatabase()] + [_onCreate]
// wiring directly by setting [DatabaseHelper.testDatabasePath] to
// [inMemoryDatabasePath] so no on-disk file is created.

import 'package:drivecam/database/database_helper.dart';
import 'package:drivecam/database/queries.dart';
import 'package:drivecam/models/clip.dart';
import 'package:drivecam/models/recording.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Configures sqflite to use the FFI database factory for unit tests.
///
/// This switches the database layer away from a mobile-only platform plugin and
/// into a desktop-friendly SQLite backend. Called once before all tests run.
void initializeDatabaseTestEnvironment() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Opens a fresh, isolated in-memory SQLite database and applies the app schema.
///
/// Using [inMemoryDatabasePath] guarantees that [onCreate] always runs so every
/// test starts from a clean state — no leftover rows or on-disk files to worry
/// about. Returns the ready-to-use [Database] instance.
Future<Database> openTestDatabase() {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        // Apply the same schema the production DatabaseHelper uses.
        await db.execute(createRecordingTable);
        await db.execute(createClipsTable);
      },
    ),
  );
}

/// Entry point for database schema and SQL workflow tests.
void main() {
  late Database db;

  // Initialize the FFI backend once for the whole suite.
  setUpAll(() {
    initializeDatabaseTestEnvironment();
  });

  // Each test gets its own empty in-memory database so _onCreate always runs
  // and no test observes state from a previous test. The same instance is
  // injected into DatabaseHelper so model methods share the same connection.
  setUp(() async {
    db = await openTestDatabase();
    // Inject the in-memory database into the singleton so that Clip model
    // methods call the same connection as the test assertions below.
    DatabaseHelper.setDatabaseForTesting(db);
  });

  // Close the in-memory database and reset the singleton after each test.
  tearDown(() async {
    DatabaseHelper.setDatabaseForTesting(null);
    await db.close();
  });

  // The schema test verifies that both tables are created with the correct
  // columns and constraints whenever a fresh database is opened.
  test('creates the expected database tables on open', () async {
    final recordingColumns = await db.rawQuery('PRAGMA table_info(recording)');
    expect(
      recordingColumns.map((row) => row['name']).toList(),
      equals(<String>[
        'id',
        'recording_location',
        'recording_length',
        'recording_size',
        'thumbnail_location',
      ]),
    );
    expect(
      recordingColumns.firstWhere((row) => row['name'] == 'recording_location')['notnull'],
      1,
    );
    expect(
      recordingColumns.firstWhere((row) => row['name'] == 'recording_size')['notnull'],
      0,
    );

    final clipColumns = await db.rawQuery('PRAGMA table_info(clips)');
    expect(
      clipColumns.map((row) => row['name']).toList(),
      equals(<String>[
        'id',
        'date_time',
        'date_time_pretty',
        'clip_length',
        'clip_size',
        'trigger_type',
        'is_flagged',
        'clip_location',
        'thumbnail_location',
      ]),
    );
    expect(
      clipColumns.firstWhere((row) => row['name'] == 'is_flagged')['dflt_value'],
      '0',
    );
  });

  // Recording SQL should insert, update, select, and delete the single row the
  // app stores for the current recording session.
  test('supports the full recording CRUD workflow', () async {
    await db.rawInsert(insertRecording, [
      'recording-1',
      '/videos/recording.mp4',
      120,
      null,
      null,
    ]);

    var rows = await db.rawQuery(selectRecording);
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'recording-1');
    expect(rows.single['recording_location'], '/videos/recording.mp4');
    expect(rows.single['recording_length'], 120);
    expect(rows.single['recording_size'], isNull);
    expect(rows.single['thumbnail_location'], isNull);

    await db.rawUpdate(updateRecording, [
      '/videos/recording-updated.mp4',
      240,
      18,
      '/thumbnails/recording.png',
      'recording-1',
    ]);

    rows = await db.rawQuery(selectRecording);
    expect(rows, hasLength(1));
    expect(rows.single['recording_location'], '/videos/recording-updated.mp4');
    expect(rows.single['recording_length'], 240);
    expect(rows.single['recording_size'], 18);
    expect(rows.single['thumbnail_location'], '/thumbnails/recording.png');

    await db.rawDelete(deleteRecording, ['recording-1']);
    rows = await db.rawQuery(selectRecording);
    expect(rows, isEmpty);
  });

  // Clip SQL should preserve ordering, flag updates, and the oldest-clip delete
  // behavior used by the app when storage needs to be reclaimed.
  test('supports clip ordering, flag updates, and oldest-row deletion', () async {
    await db.rawInsert(insertClip, [
      'clip-old',
      '2026-01-01T10:00:00.000Z',
      'Jan 1, 2026 10:00 AM',
      30,
      12,
      'manual',
      0,
      '/clips/old.mp4',
      '/thumbs/old.png',
    ]);
    await db.rawInsert(insertClip, [
      'clip-new',
      '2026-01-02T10:00:00.000Z',
      'Jan 2, 2026 10:00 AM',
      45,
      15,
      'impact',
      0,
      '/clips/new.mp4',
      '/thumbs/new.png',
    ]);

    var rows = await db.rawQuery(selectAllClips);
    expect(rows, hasLength(2));
    expect(rows.first['id'], 'clip-new');
    expect(rows.last['id'], 'clip-old');

    await db.rawUpdate(updateClipFlag, [1, 'clip-old']);
    rows = await db.rawQuery('SELECT id, is_flagged FROM clips WHERE id = ?', ['clip-old']);
    expect(rows.single['is_flagged'], 1);

    await db.rawDelete(deleteOldestClip);
    rows = await db.rawQuery(selectAllClips);
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'clip-new');
  });

  // This test exercises the actual production code path: Clip.deleteOldestClipDB()
  // calls DatabaseHelper().database and then rawDelete(deleteOldestClip).
  //
  // Previously, deleteOldestClipDB() passed [id] as a positional argument even
  // though deleteOldestClip has no '?' placeholders. Sqflite would throw a
  // DatabaseException at runtime because no binding sites exist. This test
  // would have caught that bug and will fail again if it is reintroduced.
  test('Clip.deleteOldestClipDB() removes the chronologically oldest clip via the model layer', () async {
    // Seed two clips through the model layer to ensure insertion also works
    // end-to-end.
    final older = Clip(
      id: 'clip-older',
      dateTime: '2026-01-01T10:00:00.000Z',
      dateTimePretty: 'Jan 1, 2026 10:00 AM',
      clipLength: 30,
      clipSize: 12,
      triggerType: 'manual',
      isFlagged: false,
      clipLocation: '/clips/older.mp4',
      thumbnailLocation: '/thumbs/older.png',
    );
    final newer = Clip(
      id: 'clip-newer',
      dateTime: '2026-01-02T10:00:00.000Z',
      dateTimePretty: 'Jan 2, 2026 10:00 AM',
      clipLength: 45,
      clipSize: 15,
      triggerType: 'impact',
      isFlagged: false,
      clipLocation: '/clips/newer.mp4',
      thumbnailLocation: '/thumbs/newer.png',
    );
    await older.insertClipDB();
    await newer.insertClipDB();

    // Confirm both rows are present before the delete.
    var rows = await db.rawQuery(selectAllClips);
    expect(rows, hasLength(2));

    // Call the model method — this is the path the production app executes.
    // It must complete without throwing a DatabaseException.
    await older.deleteOldestClipDB();

    // Only the newer clip should remain.
    rows = await db.rawQuery(selectAllClips);
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'clip-newer');
  });

  // This test exercises DatabaseHelper._initDatabase() and the _onCreate
  // callback directly — not the openTestDatabase() shortcut — so a regression
  // in the callback wiring (wrong SQL, wrong version, missing table, etc.)
  // will fail here while the other tests keep using their own schema creation.
  //
  // DatabaseHelper.testDatabasePath is set to inMemoryDatabasePath so no
  // on-disk file is created, making the test fully hermetic.
  test('DatabaseHelper._initDatabase() wires _onCreate correctly', () async {
    // Point the helper at an in-memory database so no disk file is created.
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
    // Reset the cached singleton so the next .database call re-runs _initDatabase().
    DatabaseHelper.setDatabaseForTesting(null);

    // This is the real production path: DatabaseHelper._initDatabase() is called,
    // which opens the database and fires _onCreate, which executes
    // createRecordingTable and createClipsTable.
    final helperDb = await DatabaseHelper().database;

    // Verify that _onCreate created both tables with the right columns.
    final recordingCols = await helperDb.rawQuery('PRAGMA table_info(recording)');
    expect(
      recordingCols.map((c) => c['name']).toList(),
      equals(<String>['id', 'recording_location', 'recording_length', 'recording_size', 'thumbnail_location']),
    );
    final clipCols = await helperDb.rawQuery('PRAGMA table_info(clips)');
    expect(
      clipCols.map((c) => c['name']).toList(),
      equals(<String>['id', 'date_time', 'date_time_pretty', 'clip_length', 'clip_size', 'trigger_type', 'is_flagged', 'clip_location', 'thumbnail_location']),
    );

    // Clean up: close the helper's database, reset the path override, and
    // restore the in-memory DB used by the other tests in this group.
    await helperDb.close();
    DatabaseHelper.testDatabasePath = null;
    DatabaseHelper.setDatabaseForTesting(db);
  });

  // Exercises the Recording model-layer methods end-to-end through the real
  // app code path (Recording.*DB() → DatabaseHelper().database → rawQuery/…).
  //
  // A parameter-order or binding-count bug in Recording model methods would
  // cause a DatabaseException at this layer but pass any SQL-constant-only test.
  test('Recording model-layer methods work end-to-end', () async {
    // insertRecordingDB — writes a new row via the INSERT OR REPLACE statement.
    final recording = Recording(
      id: 'rec-model-1',
      recordingLocation: '/videos/model-rec.mp4',
      recordingLength: 120,
    );
    await recording.insertRecordingDB();

    // openRecordingDB — reads the row back and constructs a Recording object.
    final loaded = await Recording.openRecordingDB();
    expect(loaded, isNotNull);
    expect(loaded!.id, 'rec-model-1');
    expect(loaded.recordingLocation, '/videos/model-rec.mp4');
    expect(loaded.recordingLength, 120);
    expect(loaded.recordingSize, isNull);
    expect(loaded.thumbnailLocation, isNull);

    // updateRecordingDB — updates all four mutable fields in the correct
    // binding order: [recording_location, recording_length, recording_size,
    // thumbnail_location, id]. A wrong order would silently store bad data.
    final updated = Recording(
      id: 'rec-model-1',
      recordingLocation: '/videos/model-rec-updated.mp4',
      recordingLength: 240,
      recordingSize: 50,
      thumbnailLocation: '/thumbs/model-rec.png',
    );
    await updated.updateRecordingDB();

    final reloaded = await Recording.openRecordingDB();
    expect(reloaded!.recordingLocation, '/videos/model-rec-updated.mp4');
    expect(reloaded.recordingLength, 240);
    expect(reloaded.recordingSize, 50);
    expect(reloaded.thumbnailLocation, '/thumbs/model-rec.png');

    // deleteRecordingDB — deletes only the targeted row; passing a wrong id
    // would leave a stale row and the subsequent openRecordingDB would return
    // a non-null value, catching binding or scoping bugs.
    await updated.deleteRecordingDB();
    final afterDelete = await Recording.openRecordingDB();
    expect(afterDelete, isNull);
  });
}

