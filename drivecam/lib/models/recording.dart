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

  factory Recording.fromMap(Map<String, dynamic> map) {
    return Recording(
      id: map['id'] as String,
      recordingLocation: map['recording_location'] as String,
      recordingLength: map['recording_length'] as int,
      recordingSize: map['recording_size'] as int?,
      thumbnailLocation: map['thumbnail_location'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recording_location': recordingLocation,
      'recording_length': recordingLength,
      'recording_size': recordingSize,
      'thumbnail_location': thumbnailLocation,
    };
  }

  // inserts the recording to it's table
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

  // returns the recording row
  static Future<Recording?> openRecordingDB() async {
    final db = await DatabaseHelper().database;
    final rows = await db.rawQuery(selectRecording);
    if (rows.isEmpty) return null;
    return Recording.fromMap(rows.first);
  }

  // updates the recording in the db
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

  // deletes the recording in the db
  Future<void> deleteRecordingDB() async {
    final db = await DatabaseHelper().database;
    await db.rawDelete(deleteRecording, [id]);
  }
}
