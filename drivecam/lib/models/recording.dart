import '../database/database_helper.dart';
import '../database/queries.dart';

class Recording {
  final String id;
  final String recordingLocation;
  final int recordingLength;
  final int? recordingSize;

  Recording({
    required this.id,
    required this.recordingLocation,
    required this.recordingLength,
    this.recordingSize,
  });

  factory Recording.fromMap(Map<String, dynamic> map) {
    return Recording(
      id: map['id'] as String,
      recordingLocation: map['recording_location'] as String,
      recordingLength: map['recording_length'] as int,
      recordingSize: map['recording_size'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recording_location': recordingLocation,
      'recording_length': recordingLength,
      'recording_size': recordingSize,
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
      id,
    ]);
  }

  // deletes the recording in the db
  Future<void> deleteRecordingDB() async {
    final db = await DatabaseHelper().database;
    await db.rawDelete(deleteRecording, [id]);
  }
}
