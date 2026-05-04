// Model class representing a single video clip stored in the database.
//
// Each instance corresponds to one row in the 'clips' table. Methods named
// *DB interact with [DatabaseHelper] to persist changes, so they must be
// called from an async context. Static helpers (e.g. [loadAllClips]) operate
// on all rows at once.

import '../database/database_helper.dart';
import '../database/queries.dart';

class Clip {
  final String id;
  final String dateTime;
  final String dateTimePretty;
  final int clipLength;
  final int clipSize;
  final String triggerType;
  final bool isFlagged;
  final String clipLocation;
  final String thumbnailLocation;

  Clip({
    required this.id,
    required this.dateTime,
    required this.dateTimePretty,
    required this.clipLength,
    required this.clipSize,
    required this.triggerType,
    required this.isFlagged,
    required this.clipLocation,
    required this.thumbnailLocation,
  });

  factory Clip.fromMap(Map<String, dynamic> map) {
    return Clip(
      id: map['id'] as String,
      dateTime: map['date_time'] as String,
      dateTimePretty: map['date_time_pretty'] as String,
      clipLength: map['clip_length'] as int,
      clipSize: map['clip_size'] as int,
      triggerType: map['trigger_type'] as String,
      isFlagged: (map['is_flagged'] as int) == 1,
      clipLocation: map['clip_location'] as String,
      thumbnailLocation: map['thumbnail_location'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date_time': dateTime,
      'date_time_pretty': dateTimePretty,
      'clip_length': clipLength,
      'clip_size': clipSize,
      'trigger_type': triggerType,
      'is_flagged': isFlagged ? 1 : 0,
      'clip_location': clipLocation,
      'thumbnail_location': thumbnailLocation,
    };
  }

  Future<void> insertClipDB() async {
    final db = await DatabaseHelper().database;
    await db.rawInsert(insertClip, [
      id,
      dateTime,
      dateTimePretty,
      clipLength,
      clipSize,
      triggerType,
      isFlagged ? 1 : 0,
      clipLocation,
      thumbnailLocation,
    ]);
  }

  static Future<List<Clip>> loadAllClips() async {
    final db = await DatabaseHelper().database;
    final rows = await db.rawQuery(selectAllClips);
    return rows.map((row) => Clip.fromMap(row)).toList();
  }

  Future<void> updateFlagDB(bool flagged) async {
    final db = await DatabaseHelper().database;
    await db.rawUpdate(updateClipFlag, [flagged ? 1 : 0, id]);
  }

  Future<void> deleteClipDB() async {
    final db = await DatabaseHelper().database;
    await db.rawDelete(deleteClip, [id]);
  }

  /// Deletes the oldest clip from the database based on [date_time] ascending.
  ///
  /// Uses the [deleteOldestClip] SQL constant, which selects the target row
  /// internally via a sub-query — no placeholder is needed and no id is passed.
  /// Call this from storage-management code when you decide the oldest clip
  /// should be removed, such as during cleanup for storage limits.
  Future<void> deleteOldestClipDB() async {
    final db = await DatabaseHelper().database;
    // BUG FIX: deleteOldestClip has no '?' placeholders, so no argument list
    // should be passed. Passing [id] here caused a runtime error because
    // sqflite tried to bind an argument to a non-existent placeholder.
    await db.rawDelete(deleteOldestClip);
  }
}
