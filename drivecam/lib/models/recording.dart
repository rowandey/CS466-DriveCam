// Model class representing the single active recording stored in the database.
//
// Only one row ever exists in the 'recording' table at a time. The app
// upserts it on launch and reuses it across sessions. Methods named *DB
// interact with [DatabaseHelper]; they must be called from an async context.

import '../database/database_helper.dart';
import '../database/queries.dart';

class Recording {
  final String id;
  final String recordingLocation;
  final int recordingLength;
  final int? recordingSize;
  final String? thumbnailLocation;

  Recording({
    required this.id,
    required this.recordingLocation,
    required this.recordingLength,
    this.recordingSize,
    this.thumbnailLocation,
  });

  /// Creates a [Recording] from a database row map produced by [rawQuery].
  factory Recording.fromMap(Map<String, dynamic> map) {
    return Recording(
      id: map['id'] as String,
      recordingLocation: map['recording_location'] as String,
      recordingLength: map['recording_length'] as int,
      recordingSize: map['recording_size'] as int?,
      thumbnailLocation: map['thumbnail_location'] as String?,
    );
  }

  /// Converts this instance to a column-name → value map for raw SQL use.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recording_location': recordingLocation,
      'recording_length': recordingLength,
      'recording_size': recordingSize,
      'thumbnail_location': thumbnailLocation,
    };
  }

  /// Inserts (or replaces) this recording row in the database.
  ///
  /// Uses INSERT OR REPLACE so calling this a second time with the same [id]
  /// updates the existing row rather than throwing a constraint violation.
  Future<void> insertRecordingDB() async {
    final db = await DatabaseHelper().database;
    await db.rawInsert(insertRecording, [
      id,
      recordingLocation,
      recordingLength,
      recordingSize,
      thumbnailLocation,
    ]);
  }

  /// Returns the single recording row, or `null` if the table is empty.
  static Future<Recording?> openRecordingDB() async {
    final db = await DatabaseHelper().database;
    final rows = await db.rawQuery(selectRecording);
    if (rows.isEmpty) return null;
    return Recording.fromMap(rows.first);
  }

  /// Updates all mutable fields for this recording in the database.
  ///
  /// Binds arguments in the order expected by [updateRecording]:
  /// `[recording_location, recording_length, recording_size, thumbnail_location, id]`.
  Future<void> updateRecordingDB() async {
    final db = await DatabaseHelper().database;
    await db.rawUpdate(updateRecording, [
      recordingLocation,
      recordingLength,
      recordingSize,
      thumbnailLocation,
      id,
    ]);
  }

  /// Deletes the recording row identified by [id] from the database.
  Future<void> deleteRecordingDB() async {
    final db = await DatabaseHelper().database;
    await db.rawDelete(deleteRecording, [id]);
  }
}
