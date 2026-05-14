// Tests for ClipProvider's clip storage limit enforcement.
//
// These tests exercise the eviction logic that fires after every clip save.
// They use the FFI SQLite backend + an in-memory database so no camera or
// FFmpeg is needed — the eviction method is called directly after seeding the
// database through the model layer.
//
// Design note: ClipProvider.enforceClipStorageLimit() is annotated
// @visibleForTesting so it can be called here independently from the full
// clip-save pipeline (which would require a live camera and FFmpeg). This is
// the same approach used by recording_provider_test.dart, which calls
// addSegment() to trigger eviction without a real camera.

import 'dart:io';

import 'package:drivecam/database/database_helper.dart';
import 'package:drivecam/database/queries.dart';
import 'package:drivecam/models/clip.dart';
import 'package:drivecam/provider/clip_provider.dart';
import 'package:drivecam/provider/recording_provider.dart';
import 'package:drivecam/provider/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Opens a fresh in-memory database with the app schema applied.
// Each test gets its own instance so no state leaks between tests.
Future<Database> openTestDatabase() {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute(createRecordingTable);
        await db.execute(createClipsTable);
      },
    ),
  );
}

void main() {
  late Database db;

  // Switch sqflite to the FFI backend so tests run without mobile plugins.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openTestDatabase();
    // Inject the in-memory DB so all Clip model methods use it.
    DatabaseHelper.setDatabaseForTesting(db);
    // Suppress SharedPreferences platform calls from SettingsProvider setters.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() async {
    DatabaseHelper.setDatabaseForTesting(null);
    await db.close();
  });

  /// Builds a [ClipProvider] with [clipStorageLimit] set to the given option
  /// string (must be one of clipStorageLimitOptions, e.g. '1GB').
  /// Both the [RecordingProvider] and [SettingsProvider] are created fresh so
  /// each test starts from a clean state.
  ClipProvider makeProvider({required String clipStorageLimit}) {
    final settings = SettingsProvider();
    // Set the field directly to avoid async SharedPreferences calls.
    settings.clipStorageLimit = clipStorageLimit;
    final recording = RecordingProvider(settings);
    return ClipProvider(recording, settings);
  }

  /// Inserts a clip row directly into the test database.
  ///
  /// [id] and [dateTime] are used to control FIFO ordering — an earlier
  /// [dateTime] means the clip is considered older and will be evicted first.
  /// [clipSize] is in bytes. [clipLocation] and [thumbnailLocation] are the
  /// file paths stored in the DB (used by eviction to delete files from disk).
  Future<void> insertTestClip({
    required String id,
    required String dateTime,
    required int clipSize,
    String clipLocation = '/clips/test.mp4',
    String thumbnailLocation = '/thumbs/test.jpg',
  }) async {
    await db.rawInsert(insertClip, [
      id,
      dateTime,
      'pretty $id',
      30,         // clip_length (seconds) — irrelevant to eviction
      clipSize,
      'manual',
      0,          // is_flagged
      clipLocation,
      thumbnailLocation,
    ]);
  }

  // ===========================================================================
  // No eviction when under the limit
  // ===========================================================================

  test('does not evict any clips when total size is within the limit', () async {
    // 1 GB = 1,073,741,824 bytes. Two clips at 200 MB each = 400 MB total — well under.
    const mb200 = 200 * 1024 * 1024;
    await insertTestClip(id: 'clip-a', dateTime: '2026-01-01T10:00:00.000Z', clipSize: mb200);
    await insertTestClip(id: 'clip-b', dateTime: '2026-01-02T10:00:00.000Z', clipSize: mb200);

    final provider = makeProvider(clipStorageLimit: '1GB');
    await provider.enforceClipStorageLimit();

    final remaining = await Clip.loadAllClips();
    // Both clips are under the 1 GB limit — neither should be deleted.
    expect(remaining, hasLength(2));
  });

  // ===========================================================================
  // Single-clip eviction
  // ===========================================================================

  // When two clips together exceed the limit, only the oldest is removed.
  // This mirrors the dashcam rolling-window behaviour for recordings.
  test('evicts the single oldest clip when total just exceeds the limit', () async {
    // 600 MB each. 2 × 600 = 1,200 MB > 1 GB. After evicting clip-old: 600 MB ≤ 1 GB.
    const mb600 = 600 * 1024 * 1024;
    await insertTestClip(id: 'clip-old', dateTime: '2026-01-01T10:00:00.000Z', clipSize: mb600);
    await insertTestClip(id: 'clip-new', dateTime: '2026-01-02T10:00:00.000Z', clipSize: mb600);

    final provider = makeProvider(clipStorageLimit: '1GB');
    await provider.enforceClipStorageLimit();

    final remaining = await Clip.loadAllClips();
    expect(remaining, hasLength(1));
    // The newer clip must survive — only the oldest is evicted.
    expect(remaining.single.id, 'clip-new');
  });

  // ===========================================================================
  // Multi-clip eviction in a single pass
  // ===========================================================================

  // Eviction must loop until the total is back within the limit, not just
  // remove one clip and stop. If it stopped early the app would leave the user
  // over-limit until the next clip is saved.
  test('evicts multiple oldest clips in one pass until within the limit', () async {
    // 3 clips at 600 MB each = 1,800 MB.
    // After evicting oldest: 1,200 MB > 1 GB → evict again → 600 MB ≤ 1 GB.
    const mb600 = 600 * 1024 * 1024;
    await insertTestClip(id: 'clip-1', dateTime: '2026-01-01T10:00:00.000Z', clipSize: mb600);
    await insertTestClip(id: 'clip-2', dateTime: '2026-01-02T10:00:00.000Z', clipSize: mb600);
    await insertTestClip(id: 'clip-3', dateTime: '2026-01-03T10:00:00.000Z', clipSize: mb600);

    final provider = makeProvider(clipStorageLimit: '1GB');
    await provider.enforceClipStorageLimit();

    final remaining = await Clip.loadAllClips();
    // Two oldest clips are removed; only the newest survives.
    expect(remaining, hasLength(1));
    expect(remaining.single.id, 'clip-3');
  });

  // ===========================================================================
  // FIFO ordering
  // ===========================================================================

  // Eviction must always remove the chronologically oldest clip first.
  // Removing a newer clip would cause unexpected data loss for the user.
  test('eviction is FIFO — always removes chronologically oldest clip first',
      () async {
    // Three 400 MB clips. Total 1,200 MB > 1 GB → evict oldest (clip-a).
    // Remaining 800 MB ≤ 1 GB → stop. clip-b and clip-c survive.
    const mb400 = 400 * 1024 * 1024;
    await insertTestClip(id: 'clip-a', dateTime: '2026-01-01T08:00:00.000Z', clipSize: mb400);
    await insertTestClip(id: 'clip-b', dateTime: '2026-01-02T08:00:00.000Z', clipSize: mb400);
    await insertTestClip(id: 'clip-c', dateTime: '2026-01-03T08:00:00.000Z', clipSize: mb400);

    final provider = makeProvider(clipStorageLimit: '1GB');
    await provider.enforceClipStorageLimit();

    final remaining = await Clip.loadAllClips();
    expect(remaining, hasLength(2));
    // loadAllClips returns newest-first, so index 0 is clip-c, index 1 is clip-b.
    expect(remaining[0].id, 'clip-c');
    expect(remaining[1].id, 'clip-b');
    // clip-a (oldest) must be gone.
    expect(remaining.any((c) => c.id == 'clip-a'), isFalse);
  });

  // ===========================================================================
  // Disk file deletion
  // ===========================================================================

  // When a clip is evicted, both its video file and thumbnail must be deleted
  // from disk. Keeping DB rows in sync with the filesystem is not enough —
  // the storage bytes only return to the OS once the files are gone.
  test('evicted clip video and thumbnail files are deleted from disk', () async {
    final tmpDir = Directory.systemTemp.createTempSync('clip_eviction_test_');
    try {
      final videoFile = File('${tmpDir.path}/old.mp4');
      final thumbFile = File('${tmpDir.path}/old.jpg');
      await videoFile.writeAsString('fake video');
      await thumbFile.writeAsString('fake thumbnail');

      const mb600 = 600 * 1024 * 1024;
      // Insert the older clip pointing to the real temp files.
      await insertTestClip(
        id: 'clip-old',
        dateTime: '2026-01-01T10:00:00.000Z',
        clipSize: mb600,
        clipLocation: videoFile.path,
        thumbnailLocation: thumbFile.path,
      );
      // Newer clip uses fake non-existent paths (we only care about old-clip files).
      await insertTestClip(
        id: 'clip-new',
        dateTime: '2026-01-02T10:00:00.000Z',
        clipSize: mb600,
      );

      final provider = makeProvider(clipStorageLimit: '1GB');
      await provider.enforceClipStorageLimit();

      // clip-old is evicted — both its files must no longer exist on disk.
      expect(videoFile.existsSync(), isFalse,
          reason: 'video file should be deleted from disk on eviction');
      expect(thumbFile.existsSync(), isFalse,
          reason: 'thumbnail should be deleted from disk on eviction');
    } finally {
      // Always clean up the temp directory, even if the test fails.
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    }
  });

  // ===========================================================================
  // Missing files on disk
  // ===========================================================================

  // If a clip's file has already been removed (e.g. manual deletion outside
  // the app, prior crash), enforceClipStorageLimit must not throw. The DB row
  // should still be removed so the app stays consistent.
  test('eviction with non-existent clip files does not throw', () async {
    const mb600 = 600 * 1024 * 1024;
    await insertTestClip(
      id: 'clip-missing',
      dateTime: '2026-01-01T10:00:00.000Z',
      clipSize: mb600,
      clipLocation: '/no/such/file.mp4',
      thumbnailLocation: '/no/such/thumb.jpg',
    );
    await insertTestClip(
      id: 'clip-ok',
      dateTime: '2026-01-02T10:00:00.000Z',
      clipSize: mb600,
    );

    final provider = makeProvider(clipStorageLimit: '1GB');

    // The call must complete normally — missing files must not throw.
    await expectLater(
      provider.enforceClipStorageLimit(),
      completes,
    );

    // The DB row is removed even when the file was already gone.
    final remaining = await Clip.loadAllClips();
    expect(remaining, hasLength(1));
    expect(remaining.single.id, 'clip-ok');
  });

  // ===========================================================================
  // Newly inserted clip is included in the total
  // ===========================================================================

  // enforceClipStorageLimit is called *after* insertClipDB, so the clip just
  // saved counts toward the total. If it were called before, the last clip
  // would be invisible to the check and the limit could be silently exceeded.
  test('newly inserted clip is counted in the total before any eviction check',
      () async {
    // Start with one clip that already fills 90 % of the limit (963 MB of 1 GB).
    // A second clip at 200 MB pushes the total to ~1,163 MB > 1 GB.
    // The enforcement must detect this and evict the older clip.
    const mb963 = 963 * 1024 * 1024;
    const mb200 = 200 * 1024 * 1024;
    await insertTestClip(
      id: 'clip-big-old',
      dateTime: '2026-01-01T10:00:00.000Z',
      clipSize: mb963,
    );
    // Simulate the "just saved" clip already inserted into the DB.
    await insertTestClip(
      id: 'clip-new-small',
      dateTime: '2026-01-02T10:00:00.000Z',
      clipSize: mb200,
    );

    final provider = makeProvider(clipStorageLimit: '1GB');
    await provider.enforceClipStorageLimit();

    // The old large clip must be evicted; the newly saved small clip survives.
    final remaining = await Clip.loadAllClips();
    expect(remaining, hasLength(1));
    expect(remaining.single.id, 'clip-new-small');
  });

  // ===========================================================================
  // Edge case: no clips in DB
  // ===========================================================================

  test('does not throw when the clips table is empty', () async {
    final provider = makeProvider(clipStorageLimit: '1GB');

    await expectLater(provider.enforceClipStorageLimit(), completes);

    final remaining = await Clip.loadAllClips();
    expect(remaining, isEmpty);
  });
}
