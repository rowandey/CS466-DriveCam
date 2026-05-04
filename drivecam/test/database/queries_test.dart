// Unit tests for the SQL constants in `lib/database/queries.dart`.
//
// These tests focus on the shape of the SQL strings themselves so that small
// refactors do not accidentally change table names, placeholder order, or sort
// behavior that the app depends on.

import 'package:drivecam/database/queries.dart';
import 'package:flutter_test/flutter_test.dart';

/// Entry point for SQL constant tests.
void main() {
  // The recording queries should stay aligned with the schema used by the app.
  test('recording SQL keeps the expected table shape and parameter order', () {
    expect(createRecordingTable, contains('CREATE TABLE IF NOT EXISTS recording'));
    expect(createRecordingTable, contains('recording_location TEXT NOT NULL'));
    expect(createRecordingTable, contains('recording_length INTEGER NOT NULL'));
    expect(createRecordingTable, contains('recording_size INTEGER'));
    expect(createRecordingTable, contains('thumbnail_location TEXT'));

    expect(insertRecording, contains('INSERT OR REPLACE INTO recording'));
    expect(RegExp(r'\?').allMatches(insertRecording).length, 5);
    expect(selectRecording, contains('LIMIT 1'));
    expect(updateRecording, contains('WHERE id = ?'));
    expect(RegExp(r'\?').allMatches(updateRecording).length, 5);

    // Verify that deleteRecording targets exactly one row via a WHERE clause on
    // id. Without this check, an accidental removal of the clause would turn
    // the delete into an unscoped 'DELETE FROM recording' that wipes all rows
    // rather than the single targeted row. Exactly one placeholder ensures the
    // caller must supply an id argument.
    expect(deleteRecording, contains('DELETE FROM recording'));
    expect(deleteRecording, contains('WHERE id = ?'));
    expect(RegExp(r'\?').allMatches(deleteRecording).length, 1);
  });

  // The clip queries should keep the ordering and flag behavior stable.
  test('clip SQL keeps the expected table shape, ordering, and delete logic', () {
    expect(createClipsTable, contains('CREATE TABLE IF NOT EXISTS clips'));
    expect(createClipsTable, contains('date_time TEXT NOT NULL'));
    expect(createClipsTable, contains('is_flagged INTEGER NOT NULL DEFAULT 0'));
    expect(createClipsTable, contains('thumbnail_location TEXT NOT NULL'));

    expect(insertClip, contains('INSERT INTO clips'));
    expect(RegExp(r'\?').allMatches(insertClip).length, 9);
    expect(selectAllClips, contains('ORDER BY date_time DESC'));
    expect(updateClipFlag, contains('SET is_flagged = ?'));

    // Verify that deleteClip targets exactly one row via a WHERE clause on id.
    // A plain 'DELETE FROM clips' without the WHERE would wipe the entire table,
    // so we assert both the presence of the scoping clause AND that there is
    // exactly one placeholder so the caller must supply an id argument.
    expect(deleteClip, contains('DELETE FROM clips'));
    expect(deleteClip, contains('WHERE id = ?'));
    expect(RegExp(r'\?').allMatches(deleteClip).length, 1);

    expect(deleteOldestClip, contains('ORDER BY date_time ASC'));
    expect(deleteOldestClip, contains('LIMIT 1'));
    expect(RegExp(r'\?').allMatches(deleteOldestClip).length, 0);
  });
}

